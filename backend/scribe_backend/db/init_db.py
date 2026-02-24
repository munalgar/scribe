"""Database initialization module"""

import os
import sqlite3
from pathlib import Path
import logging

logger = logging.getLogger(__name__)


def get_db_path() -> Path:
    """Get the database file path"""
    # Check for environment variable first
    db_path = os.environ.get('SCRIBE_DB_PATH')
    
    if db_path:
        return Path(db_path)
    
    # Default to backend/data directory
    backend_dir = Path(__file__).parent.parent.parent
    data_dir = backend_dir / 'data'
    data_dir.mkdir(exist_ok=True)
    
    return data_dir / 'scribe.db'


def init_database():
    """Initialize the database with schema"""
    db_path = get_db_path()
    schema_path = Path(__file__).parent / 'schema.sql'
    
    logger.info(f"Initializing database at: {db_path}")
    
    # Create connection
    conn = sqlite3.connect(str(db_path))
    
    try:
        # Read and execute schema
        with open(schema_path, 'r') as f:
            schema = f.read()
        
        conn.executescript(schema)
        
        # Migrate: add edited_text column if missing
        cursor = conn.execute("PRAGMA table_info(transcript_segments)")
        columns = {row[1] for row in cursor.fetchall()}
        if 'edited_text' not in columns:
            conn.execute(
                "ALTER TABLE transcript_segments ADD COLUMN edited_text TEXT"
            )
            conn.commit()
            logger.info("Migrated: added edited_text column")

        # Enable WAL mode for better concurrency
        conn.execute("PRAGMA journal_mode=WAL")
        conn.commit()
        
        logger.info("Database initialized successfully")
        
    except Exception as e:
        logger.error(f"Failed to initialize database: {e}")
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    init_database()