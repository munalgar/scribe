#!/usr/bin/env bash
set -euo pipefail

# Get the root directory of the project
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROTO_DIR="$ROOT/proto"
PY_OUT="$ROOT/backend/scribe_backend/proto"
DART_OUT="$ROOT/frontend/flutter/scribe_app/lib/proto"

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

# Generate Dart code
echo "Generating Dart gRPC code..."
export PATH="$HOME/.pub-cache/bin:$PATH"
protoc \
    -I "$PROTO_DIR" \
    --dart_out=grpc:"$DART_OUT" \
    "$PROTO_DIR/scribe.proto"

echo "gRPC code generation complete!"