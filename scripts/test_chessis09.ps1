param([switch]$SkipHistoric)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskGodot = $taskChain.godot -replace '_win64.exe$', '_win64_console.exe'
$taskOutput = Join-Path $taskRoot 'review/app/chessis09'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
if (-not $SkipHistoric) {
    & $taskGodot --headless --path (Join-Path $taskRoot 'godot') --script res://tests/historic_games_test.gd
    if ($LASTEXITCODE -ne 0) { throw 'Historical game validation failed.' }
}
foreach ($probeName in @('motion-probe', 'chessis09')) {
    $taskStdout = Join-Path $taskOutput ($probeName + '.log')
    $taskStderr = Join-Path $taskOutput ($probeName + '.err')
    $taskProcess = Start-Process -FilePath $taskGodot -ArgumentList @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--', '--unified-test', ('--' + $probeName)) -WindowStyle Hidden -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr -PassThru
    $null = $taskProcess.Handle
    while (-not $taskProcess.WaitForExit(1000)) {
        if ((Get-Date) - $taskProcess.StartTime -gt [TimeSpan]::FromSeconds(150)) { $taskProcess.Kill(); throw 'Visual probe timed out.' }
    }
    $taskProcess.WaitForExit()
    $taskProcess.Refresh()
    $taskErrors = Get-Content -LiteralPath $taskStderr -Raw
    if ($taskProcess.ExitCode -ne 0 -or $taskErrors -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw "Probe failed: $taskErrors" }
    Get-Content -LiteralPath $taskStdout -Tail 2
}
