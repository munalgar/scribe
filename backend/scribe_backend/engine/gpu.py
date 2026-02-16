"""GPU detection and capability checking"""

import logging
import subprocess
import platform
import importlib
from typing import Optional

logger = logging.getLogger(__name__)

# Cache GPU detection result to avoid repeated subprocess calls.
# Stores the detected GPU type: "nvidia", "apple_silicon", "amd", "directml", or None.
_gpu_type: Optional[str] = None
_gpu_type_checked: bool = False


def detect_gpu() -> bool:
    """
    Detect if GPU acceleration is available.
    Returns True if GPU can be used for inference.
    Result is cached after first call.
    """
    return detect_gpu_type() is not None


def detect_gpu_type() -> Optional[str]:
    """
    Detect the type of GPU acceleration available.
    Returns "nvidia", "apple_silicon", "amd", "directml", or None.
    Result is cached after first call.
    """
    global _gpu_type, _gpu_type_checked
    if _gpu_type_checked:
        return _gpu_type

    _gpu_type_checked = True
    system = platform.system()

    # Try NVIDIA GPU first (cross-platform)
    if check_nvidia_gpu():
        logger.info("NVIDIA GPU detected")
        _gpu_type = "nvidia"
        return _gpu_type

    # Check for Apple Silicon on macOS
    if system == "Darwin" and check_apple_silicon():
        logger.info("Apple Silicon detected")
        _gpu_type = "apple_silicon"
        return _gpu_type

    # Check for AMD GPU on Linux
    if system == "Linux" and check_amd_gpu():
        logger.info("AMD GPU detected")
        _gpu_type = "amd"
        return _gpu_type

    # Check for DirectML on Windows
    if system == "Windows" and check_directml():
        logger.info("DirectML support detected")
        _gpu_type = "directml"
        return _gpu_type

    logger.info("No GPU acceleration available, will use CPU")
    return _gpu_type


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
                # Torch is optional; import lazily to avoid static import errors
                torch = importlib.import_module("torch")
                if torch.cuda.is_available():
                    logger.debug(f"CUDA is available with {torch.cuda.device_count()} device(s)")
                    return True
            except ImportError:
                # Torch not installed yet, assume CUDA will work if nvidia-smi works
                return True
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
            if 'apple' in cpu_brand and any(f'm{i}' in cpu_brand for i in range(1, 10)):
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
        # Check Windows version (needs Windows 10 1903+)
        # platform.version() returns a string like "10.0.19045" on Windows.
        version = platform.version()
        parts = version.split(".")
        build = int(parts[2]) if len(parts) >= 3 else 0
        if build >= 18362:
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
    if not prefer_gpu:
        return "int8"

    gpu_type = detect_gpu_type()
    if gpu_type == "nvidia":
        return "float16"
    elif gpu_type == "apple_silicon":
        # CTranslate2 on Apple Silicon runs on CPU; int8 is fastest
        return "int8"
    elif gpu_type in ("amd", "directml"):
        return "float16"
    else:
        return "int8"


def get_device() -> str:
    """
    Get the device to use for inference.

    Returns:
        str: Device string for CTranslate2/faster-whisper ("cuda", "cpu", or "auto")
    """
    gpu_type = detect_gpu_type()
    if gpu_type == "nvidia":
        return "cuda"
    # Apple Silicon, AMD ROCm, DirectML, and no-GPU all use CPU for CTranslate2
    return "cpu"