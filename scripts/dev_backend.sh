#!/usr/bin/env bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Scribe Backend Development Server${NC}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Check if virtual environment exists
if [ ! -d ".venv" ]; then
    echo -e "${YELLOW}Creating Python virtual environment...${NC}"
    python3 -m venv .venv
fi

# Activate virtual environment
echo -e "${GREEN}Activating virtual environment...${NC}"
source .venv/bin/activate

# Install requirements only if they've changed
MARKER=".venv/.deps_installed"
if [ ! -f "$MARKER" ] || [ "backend/requirements.txt" -nt "$MARKER" ]; then
    echo -e "${GREEN}Installing Python dependencies...${NC}"
    pip install --quiet --upgrade pip wheel
    pip install --quiet -r backend/requirements.txt
    touch "$MARKER"
else
    echo -e "${GREEN}Dependencies up to date${NC}"
fi

# Generate gRPC code if needed
if [ ! -f "backend/scribe_backend/proto/scribe_pb2.py" ]; then
    echo -e "${YELLOW}Generating gRPC code...${NC}"
    bash scripts/gen_proto.sh
fi

# Run the server (use -m for proper package imports)
echo -e "${GREEN}Starting backend server on localhost:50051${NC}"
echo "----------------------------------------"
cd "$PROJECT_ROOT/backend"
python -m scribe_backend.server