"""Transcription engine using faster-whisper"""

import asyncio
import logging
import os
from pathlib import Path
from typing import Optional, AsyncGenerator, Dict, Any
import time

from faster_whisper import WhisperModel

from ..db.dao import Database
from .gpu import get_device, get_compute_type
from .model_manager import ModelManager

logger = logging.getLogger(__name__)


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
        
    async def run_job(self, job_id: str, audio_path: str, 
                     model_name: str = "base", language: str = None,
                     translate: bool = False, initial_prompt: str = None,
                     enable_gpu: bool = True) -> bool:
        """
        Run a transcription job.
        
        Args:
            job_id: Unique job identifier
            audio_path: Path to audio file
            model_name: Whisper model to use
            language: Source language code (None for auto-detect)
            translate: Whether to translate to English
            initial_prompt: Optional prompt to guide transcription
            enable_gpu: Whether to use GPU if available
            
        Returns:
            True if successful, False otherwise
        """
        logger.info(f"Starting transcription job {job_id}")
        logger.info(f"Audio file: {audio_path}")
        logger.info(f"Model: {model_name}, Language: {language}, Translate: {translate}")
        
        # Mark job as active
        self.active_jobs[job_id] = True
        
        try:
            # Validate audio file exists
            if not os.path.exists(audio_path):
                error_msg = f"Audio file not found: {audio_path}"
                logger.error(error_msg)
                await self.db.update_job_status(job_id, 4, error_msg)  # 4 = FAILED
                return False
            
            # Update status to RUNNING
            await self.db.update_job_status(job_id, 2)  # 2 = RUNNING
            
            # Ensure model is available
            model_path = self.model_manager.ensure_model(model_name)
            if not model_path:
                error_msg = f"Failed to load model: {model_name}"
                logger.error(error_msg)
                await self.db.update_job_status(job_id, 4, error_msg)
                return False
            
            # Determine device and compute type
            device = get_device() if enable_gpu else "cpu"
            compute_type = get_compute_type(enable_gpu)
            
            logger.info(f"Using device: {device}, compute_type: {compute_type}")
            
            # Load model
            try:
                model = WhisperModel(
                    model_name,
                    device=device,
                    compute_type=compute_type,
                    download_root=str(self.model_manager.models_dir)
                )
            except Exception as e:
                # Fallback to CPU if GPU fails
                if device != "cpu":
                    logger.warning(f"GPU initialization failed, falling back to CPU: {e}")
                    device = "cpu"
                    compute_type = "int8"
                    model = WhisperModel(
                        model_name,
                        device=device,
                        compute_type=compute_type,
                        download_root=str(self.model_manager.models_dir)
                    )
                else:
                    raise
            
            # Get audio duration for progress calculation
            audio_duration = self._get_audio_duration(audio_path)
            
            # Transcribe audio
            logger.info("Starting transcription...")
            start_time = time.time()
            
            segments, info = model.transcribe(
                audio_path,
                language=language,
                task="translate" if translate else "transcribe",
                initial_prompt=initial_prompt,
                vad_filter=True,  # Voice activity detection
                vad_parameters=dict(
                    min_silence_duration_ms=500
                )
            )
            
            # Process segments
            segment_count = 0
            processed_duration = 0.0
            
            async for segment_data in self._process_segments(
                job_id, segments, audio_duration
            ):
                if not self.active_jobs.get(job_id, False):
                    # Job was cancelled
                    logger.info(f"Job {job_id} was cancelled")
                    await self.db.update_job_status(job_id, 5)  # 5 = CANCELED
                    return False
                
                segment_count += 1
                processed_duration = segment_data['end']
                
                # Update progress
                if audio_duration > 0:
                    progress = min(processed_duration / audio_duration, 1.0)
                    await self.db.update_job_progress(job_id, progress)
            
            # Mark as completed
            elapsed_time = time.time() - start_time
            logger.info(f"Transcription completed in {elapsed_time:.2f} seconds")
            logger.info(f"Processed {segment_count} segments")
            
            await self.db.update_job_status(job_id, 3)  # 3 = COMPLETED
            await self.db.update_job_progress(job_id, 1.0)
            
            return True
            
        except Exception as e:
            error_msg = f"Transcription failed: {str(e)}"
            logger.error(error_msg, exc_info=True)
            await self.db.update_job_status(job_id, 4, error_msg)  # 4 = FAILED
            return False
            
        finally:
            # Remove from active jobs
            self.active_jobs.pop(job_id, None)
    
    async def _process_segments(self, job_id: str, segments, 
                               audio_duration: float) -> AsyncGenerator[Dict[str, Any], None]:
        """
        Process and store transcription segments.
        
        Args:
            job_id: Job identifier
            segments: Iterator of segments from faster-whisper
            audio_duration: Total audio duration for progress calculation
            
        Yields:
            Segment data dictionaries
        """
        idx = 0
        for segment in segments:
            # Check for cancellation
            if not self.active_jobs.get(job_id, False):
                break
            
            segment_data = {
                'idx': idx,
                'start': segment.start,
                'end': segment.end,
                'text': segment.text.strip()
            }
            
            # Store segment in database
            await self.db.insert_segment(
                job_id=job_id,
                idx=idx,
                start=segment.start,
                end=segment.end,
                text=segment.text.strip()
            )
            
            logger.debug(f"Segment {idx}: [{segment.start:.2f}s - {segment.end:.2f}s] {segment.text[:50]}...")
            
            idx += 1
            yield segment_data
    
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
            
            result = subprocess.run(cmd, capture_output=True, text=True)
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