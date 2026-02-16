#!/usr/bin/env bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Scribe Frontend (Flutter)${NC}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FLUTTER_APP="$PROJECT_ROOT/frontend/flutter/scribe_app"

# Add Flutter to PATH
export PATH="$HOME/flutter/bin:$HOME/.pub-cache/bin:$PATH"

cd "$FLUTTER_APP"

# Check if dependencies need to be fetched
if [ ! -d ".dart_tool" ] || [ "pubspec.yaml" -nt "pubspec.lock" ]; then
    echo -e "${YELLOW}Installing Flutter dependencies...${NC}"
    flutter pub get
fi

# Determine platform
PLATFORM="${1:-}"
if [ -z "$PLATFORM" ]; then
    # Auto-detect platform
    case "$(uname -s)" in
        Darwin*)    PLATFORM="macos" ;;
        Linux*)     PLATFORM="linux" ;;
        MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
        *)          PLATFORM="macos" ;;
    esac
    echo -e "${YELLOW}Auto-detected platform: $PLATFORM${NC}"
fi

# Run Flutter app
echo -e "${GREEN}Starting Flutter app for $PLATFORM${NC}"
echo "----------------------------------------"
flutter run -d $PLATFORM