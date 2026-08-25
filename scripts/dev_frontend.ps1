param(
    [string]$Platform,
    [switch]$DryCheck,
    [switch]$PrepareOnly
)

$ErrorActionPreference = "Stop"

function Write-DryCheck {
    param([string]$Message)
    Write-Host "[DRY-CHECK] $Message" -ForegroundColor Cyan
}

function Assert-LastExitCode {
    param([string]$CommandName)
    if ($LASTEXITCODE -ne 0) {
        throw "$CommandName failed with exit code $LASTEXITCODE"
    }
}

Write-Host "Starting Scribe Frontend (Flutter)" -ForegroundColor Green
if ($DryCheck) {
    Write-DryCheck "Dry-check mode enabled; no changes will be made."
}

$SCRIPT_DIR = $PSScriptRoot
$PROJECT_ROOT = Split-Path -Parent $SCRIPT_DIR
$FLUTTER_APP = Join-Path $PROJECT_ROOT "frontend/flutter/scribe_app"

$homeDir = if ($env:USERPROFILE) {
    $env:USERPROFILE
} elseif ($env:HOME) {
    $env:HOME
} else {
    [Environment]::GetFolderPath("UserProfile")
}
$pathSeparator = [System.IO.Path]::PathSeparator
$extraPaths = @(
    (Join-Path $homeDir "flutter/bin"),
    (Join-Path $homeDir "develop/flutter/bin"),
    (Join-Path $homeDir "development/flutter/bin"),
    (Join-Path $homeDir ".pub-cache/bin")
) | Where-Object { Test-Path $_ }
if ($extraPaths.Count -gt 0) {
    $env:PATH = ($extraPaths -join $pathSeparator) + $pathSeparator + $env:PATH
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter SDK not found. Install Flutter, add its bin directory to PATH, then run flutter doctor. See https://docs.flutter.dev/install"
}
if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
    throw "dart command not found. Flutter is present, but its bundled Dart SDK is not on PATH. See https://docs.flutter.dev/install/add-to-path"
}

Set-Location $FLUTTER_APP

$dartTool = Join-Path $FLUTTER_APP ".dart_tool"
$pubspec = Join-Path $FLUTTER_APP "pubspec.yaml"
$pubspecLock = Join-Path $FLUTTER_APP "pubspec.lock"

$needsPubGet = -not (Test-Path $dartTool)
if (-not $needsPubGet) {
    if (-not (Test-Path $pubspecLock)) {
        $needsPubGet = $true
    } else {
        $needsPubGet = (Get-Item $pubspec).LastWriteTime -gt (Get-Item $pubspecLock).LastWriteTime
    }
}

if ($needsPubGet) {
    if ($DryCheck) {
        Write-DryCheck "Would run: flutter pub get"
    } else {
        Write-Host "Installing Flutter dependencies..." -ForegroundColor Yellow
        flutter pub get
        Assert-LastExitCode "flutter pub get"
    }
} else {
    Write-Host "Dependencies up to date" -ForegroundColor Green
}

$protoFile = Join-Path $PROJECT_ROOT "proto/scribe.proto"
$dartProtoFile = Join-Path $FLUTTER_APP "lib/proto/scribe.pb.dart"
$needsProto = -not (Test-Path $dartProtoFile)
if (-not $needsProto) {
    $needsProto = (Get-Item $protoFile).LastWriteTime -gt (Get-Item $dartProtoFile).LastWriteTime
}
if ($needsProto) {
    if ($DryCheck) {
        Write-DryCheck "Would generate Dart gRPC code via scripts/gen_proto.ps1 -DartOnly"
    } else {
        Write-Host "Generating Dart gRPC code..." -ForegroundColor Yellow
        & (Join-Path $PROJECT_ROOT "scripts/gen_proto.ps1") -DartOnly
    }
}

if ($PrepareOnly) {
    Write-Host "Frontend development environment ready" -ForegroundColor Green
    return
}

if ([string]::IsNullOrWhiteSpace($Platform)) {
    $osDescription = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    if ($env:OS -eq "Windows_NT" -or $osDescription -match "Windows") {
        $Platform = "windows"
    } elseif ($osDescription -match "Darwin|Mac|macOS") {
        $Platform = "macos"
    } elseif ($osDescription -match "Linux") {
        $Platform = "linux"
    } else {
        $Platform = ""
        Write-Host "Could not auto-detect platform; using Flutter default device selection" -ForegroundColor Yellow
    }
    if (-not [string]::IsNullOrWhiteSpace($Platform)) {
        Write-Host "Auto-detected platform: $Platform" -ForegroundColor Yellow
    }
}

if ([string]::IsNullOrWhiteSpace($Platform)) {
    Write-Host "Starting Flutter app using default device selection" -ForegroundColor Green
} else {
    Write-Host "Starting Flutter app for $Platform" -ForegroundColor Green
}
Write-Host "----------------------------------------"
if ([string]::IsNullOrWhiteSpace($Platform)) {
    if ($DryCheck) {
        Write-DryCheck "Would run: flutter run"
    } else {
        flutter run
        Assert-LastExitCode "flutter run"
    }
} else {
    if ($DryCheck) {
        Write-DryCheck "Would run: flutter run -d $Platform"
    } else {
        flutter run -d $Platform
        Assert-LastExitCode "flutter run -d $Platform"
    }
}
