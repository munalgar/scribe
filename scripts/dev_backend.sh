#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

DRY_CHECK=false
if [ "${1:-}" = "--dry-check" ]; then
    DRY_CHECK=true
    shift
fi
if [ "$#" -gt 0 ]; then
    echo "Error: unexpected arguments: $*" >&2
    exit 1
fi

dry_echo() {
    echo -e "${CYAN}[DRY-CHECK] $*${NC}"
}

echo -e "${GREEN}Starting Scribe Backend Development Server${NC}"
if [ "$DRY_CHECK" = true ]; then
    dry_echo "Dry-check mode enabled; no changes will be made."
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

VENV_DIR="$PROJECT_ROOT/.venv"

# Check if virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}Creating Python virtual environment...${NC}"
    if command -v python3 >/dev/null 2>&1; then
        if [ "$DRY_CHECK" = true ]; then
            dry_echo "Would run: python3 -m venv $VENV_DIR"
        else
            python3 -m venv "$VENV_DIR"
        fi
    elif command -v python >/dev/null 2>&1; then
        if [ "$DRY_CHECK" = true ]; then
            dry_echo "Would run: python -m venv $VENV_DIR"
        else
            python -m venv "$VENV_DIR"
        fi
    else
        echo "Error: no suitable Python interpreter found (expected python3/python)." >&2
        exit 1
    fi
fi

if [ -x "$VENV_DIR/bin/python" ]; then
    VENV_PYTHON="$VENV_DIR/bin/python"
elif [ -x "$VENV_DIR/Scripts/python.exe" ]; then
    VENV_PYTHON="$VENV_DIR/Scripts/python.exe"
elif [ "$DRY_CHECK" = true ]; then
    VENV_PYTHON="$VENV_DIR/bin/python"
    dry_echo "Virtual environment Python executable not found in $VENV_DIR (expected until first non-dry run)."
else
    echo "Error: virtual environment Python executable not found in $VENV_DIR" >&2
    exit 1
fi

if [ -x "$VENV_PYTHON" ]; then
    echo -e "${GREEN}Using virtual environment Python: $VENV_PYTHON${NC}"
elif [ "$DRY_CHECK" = true ]; then
    dry_echo "Would use virtual environment Python: $VENV_PYTHON"
fi

# Install requirements only if they've changed
MARKER="$VENV_DIR/.deps_installed"
REQUIREMENTS="$PROJECT_ROOT/backend/requirements.txt"
if [ ! -f "$REQUIREMENTS" ]; then
    echo "Error: requirements file not found at $REQUIREMENTS" >&2
    exit 1
fi

if [ ! -f "$MARKER" ] || [ "$REQUIREMENTS" -nt "$MARKER" ]; then
    if [ "$DRY_CHECK" = true ]; then
        dry_echo "Would install Python dependencies from $REQUIREMENTS"
    else
        echo -e "${GREEN}Installing Python dependencies...${NC}"
        "$VENV_PYTHON" -m pip install --quiet --upgrade pip wheel
        "$VENV_PYTHON" -m pip install --quiet -r "$REQUIREMENTS"
        touch "$MARKER"
    fi
else
    echo -e "${GREEN}Dependencies up to date${NC}"
fi

# Generate gRPC code if needed
if [ ! -f "backend/scribe_backend/proto/scribe_pb2.py" ]; then
    if [ "$DRY_CHECK" = true ]; then
        dry_echo "Would generate gRPC code via scripts/gen_proto.sh"
    else
        echo -e "${YELLOW}Generating gRPC code...${NC}"
        bash scripts/gen_proto.sh
    fi
fi

# Check if port 50051 is already in use
PORT=50051
if command -v lsof >/dev/null 2>&1; then
    EXISTING_PIDS="$(lsof -ti "tcp:${PORT}" 2>/dev/null | sort -u || true)"
    if [ -n "$EXISTING_PIDS" ]; then
        echo -e "${RED}Error: Port $PORT is already in use (PID: $(echo $EXISTING_PIDS | tr '\n' ' ')).${NC}"
        echo -e "${YELLOW}Stop the existing process first, then try again.${NC}"
        exit 1
    fi
fi

# Run the server (use -m for proper package imports)
echo -e "${GREEN}Starting backend server on localhost:50051${NC}"
echo "----------------------------------------"
if [ "$DRY_CHECK" = true ]; then
    dry_echo "Would run from backend/: $VENV_PYTHON -m scribe_backend.server"
    exit 0
fi

cd "$PROJECT_ROOT/backend"
"$VENV_PYTHON" -m scribe_backend.server