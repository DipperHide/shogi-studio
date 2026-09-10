$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Get-Content -LiteralPath "$env:USERPROFILE\Development\toolchain.json" -Raw | ConvertFrom-Json
$env:JAVA_HOME = $toolchain.jdk
$env:ANDROID_HOME = $toolchain.sdk
$env:ANDROID_SDK_ROOT = $toolchain.sdk
$godotConsole = $toolchain.godot -replace '_win64.exe$', '_win64_console.exe'
$snapshot = & (Join-Path $taskRoot '.venv\Scripts\python.exe') (Join-Path $PSScriptRoot 'prepare_classic_build.py') | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Classic snapshot preparation failed' }
New-Item -ItemType Directory -Force -Path (Join-Path $snapshot.output 'windows') | Out-Null
& $godotConsole --headless --path $snapshot.project --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Classic import failed' }
& $godotConsole --headless --path $snapshot.project --export-debug Android (Join-Path $snapshot.output 'shogi-classic.apk')
if ($LASTEXITCODE -ne 0) { throw 'Classic Android export failed' }
& $godotConsole --headless --path $snapshot.project --export-debug 'Windows Desktop' (Join-Path $snapshot.output 'windows\ShogiClassic.exe')
if ($LASTEXITCODE -ne 0) { throw 'Classic Windows export failed' }
Write-Output $snapshot.output
