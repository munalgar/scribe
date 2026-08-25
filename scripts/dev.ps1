param(
    [string]$Platform,
    [switch]$DryCheck
)

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $scriptDir
$frontendScript = Join-Path $scriptDir "dev_frontend.ps1"
$backendScript = Join-Path $scriptDir "dev_backend.ps1"
$backendProcess = $null

function Invoke-Frontend {
    param(
        [switch]$PrepareOnly,
        [switch]$CheckOnly
    )

    $arguments = @{}
    if (-not [string]::IsNullOrWhiteSpace($Platform)) {
        $arguments.Platform = $Platform
    }
    if ($PrepareOnly) {
        $arguments.PrepareOnly = $true
    }
    if ($CheckOnly) {
        $arguments.DryCheck = $true
    }

    & $frontendScript @arguments
}

function Test-BackendReady {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connection = $client.ConnectAsync("127.0.0.1", 50051)
        return $connection.Wait(200) -and $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Stop-Backend {
    if ($null -eq $script:backendProcess) {
        return
    }

    $script:backendProcess.Refresh()
    if ($script:backendProcess.HasExited) {
        return
    }

    Write-Host "Stopping Scribe backend..." -ForegroundColor Yellow
    if ($env:OS -eq "Windows_NT") {
        & taskkill /PID $script:backendProcess.Id /T /F 2>$null | Out-Null
    } else {
        Stop-Process -Id $script:backendProcess.Id -Force -ErrorAction SilentlyContinue
    }
    $script:backendProcess.WaitForExit(5000) | Out-Null
}

Set-Location $projectRoot
Write-Host "Starting Scribe development environment" -ForegroundColor Green

if ($DryCheck) {
    Invoke-Frontend -PrepareOnly -CheckOnly
    & $backendScript -DryCheck
    return
}

try {
    Invoke-Frontend -PrepareOnly

    if (Test-BackendReady) {
        throw "Port 50051 is already in use. Stop the existing backend first."
    }

    $powershellExecutable = (Get-Process -Id $PID).Path
    $escapedBackendScript = $backendScript.Replace('"', '\"')
    $backendArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$escapedBackendScript`""
    $script:backendProcess = Start-Process `
        -FilePath $powershellExecutable `
        -ArgumentList $backendArguments `
        -NoNewWindow `
        -PassThru

    Write-Host "Waiting for backend on 127.0.0.1:50051..." -ForegroundColor Yellow
    $ready = $false
    for ($attempt = 0; $attempt -lt 1200; $attempt++) {
        $script:backendProcess.Refresh()
        if ($script:backendProcess.HasExited) {
            $exitCode = $script:backendProcess.ExitCode
            if ($exitCode -eq 0) {
                $exitCode = 1
            }
            throw "Backend exited before it became ready (status $exitCode)."
        }
        if (Test-BackendReady) {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 250
    }

    if (-not $ready) {
        throw "Backend did not become ready within 5 minutes."
    }

    Invoke-Frontend
} finally {
    Stop-Backend
}
