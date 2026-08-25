"""Resolve persistent data paths for source and packaged execution."""

from __future__ import annotations

import os
import sys
from collections.abc import Mapping
from pathlib import Path


def project_root() -> Path:
    """Return the repository root during source execution."""
    return Path(__file__).resolve().parents[3]


def app_data_dir(
    *,
    platform: str | None = None,
    environ: Mapping[str, str] | None = None,
    home: Path | None = None,
) -> Path:
    """Return Scribe's persistent per-user application-data directory."""
    env = os.environ if environ is None else environ
    override = env.get("SCRIBE_DATA_DIR")
    if override:
        return Path(override).expanduser()

    current_platform = platform or sys.platform
    home_dir = home or Path.home()

    if current_platform == "darwin":
        return home_dir / "Library" / "Application Support" / "Scribe"

    if current_platform.startswith("win"):
        local_app_data = env.get("LOCALAPPDATA") or env.get("APPDATA")
        if local_app_data:
            return Path(local_app_data) / "Scribe"
        return home_dir / "AppData" / "Local" / "Scribe"

    xdg_data_home = env.get("XDG_DATA_HOME")
    data_home = Path(xdg_data_home) if xdg_data_home else home_dir / ".local" / "share"
    return data_home / "scribe"


def default_models_dir(
    *,
    frozen: bool | None = None,
    repository: Path | None = None,
    application_data: Path | None = None,
) -> Path:
    """Return the default Whisper model directory for the current runtime."""
    is_frozen = bool(getattr(sys, "frozen", False)) if frozen is None else frozen
    if is_frozen:
        return (application_data or app_data_dir()) / "models"
    return (repository or project_root()) / "shared" / "models"


def default_database_path(
    *,
    frozen: bool | None = None,
    repository: Path | None = None,
    application_data: Path | None = None,
    environ: Mapping[str, str] | None = None,
) -> Path:
    """Return the SQLite path, honoring the existing explicit override."""
    env = os.environ if environ is None else environ
    override = env.get("SCRIBE_DB_PATH")
    if override:
        return Path(override).expanduser()

    is_frozen = bool(getattr(sys, "frozen", False)) if frozen is None else frozen
    if is_frozen:
        return (application_data or app_data_dir(environ=env)) / "scribe.db"
    return (repository or project_root()) / "backend" / "data" / "scribe.db"
