"""gRPC Server for Scribe Backend"""

import asyncio
import logging
import signal

import grpc
import coloredlogs

from scribe_backend.proto import scribe_pb2_grpc
from scribe_backend.service import ScribeService

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
            ('grpc.keepalive_time_ms', 30_000),  # Send keepalive ping every 30s
            ('grpc.keepalive_timeout_ms', 10_000),  # Wait 10s for ping ack
            ('grpc.keepalive_permit_without_calls', 1),  # Allow pings with no active RPCs
            ('grpc.http2.min_ping_interval_without_data_ms', 30_000),
        ]
    )
    
    # Register the service
    service = ScribeService()
    await service.start()
    scribe_pb2_grpc.add_ScribeServicer_to_server(service, server)
    logger.info("Scribe service registered")
    
    # Listen on localhost only for security
    listen_addr = '127.0.0.1:50051'
    server.add_insecure_port(listen_addr)
    
    logger.info(f"Server listening on {listen_addr}")
    
    # Start server
    await server.start()
    
    # Handle shutdown gracefully using loop-aware signal handlers
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(
            sig,
            lambda: asyncio.create_task(server.stop(5))
        )
    
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
    # When run directly, ensure the package is importable
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).parent.parent))
    main()