#!/usr/bin/env python3
"""Test if the server starts correctly"""

import asyncio
import sys
from pathlib import Path

# Add project root and backend parent to path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
BACKEND_ROOT = PROJECT_ROOT / "backend"

# Ensure both runtime and type checkers can resolve imports
for p in (PROJECT_ROOT, BACKEND_ROOT):
    p_str = str(p)
    if p_str not in sys.path:
        sys.path.insert(0, p_str)

def _load_serve():
    import importlib
    import importlib.util

    for module_name in ("backend.scribe_backend.server", "scribe_backend.server"):
        try:
            module = importlib.import_module(module_name)
            return module.serve
        except ModuleNotFoundError:
            continue

    # Fallback if the package is exposed directly from backend/
    server_path = BACKEND_ROOT / "server.py"
    spec = importlib.util.spec_from_file_location("backend_server", server_path)
    if spec is None or spec.loader is None:
        raise ModuleNotFoundError(f"Could not load server module from {server_path}")
    backend_server = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(backend_server)
    return backend_server.serve


serve = _load_serve()


async def test_server():
    """Test server startup"""
    print("Testing server startup...")

    # Run for 2 seconds then stop (TimeoutError = server started successfully)
    try:
        await asyncio.wait_for(serve(), timeout=2.0)
    except asyncio.TimeoutError:
        print("Server started successfully (timed out as expected)")
    except RuntimeError as e:
        if "bind" in str(e).lower() or "50051" in str(e):
            print("Port 50051 in use - skipping (stop backend or other process using the port)")
            return
        raise
    except Exception as e:
        print(f"Server error: {e}")
        raise

if __name__ == "__main__":
    asyncio.run(test_server())
