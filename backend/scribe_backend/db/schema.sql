-- Enable foreign key constraints
PRAGMA foreign_keys = ON;

-- Jobs table for tracking transcription jobs
CREATE TABLE IF NOT EXISTS jobs (
    job_id TEXT PRIMARY KEY,
    status INTEGER NOT NULL,
    audio_path TEXT,
    audio_duration_seconds REAL DEFAULT 0.0,
    model TEXT,
    language TEXT,
    translate INTEGER DEFAULT 0,
    progress REAL DEFAULT 0.0,
    error TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- Settings table for key-value configuration
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Transcript segments table for storing transcription results
CREATE TABLE IF NOT EXISTS transcript_segments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id TEXT NOT NULL,
    idx INTEGER NOT NULL,
    start REAL NOT NULL,
    end REAL NOT NULL,
    text TEXT NOT NULL,
    edited_text TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY(job_id) REFERENCES jobs(job_id) ON DELETE CASCADE
);

-- Index for efficient segment queries
CREATE INDEX IF NOT EXISTS idx_segments_job_id_idx 
ON transcript_segments(job_id, idx);
