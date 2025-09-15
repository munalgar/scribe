"""GPU detection and capability checking"""

import logging
import subprocess
import platform
from typing import Optional

logger = logging.getLogger(__name__)


def detect_gpu() -> bool:
    """
    Detect if GPU acceleration is available.
    Returns True if GPU can be used for inference.
    """
    system = platform.system()
    
    # Try NVIDIA GPU first (cross-platform)
    if check_nvidia_gpu():
        logger.info("NVIDIA GPU detected")
        return True
    
    # Check for Apple Silicon on macOS
    if system == "Darwin" and check_apple_silicon():
        logger.info("Apple Silicon detected")
        return True
    
    # Check for AMD GPU on Linux
    if system == "Linux" and check_amd_gpu():
        logger.info("AMD GPU detected")
        return True
    
    # Check for DirectML on Windows
    if system == "Windows" and check_directml():
        logger.info("DirectML support detected")
        return True
    
    logger.info("No GPU acceleration available, will use CPU")
    return False


def check_nvidia_gpu() -> bool:
    """Check for NVIDIA GPU with CUDA support"""
    try:
        # Try to run nvidia-smi
        result = subprocess.run(
            ['nvidia-smi', '--query-gpu=name', '--format=csv,noheader'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            logger.debug(f"NVIDIA GPU found: {result.stdout.strip()}")
            
            # Try to import and check CUDA availability
            try:
                # This will be available when faster-whisper is installed
                import torch
                if torch.cuda.is_available():
                    logger.debug(f"CUDA is available with {torch.cuda.device_count()} device(s)")
                    return True
            except ImportError:
                # Torch not installed yet, assume CUDA will work if nvidia-smi works
                return True
                
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        pass
    
    return False


def check_apple_silicon() -> bool:
    """Check for Apple Silicon (M1/M2/M3) on macOS"""
    try:
        result = subprocess.run(
            ['sysctl', '-n', 'machdep.cpu.brand_string'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            cpu_brand = result.stdout.strip().lower()
            if 'apple' in cpu_brand and ('m1' in cpu_brand or 'm2' in cpu_brand or 'm3' in cpu_brand):
                logger.debug(f"Apple Silicon detected: {result.stdout.strip()}")
                return True
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        pass
    
    return False


def check_amd_gpu() -> bool:
    """Check for AMD GPU with ROCm support on Linux"""
    try:
        # Check for ROCm installation
        result = subprocess.run(
            ['rocm-smi', '--showid'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            logger.debug("AMD GPU with ROCm detected")
            return True
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        pass
    
    return False


def check_directml() -> bool:
    """Check for DirectML support on Windows"""
    try:
        import platform
        if platform.system() == "Windows":
            # Check Windows version (needs Windows 10 1903+)
            import sys
            if sys.getwindowsversion().build >= 18362:
                logger.debug("DirectML support available on Windows")
                return True
    except Exception:
        pass
    
    return False


def get_compute_type(prefer_gpu: bool = True) -> str:
    """
    Get the optimal compute type for the current hardware.
    
    Returns:
        str: Compute type string for faster-whisper
             Options: "int8", "float16", "float32", "int8_float16", "int8_float32"
    """
    if prefer_gpu and detect_gpu():
        # GPU detected, use float16 for best performance
        return "float16"
    else:
        # CPU mode, use int8 for best performance
        return "int8"


def get_device() -> str:
    """
    Get the device to use for inference.
    
    Returns:
        str: Device string ("cuda" or "cpu")
    """
    if detect_gpu():
        return "cuda"
    return "cpu"