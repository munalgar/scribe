param(
    [switch]$DryCheck
)

$ErrorActionPreference = "Stop"

function Write-DryCheck {
    param([string]$Message)
    Write-Host "[DRY-CHECK] $Message" -ForegroundColor Cyan
}

Write-Host "Starting Scribe Backend Development Server" -ForegroundColor Green
if ($DryCheck) {
    Write-DryCheck "Dry-check mode enabled; no changes will be made."
}

$SCRIPT_DIR = $PSScriptRoot
$PROJECT_ROOT = Split-Path -Parent $SCRIPT_DIR
Set-Location $PROJECT_ROOT

$script:IsWindowsHost = $env:OS -eq "Windows_NT"
$venvPath = Join-Path $PROJECT_ROOT ".venv"
$venvPythonCandidates = @(
    (Join-Path $venvPath "Scripts/python.exe"),
    (Join-Path $venvPath "bin/python")
)
$venvPython = $venvPythonCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $venvPython) {
    # Prefer the Windows layout when probing in dry-check mode before venv creation.
    $venvPython = $venvPythonCandidates[0]
}

function New-Venv {
    param(
        [string]$Path,
        [switch]$DryCheckOnly
    )

    if ($script:IsWindowsHost -and (Get-Command py -ErrorAction SilentlyContinue)) {
        if ($DryCheckOnly) {
            Write-DryCheck "Would run: py -3 -m venv $Path"
            return
        }
        & py -3 -m venv $Path
        return
    }
    if (Get-Command python3 -ErrorAction SilentlyContinue) {
        if ($DryCheckOnly) {
            Write-DryCheck "Would run: python3 -m venv $Path"
            return
        }
        & python3 -m venv $Path
        return
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        if ($DryCheckOnly) {
            Write-DryCheck "Would run: python -m venv $Path"
            return
        }
        & python -m venv $Path
        return
    }

    throw "No suitable Python interpreter found (expected py/python3/python)."
}

function Get-ListeningPids {
    param([int]$Port)

    if ($script:IsWindowsHost) {
        $netstatMatches = netstat -ano | Select-String ":$Port\s" | Select-String "LISTENING"
        $pids = @()
        foreach ($match in $netstatMatches) {
            $parts = $match.ToString().Trim() -split '\s+'
            $candidate = $parts[-1]
            if ($candidate -match '^\d+$') {
                $pids += [int]$candidate
            }
        }
        return $pids | Sort-Object -Unique
    }

    if (Get-Command lsof -ErrorAction SilentlyContinue) {
        $pids = lsof -ti "tcp:$Port" 2>$null | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
        return $pids | Sort-Object -Unique
    }

    return @()
}

if (-not (Test-Path $venvPath)) {
    Write-Host "Creating Python virtual environment..." -ForegroundColor Yellow
    New-Venv -Path $venvPath -DryCheckOnly:$DryCheck
}

if (-not (Test-Path $venvPython)) {
    if ($DryCheck) {
        Write-DryCheck "Virtual environment Python executable not found at $venvPython (expected until first non-dry run)."
    } else {
        throw "Virtual environment Python executable not found at $venvPython"
    }
}

if (Test-Path $venvPython) {
    Write-Host "Using virtual environment Python: $venvPython" -ForegroundColor Green
} elseif ($DryCheck) {
    Write-DryCheck "Would use virtual environment Python: $venvPython"
}

$marker = Join-Path $venvPath ".deps_installed"
$requirements = Join-Path $PROJECT_ROOT "backend/requirements.txt"
if (-not (Test-Path $requirements)) {
    throw "Requirements file not found at $requirements"
}

$shouldInstall = -not (Test-Path $marker)
if (-not $shouldInstall) {
    $shouldInstall = (Get-Item $requirements).LastWriteTime -gt (Get-Item $marker).LastWriteTime
}

if ($shouldInstall) {
    if ($DryCheck) {
        Write-DryCheck "Would install Python dependencies from $requirements"
    } else {
        Write-Host "Installing Python dependencies..." -ForegroundColor Green
        & $venvPython -m pip install --quiet --upgrade pip wheel
        & $venvPython -m pip install --quiet -r $requirements
        New-Item -ItemType File -Force -Path $marker | Out-Null
    }
} else {
    Write-Host "Dependencies up to date" -ForegroundColor Green
}

$protoOut = Join-Path $PROJECT_ROOT "backend/scribe_backend/proto/scribe_pb2.py"
if (-not (Test-Path $protoOut)) {
    if ($DryCheck) {
        Write-DryCheck "Would generate gRPC code via scripts/gen_proto.ps1"
    } else {
        Write-Host "Generating gRPC code..." -ForegroundColor Yellow
        & (Join-Path $PROJECT_ROOT "scripts/gen_proto.ps1")
    }
}

# Check if port 50051 is already in use
$port = 50051
$existingPids = @(Get-ListeningPids -Port $port)
if ($existingPids.Count -gt 0) {
    $pidList = $existingPids -join ', '
    Write-Host "Error: Port $port is already in use (PID: $pidList)." -ForegroundColor Red
    Write-Host "Stop the existing process first, then try again." -ForegroundColor Yellow
    exit 1
}

Write-Host "Starting backend server on localhost:50051" -ForegroundColor Green
Write-Host "----------------------------------------"
if ($DryCheck) {
    Write-DryCheck "Would run from backend/: $venvPython -m scribe_backend.server"
    return
}

Set-Location (Join-Path $PROJECT_ROOT "backend")
& $venvPython -m scribe_backend.server
