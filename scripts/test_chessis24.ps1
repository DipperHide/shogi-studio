param([string[]]$Probes = @('chessis24', 'chessis16', 'chessis13', 'chessis11'))
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskGodot = $taskChain.godot -replace '_win64.exe$', '_win64_console.exe'
$taskOutput = Join-Path $taskRoot 'review/app/chessis24'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
foreach ($taskProbe in $Probes) {
    $taskStdout = Join-Path $taskOutput ($taskProbe + '.log')
    $taskStderr = Join-Path $taskOutput ($taskProbe + '.err')
    $taskProcess = Start-Process -FilePath $taskGodot -ArgumentList @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--', '--unified-test', ('--' + $taskProbe), '--chessis24-regression') -WindowStyle Hidden -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr -PassThru
    $null = $taskProcess.Handle
    while (-not $taskProcess.WaitForExit(1000)) {
        if ((Get-Date) - $taskProcess.StartTime -gt [TimeSpan]::FromSeconds(190)) { $taskProcess.Kill(); throw "$taskProbe timed out." }
    }
    $taskProcess.WaitForExit()
    $taskProcess.Refresh()
    [string]$taskProcess.ExitCode | Set-Content -LiteralPath (Join-Path $taskOutput ($taskProbe + '.exit'))
    $taskErrors = Get-Content -LiteralPath $taskStderr -Raw -Encoding UTF8
    if ($taskProcess.ExitCode -ne 0 -or $taskErrors -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw "Probe failed: $taskProbe; $taskErrors" }
    Get-Content -LiteralPath $taskStdout -Tail 1 -Encoding UTF8
}
