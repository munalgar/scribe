# PowerShell script to generate gRPC code for Windows
$ErrorActionPreference = "Stop"

# Get the root directory of the project
$ROOT = Split-Path -Parent $PSScriptRoot
$PROTO_DIR = Join-Path $ROOT "proto"
$PY_OUT = Join-Path $ROOT "backend\scribe_backend\proto"
$DART_OUT = Join-Path $ROOT "frontend\flutter\scribe_app\lib\proto"

Write-Host "Generating gRPC code from proto files..."

# Create output directories if they don't exist
New-Item -ItemType Directory -Force -Path $PY_OUT | Out-Null
New-Item -ItemType Directory -Force -Path $DART_OUT | Out-Null

# Generate Python code
Write-Host "Generating Python gRPC code..."
python -m grpc_tools.protoc `
    -I $PROTO_DIR `
    --python_out=$PY_OUT `
    --grpc_python_out=$PY_OUT `
    (Join-Path $PROTO_DIR "scribe.proto")

# Fix absolute imports in generated grpc file to relative imports
$grpcFile = Join-Path $PY_OUT "scribe_pb2_grpc.py"
(Get-Content $grpcFile) -replace '^import scribe_pb2', 'from . import scribe_pb2' | Set-Content $grpcFile

# Generate Dart code
Write-Host "Generating Dart gRPC code..."
protoc `
    -I $PROTO_DIR `
    --dart_out=grpc:$DART_OUT `
    (Join-Path $PROTO_DIR "scribe.proto")

Write-Host "gRPC code generation complete!"