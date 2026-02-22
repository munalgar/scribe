#!/usr/bin/env bash
set -euo pipefail

DRY_CHECK=false
for arg in "$@"; do
    if [ "$arg" = "--dry-check" ]; then
        DRY_CHECK=true
    else
        echo "Error: unexpected arguments: $*" >&2
        exit 1
    fi
done

dry_echo() {
    echo "[DRY-CHECK] $*"
}

# Get the root directory of the project
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROTO_DIR="$ROOT/proto"
PY_OUT="$ROOT/backend/scribe_backend/proto"
DART_OUT="$ROOT/frontend/flutter/scribe_app/lib/proto"
PROTO_FILE="$PROTO_DIR/scribe.proto"

if [ -x "$ROOT/.venv/bin/python" ]; then
    PYTHON_BIN="$ROOT/.venv/bin/python"
elif [ -x "$ROOT/.venv/Scripts/python.exe" ]; then
    PYTHON_BIN="$ROOT/.venv/Scripts/python.exe"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
else
    echo "Error: no suitable Python interpreter found (expected python3/python)." >&2
    exit 1
fi

if [ ! -f "$PROTO_FILE" ]; then
    echo "Error: proto file not found at $PROTO_FILE" >&2
    exit 1
fi

# Check required tools
if ! "$PYTHON_BIN" -c "import grpc_tools" < /dev/null 2>/dev/null; then
    echo "Error: grpc_tools not found. Install with: pip install grpcio-tools" >&2
    exit 1
fi

if command -v protoc >/dev/null 2>&1; then
    PROTOC_BIN="protoc"
elif command -v protoc.exe >/dev/null 2>&1; then
    PROTOC_BIN="protoc.exe"
else
    echo "Error: protoc not found. Install Protocol Buffers compiler." >&2
    exit 1
fi

echo "Generating gRPC code from proto files..."
if [ "$DRY_CHECK" = true ]; then
    dry_echo "Dry-check mode enabled; no files will be written."
fi

# Create output directories if they don't exist
if [ "$DRY_CHECK" = true ]; then
    dry_echo "Would ensure output directories exist: $PY_OUT, $DART_OUT"
else
    mkdir -p "$PY_OUT" "$DART_OUT"
fi

# Generate Python code
echo "Generating Python gRPC code..."
if [ "$DRY_CHECK" = true ]; then
    dry_echo "Would run: $PYTHON_BIN -m grpc_tools.protoc -I $PROTO_DIR --python_out=$PY_OUT --grpc_python_out=$PY_OUT $PROTO_FILE"
else
    "$PYTHON_BIN" -m grpc_tools.protoc \
        -I "$PROTO_DIR" \
        --python_out="$PY_OUT" \
        --grpc_python_out="$PY_OUT" \
        "$PROTO_FILE"
fi

# Fix absolute imports in generated grpc file to relative imports
# (grpc_tools generates 'import scribe_pb2' but we need 'from . import scribe_pb2')
if [ "$DRY_CHECK" = true ]; then
    dry_echo "Would patch Python import style in $PY_OUT/scribe_pb2_grpc.py"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's/^import scribe_pb2/from . import scribe_pb2/' "$PY_OUT/scribe_pb2_grpc.py"
else
    sed -i 's/^import scribe_pb2/from . import scribe_pb2/' "$PY_OUT/scribe_pb2_grpc.py"
fi

# Generate Dart code
echo "Generating Dart gRPC code..."
if [ -d "$HOME/.pub-cache/bin" ]; then
    export PATH="$HOME/.pub-cache/bin:$PATH"
fi
if [ "$DRY_CHECK" = true ]; then
    dry_echo "Would run: $PROTOC_BIN -I $PROTO_DIR --dart_out=grpc:$DART_OUT $PROTO_FILE"
else
    "$PROTOC_BIN" \
        -I "$PROTO_DIR" \
        --dart_out=grpc:"$DART_OUT" \
        "$PROTO_FILE"
fi

echo "gRPC code generation complete!"