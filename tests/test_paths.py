#!/usr/bin/env python3
"""Tests for persistent source and packaged-build paths."""

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


PROJECT_ROOT = Path(__file__).resolve().parent.parent
BACKEND_ROOT = PROJECT_ROOT / "backend"
sys.path.insert(0, str(BACKEND_ROOT))

from scribe_backend.utils.paths import (  # noqa: E402
    app_data_dir,
    default_database_path,
    default_models_dir,
)
from scribe_backend.db.init_db import get_db_path  # noqa: E402
from scribe_backend.engine.model_manager import ModelManager  # noqa: E402


class AppDataPathTests(unittest.TestCase):
    def test_macos_app_data(self):
        result = app_data_dir(
            platform="darwin", environ={}, home=Path("/Users/tester")
        )
        self.assertEqual(
            result, Path("/Users/tester/Library/Application Support/Scribe")
        )

    def test_windows_app_data(self):
        result = app_data_dir(
            platform="win32",
            environ={"LOCALAPPDATA": "C:/Users/tester/AppData/Local"},
            home=Path("C:/Users/tester"),
        )
        self.assertEqual(result, Path("C:/Users/tester/AppData/Local/Scribe"))

    def test_linux_app_data_honors_xdg(self):
        result = app_data_dir(
            platform="linux",
            environ={"XDG_DATA_HOME": "/data/tester"},
            home=Path("/home/tester"),
        )
        self.assertEqual(result, Path("/data/tester/scribe"))

    def test_data_dir_override(self):
        result = app_data_dir(
            platform="linux",
            environ={"SCRIBE_DATA_DIR": "~/custom-scribe"},
            home=Path("/unused"),
        )
        self.assertEqual(result, Path("~/custom-scribe").expanduser())

    def test_source_paths_remain_repository_local(self):
        repository = Path("/workspace/scribe")
        self.assertEqual(
            default_models_dir(frozen=False, repository=repository),
            repository / "shared" / "models",
        )
        self.assertEqual(
            default_database_path(
                frozen=False, repository=repository, environ={}
            ),
            repository / "backend" / "data" / "scribe.db",
        )

    def test_frozen_paths_use_persistent_app_data(self):
        application_data = Path("/persistent/scribe")
        self.assertEqual(
            default_models_dir(frozen=True, application_data=application_data),
            application_data / "models",
        )
        self.assertEqual(
            default_database_path(
                frozen=True, application_data=application_data, environ={}
            ),
            application_data / "scribe.db",
        )

    def test_database_override_takes_priority(self):
        result = default_database_path(
            frozen=True,
            application_data=Path("/unused"),
            environ={"SCRIBE_DB_PATH": "/custom/scribe.db"},
        )
        self.assertEqual(result, Path("/custom/scribe.db"))

    def test_frozen_components_use_persistent_data_directory(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            data_dir = Path(temp_dir) / "scribe-data"
            with patch.dict(
                "os.environ", {"SCRIBE_DATA_DIR": str(data_dir)}, clear=False
            ), patch.object(sys, "frozen", True, create=True):
                self.assertEqual(get_db_path(), data_dir / "scribe.db")
                self.assertEqual(ModelManager().models_dir, data_dir / "models")


if __name__ == "__main__":
    unittest.main()
