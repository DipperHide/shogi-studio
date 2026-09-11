param([string[]]$Probes = @('chessis31'), [switch]$CoreOnly, [switch]$Network)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskGodot = $taskChain.godot -replace '_win64.exe$', '_win64_console.exe'
$taskOutput = Join-Path $taskRoot 'review/app/chessis31'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
if ($CoreOnly -or ($Probes -contains 'chessis31' -or $Probes -contains 'chessis30')) {
    $taskScripts = if ($CoreOnly) { @('tournament31_test', 'tournament_sync20_test', 'import30_test', 'chessis_core_test') } else { @('import30_test') }
    foreach ($taskScript in $taskScripts) {
        $taskLog = Join-Path $taskOutput ($taskScript + '.log')
        & $taskGodot --headless --path (Join-Path $taskRoot 'godot') --script "res://tests/$taskScript.gd" -- --chessis20-regression --chessis31-regression *> $taskLog
        if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $taskLog -Raw) -match 'SCRIPT ERROR|ERROR:') { throw "$taskScript failed." }
        Get-Content -LiteralPath $taskLog -Tail 1 -Encoding UTF8
    }
    & (Join-Path $taskRoot '.venv/Scripts/python.exe') -X utf8 (Join-Path $PSScriptRoot 'prepare_import30_fixture.py') 'review/app/chessis31'
    if ($LASTEXITCODE -ne 0) { throw 'CP932 fixture preparation failed.' }
    if ($CoreOnly) { return }
}
foreach ($taskProbe in $Probes) {
    $taskStdout = Join-Path $taskOutput ($taskProbe + '.log')
    $taskStderr = Join-Path $taskOutput ($taskProbe + '.err')
    $taskArgs = @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--', '--unified-test', ('--' + $taskProbe), '--chessis31-regression')
    if ($Network) { $taskArgs += '--tournament-ui-network' }
    $taskProcess = Start-Process -FilePath $taskGodot -ArgumentList $taskArgs -WindowStyle Hidden -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr -PassThru
    $null = $taskProcess.Handle
    while (-not $taskProcess.WaitForExit(1000)) {
        if ((Get-Date) - $taskProcess.StartTime -gt [TimeSpan]::FromSeconds(255)) { $taskProcess.Kill(); throw "$taskProbe timed out." }
    }
    $taskProcess.WaitForExit()
    $taskProcess.Refresh()
    [string]$taskProcess.ExitCode | Set-Content -LiteralPath (Join-Path $taskOutput ($taskProbe + '.exit'))
    $taskErrors = Get-Content -LiteralPath $taskStderr -Raw -Encoding UTF8
    if ($taskProcess.ExitCode -ne 0 -or $taskErrors -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw "Probe failed: $taskProbe; $taskErrors" }
    Get-Content -LiteralPath $taskStdout -Tail 1 -Encoding UTF8
}
