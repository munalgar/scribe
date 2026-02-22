param(
    [string]$Platform,
    [switch]$DryCheck
)

$ErrorActionPreference = "Stop"

function Write-DryCheck {
    param([string]$Message)
    Write-Host "[DRY-CHECK] $Message" -ForegroundColor Cyan
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
    (Join-Path $homeDir ".pub-cache/bin")
) | Where-Object { Test-Path $_ }
if ($extraPaths.Count -gt 0) {
    $env:PATH = ($extraPaths -join $pathSeparator) + $pathSeparator + $env:PATH
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "flutter command not found. Add Flutter to PATH or install it first."
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
    }
} else {
    Write-Host "Dependencies up to date" -ForegroundColor Green
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
    }
} else {
    if ($DryCheck) {
        Write-DryCheck "Would run: flutter run -d $Platform"
    } else {
        flutter run -d $Platform
    }
}
