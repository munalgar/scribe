param(
    [switch]$DryCheck
)

# PowerShell script to generate gRPC code
$ErrorActionPreference = "Stop"

function Write-DryCheck {
    param([string]$Message)
    Write-Host "[DRY-CHECK] $Message" -ForegroundColor Cyan
}

# Get the root directory of the project
$ROOT = Split-Path -Parent $PSScriptRoot
$PROTO_DIR = Join-Path $ROOT "proto"
$PY_OUT = Join-Path $ROOT "backend/scribe_backend/proto"
$DART_OUT = Join-Path $ROOT "frontend/flutter/scribe_app/lib/proto"
$PROTO_FILE = Join-Path $PROTO_DIR "scribe.proto"

function Resolve-PythonCommand {
    $venvCandidates = @(
        (Join-Path $ROOT ".venv/Scripts/python.exe"),
        (Join-Path $ROOT ".venv/bin/python")
    )
    foreach ($candidate in $venvCandidates) {
        if (Test-Path $candidate) {
            return @{
                Executable = $candidate
                PrefixArgs = @()
            }
        }
    }

    if (Get-Command py -ErrorAction SilentlyContinue) {
        return @{
            Executable = "py"
            PrefixArgs = @("-3")
        }
    }
    if (Get-Command python3 -ErrorAction SilentlyContinue) {
        return @{
            Executable = "python3"
            PrefixArgs = @()
        }
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        return @{
            Executable = "python"
            PrefixArgs = @()
        }
    }
    throw "No suitable Python interpreter found (expected py/python3/python)."
}

function Invoke-PythonCommand {
    param([string[]]$Arguments)
    & $script:PythonCommand.Executable @($script:PythonCommand.PrefixArgs + $Arguments)
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path $PROTO_FILE)) {
    throw "Proto file not found at $PROTO_FILE"
}

$script:PythonCommand = Resolve-PythonCommand
Invoke-PythonCommand @("-c", "import grpc_tools")

if (Get-Command protoc -ErrorAction SilentlyContinue) {
    $script:ProtocBin = "protoc"
} elseif (Get-Command protoc.exe -ErrorAction SilentlyContinue) {
    $script:ProtocBin = "protoc.exe"
} else {
    throw "protoc not found. Install Protocol Buffers compiler."
}

# Check for protoc-gen-dart (Dart protoc plugin)
# Required minimum version to generate code compatible with protobuf ^6.0.0
$MinDartPluginVersion = 21
$homeDir = if ($env:USERPROFILE) {
    $env:USERPROFILE
} elseif ($env:HOME) {
    $env:HOME
} else {
    [Environment]::GetFolderPath("UserProfile")
}
$pubCacheBin = Join-Path $homeDir ".pub-cache/bin"
if (Test-Path $pubCacheBin) {
    $pathSeparator = [System.IO.Path]::PathSeparator
    $env:PATH = "$pubCacheBin$pathSeparator$env:PATH"
}
$dartPluginInstalled = Get-Command protoc-gen-dart -ErrorAction SilentlyContinue
if (-not $dartPluginInstalled) {
    Write-Host "protoc-gen-dart not found. Installing protoc_plugin..."
    dart pub global activate protoc_plugin
} else {
    $dartPluginList = dart pub global list 2>$null | Select-String 'protoc_plugin'
    if ($dartPluginList -match 'protoc_plugin (\d+)') {
        $dartPluginMajor = [int]$Matches[1]
        if ($dartPluginMajor -lt $MinDartPluginVersion) {
            Write-Host "protoc_plugin is too old (need >=$MinDartPluginVersion.0.0 for protobuf ^6.0.0). Updating..."
            dart pub global activate protoc_plugin
        }
    }
}

Write-Host "Generating gRPC code from proto files..."
if ($DryCheck) {
    Write-DryCheck "Dry-check mode enabled; no files will be written."
}

# Create output directories if they don't exist
if ($DryCheck) {
    Write-DryCheck "Would ensure output directories exist: $PY_OUT, $DART_OUT"
} else {
    New-Item -ItemType Directory -Force -Path $PY_OUT | Out-Null
    New-Item -ItemType Directory -Force -Path $DART_OUT | Out-Null
}

# Generate Python code
Write-Host "Generating Python gRPC code..."
if ($DryCheck) {
    $pythonPreview = @($script:PythonCommand.Executable) + $script:PythonCommand.PrefixArgs
    Write-DryCheck "Would run: $($pythonPreview -join ' ') -m grpc_tools.protoc -I $PROTO_DIR --python_out=$PY_OUT --grpc_python_out=$PY_OUT $PROTO_FILE"
} else {
    Invoke-PythonCommand @(
        "-m", "grpc_tools.protoc",
        "-I", $PROTO_DIR,
        "--python_out=$PY_OUT",
        "--grpc_python_out=$PY_OUT",
        $PROTO_FILE
    )
}

# Fix absolute imports in generated grpc file to relative imports
$grpcFile = Join-Path $PY_OUT "scribe_pb2_grpc.py"
if ($DryCheck) {
    Write-DryCheck "Would patch Python import style in $grpcFile"
} else {
    (Get-Content $grpcFile) -replace '^import scribe_pb2(.*)$', 'from . import scribe_pb2$1' | Set-Content $grpcFile
}

# Generate Dart code
Write-Host "Generating Dart gRPC code..."
if ($DryCheck) {
    Write-DryCheck "Would run: $($script:ProtocBin) -I $PROTO_DIR --dart_out=grpc:$DART_OUT $PROTO_FILE"
} else {
    & $script:ProtocBin `
        -I $PROTO_DIR `
        --dart_out=grpc:$DART_OUT `
        $PROTO_FILE
}

Write-Host "gRPC code generation complete!"