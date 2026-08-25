"""Database initialization module"""

import sqlite3
from pathlib import Path
import logging

from ..utils.paths import default_database_path

logger = logging.getLogger(__name__)


def get_db_path() -> Path:
    """Get the database file path"""
    db_path = default_database_path()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    return db_path


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
