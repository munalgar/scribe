"""Database Access Object for Scribe"""

import sqlite3
import asyncio
import threading
from typing import List, Optional, Dict, Any
from datetime import datetime, timezone
import uuid
import logging
from concurrent.futures import ThreadPoolExecutor

from .init_db import get_db_path, init_database

logger = logging.getLogger(__name__)

# Number of reader connections in the pool.
_READER_POOL_SIZE = 4


class Database:
    """Database access layer with async support.

    Uses separate connection pools for reads and writes so that readers
    never block behind the single-writer lock that SQLite requires.
    All connections run in WAL journal mode, which allows concurrent
    readers alongside a single writer.

    - **Writer**: 1 persistent connection, serialised through a 1-worker
      ThreadPoolExecutor.
    - **Reader pool**: N persistent connections (one per thread), served by
      an N-worker ThreadPoolExecutor.  A ``threading.local`` ensures each
      thread gets its own connection.
    """

    def __init__(self):
        self.db_path = get_db_path()

        # Ensure database schema exists (uses CREATE TABLE IF NOT EXISTS)
        init_database()

        # Writer: single connection, single worker
        self._write_executor = ThreadPoolExecutor(
            max_workers=1, thread_name_prefix="db-writer"
        )
        self._writer_conn: Optional[sqlite3.Connection] = None

        # Reader pool: N connections, N workers
        self._read_executor = ThreadPoolExecutor(
            max_workers=_READER_POOL_SIZE, thread_name_prefix="db-reader"
        )
        self._reader_local = threading.local()

    # ------------------------------------------------------------------
    # Connection helpers
    # ------------------------------------------------------------------

    def _get_writer(self) -> sqlite3.Connection:
        """Get or create the persistent writer connection."""
        if self._writer_conn is None:
            self._writer_conn = self._make_connection()
        return self._writer_conn

    def _get_reader(self) -> sqlite3.Connection:
        """Get or create a per-thread reader connection."""
        conn = getattr(self._reader_local, "conn", None)
        if conn is None:
            conn = self._make_connection()
            self._reader_local.conn = conn
        return conn

    def _make_connection(self) -> sqlite3.Connection:
        """Create a new connection with standard pragmas."""
        conn = sqlite3.connect(str(self.db_path), check_same_thread=False)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA journal_mode = WAL")
        return conn

    # ------------------------------------------------------------------
    # Low-level execute helpers
    # ------------------------------------------------------------------

    def _read(self, query: str, params: tuple = ()) -> List[sqlite3.Row]:
        """Execute a read-only query on a reader connection."""
        conn = self._get_reader()
        cursor = conn.execute(query, params)
        return cursor.fetchall()

    def _write(self, query: str, params: tuple = ()) -> List[sqlite3.Row]:
        """Execute a write query on the writer connection and commit."""
        conn = self._get_writer()
        cursor = conn.execute(query, params)
        results = cursor.fetchall()
        conn.commit()
        return results

    def _write_many(self, query: str, params_list: List[tuple]):
        """Execute many write queries in a single transaction."""
        conn = self._get_writer()
        conn.executemany(query, params_list)
        conn.commit()

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def close(self):
        """Close all database connections and shut down executors."""
        if self._writer_conn is not None:
            self._writer_conn.close()
            self._writer_conn = None
        self._write_executor.shutdown(wait=False)
        self._read_executor.shutdown(wait=False)

    # ------------------------------------------------------------------
    # Jobs
    # ------------------------------------------------------------------

    async def new_job_id(self) -> str:
        """Generate a new job ID"""
        return str(uuid.uuid4())

    async def create_job(self, job_id: str, audio_path: str, model: str = "base",
                        language: str = "auto", translate: bool = False) -> bool:
        """Create a new transcription job"""
        now = datetime.now(timezone.utc).isoformat()

        query = """
        INSERT INTO jobs (job_id, status, audio_path, model, language,
                         translate, progress, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        params = (job_id, 1, audio_path, model, language,
                 int(translate), 0.0, now, now)  # Status 1 = QUEUED

        def _create():
            try:
                self._write(query, params)
                return True
            except Exception as e:
                logger.error(f"Failed to create job: {e}")
                return False

        return await asyncio.get_running_loop().run_in_executor(
            self._write_executor, _create
        )

    async def update_job_status(self, job_id: str, status: int, error: Optional[str] = None) -> bool:
        """Update job status"""
        now = datetime.now(timezone.utc).isoformat()

        if error:
            query = "UPDATE jobs SET status = ?, error = ?, updated_at = ? WHERE job_id = ?"
            params = (status, error, now, job_id)
        else:
            query = "UPDATE jobs SET status = ?, updated_at = ? WHERE job_id = ?"
            params = (status, now, job_id)

        def _update():
            try:
                self._write(query, params)
                return True
            except Exception as e:
                logger.error(f"Failed to update job status: {e}")
                return False

        return await asyncio.get_running_loop().run_in_executor(
            self._write_executor, _update
        )

    async def update_job_progress(self, job_id: str, progress: float):
        """Update job progress"""
        now = datetime.now(timezone.utc).isoformat()
        query = "UPDATE jobs SET progress = ?, updated_at = ? WHERE job_id = ?"

        def _update():
            self._write(query, (progress, now, job_id))

        await asyncio.get_running_loop().run_in_executor(
            self._write_executor, _update
        )

    async def list_jobs(self, limit: int = 100) -> List[Dict[str, Any]]:
        """List recent jobs"""
        query = """
        SELECT job_id, status, audio_path, model, language, translate,
               progress, error, created_at, updated_at
        FROM jobs
        ORDER BY created_at DESC
        LIMIT ?
        """

        def _list():
            rows = self._read(query, (limit,))
            return [dict(row) for row in rows]

        return await asyncio.get_running_loop().run_in_executor(
            self._read_executor, _list
        )

    async def get_job(self, job_id: str) -> Optional[Dict[str, Any]]:
        """Get a specific job"""
        query = """
        SELECT job_id, status, audio_path, model, language, translate,
               progress, error, created_at, updated_at
        FROM jobs
        WHERE job_id = ?
        """

        def _get():
            rows = self._read(query, (job_id,))
            return dict(rows[0]) if rows else None

        return await asyncio.get_running_loop().run_in_executor(
            self._read_executor, _get
        )

    # ------------------------------------------------------------------
    # Segments
    # ------------------------------------------------------------------

    async def get_segments(self, job_id: str, after_idx: int = -1) -> List[Dict[str, Any]]:
        """Get transcript segments for a job, optionally only those after a given index"""
        query = """
        SELECT idx, start, end, text, edited_text
        FROM transcript_segments
        WHERE job_id = ? AND idx > ?
        ORDER BY idx
        """

        def _get():
            rows = self._read(query, (job_id, after_idx))
            return [dict(row) for row in rows]

        return await asyncio.get_running_loop().run_in_executor(
            self._read_executor, _get
        )

    async def insert_segments_batch(self, job_id: str, segments: List[Dict[str, Any]]):
        """Insert multiple transcript segments in a single transaction"""
        now = datetime.now(timezone.utc).isoformat()

        query = """
        INSERT INTO transcript_segments (job_id, idx, start, end, text, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """

        params_list = [
            (job_id, seg['idx'], seg['start'], seg['end'], seg['text'], now)
            for seg in segments
        ]

        def _insert():
            self._write_many(query, params_list)

        await asyncio.get_running_loop().run_in_executor(
            self._write_executor, _insert
        )

    async def save_segment_edits(self, job_id: str, edits: List[Dict[str, Any]]):
        """Save edited text for specific segments of a job.

        Each entry in *edits* must have 'segment_index' and 'edited_text'.
        An empty 'edited_text' clears a previous edit.
        """
        query = """
        UPDATE transcript_segments
           SET edited_text = ?
         WHERE job_id = ? AND idx = ?
        """

        params_list = [
            (edit['edited_text'] or None, job_id, edit['segment_index'])
            for edit in edits
        ]

        def _save():
            self._write_many(query, params_list)

        await asyncio.get_running_loop().run_in_executor(
            self._write_executor, _save
        )

    # ------------------------------------------------------------------
    # Job lifecycle
    # ------------------------------------------------------------------

    async def delete_job(self, job_id: str) -> bool:
        """Delete a job and its segments"""
        query = "DELETE FROM jobs WHERE job_id = ?"

        def _delete():
            try:
                self._write(query, (job_id,))
                return True
            except Exception as e:
                logger.error(f"Failed to delete job: {e}")
                return False

        return await asyncio.get_running_loop().run_in_executor(
            self._write_executor, _delete
        )

    async def cancel_job(self, job_id: str) -> bool:
        """Cancel a job by setting its status to CANCELED"""
        return await self.update_job_status(job_id, 5)  # 5 = CANCELED

    async def fail_stale_jobs(self) -> int:
        """Mark any QUEUED or RUNNING jobs as FAILED.

        Called at startup to recover from a previous unclean shutdown.
        Returns the number of jobs that were updated.
        """
        now = datetime.now(timezone.utc).isoformat()
        error = "Server restarted while job was in progress"
        query = """
        UPDATE jobs
           SET status = 4, error = ?, updated_at = ?
         WHERE status IN (1, 2)
        """  # 1=QUEUED, 2=RUNNING, 4=FAILED

        def _recover():
            conn = self._get_writer()
            cursor = conn.execute(query, (error, now))
            conn.commit()
            return cursor.rowcount

        return await asyncio.get_running_loop().run_in_executor(
            self._write_executor, _recover
        )

    # ------------------------------------------------------------------
    # Settings
    # ------------------------------------------------------------------

    async def get_setting(self, key: str, default: Optional[str] = None) -> Optional[str]:
        """Get a setting value"""
        query = "SELECT value FROM settings WHERE key = ?"

        def _get():
            rows = self._read(query, (key,))
            return rows[0]['value'] if rows else default

        return await asyncio.get_running_loop().run_in_executor(
            self._read_executor, _get
        )

    async def set_setting(self, key: str, value: str):
        """Set a setting value"""
        query = """
        INSERT INTO settings (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """

        def _set():
            self._write(query, (key, value))

        await asyncio.get_running_loop().run_in_executor(
            self._write_executor, _set
        )

    async def get_all_settings(self) -> Dict[str, str]:
        """Get all settings"""
        query = "SELECT key, value FROM settings"

        def _get():
            rows = self._read(query)
            return {row['key']: row['value'] for row in rows}

        return await asyncio.get_running_loop().run_in_executor(
            self._read_executor, _get
        )
