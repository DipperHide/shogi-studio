param([switch]$RegressionOnly)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskGodot = $taskChain.godot -replace '_win64.exe$', '_win64_console.exe'
$taskOutput = Join-Path $taskRoot 'review/app/chessis13'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
if (-not $RegressionOnly) {
    & $taskGodot --headless --path (Join-Path $taskRoot 'godot') --script res://tests/practice13_test.gd 1> (Join-Path $taskOutput 'practice-core.log') 2> (Join-Path $taskOutput 'practice-core.err')
    $taskCoreErrors = Get-Content -LiteralPath (Join-Path $taskOutput 'practice-core.err') -Raw -Encoding UTF8
    if ($LASTEXITCODE -ne 0 -or $taskCoreErrors -match 'SCRIPT ERROR|ERROR:') { throw "Practice core failed: $taskCoreErrors" }
    Get-Content -LiteralPath (Join-Path $taskOutput 'practice-core.log') -Tail 1 -Encoding UTF8
}
$taskProbes = if ($RegressionOnly) { @('chessis11', 'chessis12', 'chessis', 'motion-probe') } else { @('chessis13') }
foreach ($taskProbe in $taskProbes) {
    $taskStdout = Join-Path $taskOutput ($taskProbe + '.log')
    $taskStderr = Join-Path $taskOutput ($taskProbe + '.err')
    $taskProcess = Start-Process -FilePath $taskGodot -ArgumentList @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--', '--unified-test', ('--' + $taskProbe), '--chessis13-regression') -WindowStyle Hidden -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr -PassThru
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
