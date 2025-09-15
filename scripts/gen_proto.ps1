# PowerShell script to generate gRPC code for Windows

Write-Host "Generating gRPC code from proto files..."

# Generate Python code
Write-Host "Generating Python gRPC code..."
python -m grpc_tools.protoc `
    -I proto `
    --python_out backend/scribe_backend/proto `
    --grpc_python_out backend/scribe_backend/proto `
    proto/scribe.proto

# Generate Dart code
Write-Host "Generating Dart gRPC code..."
protoc `
    -I proto `
    --dart_out=grpc:frontend/flutter/scribe_app/lib/proto `
    proto/scribe.proto

Write-Host "gRPC code generation complete!"