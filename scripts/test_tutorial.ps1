$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Get-Content -LiteralPath "$env:USERPROFILE\Development\toolchain.json" -Raw | ConvertFrom-Json
$godotConsole = $toolchain.godot -replace '_win64.exe$', '_win64_console.exe'
$reports = Join-Path $taskRoot 'review\app\tutorial'
New-Item -ItemType Directory -Force -Path $reports | Out-Null
$stdout = Join-Path $reports 'stdout.log'
$stderr = Join-Path $reports 'stderr.log'
$qa = Start-Process -FilePath $godotConsole -ArgumentList @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--rendering-method', 'gl_compatibility', '--resolution', '360x800', '--script', 'res://tests/tutorial_test.gd') -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$null = $qa.Handle
if (-not $qa.WaitForExit(180000)) { $qa.Kill(); throw 'Tutorial test timeout' }
$qa.WaitForExit()
$qa.Refresh()
Get-Content -LiteralPath $stdout
$errors = Get-Content -LiteralPath $stderr -Raw
if ($qa.ExitCode -ne 0 -or $errors -match 'SCRIPT ERROR|ERROR:|TUTORIAL FAIL') { throw "Tutorial tests failed: $errors" }
