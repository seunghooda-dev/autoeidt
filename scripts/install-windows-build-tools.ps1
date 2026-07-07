param(
    [switch]$Passive
)

$ErrorActionPreference = "Stop"

$InstallerDir = Join-Path $env:TEMP "AutoEditBuildTools"
$Installer = Join-Path $InstallerDir "vs_BuildTools.exe"
$Url = "https://aka.ms/vs/17/release/vs_BuildTools.exe"

New-Item -ItemType Directory -Path $InstallerDir -Force | Out-Null

if (-not (Test-Path $Installer)) {
    Invoke-WebRequest -Uri $Url -OutFile $Installer
}

$InstallArgs = @(
    "--wait",
    "--norestart",
    "--nocache",
    "--installPath", "C:\BuildTools",
    "--add", "Microsoft.VisualStudio.Workload.VCTools",
    "--includeRecommended"
)

if ($Passive) {
    $InstallArgs = @("--passive") + $InstallArgs
}

Start-Process -FilePath $Installer -ArgumentList $InstallArgs -Verb RunAs -Wait

Write-Host "Visual Studio Build Tools 설치가 끝났습니다. 새 터미널에서 flutter doctor -v를 확인해 주세요."
