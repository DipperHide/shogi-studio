param([switch]$RegressionOnly, [switch]$UiOnly, [string[]]$Probes)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskGodot = $taskChain.godot -replace '_win64.exe$', '_win64_console.exe'
$taskOutput = Join-Path $taskRoot 'review/app/chessis16'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
if (-not $UiOnly) {
    $taskCore = if ($RegressionOnly) { @('report10_test', 'report12_test') } else { @('report_move16_test', 'rules_test', 'usi_test') }
    foreach ($taskScript in $taskCore) {
        & $taskGodot --headless --path (Join-Path $taskRoot 'godot') --script "res://tests/$taskScript.gd" -- --chessis16-regression *> (Join-Path $taskOutput ($taskScript + '.log'))
        if ($LASTEXITCODE -ne 0) { throw "$taskScript failed." }
        Get-Content -LiteralPath (Join-Path $taskOutput ($taskScript + '.log')) -Tail 1
    }
}
$taskProbes = if ($Probes) { $Probes } elseif ($RegressionOnly) { @('chessis10', 'chessis15', 'chessis12', 'chessis14', 'chessis13', 'chessis11', 'chessis') } else { @('chessis16') }
foreach ($taskProbe in $taskProbes) {
    $taskStdout = Join-Path $taskOutput ($taskProbe + '.log')
    $taskStderr = Join-Path $taskOutput ($taskProbe + '.err')
    $taskProcess = Start-Process -FilePath $taskGodot -ArgumentList @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--', '--unified-test', ('--' + $taskProbe), '--chessis16-regression') -WindowStyle Hidden -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr -PassThru
    $null = $taskProcess.Handle
    while (-not $taskProcess.WaitForExit(1000)) {
        if ((Get-Date) - $taskProcess.StartTime -gt [TimeSpan]::FromSeconds(190)) { $taskProcess.Kill(); throw 'Visual probe timed out.' }
    }
    $taskProcess.WaitForExit()
    $taskProcess.Refresh()
    $taskErrors = Get-Content -LiteralPath $taskStderr -Raw -Encoding UTF8
    if ($taskProcess.ExitCode -ne 0 -or $taskErrors -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw "Probe failed: $taskErrors" }
    Get-Content -LiteralPath $taskStdout -Tail 1 -Encoding UTF8
}
if (-not $UiOnly -and -not $RegressionOnly) {
    # The visual probe above first produces the real-engine lines for timing.
    & $taskGodot --headless --path (Join-Path $taskRoot 'godot') --script res://tests/usi_move16_test.gd *> (Join-Path $taskOutput 'usi_move16_test.log')
    if ($LASTEXITCODE -ne 0) { throw 'USI move differential failed.' }
    Get-Content -LiteralPath (Join-Path $taskOutput 'usi_move16_test.log') -Tail 1
}
