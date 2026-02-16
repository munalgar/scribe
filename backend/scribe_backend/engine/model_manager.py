"""Model management for Whisper models"""

import os
import logging
import threading
from pathlib import Path
from typing import Optional, List, Dict, Any, Callable

import huggingface_hub
import requests
from tqdm.auto import tqdm

logger = logging.getLogger(__name__)

# Map short model names to HuggingFace repo IDs (mirrors faster_whisper.utils._MODELS)
_MODEL_REPOS = {
    "tiny.en": "Systran/faster-whisper-tiny.en",
    "tiny": "Systran/faster-whisper-tiny",
    "base.en": "Systran/faster-whisper-base.en",
    "base": "Systran/faster-whisper-base",
    "small.en": "Systran/faster-whisper-small.en",
    "small": "Systran/faster-whisper-small",
    "medium.en": "Systran/faster-whisper-medium.en",
    "medium": "Systran/faster-whisper-medium",
    "large-v1": "Systran/faster-whisper-large-v1",
    "large-v2": "Systran/faster-whisper-large-v2",
    "large-v3": "Systran/faster-whisper-large-v3",
    "large": "Systran/faster-whisper-large-v3",
}

_ALLOW_PATTERNS = [
    "config.json",
    "preprocessor_config.json",
    "model.bin",
    "tokenizer.json",
    "vocabulary.*",
]


class DownloadCanceled(Exception):
    """Raised when a model download is canceled by the user."""


class _ProgressTqdm(tqdm):
    """Custom tqdm that reports progress via a callback and supports cancellation."""

    def __init__(self, *args, progress_callback=None, cancel_event=None, **kwargs):
        self._progress_callback = progress_callback
        self._cancel_event = cancel_event
        super().__init__(*args, **kwargs)

    def update(self, n=1):
        if self._cancel_event and self._cancel_event.is_set():
            raise DownloadCanceled("Download canceled by user")
        super().update(n)
        if self._progress_callback and self.total:
            self._progress_callback(self.n, self.total)


class ModelManager:
    """Manages Whisper model downloads and caching"""
    
    # Available Whisper models with their approximate sizes in bytes
    AVAILABLE_MODELS = {
        "tiny": 39_000_000,      # ~39 MB
        "tiny.en": 39_000_000,   # ~39 MB
        "base": 74_000_000,      # ~74 MB
        "base.en": 74_000_000,   # ~74 MB
        "small": 244_000_000,    # ~244 MB
        "small.en": 244_000_000, # ~244 MB
        "medium": 769_000_000,   # ~769 MB
        "medium.en": 769_000_000,# ~769 MB
        "large-v1": 1_550_000_000,  # ~1.5 GB
        "large-v2": 1_550_000_000,  # ~1.5 GB
        "large-v3": 1_550_000_000,  # ~1.5 GB
        "large": 1_550_000_000,      # ~1.5 GB (alias for large-v3)
    }
    
    def __init__(self, models_dir: Optional[str] = None):
        """
        Initialize model manager.

        Args:
            models_dir: Directory to store models. If None, uses default.
        """
        if models_dir:
            self.models_dir = Path(models_dir)
        else:
            # Default to shared/models in project root
            project_root = Path(__file__).parent.parent.parent.parent
            self.models_dir = project_root / "shared" / "models"

        # Create models directory if it doesn't exist
        self.models_dir.mkdir(parents=True, exist_ok=True)
        logger.info(f"Model directory: {self.models_dir}")

        # Track active downloads for cancellation
        self._active_downloads: Dict[str, threading.Event] = {}
    
    def get_model_path(self, model_name: str) -> Path:
        """Get the path where a model should be stored"""
        return self.models_dir / model_name
    
    def is_model_downloaded(self, model_name: str) -> bool:
        """Check if a model is already downloaded"""
        model_path = self.get_model_path(model_name)
        
        # Check if the model directory exists and has files
        if model_path.exists() and model_path.is_dir():
            # Check for model files (should have at least model.bin or similar)
            model_files = list(model_path.glob("*"))
            return len(model_files) > 0
        
        return False
    
    def list_downloaded_models(self) -> List[str]:
        """List all downloaded models"""
        downloaded = []
        
        for model_name in self.AVAILABLE_MODELS.keys():
            if self.is_model_downloaded(model_name):
                downloaded.append(model_name)
        
        return downloaded
    
    def list_available_models(self) -> List[Dict[str, Any]]:
        """List all available models with their status"""
        models = []
        
        for model_name, size in self.AVAILABLE_MODELS.items():
            models.append({
                "name": model_name,
                "size": size,
                "downloaded": self.is_model_downloaded(model_name)
            })
        
        return models
    
    def ensure_model(self, model_name: str = "base") -> Optional[str]:
        """
        Ensure a model is available, downloading if necessary.
        
        Args:
            model_name: Name of the model to ensure
            
        Returns:
            Path to the model directory if successful, None otherwise
        """
        if model_name not in self.AVAILABLE_MODELS:
            logger.error(f"Unknown model: {model_name}")
            return None
        
        # Check if already downloaded
        if self.is_model_downloaded(model_name):
            logger.info(f"Model {model_name} already downloaded")
            return str(self.get_model_path(model_name))
        
        # Download the model using faster-whisper
        try:
            from faster_whisper import WhisperModel
            logger.info(f"Downloading model {model_name}...")
            
            # This will download the model if not present
            model = WhisperModel(
                model_name,
                device="cpu",  # Use CPU for download
                compute_type="int8",
                download_root=str(self.models_dir)
            )
            
            logger.info(f"Model {model_name} downloaded successfully")
            return str(self.get_model_path(model_name))
            
        except Exception as e:
            logger.error(f"Failed to download model {model_name}: {e}")
            return None
    
    def download_model_with_progress(
        self,
        model_name: str,
        progress_callback: Callable[[int, int], None],
    ) -> str:
        """Download a model with progress reporting.

        Args:
            model_name: Name of the model to download.
            progress_callback: Called with (downloaded_bytes, total_bytes).

        Returns:
            Path to the downloaded model directory.

        Raises:
            ValueError: If the model name is unknown.
            DownloadCanceled: If the download was canceled.
        """
        repo_id = _MODEL_REPOS.get(model_name)
        if repo_id is None:
            raise ValueError(f"Unknown model: {model_name}")

        if self.is_model_downloaded(model_name):
            size = self.AVAILABLE_MODELS.get(model_name, 0)
            progress_callback(size, size)
            return str(self.get_model_path(model_name))

        cancel_event = threading.Event()
        self._active_downloads[model_name] = cancel_event

        # Create a proper tqdm subclass (not a factory function) so that
        # huggingface_hub can call class-level methods like get_lock().
        cb = progress_callback
        ce = cancel_event

        class _BoundProgressTqdm(_ProgressTqdm):
            def __init__(self, *args, **kwargs):
                kwargs.setdefault("progress_callback", cb)
                kwargs.setdefault("cancel_event", ce)
                super().__init__(*args, **kwargs)

        output_dir = str(self.models_dir / model_name)
        try:
            huggingface_hub.snapshot_download(
                repo_id,
                local_dir=output_dir,
                local_dir_use_symlinks=False,
                allow_patterns=_ALLOW_PATTERNS,
                tqdm_class=_BoundProgressTqdm,
            )
            logger.info(f"Model {model_name} downloaded successfully")
            return output_dir
        except DownloadCanceled:
            logger.info(f"Download of model {model_name} canceled")
            # Clean up partial download
            import shutil
            model_path = self.get_model_path(model_name)
            if model_path.exists():
                shutil.rmtree(model_path)
            raise
        finally:
            self._active_downloads.pop(model_name, None)

    def cancel_download(self, model_name: str) -> bool:
        """Cancel an active download.

        Returns:
            True if a download was found and signaled to cancel.
        """
        cancel_event = self._active_downloads.get(model_name)
        if cancel_event is not None:
            cancel_event.set()
            return True
        return False

    def delete_model(self, model_name: str) -> bool:
        """
        Delete a downloaded model.
        
        Args:
            model_name: Name of the model to delete
            
        Returns:
            True if successful, False otherwise
        """
        if model_name not in self.AVAILABLE_MODELS:
            logger.error(f"Unknown model: {model_name}")
            return False
        
        model_path = self.get_model_path(model_name)
        
        if not model_path.exists():
            logger.info(f"Model {model_name} not found")
            return False
        
        try:
            # Remove the model directory and all its contents
            import shutil
            shutil.rmtree(model_path)
            logger.info(f"Deleted model {model_name}")
            return True
        except Exception as e:
            logger.error(f"Failed to delete model {model_name}: {e}")
            return False
    
    def get_model_info(self, model_name: str) -> Optional[Dict[str, Any]]:
        """Get information about a specific model"""
        if model_name not in self.AVAILABLE_MODELS:
            return None
        
        return {
            "name": model_name,
            "size": self.AVAILABLE_MODELS[model_name],
            "downloaded": self.is_model_downloaded(model_name),
            "path": str(self.get_model_path(model_name)) if self.is_model_downloaded(model_name) else None
        }