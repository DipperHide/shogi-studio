$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$godotConsole = $toolchain.godot -replace '_win64.exe$', '_win64_console.exe'
$reportRoot = Join-Path $taskRoot 'review/app/chessis'
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
& $godotConsole --headless --path (Join-Path $taskRoot 'godot') --script res://tests/chessis_core_test.gd
if ($LASTEXITCODE -ne 0) { throw 'Chessis adaptation core tests failed.' }
$stdout = Join-Path $reportRoot 'ui-stdout.log'
$stderr = Join-Path $reportRoot 'ui-stderr.log'
$qa = Start-Process -FilePath $godotConsole -ArgumentList @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--rendering-method', 'gl_compatibility', '--resolution', '393x852', '--', '--unified-test', '--chessis') -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$null = $qa.Handle
while (-not $qa.WaitForExit(1000)) {
    if ((Get-Date) - $qa.StartTime -gt [TimeSpan]::FromSeconds(120)) { $qa.Kill(); throw 'UI tests timed out.' }
}
$qa.WaitForExit()
$qa.Refresh()
Get-Content -LiteralPath $stdout
$errors = Get-Content -LiteralPath $stderr -Raw
if ($qa.ExitCode -ne 0 -or $errors -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw "UI verification failed: $errors" }
