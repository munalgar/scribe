"""Model management for Whisper models"""

import os
import logging
from pathlib import Path
from typing import Optional, List, Dict, Any

logger = logging.getLogger(__name__)


class ModelManager:
    """Manages Whisper model downloads and caching"""
    
    # Available Whisper models with their approximate sizes
    AVAILABLE_MODELS = {
        "tiny": "39 MB",
        "tiny.en": "39 MB",
        "base": "74 MB",
        "base.en": "74 MB",
        "small": "244 MB",
        "small.en": "244 MB",
        "medium": "769 MB",
        "medium.en": "769 MB",
        "large-v1": "1550 MB",
        "large-v2": "1550 MB",
        "large-v3": "1550 MB",
        "large": "1550 MB",  # Alias for large-v3
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
        
        # Model will be downloaded automatically by faster-whisper
        # when we try to load it for the first time
        logger.info(f"Model {model_name} will be downloaded on first use")
        
        # Return the path where it should be stored
        # faster-whisper will handle the actual download
        return str(self.models_dir)
    
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