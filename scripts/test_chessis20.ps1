param([switch]$CoreOnly, [switch]$UiOnly, [switch]$Network)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskGodot = $taskChain.godot -replace '_win64.exe$', '_win64_console.exe'
$taskOutput = Join-Path $taskRoot 'review/app/chessis20'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
if (-not $UiOnly) {
    & (Join-Path $taskRoot '.venv/Scripts/python.exe') -X utf8 (Join-Path $PSScriptRoot 'test_tournaments.py') *> (Join-Path $taskOutput 'collector-tests.log')
    if ($LASTEXITCODE -ne 0) { throw 'Tournament collector tests failed.' }
    $taskCore = @('tournament_sync20_test', 'rules_test', 'usi_test', 'chessis_core_test', 'historic_games_test', 'report12_test', 'story19_test')
    if ($Network) { $taskCore += 'tournament_network20_test' }
    foreach ($taskScript in $taskCore) {
        & $taskGodot --headless --path (Join-Path $taskRoot 'godot') --script "res://tests/$taskScript.gd" -- --chessis20-regression *> (Join-Path $taskOutput ($taskScript + '.log'))
        if ($LASTEXITCODE -ne 0) { throw "$taskScript failed. See review/app/chessis20/$taskScript.log" }
        Get-Content -LiteralPath (Join-Path $taskOutput ($taskScript + '.log')) -Tail 1
    }
    & (Join-Path $taskRoot '.venv/Scripts/python.exe') -X utf8 (Join-Path $PSScriptRoot 'check_rules_oracle.py') --report (Join-Path $taskOutput 'rules-oracle.json')
    if ($LASTEXITCODE -ne 0) { throw 'Independent rule comparison failed.' }
}
if (-not $CoreOnly) {
    foreach ($taskProbe in @('chessis20', 'motion-probe', 'chessis11', 'chessis16', 'chessis19')) {
        $taskStdout = Join-Path $taskOutput ($taskProbe + '.log')
        $taskStderr = Join-Path $taskOutput ($taskProbe + '.err')
        $taskProcess = Start-Process -FilePath $taskGodot -ArgumentList @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--', '--unified-test', ('--' + $taskProbe), '--chessis20-regression') -WindowStyle Hidden -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr -PassThru
        $null = $taskProcess.Handle
        while (-not $taskProcess.WaitForExit(1000)) {
            if ((Get-Date) - $taskProcess.StartTime -gt [TimeSpan]::FromSeconds(190)) { $taskProcess.Kill(); throw "$taskProbe timed out." }
        }
        $taskProcess.WaitForExit()
        $taskProcess.Refresh()
        $taskErrors = Get-Content -LiteralPath $taskStderr -Raw -Encoding UTF8
        if ($taskProcess.ExitCode -ne 0 -or $taskErrors -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw "Probe failed: $taskErrors" }
        Get-Content -LiteralPath $taskStdout -Tail 1 -Encoding UTF8
    }
}
