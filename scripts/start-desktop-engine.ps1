param(
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Backend = Join-Path $Root "backend"
$VenvPython = Join-Path $Backend ".venv\Scripts\python.exe"
$Requirements = Join-Path $Backend "requirements.txt"
$Stamp = Join-Path $Backend ".venv\.desktop-deps.stamp"
$DataDir = Join-Path $Backend "data"
$PidFile = Join-Path $DataDir "desktop-engine-$Port.pid"

function Get-FirstCommandPath {
    param([string[]]$Names)

    foreach ($Name in $Names) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($Command) {
            return $Command.Source
        }
    }

    return $null
}

function Add-FFmpegPath {
    $FFmpeg = Get-FirstCommandPath @("ffmpeg.exe", "ffmpeg")
    if ($FFmpeg) {
        $BinDir = Split-Path -Parent $FFmpeg
        if ($env:Path -notlike "*$BinDir*") {
            $env:Path = "$BinDir;$env:Path"
        }
        return
    }

    $WingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $WingetRoot) {
        $Candidate = Get-ChildItem $WingetRoot -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($Candidate) {
            $BinDir = Split-Path -Parent $Candidate.FullName
            $env:Path = "$BinDir;$env:Path"
            return
        }
    }

    throw "FFmpeg을 찾을 수 없습니다. winget install Gyan.FFmpeg 후 다시 실행해 주세요."
}

function New-BackendVenv {
    Push-Location $Backend
    try {
        if (Get-Command py -ErrorAction SilentlyContinue) {
            try {
                py -3.12 -m venv .venv
                return
            } catch {
                try {
                    py -3.11 -m venv .venv
                    return
                } catch {
                    py -3 -m venv .venv
                    return
                }
            }
        }

        python -m venv .venv
    } finally {
        Pop-Location
    }
}

Add-FFmpegPath

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
$env:DATA_DIR = $DataDir
$env:PREVIEW_PROXY_SECONDS = "8"

New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
Set-Content -LiteralPath $PidFile -Value $PID -NoNewline -Encoding ascii

Push-Location $Root
try {
    & $VenvPython -m uvicorn app.main:app --app-dir $Backend --host 127.0.0.1 --port $Port
} finally {
    Pop-Location
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}
