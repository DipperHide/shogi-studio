$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Get-Content -LiteralPath "$env:USERPROFILE\Development\toolchain.json" -Raw | ConvertFrom-Json
$godotConsole = $toolchain.godot -replace '_win64.exe$', '_win64_console.exe'
$reports = Join-Path $taskRoot 'review\app\unified'
$processes = @()
try {
    foreach ($role in @('host', 'guest')) {
        $qa = Start-Process -FilePath $godotConsole -ArgumentList @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--resolution', '480x800', '--', '--unified-peer', $role) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $reports "peer-$role.log") -RedirectStandardError (Join-Path $reports "peer-$role-errors.log") -PassThru
        $null = $qa.Handle
        $processes += $qa
        if ($role -eq 'host') { Start-Sleep -Milliseconds 800 }
    }
    foreach ($qa in $processes) {
        if (-not $qa.WaitForExit(55000)) { throw 'Unified network test timeout' }
        $qa.WaitForExit()
        $qa.Refresh()
    }
    foreach ($role in @('host', 'guest')) {
        Get-Content -LiteralPath (Join-Path $reports "peer-$role.log")
        $errors = Get-Content -LiteralPath (Join-Path $reports "peer-$role-errors.log") -Raw
        if ($errors -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw $errors }
    }
    if ($processes | Where-Object ExitCode -ne 0) { throw 'Unified peer exited with an error' }
    $hostReport = Get-Content -LiteralPath (Join-Path $reports 'peer-host.json') -Raw | ConvertFrom-Json
    $guestReport = Get-Content -LiteralPath (Join-Path $reports 'peer-guest.json') -Raw | ConvertFrom-Json
    if ($hostReport.key -ne $guestReport.key -or $hostReport.result_code -ne $guestReport.result_code -or $hostReport.winner -ne $guestReport.winner) { throw 'Unified peers disagree' }
} finally {
    foreach ($qa in $processes) { if (-not $qa.HasExited) { $qa.Kill() } }
}
