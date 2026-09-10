$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Get-Content -LiteralPath "$env:USERPROFILE\Development\toolchain.json" -Raw | ConvertFrom-Json
$godotConsole = $toolchain.godot -replace '_win64.exe$', '_win64_console.exe'
$reports = Join-Path $taskRoot 'review\app\complete'
$processes = @()
try {
    foreach ($role in @('host', 'guest')) {
        $outLog = Join-Path $reports "network-$role.log"
        $errorLog = Join-Path $reports "network-$role-errors.log"
        $qa = Start-Process -FilePath $godotConsole -ArgumentList @('--headless', '--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--script', 'res://tests/network_peer_test.gd', '--', $role) -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errorLog -PassThru
        $null = $qa.Handle
        $processes += $qa
        if ($role -eq 'host') { Start-Sleep -Milliseconds 600 }
    }
    foreach ($qa in $processes) {
        if (-not $qa.WaitForExit(55000)) { throw 'Network tests exceeded time limit.' }
        $qa.WaitForExit()
        $qa.Refresh()
        if ($qa.ExitCode -ne 0) { throw "Network peer failed with exit code $($qa.ExitCode). See $reports" }
    }
    foreach ($role in @('host', 'guest')) {
        $errors = Get-Content (Join-Path $reports "network-$role-errors.log") -Raw
        if ($errors -match 'SCRIPT ERROR|ERROR:|NETWORK FAIL') { throw $errors }
        Get-Content (Join-Path $reports "network-$role.log")
    }
    $hostReport = Get-Content (Join-Path $reports 'network-host.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $guestReport = Get-Content (Join-Path $reports 'network-guest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($hostReport.key -ne $guestReport.key -or $hostReport.result -ne $guestReport.result) { throw 'Peers disagree on final board or result.' }
} finally {
    foreach ($qa in $processes) { if (-not $qa.HasExited) { $qa.Kill() } }
}
