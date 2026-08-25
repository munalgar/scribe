#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLATFORM=""
DRY_CHECK=false

for arg in "$@"; do
    if [ "$arg" = "--dry-check" ]; then
        DRY_CHECK=true
    elif [ -z "$PLATFORM" ]; then
        PLATFORM="$arg"
    else
        echo "Error: unexpected arguments: $*" >&2
        exit 1
    fi
done

run_frontend() {
    if [ -n "$PLATFORM" ]; then
        bash "$SCRIPT_DIR/dev_frontend.sh" "$PLATFORM" "$@"
    else
        bash "$SCRIPT_DIR/dev_frontend.sh" "$@"
    fi
}

cd "$PROJECT_ROOT"
echo -e "${GREEN}Starting Scribe development environment${NC}"

if [ "$DRY_CHECK" = true ]; then
    run_frontend --dry-check --prepare-only
    bash "$SCRIPT_DIR/dev_backend.sh" --dry-check
    exit 0
fi

# Prepare the frontend before starting a long-lived backend process. This makes
# missing Flutter/Dart setup fail cleanly without leaving the backend running.
run_frontend --prepare-only

if command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 50051 >/dev/null 2>&1; then
    echo -e "${RED}Error: Port 50051 is already in use. Stop the existing backend first.${NC}" >&2
    exit 1
fi

BACKEND_PID=""
cleanup() {
    if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
        echo -e "${YELLOW}Stopping Scribe backend...${NC}"
        kill "$BACKEND_PID" 2>/dev/null || true
        wait "$BACKEND_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

bash "$SCRIPT_DIR/dev_backend.sh" &
BACKEND_PID=$!

if command -v nc >/dev/null 2>&1; then
    echo -e "${YELLOW}Waiting for backend on 127.0.0.1:50051...${NC}"
    for _ in $(seq 1 1200); do
        if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
            set +e
            wait "$BACKEND_PID"
            backend_status=$?
            set -e
            if [ "$backend_status" -eq 0 ]; then
                backend_status=1
            fi
            echo -e "${RED}Error: backend exited before it became ready (status $backend_status).${NC}" >&2
            exit "$backend_status"
        fi
        if nc -z 127.0.0.1 50051 >/dev/null 2>&1; then
            break
        fi
        sleep 0.25
    done

    if ! nc -z 127.0.0.1 50051 >/dev/null 2>&1; then
        echo -e "${RED}Error: backend did not become ready within 5 minutes.${NC}" >&2
        exit 1
    fi
fi

set +e
run_frontend
frontend_status=$?
set -e
exit "$frontend_status"
