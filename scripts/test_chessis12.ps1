param([switch]$FullRegression, [switch]$RegressionOnly)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskGodot = $taskChain.godot -replace '_win64.exe$', '_win64_console.exe'
$taskOutput = Join-Path $taskRoot 'review/app/chessis12'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
$taskScripts = @('report12_test')
if ($FullRegression) { $taskScripts += 'report10_test' }
if ($RegressionOnly) { $taskScripts = @('report10_test') }
foreach ($taskScript in $taskScripts) {
    & $taskGodot --headless --path (Join-Path $taskRoot 'godot') --script "res://tests/$taskScript.gd" -- --chessis12-regression *> (Join-Path $taskOutput ($taskScript + '.log'))
    if ($LASTEXITCODE -ne 0) { throw "$taskScript failed." }
    Get-Content -LiteralPath (Join-Path $taskOutput ($taskScript + '.log')) -Tail 1
}
$taskProbes = @('chessis12')
if ($FullRegression) { $taskProbes += @('chessis10', 'chessis11', 'chessis') }
if ($RegressionOnly) { $taskProbes = @('chessis10', 'chessis11', 'chessis') }
foreach ($taskProbe in $taskProbes) {
    $taskStdout = Join-Path $taskOutput ($taskProbe + '.log')
    $taskStderr = Join-Path $taskOutput ($taskProbe + '.err')
    $taskProcess = Start-Process -FilePath $taskGodot -ArgumentList @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--', '--unified-test', ('--' + $taskProbe), '--chessis12-regression') -WindowStyle Hidden -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr -PassThru
    $null = $taskProcess.Handle
    while (-not $taskProcess.WaitForExit(1000)) {
        if ((Get-Date) - $taskProcess.StartTime -gt [TimeSpan]::FromSeconds(185)) { $taskProcess.Kill(); throw 'Visual probe timed out.' }
    }
    $taskProcess.WaitForExit()
    $taskProcess.Refresh()
    $taskErrors = Get-Content -LiteralPath $taskStderr -Raw
    if ($taskProcess.ExitCode -ne 0 -or $taskErrors -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw "Probe failed: $taskErrors" }
    Get-Content -LiteralPath $taskStdout -Tail 1
}
