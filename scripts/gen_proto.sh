#!/usr/bin/env bash
set -euo pipefail

# Get the root directory of the project
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROTO_DIR="$ROOT/proto"
PY_OUT="$ROOT/backend/scribe_backend/proto"
DART_OUT="$ROOT/frontend/flutter/scribe_app/lib/proto"

# Check required tools
if ! python3 -c "import grpc_tools" 2>/dev/null; then
    echo "Error: grpc_tools not found. Install with: pip install grpcio-tools" >&2
    exit 1
fi

if ! command -v protoc &>/dev/null; then
    echo "Error: protoc not found. Install Protocol Buffers compiler." >&2
    exit 1
fi

echo "Generating gRPC code from proto files..."

# Create output directories if they don't exist
mkdir -p "$PY_OUT" "$DART_OUT"

# Generate Python code
echo "Generating Python gRPC code..."
python3 -m grpc_tools.protoc \
    -I "$PROTO_DIR" \
    --python_out="$PY_OUT" \
    --grpc_python_out="$PY_OUT" \
    "$PROTO_DIR/scribe.proto"

# Fix absolute imports in generated grpc file to relative imports
# (grpc_tools generates 'import scribe_pb2' but we need 'from . import scribe_pb2')
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's/^import scribe_pb2/from . import scribe_pb2/' "$PY_OUT/scribe_pb2_grpc.py"
else
    sed -i 's/^import scribe_pb2/from . import scribe_pb2/' "$PY_OUT/scribe_pb2_grpc.py"
fi

# Generate Dart code
echo "Generating Dart gRPC code..."
export PATH="$HOME/.pub-cache/bin:$PATH"
protoc \
    -I "$PROTO_DIR" \
    --dart_out=grpc:"$DART_OUT" \
    "$PROTO_DIR/scribe.proto"

echo "gRPC code generation complete!"