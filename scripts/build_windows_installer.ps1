# =====================================================================
# FinAudio Windows Installer Builder
# Builds Flutter release binaries and compiles the Inno Setup installer.
# =====================================================================

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
Set-Location $ProjectRoot

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   FinAudio Windows Installer Builder     " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Locate Inno Setup Compiler (ISCC)
$InnoPaths = @(
    "C:\Program Files\Inno Setup 7\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    (Get-Command iscc.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
)

$IsccExe = $InnoPaths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $IsccExe) {
    Write-Host "`n[ERROR] Inno Setup compiler (ISCC.exe) not found!" -ForegroundColor Red
    Write-Host "Please install Inno Setup 7 from https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
    Exit 1
}

Write-Host "`n[1/3] Found Inno Setup Compiler:" -ForegroundColor Green
Write-Host "      $IsccExe"

# 2. Build Flutter Windows Release
Write-Host "`n[2/3] Building Flutter Windows (Release mode)..." -ForegroundColor Green
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Flutter build failed." -ForegroundColor Red
    Exit $LASTEXITCODE
}

# 3. Compile Inno Setup Script
$IssScript = "$ProjectRoot\windows\installer\finaudio_setup.iss"
Write-Host "`n[3/3] Compiling Setup Wizard with Inno Setup..." -ForegroundColor Green
& "$IsccExe" "$IssScript"

if ($LASTEXITCODE -eq 0) {
    $OutputDir = "$ProjectRoot\build\installer"
    $InstallerFile = Get-ChildItem "$OutputDir\FinAudio-Setup-*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "`n=======================================================" -ForegroundColor Green
    Write-Host " SUCCESS! Installer generated at:" -ForegroundColor Green
    Write-Host " $($InstallerFile.FullName)" -ForegroundColor White
    Write-Host " Size: $([math]::Round($InstallerFile.Length / 1MB, 2)) MB" -ForegroundColor Gray
    Write-Host "=======================================================" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Inno Setup compilation failed." -ForegroundColor Red
    Exit $LASTEXITCODE
}

