#!/usr/bin/env python3
"""Build and package cross-platform Scribe desktop release artifacts.

This script builds:
1) PyInstaller backend executable (`scribe_backend`)
2) Flutter desktop frontend bundle (Windows/macOS/Linux)
3) A release archive that includes the frontend bundle plus backend binary

Expected output:
  dist/release/scribe-<platform>-<version>.zip
"""

from __future__ import annotations

import argparse
import os
import shlex
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from shutil import which
from zipfile import ZIP_DEFLATED, ZipFile


PROJECT_ROOT = Path(__file__).resolve().parent.parent
BACKEND_DIR = PROJECT_ROOT / "backend"
FRONTEND_APP_DIR = PROJECT_ROOT / "frontend" / "flutter" / "scribe_app"
DIST_DIR = PROJECT_ROOT / "dist" / "release"
PROTO_DIR = PROJECT_ROOT / "proto"
PROTO_FILE = PROTO_DIR / "scribe.proto"
PY_PROTO_OUT = BACKEND_DIR / "scribe_backend" / "proto"
DART_PROTO_OUT = FRONTEND_APP_DIR / "lib" / "proto"


class BuildError(RuntimeError):
    """Raised when a build step fails validation."""


def log(message: str) -> None:
    print(f"[release] {message}")


def run(cmd: list[str], cwd: Path | None = None) -> None:
    workdir = cwd or PROJECT_ROOT
    rendered = " ".join(shlex.quote(str(part)) for part in cmd)
    log(f"$ {rendered}")
    subprocess.run(cmd, cwd=workdir, check=True)


def detect_platform() -> str:
    if sys.platform.startswith("win"):
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    if sys.platform.startswith("linux"):
        return "linux"
    raise BuildError(f"Unsupported host platform: {sys.platform}")


def sanitize_version(version: str) -> str:
    cleaned = [
        char if (char.isalnum() or char in {".", "-", "_"}) else "-"
        for char in version.strip()
    ]
    result = "".join(cleaned).strip("-")
    return result or "local"


def release_python_path(venv_dir: Path, platform: str) -> Path:
    if platform == "windows":
        return venv_dir / "Scripts" / "python.exe"
    return venv_dir / "bin" / "python"


def ensure_release_venv(platform: str) -> Path:
    venv_dir = PROJECT_ROOT / ".venv-release"
    if not venv_dir.exists():
        log("Creating .venv-release")
        run([sys.executable, "-m", "venv", str(venv_dir)])

    python = release_python_path(venv_dir, platform)
    if not python.exists():
        raise BuildError(f"Python executable not found in release venv: {python}")

    run([str(python), "-m", "pip", "install", "--upgrade", "pip"])
    run(
        [
            str(python),
            "-m",
            "pip",
            "install",
            "-r",
            str(BACKEND_DIR / "requirements.txt"),
            "pyinstaller",
        ]
    )
    return python


def build_backend_binary(platform: str, python: Path) -> Path:
    log("Building backend executable with PyInstaller")

    backend_dist_dir = BACKEND_DIR / "dist"
    backend_work_dir = BACKEND_DIR / "build_pyinstaller"
    backend_spec = BACKEND_DIR / "scribe_backend.spec"

    if backend_work_dir.exists():
        shutil.rmtree(backend_work_dir)
    if backend_spec.exists():
        backend_spec.unlink()

    one_dir_build = backend_dist_dir / "scribe_backend"
    if one_dir_build.exists() and one_dir_build.is_dir():
        shutil.rmtree(one_dir_build)

    exe_name = "scribe_backend.exe" if platform == "windows" else "scribe_backend"
    backend_exe = backend_dist_dir / exe_name
    if backend_exe.exists() and backend_exe.is_file():
        backend_exe.unlink()

    data_separator = ";" if platform == "windows" else ":"
    proto_data = (
        f"{BACKEND_DIR / 'scribe_backend' / 'proto'}"
        f"{data_separator}scribe_backend/proto"
    )
    schema_data = (
        f"{BACKEND_DIR / 'scribe_backend' / 'db' / 'schema.sql'}"
        f"{data_separator}scribe_backend/db"
    )

    cmd = [
        str(python),
        "-m",
        "PyInstaller",
        "--name",
        "scribe_backend",
        "--noconfirm",
        "--clean",
        "--onefile",
        "--add-data",
        proto_data,
        "--add-data",
        schema_data,
        "--hidden-import",
        "grpc",
        "--hidden-import",
        "grpc._cython",
        "--hidden-import",
        "grpc._cython.cygrpc",
        "--hidden-import",
        "faster_whisper",
        "--hidden-import",
        "coloredlogs",
        "--distpath",
        str(backend_dist_dir),
        "--workpath",
        str(backend_work_dir),
        "--specpath",
        str(BACKEND_DIR),
        str(BACKEND_DIR / "scribe_backend" / "server.py"),
    ]
    run(cmd)

    if not backend_exe.exists():
        raise BuildError(f"Backend executable was not created: {backend_exe}")

    if platform != "windows":
        backend_exe.chmod(backend_exe.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    return backend_exe


def generate_proto_stubs(python: Path) -> None:
    log("Generating gRPC stubs from proto/scribe.proto")

    if not PROTO_FILE.exists():
        raise BuildError(f"Proto file not found: {PROTO_FILE}")

    protoc = which("protoc")
    if not protoc:
        raise BuildError(
            "protoc was not found in PATH. Install Protocol Buffers compiler."
        )

    if not which("protoc-gen-dart"):
        raise BuildError(
            "protoc-gen-dart was not found in PATH. "
            "Install with: dart pub global activate protoc_plugin"
        )

    PY_PROTO_OUT.mkdir(parents=True, exist_ok=True)
    DART_PROTO_OUT.mkdir(parents=True, exist_ok=True)

    run(
        [
            str(python),
            "-m",
            "grpc_tools.protoc",
            "-I",
            str(PROTO_DIR),
            f"--python_out={PY_PROTO_OUT}",
            f"--grpc_python_out={PY_PROTO_OUT}",
            str(PROTO_FILE),
        ]
    )

    # grpc_tools uses absolute-style import by default; convert to package-relative.
    py_grpc = PY_PROTO_OUT / "scribe_pb2_grpc.py"
    if not py_grpc.exists():
        raise BuildError(f"Expected generated file not found: {py_grpc}")
    py_grpc.write_text(
        py_grpc.read_text().replace(
            "import scribe_pb2 as scribe__pb2",
            "from . import scribe_pb2 as scribe__pb2",
        )
    )

    run(
        [
            protoc,
            "-I",
            str(PROTO_DIR),
            f"--dart_out=grpc:{DART_PROTO_OUT}",
            str(PROTO_FILE),
        ]
    )


def build_frontend(platform: str) -> None:
    log(f"Building Flutter desktop app for {platform}")
    run(["flutter", "pub", "get"], cwd=FRONTEND_APP_DIR)

    cmd = ["flutter", "build", platform, "--release"]
    if platform == "macos":
        cmd.append("--no-codesign")
    run(cmd, cwd=FRONTEND_APP_DIR)


def frontend_output_dir(platform: str) -> Path:
    build_root = FRONTEND_APP_DIR / "build"
    if platform == "windows":
        return build_root / "windows" / "x64" / "runner" / "Release"
    if platform == "linux":
        return build_root / "linux" / "x64" / "release" / "bundle"
    if platform == "macos":
        return build_root / "macos" / "Build" / "Products" / "Release"
    raise BuildError(f"Unsupported platform: {platform}")


def copy_frontend_bundle(platform: str, staging_dir: Path) -> Path | None:
    source = frontend_output_dir(platform)
    if not source.exists():
        raise BuildError(f"Frontend output directory not found: {source}")

    if platform in {"windows", "linux"}:
        shutil.copytree(source, staging_dir, dirs_exist_ok=True)
        return None

    app_candidates = sorted(source.glob("*.app"))
    if len(app_candidates) != 1:
        raise BuildError(
            f"Expected exactly one .app in {source}, found {len(app_candidates)}"
        )

    app_bundle = app_candidates[0]
    destination = staging_dir / app_bundle.name
    shutil.copytree(app_bundle, destination, dirs_exist_ok=True)
    return destination


def place_backend_binary(
    platform: str,
    staging_dir: Path,
    backend_exe: Path,
    macos_app_bundle: Path | None,
) -> None:
    if platform == "windows":
        target = staging_dir / "scribe_backend" / backend_exe.name
    elif platform == "linux":
        target = staging_dir / "lib" / "scribe_backend" / backend_exe.name
    elif platform == "macos":
        if macos_app_bundle is None:
            raise BuildError("Missing macOS app bundle path for backend placement")
        target = (
            macos_app_bundle
            / "Contents"
            / "Resources"
            / "scribe_backend"
            / backend_exe.name
        )
    else:
        raise BuildError(f"Unsupported platform: {platform}")

    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(backend_exe, target)

    if platform != "windows":
        target.chmod(target.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def create_zip(source_dir: Path, archive_path: Path) -> None:
    if archive_path.exists():
        archive_path.unlink()

    root_for_archive = source_dir.parent
    with ZipFile(archive_path, "w", compression=ZIP_DEFLATED) as zipf:
        for item in sorted(source_dir.rglob("*")):
            if item.is_dir():
                continue
            arcname = item.relative_to(root_for_archive)
            zipf.write(item, arcname=arcname)


def create_archive(platform: str, source_dir: Path, archive_path: Path) -> None:
    # Use macOS ditto to preserve app bundle resource metadata.
    if platform == "macos":
        if archive_path.exists():
            archive_path.unlink()
        run(
            [
                "ditto",
                "-c",
                "-k",
                "--sequesterRsrc",
                "--keepParent",
                source_dir.name,
                archive_path.name,
            ],
            cwd=source_dir.parent,
        )
        return

    create_zip(source_dir, archive_path)


def package_release(platform: str, version: str) -> Path:
    DIST_DIR.mkdir(parents=True, exist_ok=True)
    package_name = f"scribe-{platform}-{version}"
    staging_dir = DIST_DIR / package_name
    archive_path = DIST_DIR / f"{package_name}.zip"

    if staging_dir.exists():
        shutil.rmtree(staging_dir)
    staging_dir.mkdir(parents=True, exist_ok=True)

    python = ensure_release_venv(platform)
    generate_proto_stubs(python)
    backend_exe = build_backend_binary(platform, python)
    build_frontend(platform)
    macos_app_bundle = copy_frontend_bundle(platform, staging_dir)
    place_backend_binary(platform, staging_dir, backend_exe, macos_app_bundle)
    create_archive(platform, staging_dir, archive_path)

    return archive_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build Scribe desktop release package")
    parser.add_argument(
        "--platform",
        choices=["windows", "macos", "linux"],
        help="Target desktop platform. Defaults to current host platform.",
    )
    parser.add_argument(
        "--version",
        help="Version label used in output filenames (e.g. v1.2.0).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    host_platform = detect_platform()
    if args.platform and args.platform != host_platform:
        raise BuildError(
            f"Cross-platform build requested ({args.platform}) on host "
            f"{host_platform}. Run this script on a matching host OS."
        )
    platform = args.platform or host_platform
    version = sanitize_version(
        args.version or os.environ.get("GITHUB_REF_NAME") or "local"
    )

    log(f"Platform: {platform}")
    log(f"Version: {version}")

    artifact = package_release(platform, version)
    log(f"Release artifact: {artifact}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BuildError as exc:
        log(f"ERROR: {exc}")
        raise SystemExit(1)
