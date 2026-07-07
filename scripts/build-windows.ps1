param(
    [string]$ApiBaseUrl = "http://localhost:8000",
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Frontend = Join-Path $Root "frontend"
$ReleaseDir = Join-Path $Frontend "build\windows\x64\runner\Release"
$ArtifactDir = Join-Path $Root "dist"
$ZipPath = Join-Path $ArtifactDir "AutoEdit-windows-x64.zip"

function Assert-Command {
    param([string]$Name, [string]$Help)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name 명령을 찾지 못했습니다. $Help"
    }
}

function Assert-VisualStudioTools {
    $VsWhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $VsWhere)) {
        throw "Visual Studio Build Tools가 없습니다. .\scripts\install-windows-build-tools.ps1 -Passive 를 먼저 실행해 주세요."
    }

    $InstallPath = & $VsWhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $InstallPath) {
        throw "C++ 빌드 도구가 없습니다. Visual Studio Installer에서 Desktop development with C++ 또는 VCTools를 설치해 주세요."
    }
}

Assert-Command "flutter" "Flutter SDK가 PATH에 있어야 합니다."
Assert-Command "ffmpeg" "winget install Gyan.FFmpeg 로 FFmpeg를 설치해 주세요."
Assert-VisualStudioTools

Push-Location $Frontend
try {
    flutter config --enable-windows-desktop
    flutter pub get
    if (-not $SkipTests) {
        flutter analyze
        flutter test
    }
    flutter build windows --release --dart-define=API_BASE_URL=$ApiBaseUrl
} finally {
    Pop-Location
}

if (-not (Test-Path (Join-Path $ReleaseDir "AutoEdit.exe"))) {
    throw "AutoEdit.exe 빌드 산출물을 찾지 못했습니다."
}

New-Item -ItemType Directory -Path $ArtifactDir -Force | Out-Null
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

Compress-Archive -Path (Join-Path $ReleaseDir "*") -DestinationPath $ZipPath
Write-Host "Windows 패키지 생성 완료: $ZipPath"
