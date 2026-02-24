"""Transcription engine using faster-whisper"""

import asyncio
import collections
import logging
import os
from concurrent.futures import ThreadPoolExecutor
from typing import Optional, Dict, Any, Callable
import time

from faster_whisper import WhisperModel
import requests

from ..db.dao import Database
from ..proto import scribe_pb2
from .gpu import get_device, get_compute_type
from .model_manager import ModelManager

logger = logging.getLogger(__name__)

# Type alias for the event callback: (job_id, event_dict) -> None
# event_dict keys: status, progress, segment (optional), error (optional), final (optional)
EventCallback = Callable[[str, Dict[str, Any]], None]

# Maximum total estimated memory (in bytes) the model cache may occupy.
# Default 2 GB — enough for e.g. one large + one small, or several smaller
# models, while preventing unbounded growth.
_MODEL_CACHE_BUDGET = int(os.environ.get(
    'SCRIBE_MODEL_CACHE_BYTES', 2 * 1024 * 1024 * 1024
))
_TRANSLATE_API_URL = "https://translate.googleapis.com/translate_a/single"
_SUPPORTED_TRANSLATION_LANGUAGES = {
    "en", "es", "fr", "de", "it", "pt", "ja", "zh", "ko"
}


class _ModelCache:
    """LRU model cache with a memory budget.

    Keeps loaded WhisperModel instances keyed by
    ``(model_name, device, compute_type)`` and evicts the
    least-recently-used entry when loading a new model would exceed
    the budget.

    The *estimated* size of each model is taken from
    ``ModelManager.AVAILABLE_MODELS``; it doesn't reflect actual
    process RSS but is a good-enough proxy for eviction decisions.
    """

    def __init__(self, budget: int):
        self._budget = budget
        # OrderedDict gives us O(1) move-to-end (LRU touch) and
        # pop-from-front (evict oldest).
        self._entries: collections.OrderedDict[
            tuple, tuple[WhisperModel, int]  # (model, estimated_bytes)
        ] = collections.OrderedDict()
        self._current_bytes = 0

    def get(self, key: tuple) -> Optional[WhisperModel]:
        """Return a cached model (and mark it as recently used), or None."""
        entry = self._entries.get(key)
        if entry is None:
            return None
        self._entries.move_to_end(key)  # mark as most-recently-used
        return entry[0]

    def put(self, key: tuple, model: WhisperModel, estimated_bytes: int):
        """Insert a model, evicting LRU entries if the budget is exceeded."""
        # If this exact key already exists, remove the old entry first.
        if key in self._entries:
            _, old_bytes = self._entries.pop(key)
            self._current_bytes -= old_bytes

        # Evict LRU entries until there is room (or cache is empty).
        while (
            self._entries
            and self._current_bytes + estimated_bytes > self._budget
        ):
            evicted_key, (_, evicted_bytes) = self._entries.popitem(last=False)
            self._current_bytes -= evicted_bytes
            logger.info(
                f"Evicted model {evicted_key[0]} from cache "
                f"({evicted_bytes / 1_000_000:.0f} MB freed)"
            )

        self._entries[key] = (model, estimated_bytes)
        self._current_bytes += estimated_bytes
        logger.info(
            f"Model cache: {len(self._entries)} model(s), "
            f"~{self._current_bytes / 1_000_000:.0f} MB used / "
            f"{self._budget / 1_000_000:.0f} MB budget"
        )

    def clear(self):
        """Drop all cached models."""
        self._entries.clear()
        self._current_bytes = 0


class TranscriptionEngine:
    """Handles audio transcription using Whisper models"""

    def __init__(self, db: Database, model_manager: ModelManager):
        """
        Initialize transcription engine.

        Args:
            db: Database instance for storing results
            model_manager: Model manager for handling Whisper models
        """
        self.db = db
        self.model_manager = model_manager
        self.active_jobs: Dict[str, bool] = {}  # Track cancellation
        self._executor = ThreadPoolExecutor(max_workers=1)
        self._model_cache = _ModelCache(_MODEL_CACHE_BUDGET)
        
    async def run_job(self, job_id: str, audio_path: str,
                     model_name: str = "base", language: str = None,
                     translate: bool = False, translate_to_language: str = None,
                     initial_prompt: str = None,
                     enable_gpu: bool = True,
                     on_event: EventCallback = None) -> bool:
        """
        Run a transcription job.

        Args:
            job_id: Unique job identifier
            audio_path: Path to audio file
            model_name: Whisper model to use
            language: Source language code (None for auto-detect)
            translate: Whether to translate to English
            translate_to_language: Optional translation target language code
            initial_prompt: Optional prompt to guide transcription
            enable_gpu: Whether to use GPU if available
            on_event: Optional callback fired for each transcription event

        Returns:
            True if successful, False otherwise
        """
        target_language = (
            (translate_to_language or ("en" if translate else None)) or None
        )
        if target_language is not None:
            target_language = target_language.lower()

        logger.info(f"Starting transcription job {job_id}")
        logger.info(f"Audio file: {audio_path}")
        logger.info(
            f"Model: {model_name}, Language: {language}, "
            f"Translate target: {target_language or 'off'}"
        )

        def _emit(status: int, progress: float = 0.0, **kwargs):
            """Fire the event callback if one was provided."""
            if on_event is not None:
                on_event(job_id, {'status': status, 'progress': progress, **kwargs})

        # Mark job as active
        self.active_jobs[job_id] = True

        try:
            if target_language is not None and (
                target_language not in _SUPPORTED_TRANSLATION_LANGUAGES
            ):
                raise ValueError(
                    f"Unsupported translation language: {target_language}"
                )

            # Validate audio file exists
            if not os.path.exists(audio_path):
                error_msg = f"Audio file not found: {audio_path}"
                logger.error(error_msg)
                await self.db.update_job_status(job_id, scribe_pb2.JobStatus.FAILED, error_msg)
                _emit(scribe_pb2.JobStatus.FAILED, error=error_msg, final=True)
                return False

            # Update status to RUNNING
            await self.db.update_job_status(job_id, scribe_pb2.JobStatus.RUNNING)
            _emit(scribe_pb2.JobStatus.RUNNING)

            # Ensure model is available (blocking I/O, run in executor)
            loop = asyncio.get_running_loop()
            model_path = await loop.run_in_executor(
                self._executor, self.model_manager.ensure_model, model_name
            )
            if not model_path:
                error_msg = f"Failed to load model: {model_name}"
                logger.error(error_msg)
                await self.db.update_job_status(job_id, scribe_pb2.JobStatus.FAILED, error_msg)
                _emit(scribe_pb2.JobStatus.FAILED, error=error_msg, final=True)
                return False

            # Determine device and compute type
            device = get_device() if enable_gpu else "cpu"
            compute_type = get_compute_type(enable_gpu)

            logger.info(f"Using device: {device}, compute_type: {compute_type}")

            # Load model (with caching)
            model = await self._get_or_load_model(
                model_name, device, compute_type
            )

            # Get audio duration for progress calculation (non-blocking)
            loop = asyncio.get_running_loop()
            audio_duration = await loop.run_in_executor(
                self._executor, self._get_audio_duration, audio_path
            )
            if audio_duration > 0:
                await self.db.update_job_audio_duration(job_id, audio_duration)

            # Run blocking transcription in executor
            logger.info("Starting transcription...")
            start_time = time.time()

            def _transcribe():
                return model.transcribe(
                    audio_path,
                    language=language,
                    task="translate" if target_language == "en" else "transcribe",
                    initial_prompt=initial_prompt,
                    vad_filter=True,
                    vad_parameters=dict(min_silence_duration_ms=500),
                )

            segments_iter, info = await loop.run_in_executor(
                self._executor, _transcribe
            )

            # Process segments (iterating the generator is also blocking)
            segment_count = 0
            processed_duration = 0.0
            segment_batch = []
            translation_cache: Dict[str, str] = {}

            def _next_segment(it):
                """Get next segment from iterator, returns None at end."""
                try:
                    return next(it)
                except StopIteration:
                    return None

            while True:
                if not self.active_jobs.get(job_id, False):
                    logger.info(f"Job {job_id} was cancelled")
                    await self.db.update_job_status(job_id, scribe_pb2.JobStatus.CANCELED)
                    _emit(scribe_pb2.JobStatus.CANCELED, final=True)
                    return False

                segment = await loop.run_in_executor(
                    self._executor, _next_segment, segments_iter
                )
                if segment is None:
                    break

                segment_data = {
                    'idx': segment_count,
                    'start': segment.start,
                    'end': segment.end,
                    'text': segment.text.strip(),
                }
                if target_language and target_language != "en" and segment_data['text']:
                    source_text = segment_data['text']
                    translated_text = translation_cache.get(source_text)
                    if translated_text is None:
                        translated_text = await loop.run_in_executor(
                            self._executor,
                            self._translate_text,
                            source_text,
                            target_language,
                        )
                        translation_cache[source_text] = translated_text
                    segment_data['text'] = translated_text

                segment_batch.append(segment_data)
                segment_count += 1
                processed_duration = segment.end

                # Emit event for each segment immediately
                progress = min(processed_duration / audio_duration, 1.0) if audio_duration > 0 else 0.0
                _emit(scribe_pb2.JobStatus.RUNNING, progress=progress, segment=segment_data)

                # Flush batch to DB every 10 segments
                if len(segment_batch) >= 10:
                    await self.db.insert_segments_batch(job_id, segment_batch)
                    segment_batch = []
                    await self.db.update_job_progress(job_id, progress)

            # Flush remaining segments
            if segment_batch:
                await self.db.insert_segments_batch(job_id, segment_batch)
                if audio_duration > 0:
                    progress = min(processed_duration / audio_duration, 1.0)
                    await self.db.update_job_progress(job_id, progress)

            # Mark as completed
            elapsed_time = time.time() - start_time
            logger.info(f"Transcription completed in {elapsed_time:.2f} seconds")
            logger.info(f"Processed {segment_count} segments")

            await self.db.update_job_status(job_id, scribe_pb2.JobStatus.COMPLETED)
            await self.db.update_job_progress(job_id, 1.0)
            _emit(scribe_pb2.JobStatus.COMPLETED, progress=1.0, final=True)

            return True

        except Exception as e:
            error_msg = f"Transcription failed: {str(e)}"
            logger.error(error_msg, exc_info=True)
            await self.db.update_job_status(job_id, scribe_pb2.JobStatus.FAILED, error_msg)
            _emit(scribe_pb2.JobStatus.FAILED, error=error_msg, final=True)
            return False

        finally:
            # Remove from active jobs
            self.active_jobs.pop(job_id, None)

    def _translate_text(self, text: str, target_language: str) -> str:
        """Translate text to a target language using Google Translate API."""
        if not text.strip():
            return text

        response = requests.get(
            _TRANSLATE_API_URL,
            params={
                "client": "gtx",
                "sl": "auto",
                "tl": target_language,
                "dt": "t",
                "q": text,
            },
            timeout=10,
        )
        response.raise_for_status()

        payload = response.json()
        translated_chunks = payload[0] if payload and len(payload) > 0 else []
        translated_text = "".join(
            chunk[0] for chunk in translated_chunks if chunk and chunk[0]
        ).strip()

        if not translated_text:
            raise RuntimeError("Translation service returned an empty result")
        return translated_text
    
    async def _get_or_load_model(self, model_name: str, device: str,
                                compute_type: str) -> WhisperModel:
        """Load a WhisperModel, using a memory-budgeted LRU cache."""
        cache_key = (model_name, device, compute_type)

        cached = self._model_cache.get(cache_key)
        if cached is not None:
            logger.info(f"Using cached model: {model_name} ({device}/{compute_type})")
            return cached

        loop = asyncio.get_running_loop()

        # Resolve to the canonical path (shared/models/<name>) so
        # faster_whisper loads from the same directory that
        # ModelManager.is_model_downloaded() checks.
        model_path = self.model_manager.get_model_path(model_name)
        model_id = str(model_path) if model_path.exists() else model_name

        def _load():
            try:
                return WhisperModel(
                    model_id,
                    device=device,
                    compute_type=compute_type,
                    download_root=str(self.model_manager.models_dir),
                )
            except Exception as e:
                if device != "cpu":
                    logger.warning(f"GPU init failed, falling back to CPU: {e}")
                    return WhisperModel(
                        model_id,
                        device="cpu",
                        compute_type="int8",
                        download_root=str(self.model_manager.models_dir),
                    )
                raise

        model = await loop.run_in_executor(self._executor, _load)

        estimated_bytes = self.model_manager.AVAILABLE_MODELS.get(
            model_name, 0
        )
        self._model_cache.put(cache_key, model, estimated_bytes)
        return model

    def _get_audio_duration(self, audio_path: str) -> float:
        """
        Get duration of audio file in seconds.
        
        Args:
            audio_path: Path to audio file
            
        Returns:
            Duration in seconds, or 0 if unable to determine
        """
        try:
            import subprocess
            import json
            
            # Use ffprobe to get duration
            cmd = [
                'ffprobe',
                '-v', 'quiet',
                '-print_format', 'json',
                '-show_format',
                audio_path
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                duration = float(data.get('format', {}).get('duration', 0))
                logger.debug(f"Audio duration: {duration:.2f} seconds")
                return duration
                
        except Exception as e:
            logger.warning(f"Could not determine audio duration: {e}")
            
        return 0.0
    
    async def cancel_job(self, job_id: str) -> bool:
        """
        Cancel an active transcription job.
        
        Args:
            job_id: Job identifier to cancel
            
        Returns:
            True if job was active and cancelled, False otherwise
        """
        if job_id in self.active_jobs:
            logger.info(f"Cancelling job {job_id}")
            self.active_jobs[job_id] = False
            await self.db.cancel_job(job_id)
            return True
        return False
