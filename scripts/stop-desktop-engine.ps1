param(
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Backend = [IO.Path]::GetFullPath((Join-Path $Root "backend"))
$PidFile = Join-Path $Backend "data\desktop-engine-$Port.pid"
$Listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $Listener) {
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    exit 0
}

$OwnerPid = [int]$Listener.OwningProcess
$CurrentPid = $OwnerPid
$RootPid = $OwnerPid
$VerifiedBackend = $false

for ($Depth = 0; $Depth -lt 8 -and $CurrentPid -gt 0; $Depth++) {
    $Process = Get-CimInstance Win32_Process -Filter "ProcessId=$CurrentPid" -ErrorAction SilentlyContinue
    if (-not $Process) {
        break
    }

    $CommandLine = [string]$Process.CommandLine
    if (
        $CommandLine -like "*uvicorn app.main:app*" -and
        $CommandLine.ToLowerInvariant().Contains($Backend.ToLowerInvariant())
    ) {
        $VerifiedBackend = $true
    }
    if ($CommandLine -like "*start-desktop-engine.ps1*") {
        $RootPid = [int]$Process.ProcessId
        break
    }

    $ParentPid = [int]$Process.ParentProcessId
    if ($ParentPid -le 0 -or $ParentPid -eq $CurrentPid) {
        break
    }
    $CurrentPid = $ParentPid
}

if (-not $VerifiedBackend) {
    throw "Port $Port is not owned by this AutoEdit backend."
}

& taskkill.exe /PID $RootPid /T /F 2>$null | Out-Null

for ($Attempt = 0; $Attempt -lt 30; $Attempt++) {
    Start-Sleep -Milliseconds 200
    if (-not (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        exit 0
    }
}

throw "AutoEdit backend on port $Port did not stop."
