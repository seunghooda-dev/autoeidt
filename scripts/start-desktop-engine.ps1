param(
    [int]$Port = 8000,
    [string]$WorkspaceRoot = ""
)

$ErrorActionPreference = "Stop"

$Root = if ($WorkspaceRoot) {
    [IO.Path]::GetFullPath($WorkspaceRoot)
} else {
    Split-Path -Parent $PSScriptRoot
}
$Backend = Join-Path $Root "backend"
$Requirements = Join-Path $Backend "requirements.txt"
$IsSourceWorkspace = Test-Path -LiteralPath (Join-Path $Root ".git")
$RuntimeRoot = if ($IsSourceWorkspace) {
    $Backend
} else {
    Join-Path $env:LOCALAPPDATA "AutoEdit\engine-runtime"
}
$VenvDir = Join-Path $RuntimeRoot ".venv"
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
$Stamp = Join-Path $VenvDir ".desktop-deps.stamp"
$DataDir = if ($IsSourceWorkspace) {
    Join-Path $Backend "data"
} else {
    Join-Path $env:LOCALAPPDATA "AutoEdit\engine-data"
}
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
    function Invoke-VenvCreation {
        param(
            [string]$Executable,
            [string[]]$PrefixArguments = @()
        )

        try {
            & $Executable @PrefixArguments -m venv $VenvDir 2>&1 | Out-Host
            $Succeeded = $LASTEXITCODE -eq 0
        } catch {
            Write-Host $_
            $Succeeded = $false
        }
        return [bool]($Succeeded -and (Test-Path -LiteralPath $VenvPython))
    }

    New-Item -ItemType Directory -Path $RuntimeRoot -Force | Out-Null
    Push-Location $RuntimeRoot
    try {
        $PyLauncher = Join-Path $env:WINDIR "py.exe"
        if (Test-Path -LiteralPath $PyLauncher) {
            foreach ($Version in @("-3.12", "-3.11", "-3")) {
                if (Invoke-VenvCreation -Executable $PyLauncher -PrefixArguments @($Version)) {
                    return
                }
            }
        }

        $Candidates = @(
            (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
            (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"),
            (Join-Path $env:LOCALAPPDATA "Python\pythoncore-3.14-64\python.exe")
        )
        foreach ($Candidate in $Candidates) {
            if (
                (Test-Path -LiteralPath $Candidate) -and
                (Invoke-VenvCreation -Executable $Candidate)
            ) {
                return
            }
        }

        $Python = Get-Command python.exe -ErrorAction SilentlyContinue
        if (
            $Python -and
            $Python.Source -notlike "*\WindowsApps\*" -and
            (Invoke-VenvCreation -Executable $Python.Source)
        ) {
            return
        }

        throw "Python 3.11 이상 런타임을 찾지 못해 로컬 엔진 환경을 만들 수 없습니다."
    } finally {
        Pop-Location
    }
}

Add-FFmpegPath

if (-not (Test-Path $VenvPython)) {
    New-BackendVenv
}

if (-not (Test-Path -LiteralPath $VenvPython)) {
    throw "로컬 엔진 Python을 준비하지 못했습니다: $VenvPython"
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
