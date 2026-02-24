"""gRPC Service implementation for Scribe"""

import asyncio
import functools
import logging
import os
from pathlib import Path
from typing import AsyncIterator, Dict, List, Optional, Tuple

import grpc

from .proto import scribe_pb2
from .proto import scribe_pb2_grpc

from .db.dao import Database
from .engine.model_manager import ModelManager
from .engine.transcription import (
    TranscriptionEngine,
    _SUPPORTED_TRANSLATION_LANGUAGES,
)

logger = logging.getLogger(__name__)

# Allowed audio/video file extensions (matches the Flutter frontend).
_ALLOWED_EXTENSIONS = {'.wav', '.mp3', '.m4a', '.flac', '.ogg', '.mp4', '.webm'}

# System directories that should never be read by the transcription engine.
_BLOCKED_PREFIXES = (
    '/etc', '/proc', '/sys', '/dev',
    '/boot', '/sbin', '/bin', '/lib',
)


def _validate_audio_path(raw_path: str) -> Tuple[Optional[str], Optional[str]]:
    """Sanitise and validate a user-supplied audio file path.

    Returns:
        (resolved_path, None) on success, or (None, error_message) on failure.
    """
    if not raw_path or not raw_path.strip():
        return None, "Audio file path is empty"

    # Require an absolute path — relative paths are ambiguous.
    if not os.path.isabs(raw_path):
        return None, "Audio file path must be absolute"

    # Resolve '..' / symlinks to a canonical path to prevent traversal.
    resolved = str(Path(raw_path).resolve())

    # Block access to sensitive system directories.
    for prefix in _BLOCKED_PREFIXES:
        if resolved == prefix or resolved.startswith(prefix + os.sep):
            return None, f"Access denied: path is inside a system directory"

    # Check file extension.
    ext = Path(resolved).suffix.lower()
    if ext not in _ALLOWED_EXTENSIONS:
        allowed = ', '.join(sorted(_ALLOWED_EXTENSIONS))
        return None, f"Unsupported file type '{ext}'. Allowed: {allowed}"

    # Must be a regular file (not a directory, device node, etc.).
    if not os.path.isfile(resolved):
        return None, f"Audio file not found: {resolved}"

    return resolved, None


class ScribeService(scribe_pb2_grpc.ScribeServicer):
    """Implementation of the Scribe gRPC service"""

    def __init__(self):
        """Initialize the service with database and transcription engine"""
        self.db = Database()
        self.model_manager = ModelManager()
        self.engine = TranscriptionEngine(self.db, self.model_manager)
        self._background_tasks: set[asyncio.Task] = set()
        # Event-driven streaming: job_id -> list of subscriber queues
        self._job_subscribers: Dict[str, List[asyncio.Queue]] = {}

    async def start(self):
        """Start background tasks. Must be called after the event loop is running."""
        recovered = await self.db.fail_stale_jobs()
        if recovered:
            logger.warning(
                f"Recovered {recovered} stale job(s) from previous run "
                f"(marked as FAILED)"
            )

    def _subscribe(self, job_id: str) -> asyncio.Queue:
        """Add a subscriber queue for a job's events."""
        queue = asyncio.Queue()
        self._job_subscribers.setdefault(job_id, []).append(queue)
        return queue

    def _unsubscribe(self, job_id: str, queue: asyncio.Queue):
        """Remove a subscriber queue and clean up if no subscribers remain."""
        subs = self._job_subscribers.get(job_id)
        if subs:
            try:
                subs.remove(queue)
            except ValueError:
                pass
            if not subs:
                del self._job_subscribers[job_id]

    def _publish(self, job_id: str, event: scribe_pb2.TranscriptionEvent):
        """Push an event to all subscribers of a job. None signals end-of-stream."""
        for queue in self._job_subscribers.get(job_id, []):
            queue.put_nowait(event)

    def _publish_end(self, job_id: str):
        """Signal all subscribers that no more events will be sent."""
        for queue in self._job_subscribers.get(job_id, []):
            queue.put_nowait(None)

    async def HealthCheck(self, request, context):
        """Check if the service is healthy"""
        logger.info("Health check requested")
        
        # Check if database is accessible
        try:
            await self.db.get_all_settings()
            return scribe_pb2.HealthCheckResponse(
                ok=True,
                message="Service is healthy"
            )
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return scribe_pb2.HealthCheckResponse(
                ok=False,
                message=f"Database error: {str(e)}"
            )
    
    async def StartTranscription(self, request, context):
        """Start a new transcription job"""
        logger.info("Starting transcription job")
        
        # Extract audio path
        if not request.audio.HasField('file_path'):
            await context.abort(
                grpc.StatusCode.INVALID_ARGUMENT,
                "Only file_path audio source is supported"
            )
            return

        audio_path, error = _validate_audio_path(request.audio.file_path)
        if error:
            await context.abort(grpc.StatusCode.INVALID_ARGUMENT, error)
            return

        # Generate job ID if not provided
        job_id = request.job_id if request.job_id else await self.db.new_job_id()
        
        # Get transcription options
        options = request.options if request.HasField('options') else None
        model_name = options.model if options and options.model else "base"
        language = options.language if options and options.language else None
        translate = options.translate_to_english if options else False
        translate_to_language = (
            options.translate_to_language.lower()
            if options and options.translate_to_language
            else ("en" if translate else None)
        )
        initial_prompt = options.initial_prompt if options and options.initial_prompt else None
        enable_gpu = options.enable_gpu if options else True
        
        # Create job in database
        success = await self.db.create_job(
            job_id=job_id,
            audio_path=audio_path,
            model=model_name,
            language=language or "auto",
            translate=bool(translate_to_language)
        )
        
        if not success:
            await context.abort(
                grpc.StatusCode.INTERNAL,
                "Failed to create job in database"
            )
            return

        # Build event callback that converts engine events to protobuf
        # and publishes them to all stream subscribers.
        def _on_engine_event(jid: str, event: dict):
            proto_event = scribe_pb2.TranscriptionEvent(
                job_id=jid,
                status=event['status'],
                progress=event.get('progress', 0.0),
            )
            if event.get('error'):
                proto_event.error = event['error']
            seg = event.get('segment')
            if seg:
                proto_event.segment.CopyFrom(scribe_pb2.Segment(
                    index=seg['idx'],
                    start=seg['start'],
                    end=seg['end'],
                    text=seg['text'],
                ))
            self._publish(jid, proto_event)
            if event.get('final'):
                self._publish_end(jid)

        # Start transcription in background
        task = asyncio.create_task(
            self.engine.run_job(
                job_id=job_id,
                audio_path=audio_path,
                model_name=model_name,
                language=language,
                translate=translate,
                translate_to_language=translate_to_language,
                initial_prompt=initial_prompt,
                enable_gpu=enable_gpu,
                on_event=_on_engine_event,
            )
        )
        self._background_tasks.add(task)
        task.add_done_callback(self._background_tasks.discard)
        task.add_done_callback(self._on_task_done)
        
        return scribe_pb2.StartTranscriptionResponse(
            job_id=job_id,
            status=scribe_pb2.JobStatus.QUEUED
        )
    
    async def StreamTranscription(self, request, context) -> AsyncIterator:
        """Stream transcription events for a job using an event-driven queue."""
        job_id = request.job_id
        logger.info(f"Streaming transcription for job {job_id}")

        # Check if job exists
        job = await self.db.get_job(job_id)
        if not job:
            await context.abort(
                grpc.StatusCode.NOT_FOUND,
                f"Job not found: {job_id}"
            )
            return

        # If the job already finished before the client subscribed, replay
        # the final state from the DB and return immediately.
        terminal_statuses = [
            scribe_pb2.JobStatus.COMPLETED,
            scribe_pb2.JobStatus.FAILED,
            scribe_pb2.JobStatus.CANCELED,
        ]
        if job['status'] in terminal_statuses:
            # Replay all segments then the terminal event
            segments = await self.db.get_segments(job_id)
            for seg in segments:
                yield scribe_pb2.TranscriptionEvent(
                    job_id=job_id,
                    status=job['status'],
                    progress=job.get('progress', 0.0),
                    segment=scribe_pb2.Segment(
                        index=seg['idx'],
                        start=seg['start'],
                        end=seg['end'],
                        text=seg['text'],
                    ),
                )
            final = scribe_pb2.TranscriptionEvent(
                job_id=job_id,
                status=job['status'],
                progress=job.get('progress', 0.0),
            )
            if job.get('error'):
                final.error = job['error']
            yield final
            return

        # Subscribe to live events
        queue = self._subscribe(job_id)
        try:
            while True:
                event = await queue.get()
                if event is None:
                    # End-of-stream sentinel
                    break
                yield event
        finally:
            self._unsubscribe(job_id, queue)
    
    async def GetJob(self, request, context):
        """Get information about a specific job"""
        job = await self.db.get_job(request.job_id)

        if not job:
            await context.abort(
                grpc.StatusCode.NOT_FOUND,
                f"Job not found: {request.job_id}"
            )
            return

        response = scribe_pb2.GetJobResponse(
            job_id=job['job_id'],
            status=job['status'],
            progress=job.get('progress', 0.0)
        )
        
        if job.get('error'):
            response.error = job['error']
            
        return response
    
    async def ListJobs(self, request, context):
        """List all transcription jobs"""
        jobs = await self.db.list_jobs()
        
        response = scribe_pb2.ListJobsResponse()
        for job in jobs:
            duration_seconds = await self._resolve_job_duration_seconds(job)
            summary = scribe_pb2.JobSummary(
                job_id=job['job_id'],
                status=job['status'],
                created_at=job['created_at'],
                updated_at=job['updated_at'],
                audio_path=job.get('audio_path', ''),
                duration_seconds=duration_seconds,
            )
            if job.get('error'):
                summary.error = job['error']
            response.jobs.append(summary)
        
        return response

    async def _resolve_job_duration_seconds(self, job: Dict) -> float:
        """Resolve and persist accurate duration for jobs missing it."""
        stored = float(job.get('stored_duration_seconds') or 0.0)
        if stored > 0:
            return stored

        audio_path = job.get('audio_path')
        if not isinstance(audio_path, str) or not audio_path:
            return float(job.get('duration_seconds') or 0.0)

        loop = asyncio.get_running_loop()
        duration = await loop.run_in_executor(
            self.engine._executor,
            self.engine._get_audio_duration,
            audio_path,
        )
        if duration > 0:
            await self.db.update_job_audio_duration(job['job_id'], duration)
            job['stored_duration_seconds'] = duration
            job['duration_seconds'] = duration
            return float(duration)

        return float(job.get('duration_seconds') or 0.0)
    
    async def CancelJob(self, request, context):
        """Cancel a running job"""
        # Try to cancel in engine first
        cancelled = await self.engine.cancel_job(request.job_id)
        
        if not cancelled:
            # Job might not be running, update status in DB
            job = await self.db.get_job(request.job_id)
            if job and job['status'] in [scribe_pb2.JobStatus.QUEUED, scribe_pb2.JobStatus.RUNNING]:
                await self.db.cancel_job(request.job_id)
                cancelled = True
        
        return scribe_pb2.CancelJobResponse(canceled=cancelled)
    
    async def DeleteJob(self, request, context):
        """Delete a job and its data"""
        deleted = await self.db.delete_job(request.job_id)
        return scribe_pb2.DeleteJobResponse(deleted=deleted)

    async def GetTranscript(self, request, context):
        """Get full transcript with segments for a completed job"""
        job = await self.db.get_job(request.job_id)

        if not job:
            await context.abort(
                grpc.StatusCode.NOT_FOUND,
                f"Job not found: {request.job_id}"
            )
            return

        segments = await self.db.get_segments(request.job_id)

        proto_segments = [
            scribe_pb2.Segment(
                index=seg['idx'],
                start=seg['start'],
                end=seg['end'],
                text=seg['text'],
                edited_text=seg.get('edited_text') or ''
            )
            for seg in segments
        ]

        return scribe_pb2.GetTranscriptResponse(
            job_id=job['job_id'],
            status=job['status'],
            segments=proto_segments,
            audio_path=job.get('audio_path', ''),
            model=job.get('model', ''),
            language=job.get('language', ''),
            created_at=job.get('created_at', '')
        )

    async def SaveTranscriptEdits(self, request, context):
        """Persist user edits to transcript segments"""
        job_id = request.job_id

        job = await self.db.get_job(job_id)
        if not job:
            await context.abort(
                grpc.StatusCode.NOT_FOUND,
                f"Job not found: {job_id}"
            )
            return

        edits = [
            {'segment_index': e.segment_index, 'edited_text': e.edited_text}
            for e in request.edits
        ]

        try:
            await self.db.save_segment_edits(job_id, edits)
            return scribe_pb2.SaveTranscriptEditsResponse(saved=True)
        except Exception as e:
            logger.error(f"Failed to save transcript edits: {e}")
            return scribe_pb2.SaveTranscriptEditsResponse(saved=False)

    async def TranslateTranscript(self, request, context):
        """Translate an existing transcript and return translated edits."""
        job_id = request.job_id
        target_language = (request.target_language or "").strip().lower()

        if not target_language:
            await context.abort(
                grpc.StatusCode.INVALID_ARGUMENT,
                "target_language is required",
            )
            return

        if target_language not in _SUPPORTED_TRANSLATION_LANGUAGES:
            await context.abort(
                grpc.StatusCode.INVALID_ARGUMENT,
                f"Unsupported translation language: {target_language}",
            )
            return

        job = await self.db.get_job(job_id)
        if not job:
            await context.abort(
                grpc.StatusCode.NOT_FOUND,
                f"Job not found: {job_id}"
            )
            return

        segments = await self.db.get_segments(job_id)
        if not segments:
            return scribe_pb2.TranslateTranscriptResponse(
                translated=True,
                target_language=target_language,
            )

        requested_indices = set(request.segment_indices)
        if requested_indices:
            segments = [seg for seg in segments if seg['idx'] in requested_indices]
            if not segments:
                await context.abort(
                    grpc.StatusCode.INVALID_ARGUMENT,
                    "No transcript segments match the requested segment_indices",
                )
                return

        # Caller-provided unsaved edits take precedence over persisted text.
        # Empty edits are meaningful (deleted lines) and should suppress
        # translation for those segments.
        source_edits = {
            edit.segment_index: edit.edited_text
            for edit in request.source_edits
        }

        loop = asyncio.get_running_loop()
        translation_cache: Dict[str, str] = {}
        translated_edits: List[scribe_pb2.SegmentEdit] = []

        try:
            for seg in segments:
                if seg['idx'] in source_edits:
                    source_text = (source_edits[seg['idx']] or "").strip()
                else:
                    source_text = (
                        seg.get('edited_text')
                        or seg.get('text')
                        or ""
                    ).strip()
                if not source_text:
                    continue

                translated = translation_cache.get(source_text)
                if translated is None:
                    translated = await loop.run_in_executor(
                        None,
                        self.engine._translate_text,
                        source_text,
                        target_language,
                    )
                    translation_cache[source_text] = translated

                translated_edits.append(
                    scribe_pb2.SegmentEdit(
                        segment_index=seg['idx'],
                        edited_text=translated,
                    )
                )
        except Exception as e:
            logger.error(
                f"Failed to translate transcript for job {job_id}: {e}",
                exc_info=True,
            )
            await context.abort(
                grpc.StatusCode.INTERNAL,
                f"Failed to translate transcript: {e}",
            )
            return

        return scribe_pb2.TranslateTranscriptResponse(
            translated=True,
            target_language=target_language,
            translated_edits=translated_edits,
        )

    async def GetSettings(self, request, context):
        """Get application settings"""
        settings = await self.db.get_all_settings()
        
        # Get defaults if not set
        models_dir = settings.get('models_dir', str(self.model_manager.models_dir))
        prefer_gpu = settings.get('prefer_gpu', 'true').lower() == 'true'
        default_model = settings.get('default_model', 'base')
        compute_type = settings.get('compute_type', 'auto')
        
        return scribe_pb2.GetSettingsResponse(
            settings=scribe_pb2.Settings(
                models_dir=models_dir,
                prefer_gpu=prefer_gpu,
                default_model=default_model,
                compute_type=compute_type
            )
        )
    
    async def UpdateSettings(self, request, context):
        """Update application settings"""
        settings = request.settings
        
        # Save settings to database
        if settings.models_dir:
            await self.db.set_setting('models_dir', settings.models_dir)
            # Update model manager and propagate to engine
            self.model_manager = ModelManager(settings.models_dir)
            self.engine.model_manager = self.model_manager
            
        await self.db.set_setting('prefer_gpu', str(settings.prefer_gpu).lower())
        
        if settings.default_model:
            await self.db.set_setting('default_model', settings.default_model)
            
        if settings.compute_type:
            await self.db.set_setting('compute_type', settings.compute_type)
        
        # Return updated settings
        return await self.GetSettings(request, context)
    
    async def ListModels(self, request, context):
        """List available Whisper models"""
        models = self.model_manager.list_available_models()
        
        response = scribe_pb2.ListModelsResponse()
        for model in models:
            model_info = scribe_pb2.ModelInfo(
                name=model['name'],
                size=model['size'],
                downloaded=model['downloaded']
            )
            response.models.append(model_info)
        
        return response
    
    async def DownloadModel(self, request, context) -> AsyncIterator:
        """Stream model download progress"""
        model_name = request.name

        if model_name not in self.model_manager.AVAILABLE_MODELS:
            await context.abort(
                grpc.StatusCode.NOT_FOUND,
                f"Unknown model: {model_name}"
            )
            return

        # Check if already downloaded
        if self.model_manager.is_model_downloaded(model_name):
            logger.info(f"Model {model_name} already downloaded")
            size = self.model_manager.AVAILABLE_MODELS[model_name]
            yield scribe_pb2.DownloadModelProgress(
                name=model_name,
                status=scribe_pb2.DOWNLOAD_COMPLETE,
                downloaded_bytes=size,
                total_bytes=size,
            )
            return

        yield scribe_pb2.DownloadModelProgress(
            name=model_name,
            status=scribe_pb2.DOWNLOAD_STARTING,
            total_bytes=self.model_manager.AVAILABLE_MODELS.get(model_name, 0),
        )

        loop = asyncio.get_running_loop()
        queue: asyncio.Queue = asyncio.Queue()

        def progress_callback(downloaded: int, total: int):
            loop.call_soon_threadsafe(
                queue.put_nowait, (downloaded, total)
            )

        from .engine.model_manager import DownloadCanceled

        download_future = loop.run_in_executor(
            None,
            functools.partial(
                self.model_manager.download_model_with_progress,
                model_name,
                progress_callback,
            ),
        )

        try:
            # Yield progress events until the download finishes
            while True:
                # Wait for either a progress update or the download to finish
                get_task = asyncio.ensure_future(queue.get())
                done, _ = await asyncio.wait(
                    [get_task, download_future],
                    return_when=asyncio.FIRST_COMPLETED,
                )

                if get_task in done:
                    downloaded, total = get_task.result()
                    yield scribe_pb2.DownloadModelProgress(
                        name=model_name,
                        status=scribe_pb2.DOWNLOAD_DOWNLOADING,
                        downloaded_bytes=downloaded,
                        total_bytes=total,
                    )
                else:
                    get_task.cancel()

                if download_future.done():
                    # Drain any remaining progress events
                    while not queue.empty():
                        downloaded, total = queue.get_nowait()
                        yield scribe_pb2.DownloadModelProgress(
                            name=model_name,
                            status=scribe_pb2.DOWNLOAD_DOWNLOADING,
                            downloaded_bytes=downloaded,
                            total_bytes=total,
                        )
                    break

            # Check download result
            try:
                download_future.result()
                yield scribe_pb2.DownloadModelProgress(
                    name=model_name,
                    status=scribe_pb2.DOWNLOAD_COMPLETE,
                    downloaded_bytes=self.model_manager.AVAILABLE_MODELS.get(model_name, 0),
                    total_bytes=self.model_manager.AVAILABLE_MODELS.get(model_name, 0),
                )
            except DownloadCanceled:
                yield scribe_pb2.DownloadModelProgress(
                    name=model_name,
                    status=scribe_pb2.DOWNLOAD_CANCELED,
                )
            except Exception as e:
                logger.error(f"Download failed for {model_name}: {e}")
                yield scribe_pb2.DownloadModelProgress(
                    name=model_name,
                    status=scribe_pb2.DOWNLOAD_FAILED,
                    error=str(e),
                )
        except Exception as e:
            # Client disconnected (broken pipe) or other stream error.
            # Cancel the download so it doesn't keep running in the background.
            logger.warning(f"Client disconnected during download of {model_name}: {e}")
            self.model_manager.cancel_download(model_name)
            if not download_future.done():
                try:
                    await download_future
                except Exception:
                    pass

    async def CancelDownload(self, request, context):
        """Cancel an active model download"""
        canceled = self.model_manager.cancel_download(request.name)
        return scribe_pb2.CancelDownloadResponse(canceled=canceled)

    async def DeleteModel(self, request, context):
        """Delete a downloaded model"""
        deleted = self.model_manager.delete_model(request.name)
        
        return scribe_pb2.DeleteModelResponse(
            name=request.name,
            deleted=deleted
        )
    
    @staticmethod
    def _on_task_done(task: asyncio.Task):
        """Log unhandled exceptions from background transcription tasks."""
        if task.cancelled():
            return
        exc = task.exception()
        if exc is not None:
            logger.error(f"Background transcription task failed: {exc}", exc_info=exc)
