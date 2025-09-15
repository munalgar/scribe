"""Database Access Object for Scribe"""

import sqlite3
import asyncio
from pathlib import Path
from typing import List, Optional, Dict, Any
from datetime import datetime
import uuid
import logging
from concurrent.futures import ThreadPoolExecutor

from .init_db import get_db_path, init_database

logger = logging.getLogger(__name__)


class Database:
    """Database access layer with async support"""
    
    def __init__(self):
        self.db_path = get_db_path()
        self.executor = ThreadPoolExecutor(max_workers=1)
        
        # Initialize database if it doesn't exist
        if not self.db_path.exists():
            init_database()
    
    def _get_connection(self) -> sqlite3.Connection:
        """Get a database connection"""
        conn = sqlite3.connect(str(self.db_path), check_same_thread=False)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        return conn
    
    def _execute(self, query: str, params: tuple = ()) -> List[sqlite3.Row]:
        """Execute a query and return results"""
        conn = self._get_connection()
        try:
            cursor = conn.execute(query, params)
            results = cursor.fetchall()
            conn.commit()
            return results
        finally:
            conn.close()
    
    def _execute_many(self, query: str, params_list: List[tuple]):
        """Execute many queries"""
        conn = self._get_connection()
        try:
            conn.executemany(query, params_list)
            conn.commit()
        finally:
            conn.close()
    
    async def new_job_id(self) -> str:
        """Generate a new job ID"""
        return str(uuid.uuid4())
    
    async def create_job(self, job_id: str, audio_path: str, model: str = "base",
                        language: str = "auto", translate: bool = False) -> bool:
        """Create a new transcription job"""
        now = datetime.utcnow().isoformat()
        
        query = """
        INSERT INTO jobs (job_id, status, audio_path, model, language, 
                         translate, progress, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        params = (job_id, 1, audio_path, model, language, 
                 int(translate), 0.0, now, now)  # Status 1 = QUEUED
        
        def _create():
            try:
                self._execute(query, params)
                return True
            except Exception as e:
                logger.error(f"Failed to create job: {e}")
                return False
        
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, _create
        )
    
    async def update_job_status(self, job_id: str, status: int, error: str = None):
        """Update job status"""
        now = datetime.utcnow().isoformat()
        
        if error:
            query = "UPDATE jobs SET status = ?, error = ?, updated_at = ? WHERE job_id = ?"
            params = (status, error, now, job_id)
        else:
            query = "UPDATE jobs SET status = ?, updated_at = ? WHERE job_id = ?"
            params = (status, now, job_id)
        
        def _update():
            self._execute(query, params)
        
        await asyncio.get_event_loop().run_in_executor(self.executor, _update)
    
    async def update_job_progress(self, job_id: str, progress: float):
        """Update job progress"""
        now = datetime.utcnow().isoformat()
        query = "UPDATE jobs SET progress = ?, updated_at = ? WHERE job_id = ?"
        
        def _update():
            self._execute(query, (progress, now, job_id))
        
        await asyncio.get_event_loop().run_in_executor(self.executor, _update)
    
    async def insert_segment(self, job_id: str, idx: int, start: float, 
                            end: float, text: str):
        """Insert a transcript segment"""
        now = datetime.utcnow().isoformat()
        
        query = """
        INSERT INTO transcript_segments (job_id, idx, start, end, text, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """
        
        params = (job_id, idx, start, end, text, now)
        
        def _insert():
            self._execute(query, params)
        
        await asyncio.get_event_loop().run_in_executor(self.executor, _insert)
    
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
            rows = self._execute(query, (limit,))
            return [dict(row) for row in rows]
        
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, _list
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
            rows = self._execute(query, (job_id,))
            return dict(rows[0]) if rows else None
        
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, _get
        )
    
    async def get_segments(self, job_id: str) -> List[Dict[str, Any]]:
        """Get transcript segments for a job"""
        query = """
        SELECT idx, start, end, text
        FROM transcript_segments
        WHERE job_id = ?
        ORDER BY idx
        """
        
        def _get():
            rows = self._execute(query, (job_id,))
            return [dict(row) for row in rows]
        
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, _get
        )
    
    async def delete_job(self, job_id: str) -> bool:
        """Delete a job and its segments"""
        query = "DELETE FROM jobs WHERE job_id = ?"
        
        def _delete():
            try:
                self._execute(query, (job_id,))
                return True
            except Exception as e:
                logger.error(f"Failed to delete job: {e}")
                return False
        
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, _delete
        )
    
    async def cancel_job(self, job_id: str) -> bool:
        """Cancel a job by setting its status to CANCELED"""
        return await self.update_job_status(job_id, 5)  # 5 = CANCELED
    
    async def get_setting(self, key: str, default: str = None) -> Optional[str]:
        """Get a setting value"""
        query = "SELECT value FROM settings WHERE key = ?"
        
        def _get():
            rows = self._execute(query, (key,))
            return rows[0]['value'] if rows else default
        
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, _get
        )
    
    async def set_setting(self, key: str, value: str):
        """Set a setting value"""
        query = """
        INSERT INTO settings (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """
        
        def _set():
            self._execute(query, (key, value))
        
        await asyncio.get_event_loop().run_in_executor(self.executor, _set)
    
    async def get_all_settings(self) -> Dict[str, str]:
        """Get all settings"""
        query = "SELECT key, value FROM settings"
        
        def _get():
            rows = self._execute(query)
            return {row['key']: row['value'] for row in rows}
        
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, _get
        )