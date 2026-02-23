#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Build the Scribe backend into a standalone executable using PyInstaller.
#
# The resulting binary is placed at:
#   backend/dist/scribe_backend (single-directory bundle)
#
# Usage:
#   bash scripts/build_backend.sh          # normal build
#   bash scripts/build_backend.sh --onefile # single-file executable
# ---------------------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ONEFILE=false
if [ "${1:-}" = "--onefile" ]; then
    ONEFILE=true
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_ROOT/backend"
VENV_DIR="$PROJECT_ROOT/.venv"

cd "$PROJECT_ROOT"

# ---------- virtual env ----------
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}Creating Python virtual environment...${NC}"
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"

# ---------- deps ----------
echo -e "${CYAN}Installing dependencies...${NC}"
pip install --quiet -r backend/requirements.txt
pip install --quiet pyinstaller

# ---------- build ----------
echo -e "${GREEN}Building backend executable...${NC}"

PYINSTALLER_ARGS=(
    --name scribe_backend
    --noconfirm
    --clean
    # Include the package data directories
    --add-data "$BACKEND_DIR/scribe_backend/proto:scribe_backend/proto"
    --add-data "$BACKEND_DIR/scribe_backend/db/schema.sql:scribe_backend/db"
    # Hidden imports that PyInstaller sometimes misses
    --hidden-import grpc
    --hidden-import grpc._cython
    --hidden-import grpc._cython.cygrpc
    --hidden-import faster_whisper
    --hidden-import coloredlogs
    # Working/output dirs
    --distpath "$BACKEND_DIR/dist"
    --workpath "$BACKEND_DIR/build_pyinstaller"
    --specpath "$BACKEND_DIR"
    # Entry point
    "$BACKEND_DIR/scribe_backend/server.py"
)

if [ "$ONEFILE" = true ]; then
    PYINSTALLER_ARGS=(--onefile "${PYINSTALLER_ARGS[@]}")
    echo -e "${CYAN}Mode: single-file executable${NC}"
else
    PYINSTALLER_ARGS=(--onedir "${PYINSTALLER_ARGS[@]}")
    echo -e "${CYAN}Mode: single-directory bundle${NC}"
fi

pyinstaller "${PYINSTALLER_ARGS[@]}"

echo ""
echo -e "${GREEN}✓ Build complete!${NC}"
if [ "$ONEFILE" = true ]; then
    echo -e "  Executable: ${CYAN}$BACKEND_DIR/dist/scribe_backend${NC}"
else
    echo -e "  Bundle dir: ${CYAN}$BACKEND_DIR/dist/scribe_backend/${NC}"
    echo -e "  Executable: ${CYAN}$BACKEND_DIR/dist/scribe_backend/scribe_backend${NC}"
fi
echo ""
echo -e "Test it with:"
echo -e "  ${CYAN}$BACKEND_DIR/dist/scribe_backend/scribe_backend --port 50051${NC}"
