#!/usr/bin/env python3
"""End-to-end transcription test.

Starts the real backend server as a subprocess (exactly as the desktop app's
managed mode does), then drives it over gRPC:

  health check -> settings -> model download -> transcription (streamed)
  -> stored transcript -> edit -> job list -> delete

The fixture is a ~4 second English recording of "The quick brown fox jumps
over the lazy dog". It runs on CPU with the ``tiny.en`` model, so it needs
network access the first time to download ~75 MB of model weights.

Environment overrides:
  SCRIBE_E2E_MODEL       Whisper model to use (default: tiny.en)
  SCRIBE_E2E_MODELS_DIR  Where to store/reuse models (default: shared/models)
  SCRIBE_E2E_BACKEND     Path to a packaged scribe_backend executable to test
                         instead of the source backend (used by release CI)
"""

from __future__ import annotations

import os
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
BACKEND_ROOT = PROJECT_ROOT / "backend"
FIXTURE = PROJECT_ROOT / "tests" / "fixtures" / "quick_brown_fox.ogg"

if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

import grpc  # noqa: E402

from scribe_backend.proto import scribe_pb2, scribe_pb2_grpc  # noqa: E402

MODEL = os.environ.get("SCRIBE_E2E_MODEL", "tiny.en")
MODELS_DIR = Path(
    os.environ.get("SCRIBE_E2E_MODELS_DIR", PROJECT_ROOT / "shared" / "models")
).resolve()
PACKAGED_BACKEND = os.environ.get("SCRIBE_E2E_BACKEND")

SERVER_READY_TIMEOUT = 60
DOWNLOAD_TIMEOUT = 600
TRANSCRIBE_TIMEOUT = 300

TERMINAL_STATUSES = {
    scribe_pb2.JobStatus.COMPLETED,
    scribe_pb2.JobStatus.FAILED,
    scribe_pb2.JobStatus.CANCELED,
}


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def _normalize(text: str) -> str:
    """Lowercase and strip punctuation so assertions ignore formatting."""
    return " ".join(re.sub(r"[^a-z0-9 ]+", " ", text.lower()).split())


class EndToEndTranscriptionTest(unittest.TestCase):
    server: subprocess.Popen
    channel: grpc.Channel
    stub: scribe_pb2_grpc.ScribeStub

    @classmethod
    def setUpClass(cls) -> None:
        if not FIXTURE.is_file():
            raise unittest.SkipTest(f"Missing audio fixture: {FIXTURE}")

        cls._tmp = tempfile.TemporaryDirectory(
            prefix="scribe-e2e-", ignore_cleanup_errors=True
        )
        tmp = Path(cls._tmp.name)
        MODELS_DIR.mkdir(parents=True, exist_ok=True)

        env = os.environ.copy()
        env["SCRIBE_DATA_DIR"] = str(tmp)
        env["SCRIBE_DB_PATH"] = str(tmp / "scribe.db")
        env["PYTHONPATH"] = os.pathsep.join(
            filter(None, [str(BACKEND_ROOT), env.get("PYTHONPATH")])
        )
        env["PYTHONUNBUFFERED"] = "1"

        port = _free_port()
        if PACKAGED_BACKEND:
            backend = Path(PACKAGED_BACKEND).resolve()
            if not backend.is_file():
                raise RuntimeError(f"SCRIBE_E2E_BACKEND not found: {backend}")
            command = [str(backend), "--port", str(port)]
        else:
            command = [sys.executable, "-m", "scribe_backend.server", "--port", str(port)]

        cls._log_lines: list[str] = []
        cls.server = subprocess.Popen(
            command,
            cwd=str(BACKEND_ROOT),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )

        ready = threading.Event()

        def _pump_output() -> None:
            assert cls.server.stdout is not None
            for line in cls.server.stdout:
                cls._log_lines.append(line.rstrip())
                if line.startswith("SCRIBE_READY"):
                    ready.set()

        threading.Thread(target=_pump_output, daemon=True).start()

        if not ready.wait(SERVER_READY_TIMEOUT):
            cls._stop_server()
            raise RuntimeError(
                "Backend did not report SCRIBE_READY in time.\n" + cls._server_log()
            )

        cls.channel = grpc.insecure_channel(f"127.0.0.1:{port}")
        grpc.channel_ready_future(cls.channel).result(timeout=SERVER_READY_TIMEOUT)
        cls.stub = scribe_pb2_grpc.ScribeStub(cls.channel)

    @classmethod
    def tearDownClass(cls) -> None:
        channel = getattr(cls, "channel", None)
        if channel is not None:
            channel.close()
        cls._stop_server()
        cls._tmp.cleanup()

    @classmethod
    def _stop_server(cls) -> None:
        server = getattr(cls, "server", None)
        if server is None or server.poll() is not None:
            return
        if sys.platform.startswith("win"):
            # A venv's python.exe on Windows is a launcher that runs the real
            # interpreter as a child process; kill the whole tree so the
            # server releases its SQLite database.
            subprocess.run(
                ["taskkill", "/T", "/F", "/PID", str(server.pid)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        else:
            server.terminate()
        try:
            server.wait(timeout=15)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait(timeout=15)

    @classmethod
    def _server_log(cls) -> str:
        tail = cls._log_lines[-60:]
        return "--- backend log (tail) ---\n" + "\n".join(tail)

    def _fail_with_log(self, message: str) -> None:
        self.fail(f"{message}\n{self._server_log()}")

    def test_transcribes_quick_brown_fox(self) -> None:
        stub = self.stub

        # 1. Health check
        health = stub.HealthCheck(scribe_pb2.HealthCheckRequest(), timeout=10)
        self.assertTrue(health.ok, health.message)

        # 2. Point the backend at the shared model cache
        updated = stub.UpdateSettings(
            scribe_pb2.UpdateSettingsRequest(
                settings=scribe_pb2.Settings(models_dir=str(MODELS_DIR))
            ),
            timeout=10,
        )
        self.assertEqual(
            Path(updated.settings.models_dir).resolve(), MODELS_DIR
        )

        # 3. Download the model (instant if it is already cached)
        listed = stub.ListModels(scribe_pb2.ListModelsRequest(), timeout=10)
        self.assertIn(MODEL, {m.name for m in listed.models})

        final_download = None
        for progress in stub.DownloadModel(
            scribe_pb2.DownloadModelRequest(name=MODEL), timeout=DOWNLOAD_TIMEOUT
        ):
            final_download = progress
            if progress.status in (
                scribe_pb2.DOWNLOAD_COMPLETE,
                scribe_pb2.DOWNLOAD_FAILED,
                scribe_pb2.DOWNLOAD_CANCELED,
            ):
                break
        self.assertIsNotNone(final_download, "DownloadModel streamed no events")
        if final_download.status != scribe_pb2.DOWNLOAD_COMPLETE:
            self._fail_with_log(
                f"Model download did not complete: {final_download.error}"
            )

        listed = stub.ListModels(scribe_pb2.ListModelsRequest(), timeout=10)
        downloaded = {m.name for m in listed.models if m.downloaded}
        self.assertIn(MODEL, downloaded)

        # 4. Transcribe the clip and stream segments as the app does
        started = stub.StartTranscription(
            scribe_pb2.StartTranscriptionRequest(
                audio=scribe_pb2.AudioSource(file_path=str(FIXTURE)),
                options=scribe_pb2.TranscriptionOptions(
                    model=MODEL,
                    language="en",
                    enable_gpu=False,
                ),
            ),
            timeout=30,
        )
        job_id = started.job_id
        self.assertTrue(job_id, "StartTranscription returned no job id")

        streamed: dict[int, str] = {}
        final_status = None
        final_error = ""
        deadline = time.monotonic() + TRANSCRIBE_TIMEOUT
        for event in stub.StreamTranscription(
            scribe_pb2.StreamTranscriptionRequest(job_id=job_id),
            timeout=TRANSCRIBE_TIMEOUT,
        ):
            self.assertEqual(event.job_id, job_id)
            if event.HasField("segment") and event.segment.text:
                streamed[event.segment.index] = event.segment.text
            if event.status in TERMINAL_STATUSES:
                final_status = event.status
                final_error = event.error
            if time.monotonic() > deadline:
                break

        if final_status != scribe_pb2.JobStatus.COMPLETED:
            self._fail_with_log(
                f"Job ended with status "
                f"{scribe_pb2.JobStatus.Name(final_status or 0)}: {final_error}"
            )
        self.assertTrue(streamed, "No segments were streamed")

        streamed_text = _normalize(" ".join(streamed[i] for i in sorted(streamed)))
        self.assertIn("quick brown fox", streamed_text)
        self.assertIn("lazy dog", streamed_text)

        # 5. The stored transcript matches what was streamed
        job = stub.GetJob(scribe_pb2.GetJobRequest(job_id=job_id), timeout=10)
        self.assertEqual(job.status, scribe_pb2.JobStatus.COMPLETED)

        transcript = stub.GetTranscript(
            scribe_pb2.GetTranscriptRequest(job_id=job_id), timeout=10
        )
        self.assertEqual(transcript.status, scribe_pb2.JobStatus.COMPLETED)
        self.assertEqual(transcript.model, MODEL)
        self.assertEqual(Path(transcript.audio_path).resolve(), FIXTURE.resolve())
        self.assertEqual(
            {s.index: s.text for s in transcript.segments}, streamed
        )
        for seg in transcript.segments:
            self.assertGreaterEqual(seg.start, 0.0)
            self.assertGreater(seg.end, seg.start)
            self.assertLessEqual(seg.end, 6.0)

        # 6. Edits persist
        first = transcript.segments[0]
        saved = stub.SaveTranscriptEdits(
            scribe_pb2.SaveTranscriptEditsRequest(
                job_id=job_id,
                edits=[
                    scribe_pb2.SegmentEdit(
                        segment_index=first.index,
                        edited_text="The quick brown fox (edited).",
                    )
                ],
            ),
            timeout=10,
        )
        self.assertTrue(saved.saved)
        reloaded = stub.GetTranscript(
            scribe_pb2.GetTranscriptRequest(job_id=job_id), timeout=10
        )
        edited = {s.index: s.edited_text for s in reloaded.segments}
        self.assertEqual(edited[first.index], "The quick brown fox (edited).")

        # 7. History lists the job, and deleting removes it
        jobs = stub.ListJobs(scribe_pb2.ListJobsRequest(), timeout=10)
        self.assertIn(job_id, {j.job_id for j in jobs.jobs})

        deleted = stub.DeleteJob(
            scribe_pb2.DeleteJobRequest(job_id=job_id), timeout=10
        )
        self.assertTrue(deleted.deleted)
        jobs = stub.ListJobs(scribe_pb2.ListJobsRequest(), timeout=10)
        self.assertNotIn(job_id, {j.job_id for j in jobs.jobs})


if __name__ == "__main__":
    unittest.main(verbosity=2)
