param(
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Backend = Join-Path $Root "backend"
$VenvPython = Join-Path $Backend ".venv\Scripts\python.exe"
$Requirements = Join-Path $Backend "requirements.txt"
$Stamp = Join-Path $Backend ".venv\.desktop-deps.stamp"

function New-BackendVenv {
    Push-Location $Backend
    try {
        if (Get-Command py -ErrorAction SilentlyContinue) {
            try {
                py -3.12 -m venv .venv
                return
            } catch {
                py -3 -m venv .venv
                return
            }
        }

        python -m venv .venv
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path $VenvPython)) {
    New-BackendVenv
}

$NeedsInstall = -not (Test-Path $Stamp)
if (-not $NeedsInstall) {
    $NeedsInstall = (Get-Item $Requirements).LastWriteTimeUtc -gt (Get-Item $Stamp).LastWriteTimeUtc
}

if ($NeedsInstall) {
    & $VenvPython -m pip install --upgrade pip
    & $VenvPython -m pip install -r $Requirements
    New-Item -ItemType File -Path $Stamp -Force | Out-Null
}

$env:TASK_RUNNER = "inline"
$env:REDIS_URL = "redis://localhost:6379/0"
$env:DATA_DIR = Join-Path $Backend "data"

Push-Location $Root
try {
    & $VenvPython -m uvicorn app.main:app --app-dir $Backend --host 127.0.0.1 --port $Port
} finally {
    Pop-Location
}
