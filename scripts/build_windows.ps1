param([string]$OutputDirectory = 'builds/windows')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Get-Content -LiteralPath "$env:USERPROFILE\Development\toolchain.json" -Raw | ConvertFrom-Json
$godotConsole = $toolchain.godot -replace '_win64.exe$', '_win64_console.exe'
$destination = Join-Path (Join-Path $taskRoot $OutputDirectory) 'Shogi.exe'
New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
& (Join-Path $PSScriptRoot 'build_engine_host.ps1')
& (Join-Path $taskRoot '.venv\Scripts\python.exe') (Join-Path $PSScriptRoot 'package_engine_sources.py')
if ($LASTEXITCODE -ne 0) { throw 'Engine source packaging failed' }
& (Join-Path $taskRoot '.venv\Scripts\python.exe') (Join-Path $PSScriptRoot 'package_courses.py')
if ($LASTEXITCODE -ne 0) { throw 'Course manifest validation failed' }
$engineSource = Join-Path $taskRoot 'engines\yaneuraou'
$engineDestination = Join-Path (Split-Path $destination) 'engines\yaneuraou'
New-Item -ItemType Directory -Force -Path $engineDestination | Out-Null
foreach ($name in @('YaneuraOu.exe', 'EngineHost.exe', 'EngineHost.cs', 'LICENSE.txt', 'NOTICE.md')) {
    Copy-Item -LiteralPath (Join-Path $engineSource $name) -Destination (Join-Path $engineDestination $name) -Force
}
Copy-Item -LiteralPath (Join-Path $engineSource 'eval') -Destination $engineDestination -Recurse -Force
Copy-Item -LiteralPath (Join-Path $engineSource 'vendor\source') -Destination $engineDestination -Recurse -Force
Copy-Item -LiteralPath (Join-Path $taskRoot 'godot\assets\licenses\yaneuraou-source.zip') -Destination (Join-Path $engineDestination 'yaneuraou-source.zip') -Force
$engineBuildScripts = Join-Path $engineDestination 'scripts'
New-Item -ItemType Directory -Force -Path $engineBuildScripts | Out-Null
foreach ($name in @('build_engine_android.py', 'build_engine_host.ps1', 'build_android_plugin.py', 'toolchain.py')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $engineBuildScripts $name) -Force
}
& $godotConsole --headless --path (Join-Path $taskRoot 'godot') --export-release 'Windows Desktop' $destination --quit
if ($LASTEXITCODE -ne 0) { throw "Windows export failed: $LASTEXITCODE" }
Write-Output $destination
