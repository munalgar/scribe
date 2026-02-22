#!/usr/bin/env bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

DRY_CHECK=false
PLATFORM=""
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

dry_echo() {
    echo -e "${CYAN}[DRY-CHECK] $*${NC}"
}

echo -e "${GREEN}Starting Scribe Frontend (Flutter)${NC}"
if [ "$DRY_CHECK" = true ]; then
    dry_echo "Dry-check mode enabled; no changes will be made."
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FLUTTER_APP="$PROJECT_ROOT/frontend/flutter/scribe_app"

# Add Flutter to PATH if standard locations exist
if [ -d "$HOME/flutter/bin" ]; then
    PATH="$HOME/flutter/bin:$PATH"
fi
if [ -d "$HOME/.pub-cache/bin" ]; then
    PATH="$HOME/.pub-cache/bin:$PATH"
fi
export PATH

if ! command -v flutter >/dev/null 2>&1; then
    echo "Error: flutter command not found. Add Flutter to PATH or install it first." >&2
    exit 1
fi

cd "$FLUTTER_APP"

# Check if dependencies need to be fetched
if [ ! -d ".dart_tool" ] || [ ! -f "pubspec.lock" ] || [ "pubspec.yaml" -nt "pubspec.lock" ]; then
    if [ "$DRY_CHECK" = true ]; then
        dry_echo "Would run: flutter pub get"
    else
        echo -e "${YELLOW}Installing Flutter dependencies...${NC}"
        flutter pub get
    fi
else
    echo -e "${GREEN}Dependencies up to date${NC}"
fi

# Determine platform
if [ -z "$PLATFORM" ]; then
    # Auto-detect platform
    case "$(uname -s)" in
        Darwin*)    PLATFORM="macos" ;;
        Linux*)     PLATFORM="linux" ;;
        MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
        *)          PLATFORM="" ;;
    esac
    if [ -n "$PLATFORM" ]; then
        echo -e "${YELLOW}Auto-detected platform: $PLATFORM${NC}"
    else
        echo -e "${YELLOW}Could not auto-detect platform; using Flutter default device selection${NC}"
    fi
fi

# Run Flutter app
if [ -n "$PLATFORM" ]; then
    echo -e "${GREEN}Starting Flutter app for $PLATFORM${NC}"
else
    echo -e "${GREEN}Starting Flutter app using default device selection${NC}"
fi
echo "----------------------------------------"
if [ -n "$PLATFORM" ]; then
    if [ "$DRY_CHECK" = true ]; then
        dry_echo "Would run: flutter run -d $PLATFORM"
    else
        flutter run -d "$PLATFORM"
    fi
else
    if [ "$DRY_CHECK" = true ]; then
        dry_echo "Would run: flutter run"
    else
        flutter run
    fi
fi