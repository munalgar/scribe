#!/usr/bin/env python3
"""Quick test script to verify backend components work"""

import asyncio
import logging
import sys
from pathlib import Path

# Add project/backend roots to path for runtime and type checking
PROJECT_ROOT = Path(__file__).resolve().parent.parent
BACKEND_ROOT = PROJECT_ROOT / "backend"

for p in (PROJECT_ROOT, BACKEND_ROOT):
    p_str = str(p)
    if p_str not in sys.path:
        sys.path.insert(0, p_str)

def _load_backend_symbols():
    import importlib

    candidates = ("backend.scribe_backend", "scribe_backend")
    last_error = None

    for base in candidates:
        try:
            dao_mod = importlib.import_module(f"{base}.db.dao")
            gpu_mod = importlib.import_module(f"{base}.engine.gpu")
            mm_mod = importlib.import_module(f"{base}.engine.model_manager")
            return (
                dao_mod.Database,
                gpu_mod.detect_gpu,
                gpu_mod.get_device,
                gpu_mod.get_compute_type,
                mm_mod.ModelManager,
            )
        except ModuleNotFoundError as e:
            last_error = e
            continue

    raise ModuleNotFoundError(
        "Could not import backend modules from either 'backend.scribe_backend' or 'scribe_backend'"
    ) from last_error


Database, detect_gpu, get_device, get_compute_type, ModelManager = _load_backend_symbols()

logging.basicConfig(level=logging.INFO)


async def test_backend():
    """Test backend components"""
    print("=" * 60)
    print("Scribe Backend Component Test")
    print("=" * 60)

    # Test GPU detection
    print("\n1. GPU Detection:")
    print(f"   GPU Available: {detect_gpu()}")
    print(f"   Device: {get_device()}")
    print(f"   Compute Type: {get_compute_type()}")

    # Test Database
    print("\n2. Database:")
    try:
        db = Database()
        settings = await db.get_all_settings()
        print(f"   Database initialized successfully")
        print(f"   Settings: {settings}")

        # Test job creation
        job_id = await db.new_job_id()
        print(f"   Generated job ID: {job_id}")
    except Exception as e:
        print(f"   Database error: {e}")

    # Test Model Manager
    print("\n3. Model Manager:")
    try:
        mm = ModelManager()
        models = mm.list_models()
        print(f"   Found {len(models)} model(s)")
        for model in models:
            status = "Downloaded" if model.get("downloaded", False) else "Not downloaded"
            print(f"   [{status}] {model.get('name', 'unknown')} ({model.get('size', 'unknown')})")
    except Exception as e:
        print(f"   Model manager error: {e}")

    # Test Proto imports
    print("\n4. gRPC Proto Files:")
    try:
        import importlib

        for proto_base in ("backend.scribe_backend.proto", "scribe_backend.proto"):
            try:
                importlib.import_module(f"{proto_base}.scribe_pb2")
                importlib.import_module(f"{proto_base}.scribe_pb2_grpc")
                print("   ✓ Proto files imported successfully")
                break
            except ModuleNotFoundError:
                continue
        else:
            raise ModuleNotFoundError(
                "Could not import proto modules from either 'backend.scribe_backend.proto' or 'scribe_backend.proto'"
            )
    except ImportError as e:
        print(f"   ✗ Proto import failed: {e}")

    print("\n" + "=" * 60)
    print("Test complete!")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(test_backend())
