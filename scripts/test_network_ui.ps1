$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Get-Content -LiteralPath "$env:USERPROFILE\Development\toolchain.json" -Raw | ConvertFrom-Json
$godotConsole = $toolchain.godot -replace '_win64.exe$', '_win64_console.exe'
$reports = Join-Path $taskRoot 'review\app\complete'
$stdout = Join-Path $reports 'network-ui-stdout.log'
$stderr = Join-Path $reports 'network-ui-stderr.log'
$qa = Start-Process -FilePath $godotConsole -ArgumentList @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--rendering-method', 'gl_compatibility', '--resolution', '480x800', '--', '--network-ui-test') -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$null = $qa.Handle
if (-not $qa.WaitForExit(60000)) { $qa.Kill(); throw 'Network UI tests exceeded 60 seconds.' }
$qa.WaitForExit()
$qa.Refresh()
Get-Content -LiteralPath $stdout
$errors = Get-Content -LiteralPath $stderr -Raw
if ($qa.ExitCode -ne 0 -or $errors -match 'SCRIPT ERROR|ERROR:|COMPLETE UI FAIL') { throw "Network UI tests failed: $errors" }
