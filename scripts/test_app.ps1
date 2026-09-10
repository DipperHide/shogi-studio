$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Get-Content -LiteralPath "$env:USERPROFILE\Development\toolchain.json" -Raw | ConvertFrom-Json
$godotConsole = $toolchain.godot -replace '_win64.exe$', '_win64_console.exe'
$projectPath = Join-Path $taskRoot 'godot'
$reports = Join-Path $taskRoot 'review\app'
New-Item -ItemType Directory -Force -Path $reports | Out-Null
& $godotConsole --headless --path $projectPath --script res://tests/history_motion_test.gd
if ($LASTEXITCODE -ne 0) { throw 'History animation tests failed' }
& $godotConsole --headless --path $projectPath --script res://tests/rules_test.gd
if ($LASTEXITCODE -ne 0) { throw 'Rules tests failed' }
& (Join-Path $taskRoot '.venv\Scripts\python.exe') (Join-Path $taskRoot 'scripts\check_rules_oracle.py')
if ($LASTEXITCODE -ne 0) { throw 'Independent rule comparison failed; install python-shogi==1.1.1 in .venv if missing' }
$stdout = Join-Path $reports 'ui-stdout.log'
$stderr = Join-Path $reports 'ui-stderr.log'
$qa = Start-Process -FilePath $godotConsole -ArgumentList @('--path', ('"' + $projectPath + '"'), '--rendering-method', 'gl_compatibility', '--resolution', '1280x720', '--', '--ui-test') -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$qaHandle = $qa.Handle
if (-not $qa.WaitForExit(55000) -and -not $qa.WaitForExit(60000)) {
    $qa.Kill()
    throw 'UI tests exceeded 115 seconds. Inspect review/app/ui-stderr.log.'
}
$qa.WaitForExit()
$qa.Refresh()
Write-Output "Godot UI exit code: $($qa.ExitCode)"
Get-Content -LiteralPath $stdout
$errors = Get-Content -LiteralPath $stderr -Raw
if ($qa.ExitCode -ne 0 -or $errors -match 'SCRIPT ERROR|ERROR:|UI FAIL') {
    throw "UI tests failed: $errors"
}
Write-Output 'All app checks passed. Reports and screenshots: review/app/'
