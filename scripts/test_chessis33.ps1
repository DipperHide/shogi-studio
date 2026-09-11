param([switch]$CoreOnly)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskGodot = $taskChain.godot -replace '_win64.exe$', '_win64_console.exe'
$taskOutput = Join-Path $taskRoot 'review/app/chessis33'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
& $taskGodot --headless --path (Join-Path $taskRoot 'godot') --editor --import --quit *> (Join-Path $taskOutput 'import.log')
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskOutput 'import.log') -Raw) -match 'SCRIPT ERROR|ERROR:') { throw 'Godot import failed.' }
& $taskGodot --headless --path (Join-Path $taskRoot 'godot') --script res://tests/archive33_test.gd *> (Join-Path $taskOutput 'archive-core.log')
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskOutput 'archive-core.log') -Raw) -match 'SCRIPT ERROR|ERROR:') { throw 'Archive core tests failed.' }
Get-Content -LiteralPath (Join-Path $taskOutput 'archive-core.log') -Tail 1
if ($CoreOnly) { return }
$taskArgs = @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--', '--unified-test', '--chessis33')
$taskProcess = Start-Process -FilePath $taskGodot -ArgumentList $taskArgs -WindowStyle Hidden -RedirectStandardOutput (Join-Path $taskOutput 'ui.log') -RedirectStandardError (Join-Path $taskOutput 'ui.err') -PassThru
$null = $taskProcess.Handle
while (-not $taskProcess.WaitForExit(1000)) {
    if ((Get-Date) - $taskProcess.StartTime -gt [TimeSpan]::FromSeconds(270)) { $taskProcess.Kill(); throw 'Archive UI tests timed out.' }
}
$taskProcess.WaitForExit(); $taskProcess.Refresh()
[string]$taskProcess.ExitCode | Set-Content -LiteralPath (Join-Path $taskOutput 'ui.exit')
if ($taskProcess.ExitCode -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskOutput 'ui.err') -Raw) -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw 'Archive UI tests failed; inspect ui.log and ui.err.' }
Get-Content -LiteralPath (Join-Path $taskOutput 'ui.log') -Tail 1
