#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
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

# Upgrade pip
echo -e "${GREEN}Upgrading pip...${NC}"
pip install --quiet --upgrade pip wheel

# Install requirements
echo -e "${GREEN}Installing Python dependencies...${NC}"
pip install --quiet -r backend/requirements.txt

# Generate gRPC code if needed
if [ ! -f "backend/scribe_backend/proto/scribe_pb2.py" ]; then
    echo -e "${YELLOW}Generating gRPC code...${NC}"
    bash scripts/gen_proto.sh
fi

# Run the server
echo -e "${GREEN}Starting backend server on localhost:50051${NC}"
echo "----------------------------------------"
python backend/scribe_backend/server.py