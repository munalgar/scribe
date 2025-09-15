"""gRPC Server for Scribe Backend"""

import asyncio
import logging
import signal
import sys
from pathlib import Path

import grpc
import coloredlogs

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from scribe_backend.service import ScribeService

# Try to import generated proto files
try:
    from scribe_backend.proto import scribe_pb2_grpc
except ImportError:
    logger = logging.getLogger(__name__)
    logger.warning("Proto files not generated yet. Run scripts/gen_proto.sh first.")
    scribe_pb2_grpc = None

logger = logging.getLogger(__name__)


async def serve():
    """Start the gRPC server"""
    # Configure logging
    coloredlogs.install(
        level='INFO',
        fmt='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    logger.info("Starting Scribe backend server...")
    
    # Create server
    server = grpc.aio.server(
        options=[
            ('grpc.max_send_message_length', 50 * 1024 * 1024),  # 50MB
            ('grpc.max_receive_message_length', 50 * 1024 * 1024),  # 50MB
        ]
    )
    
    # Register the service
    if scribe_pb2_grpc:
        service = ScribeService()
        scribe_pb2_grpc.add_ScribeServicer_to_server(service, server)
        logger.info("Scribe service registered")
    else:
        logger.warning("Running without service (proto files not generated)")
    
    # Listen on localhost only for security
    listen_addr = '127.0.0.1:50051'
    server.add_insecure_port(listen_addr)
    
    logger.info(f"Server listening on {listen_addr}")
    
    # Start server
    await server.start()
    
    # Handle shutdown gracefully
    def signal_handler(sig, frame):
        logger.info("Shutting down server...")
        asyncio.create_task(server.stop(5))
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        await server.wait_for_termination()
    except KeyboardInterrupt:
        logger.info("Server interrupted")
    finally:
        logger.info("Server stopped")


def main():
    """Main entry point"""
    asyncio.run(serve())


if __name__ == "__main__":
    main()