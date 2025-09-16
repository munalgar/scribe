"""gRPC Service implementation for Scribe"""

import asyncio
import logging
import os
from typing import AsyncIterator
from pathlib import Path

import grpc

# Import generated protobuf classes (will be created by gen_proto.sh)
try:
    from .proto import scribe_pb2
    from .proto import scribe_pb2_grpc
except ImportError:
    # Proto files not generated yet
    import sys
    sys.path.append(str(Path(__file__).parent.parent))
    try:
        from scribe_backend.proto import scribe_pb2
        from scribe_backend.proto import scribe_pb2_grpc
    except ImportError:
        # Create dummy classes for initial development
        class scribe_pb2:
            pass
        class scribe_pb2_grpc:
            class ScribeServicer:
                pass

from .db.dao import Database
from .engine.model_manager import ModelManager
from .engine.transcription import TranscriptionEngine

logger = logging.getLogger(__name__)


class ScribeService(scribe_pb2_grpc.ScribeServicer):
    """Implementation of the Scribe gRPC service"""
    
    def __init__(self):
        """Initialize the service with database and transcription engine"""
        self.db = Database()
        self.model_manager = ModelManager()
        self.engine = TranscriptionEngine(self.db, self.model_manager)
        self.active_streams = {}
        
        # Start background task for managing streams
        asyncio.create_task(self._cleanup_streams())
    
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
        logger.info(f"job_id={request.job_id or 'new'} StartTranscription received")
        
        # Extract audio path
        if not request.audio.HasField('file_path'):
            await context.abort(
                grpc.StatusCode.INVALID_ARGUMENT,
                "Only file_path audio source is supported"
            )
            
        audio_path = request.audio.file_path
        
        # Validate file exists
        if not os.path.exists(audio_path):
            await context.abort(
                grpc.StatusCode.NOT_FOUND,
                f"Audio file not found: {audio_path}"
            )
        
        # Generate job ID if not provided
        job_id = request.job_id if request.job_id else await self.db.new_job_id()
        
        # Get transcription options
        options = request.options if request.HasField('options') else None
        model_name = options.model if options and options.model else "base"
        language = options.language if options and options.language else None
        translate = options.translate_to_english if options else False
        initial_prompt = options.initial_prompt if options and options.initial_prompt else None
        enable_gpu = options.enable_gpu if options else True
        
        # Create job in database
        success = await self.db.create_job(
            job_id=job_id,
            audio_path=audio_path,
            model=model_name,
            language=language or "auto",
            translate=translate
        )
        
        if not success:
            await context.abort(
                grpc.StatusCode.INTERNAL,
                "Failed to create job in database"
            )
        
        # Start transcription in background
        asyncio.create_task(
            self.engine.run_job(
                job_id=job_id,
                audio_path=audio_path,
                model_name=model_name,
                language=language,
                translate=translate,
                initial_prompt=initial_prompt,
                enable_gpu=enable_gpu
            )
        )
        
        return scribe_pb2.StartTranscriptionResponse(
            job_id=job_id,
            status=scribe_pb2.JobStatus.QUEUED
        )
    
    async def StreamTranscription(self, request, context) -> AsyncIterator:
        """Stream transcription events for a job"""
        job_id = request.job_id
        logger.info(f"Streaming transcription for job {job_id}")
        
        # Check if job exists
        job = await self.db.get_job(job_id)
        if not job:
            await context.abort(
                grpc.StatusCode.NOT_FOUND,
                f"Job not found: {job_id}"
            )
        
        # Track this stream
        self.active_streams[job_id] = True
        
        try:
            last_segment_idx = -1
            last_heartbeat = 0.0
            
            while self.active_streams.get(job_id, False):
                # Stop if client disconnected
                if context.done():
                    break
                # Get current job status
                job = await self.db.get_job(job_id)
                if not job:
                    break
                
                # Send status update
                event = scribe_pb2.TranscriptionEvent(
                    job_id=job_id,
                    status=job['status'],
                    progress=job.get('progress', 0.0)
                )
                
                if job.get('error'):
                    event.error = job['error']
                
                # Get new segments
                segments = await self.db.get_segments(job_id)
                for segment in segments:
                    if segment['idx'] > last_segment_idx:
                        segment_event = scribe_pb2.TranscriptionEvent(
                            job_id=job_id,
                            status=job['status'],
                            progress=job.get('progress', 0.0),
                            segment=scribe_pb2.Segment(
                                index=segment['idx'],
                                start=segment['start'],
                                end=segment['end'],
                                text=segment['text']
                            )
                        )
                        yield segment_event
                        last_segment_idx = segment['idx']
                
                # Check if job is terminal
                if job['status'] in [3, 4, 5]:  # COMPLETED, FAILED, CANCELED
                    yield event
                    break
                
                # Periodic heartbeat (no new segments)
                # Yield at least every second so clients see progress updates
                import time as _time
                now = _time.time()
                if now - last_heartbeat >= 1.0:
                    yield event
                    last_heartbeat = now

                # Wait before checking again
                await asyncio.sleep(0.5)
                
        finally:
            # Clean up stream tracking
            self.active_streams.pop(job_id, None)
    
    async def GetJob(self, request, context):
        """Get information about a specific job"""
        job = await self.db.get_job(request.job_id)
        
        if not job:
            await context.abort(
                grpc.StatusCode.NOT_FOUND,
                f"Job not found: {request.job_id}"
            )
        
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
            summary = scribe_pb2.JobSummary(
                job_id=job['job_id'],
                status=job['status'],
                created_at=job['created_at'],
                updated_at=job['updated_at']
            )
            if job.get('error'):
                summary.error = job['error']
            response.jobs.append(summary)
        
        return response
    
    async def CancelJob(self, request, context):
        """Cancel a running job"""
        # Try to cancel in engine first
        cancelled = await self.engine.cancel_job(request.job_id)
        
        if not cancelled:
            # Job might not be running, update status in DB
            job = await self.db.get_job(request.job_id)
            if job and job['status'] in [1, 2]:  # QUEUED or RUNNING
                await self.db.cancel_job(request.job_id)
                cancelled = True
        
        return scribe_pb2.CancelJobResponse(canceled=cancelled)
    
    async def DeleteJob(self, request, context):
        """Delete a job and its data"""
        deleted = await self.db.delete_job(request.job_id)
        return scribe_pb2.DeleteJobResponse(deleted=deleted)
    
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
            # Update model manager
            self.model_manager = ModelManager(settings.models_dir)
            
        await self.db.set_setting('prefer_gpu', str(settings.prefer_gpu))
        
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
    
    async def DownloadModel(self, request, context):
        """Start downloading a model"""
        model_name = request.name
        
        if model_name not in self.model_manager.AVAILABLE_MODELS:
            await context.abort(
                grpc.StatusCode.NOT_FOUND,
                f"Unknown model: {model_name}"
            )
        
        # Check if already downloaded
        if self.model_manager.is_model_downloaded(model_name):
            logger.info(f"Model {model_name} already downloaded")
            return scribe_pb2.DownloadModelResponse(
                name=model_name,
                started=False  # Already exists
            )
        
        # Trigger download
        logger.info(f"Starting download of model {model_name}")
        model_path = self.model_manager.ensure_model(model_name)
        
        if model_path:
            return scribe_pb2.DownloadModelResponse(
                name=model_name,
                started=True
            )
        else:
            await context.abort(
                grpc.StatusCode.INTERNAL,
                f"Failed to download model {model_name}"
            )
    
    async def DeleteModel(self, request, context):
        """Delete a downloaded model"""
        deleted = self.model_manager.delete_model(request.name)
        
        return scribe_pb2.DeleteModelResponse(
            name=request.name,
            deleted=deleted
        )
    
    async def _cleanup_streams(self):
        """Periodically clean up inactive streams"""
        while True:
            await asyncio.sleep(60)  # Check every minute
            # Clean up any streams that have been inactive
            # This is a placeholder for more sophisticated cleanup