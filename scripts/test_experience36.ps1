param([switch]$CoreOnly, [switch]$SkipCore, [string[]]$Probes = @('experience36', 'board-hud', 'chessis34', 'live-navigation'))
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskGodot = $taskChain.godot -replace '_win64.exe$', '_win64_console.exe'
$taskOutput = Join-Path $taskRoot 'review/app/experience36'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
foreach ($taskTest in $(if ($SkipCore) { @() } else { @('difficulty36_test', 'rules_test', 'hint32_test', 'history_motion_test', 'variation25_test', 'archive33_test') })) {
    & $taskGodot --headless --path (Join-Path $taskRoot 'godot') --script "res://tests/$taskTest.gd" *> (Join-Path $taskOutput "$taskTest.log")
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskOutput "$taskTest.log") -Raw) -match 'SCRIPT ERROR|ERROR:|FAIL:') { throw "Core regression failed: $taskTest" }
    Get-Content -LiteralPath (Join-Path $taskOutput "$taskTest.log") -Tail 1
}
if ($CoreOnly) { return }
foreach ($taskProbe in $Probes) {
    $taskArgs = @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--resolution', '360x760', '--', '--unified-test', ('--' + $taskProbe))
    $taskProcess = Start-Process -FilePath $taskGodot -ArgumentList $taskArgs -WindowStyle Hidden -RedirectStandardOutput (Join-Path $taskOutput "$taskProbe.log") -RedirectStandardError (Join-Path $taskOutput "$taskProbe.err") -PassThru
    $null = $taskProcess.Handle
    while (-not $taskProcess.WaitForExit(1000)) {
        if ((Get-Date) - $taskProcess.StartTime -gt [TimeSpan]::FromSeconds(270)) { $taskProcess.Kill(); throw "UI regression timed out: $taskProbe" }
    }
    $taskProcess.WaitForExit(); $taskProcess.Refresh()
    if ($taskProcess.ExitCode -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskOutput "$taskProbe.err") -Raw) -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw "UI regression failed: $taskProbe" }
    Get-Content -LiteralPath (Join-Path $taskOutput "$taskProbe.log") -Tail 1
}
