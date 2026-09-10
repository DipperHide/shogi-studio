param([switch]$Release)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Get-Content -LiteralPath "$env:USERPROFILE\Development\toolchain.json" -Raw | ConvertFrom-Json
$env:JAVA_HOME = $toolchain.jdk
$env:ANDROID_HOME = $toolchain.sdk
$env:ANDROID_SDK_ROOT = $toolchain.sdk
$godotConsole = $toolchain.godot -replace '_win64.exe$', '_win64_console.exe'
New-Item -ItemType Directory -Force -Path (Join-Path $taskRoot 'builds') | Out-Null
& (Join-Path $taskRoot '.venv\Scripts\python.exe') (Join-Path $PSScriptRoot 'test_android_startup.py')
if ($LASTEXITCODE -ne 0) { throw 'Android startup regression checks failed' }
& (Join-Path $taskRoot '.venv\Scripts\python.exe') (Join-Path $PSScriptRoot 'prepare_android_build.py')
if ($LASTEXITCODE -ne 0) { throw 'Android template preparation failed' }
& (Join-Path $taskRoot '.venv\Scripts\python.exe') (Join-Path $PSScriptRoot 'build_android_plugin.py')
if ($LASTEXITCODE -ne 0) { throw 'Android platform plugin compilation failed' }
& (Join-Path $taskRoot '.venv\Scripts\python.exe') (Join-Path $PSScriptRoot 'package_engine_sources.py')
if ($LASTEXITCODE -ne 0) { throw 'Engine source packaging failed' }
& (Join-Path $taskRoot '.venv\Scripts\python.exe') (Join-Path $PSScriptRoot 'package_courses.py')
if ($LASTEXITCODE -ne 0) { throw 'Course manifest validation failed' }
$taskExport = if ($Release) { '--export-release' } else { '--export-debug' }
& $godotConsole --headless --path (Join-Path $taskRoot 'godot') $taskExport Android (Join-Path $taskRoot 'builds\shogi-playable.apk') --quit
if ($LASTEXITCODE -ne 0) { throw "Android export failed: $LASTEXITCODE" }
Write-Output (Join-Path $taskRoot 'builds\shogi-playable.apk')
