# Changelog

All notable changes to Scribe are documented here. This project follows [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-11-15

### Changed
- Packaged releases now store Whisper models and transcription history in a persistent per-user data directory (`~/Library/Application Support/Scribe/`, `%LOCALAPPDATA%\Scribe\`, or `${XDG_DATA_HOME:-~/.local/share}/scribe/`), so data survives app updates. Override with `SCRIBE_DATA_DIR` / `SCRIBE_DB_PATH`.
- One-command development setup: `scripts/dev.sh` and `scripts/dev.ps1` create the virtualenv, install dependencies, generate gRPC bindings, and run backend and frontend together.
- The app version shown in Settings now matches the release tag.

### Fixed
- Flutter package renamed to `scribe_app` so the frontend test suite builds and runs.
- Cleaned up analyzer warnings in the Settings screen and JSON export.

### Added
- CI workflow running backend tests, `flutter analyze`, and `flutter test` on every push and pull request.

## [1.0.4] - 2026-02-25

- First cross-platform desktop release (macOS arm64, Windows x64, Linux x64) with batch transcription, live editing, translation, local model management, and TXT/SRT/VTT/JSON/CSV export.

[1.1.0]: https://github.com/munalgar/scribe/compare/v1.0.4...v1.1.0
[1.0.4]: https://github.com/munalgar/scribe/releases/tag/v1.0.4
