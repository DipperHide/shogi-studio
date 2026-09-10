param([switch]$UiOnly, [string[]]$Probes = @('chessis23', 'chessis22', 'chessis21', 'chessis12', 'chessis16', 'chessis19'))
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskGodot = $taskChain.godot -replace '_win64.exe$', '_win64_console.exe'
$taskOutput = Join-Path $taskRoot 'review/app/chessis23'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
if (-not $UiOnly) {
    & $taskGodot --headless --path (Join-Path $taskRoot 'godot') --script res://tests/report_quality23_test.gd *> (Join-Path $taskOutput 'quality-core.log')
    if ($LASTEXITCODE -ne 0) { throw 'Quality statistics tests failed.' }
    Get-Content -LiteralPath (Join-Path $taskOutput 'quality-core.log') -Tail 1
}
foreach ($taskProbe in $Probes) {
    $taskStdout = Join-Path $taskOutput ($taskProbe + '.log')
    $taskStderr = Join-Path $taskOutput ($taskProbe + '.err')
    $taskProcess = Start-Process -FilePath $taskGodot -ArgumentList @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--', '--unified-test', ('--' + $taskProbe), '--chessis23-regression') -WindowStyle Hidden -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr -PassThru
    $null = $taskProcess.Handle
    while (-not $taskProcess.WaitForExit(1000)) {
        if ((Get-Date) - $taskProcess.StartTime -gt [TimeSpan]::FromSeconds(190)) { $taskProcess.Kill(); throw "$taskProbe timed out." }
    }
    $taskProcess.WaitForExit()
    $taskProcess.Refresh()
    $taskErrors = Get-Content -LiteralPath $taskStderr -Raw -Encoding UTF8
    if ($taskProcess.ExitCode -ne 0 -or $taskErrors -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw "Probe failed: $taskProbe; $taskErrors" }
    Get-Content -LiteralPath $taskStdout -Tail 1 -Encoding UTF8
}
