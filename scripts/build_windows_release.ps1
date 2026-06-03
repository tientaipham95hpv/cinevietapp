$ErrorActionPreference = 'Stop'

Write-Host '== CineViet Windows release build ==' -ForegroundColor Cyan

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter command not found. Install Flutter and add it to PATH first.'
}

flutter config --enable-windows-desktop
flutter pub get
flutter clean
flutter build windows --release

$releaseDir = 'build\windows\x64\runner\Release'
if (-not (Test-Path $releaseDir)) {
  throw "Release folder not found: $releaseDir"
}

$outDir = 'build\windows\package'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$zip = Join-Path $outDir 'CineViet-Windows-1.0.1.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }

Compress-Archive -Path "$releaseDir\*" -DestinationPath $zip -Force

Write-Host ''
Write-Host "DONE: $zip" -ForegroundColor Green
Write-Host "EXE:  $releaseDir\CineViet.exe" -ForegroundColor Green
Write-Host ''
Write-Host 'Upload ZIP to /var/www/html/apk/cineviet-windows.zip or send it back to Thảo to publish.' -ForegroundColor Yellow
