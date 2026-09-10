$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Get-Content -LiteralPath "$env:USERPROFILE\Development\toolchain.json" -Raw | ConvertFrom-Json
$godotConsole = $toolchain.godot -replace '_win64.exe$', '_win64_console.exe'
$reports = Join-Path $taskRoot 'review\app\unified'
New-Item -ItemType Directory -Force -Path $reports | Out-Null
$stdout = Join-Path $reports 'ui-stdout.log'
$stderr = Join-Path $reports 'ui-stderr.log'
$qa = Start-Process -FilePath $godotConsole -ArgumentList @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--rendering-method', 'gl_compatibility', '--resolution', '480x800', '--', '--unified-test') -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$null = $qa.Handle
if (-not $qa.WaitForExit(165000)) { $qa.Kill(); throw 'Unified UI test timeout' }
$qa.WaitForExit()
$qa.Refresh()
Get-Content -LiteralPath $stdout
$errors = Get-Content -LiteralPath $stderr -Raw
if ($qa.ExitCode -ne 0 -or $errors -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw "Unified UI tests failed: $errors" }
