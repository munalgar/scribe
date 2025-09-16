#!/usr/bin/env python3
"""Test if the server starts correctly"""

import asyncio
import sys
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent / 'backend'))

async def test_server():
    """Test server startup"""
    print("Testing server startup...")
    
    # Import and start server
    from scribe_backend.server import serve
    
    # Run for 2 seconds then stop
    try:
        await asyncio.wait_for(serve(), timeout=2.0)
    except asyncio.TimeoutError:
        print("Server started successfully (timed out as expected)")
    except Exception as e:
        print(f"Server error: {e}")
        raise

if __name__ == "__main__":
    asyncio.run(test_server())