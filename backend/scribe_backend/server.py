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
    
    # Handle shutdown gracefully using an explicit shutdown event.
    loop = asyncio.get_running_loop()
    shutdown_event = asyncio.Event()
    registered_signals = []

    def _request_shutdown():
        if not shutdown_event.is_set():
            logger.info("Shutdown requested")
            shutdown_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _request_shutdown)
            registered_signals.append(sig)
        except (NotImplementedError, RuntimeError):
            # add_signal_handler is not available on some platforms/event loops.
            pass
    
    termination_task = asyncio.create_task(server.wait_for_termination())
    shutdown_task = asyncio.create_task(shutdown_event.wait())

    try:
        done, pending = await asyncio.wait(
            {termination_task, shutdown_task},
            return_when=asyncio.FIRST_COMPLETED,
        )
        for task in pending:
            task.cancel()
        if pending:
            await asyncio.gather(*pending, return_exceptions=True)
    except (KeyboardInterrupt, asyncio.CancelledError):
        logger.info("Server interrupted")
    finally:
        for sig in registered_signals:
            loop.remove_signal_handler(sig)
        await server.stop(5)
        service.db.close()
        logger.info("Server stopped")


def main():
    """Main entry point"""
    try:
        asyncio.run(serve())
    except KeyboardInterrupt:
        # asyncio.run() may still raise KeyboardInterrupt after task cancellation.
        # Treat Ctrl+C as normal shutdown to avoid noisy traceback output.
        pass


if __name__ == "__main__":
    # When run directly, ensure the package is importable
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).parent.parent))
    main()