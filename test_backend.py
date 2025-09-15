#!/usr/bin/env python3
"""Quick test script to verify backend components work"""

import asyncio
import logging
import sys
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent / 'backend'))

from scribe_backend.db.dao import Database
from scribe_backend.engine.gpu import detect_gpu, get_device, get_compute_type
from scribe_backend.engine.model_manager import ModelManager

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
        print(f"   Models directory: {mm.models_dir}")
        
        models = mm.list_available_models()
        print(f"   Available models: {len(models)}")
        
        for model in models[:3]:  # Show first 3
            status = "✓" if model['downloaded'] else "✗"
            print(f"   [{status}] {model['name']} ({model['size']})")
    except Exception as e:
        print(f"   Model manager error: {e}")
    
    # Test Proto imports
    print("\n4. gRPC Proto Files:")
    try:
        from scribe_backend.proto import scribe_pb2, scribe_pb2_grpc
        print("   ✓ Proto files imported successfully")
    except ImportError as e:
        print(f"   ✗ Proto import failed: {e}")
    
    print("\n" + "=" * 60)
    print("Test complete!")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(test_backend())