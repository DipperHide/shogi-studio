param([switch]$CoreOnly)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskGodot = $taskChain.godot -replace '_win64.exe$', '_win64_console.exe'
$taskOutput = Join-Path $taskRoot 'review/app/chessis32'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
& $taskGodot --headless --path (Join-Path $taskRoot 'godot') --editor --import --quit *> (Join-Path $taskOutput 'import.log')
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskOutput 'import.log') -Raw) -match 'SCRIPT ERROR|ERROR:') { throw 'Godot import failed.' }
& $taskGodot --headless --path (Join-Path $taskRoot 'godot') --script res://tests/hint32_test.gd *> (Join-Path $taskOutput 'hint-core.log')
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskOutput 'hint-core.log') -Raw) -match 'SCRIPT ERROR|ERROR:') { throw 'Hint core tests failed.' }
Get-Content -LiteralPath (Join-Path $taskOutput 'hint-core.log') -Tail 1
if ($CoreOnly) { return }
$taskArgs = @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--', '--unified-test', '--chessis32')
$taskProcess = Start-Process -FilePath $taskGodot -ArgumentList $taskArgs -WindowStyle Hidden -RedirectStandardOutput (Join-Path $taskOutput 'ui.log') -RedirectStandardError (Join-Path $taskOutput 'ui.err') -PassThru
$null = $taskProcess.Handle
while (-not $taskProcess.WaitForExit(1000)) {
    if ((Get-Date) - $taskProcess.StartTime -gt [TimeSpan]::FromSeconds(195)) { $taskProcess.Kill(); throw 'Hint UI tests timed out.' }
}
$taskProcess.WaitForExit(); $taskProcess.Refresh()
[string]$taskProcess.ExitCode | Set-Content -LiteralPath (Join-Path $taskOutput 'ui.exit')
if ($taskProcess.ExitCode -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskOutput 'ui.err') -Raw) -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw 'Hint UI tests failed; inspect ui.log and ui.err.' }
Get-Content -LiteralPath (Join-Path $taskOutput 'ui.log') -Tail 1
