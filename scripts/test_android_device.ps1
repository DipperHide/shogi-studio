param([string]$Serial = '', [switch]$SkipInstall, [string]$ReportDirectory = '')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Get-Content -LiteralPath "$env:USERPROFILE\Development\toolchain.json" -Raw | ConvertFrom-Json
$adb = Join-Path $toolchain.sdk 'platform-tools\adb.exe'
$packageName = 'org.shogistudio.artpreview'
$deviceReports = if ($ReportDirectory) { $ReportDirectory } else { Join-Path $taskRoot 'review\app\complete\android-device' }
if (-not [System.IO.Path]::IsPathRooted($deviceReports)) { $deviceReports = Join-Path $taskRoot $deviceReports }
New-Item -ItemType Directory -Force -Path $deviceReports | Out-Null
$devices = @(& $adb devices | Where-Object { $_ -match '^([^\s]+)\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
if (-not $Serial) {
    if ($devices.Count -ne 1) { throw 'Connect exactly one authorized Android device, or specify -Serial.' }
    $Serial = $devices[0]
}
if ($Serial -notin $devices) { throw 'This device is not connected and authorized for USB debugging.' }
function Invoke-Device([string[]]$Arguments) {
    $output = & $adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "adb command failed: $output" }
    return $output
}
if (-not $SkipInstall) {
    Invoke-Device @('install', '-r', (Join-Path $taskRoot 'builds\shogi-playable.apk'))
}
$launcherOutput = Invoke-Device @('shell', 'cmd', 'package', 'resolve-activity', '--brief', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.LAUNCHER', $packageName)
$launcher = @($launcherOutput | Where-Object { $_ -match ('^' + [regex]::Escape($packageName) + '/\S+$') })
if ($launcher.Count -ne 1) { throw "Could not resolve the exported app launcher: $launcherOutput" }
$launcherComponent = $launcher[0].Trim()
$null = Invoke-Device @('shell', 'am', 'force-stop', $packageName)
$probePid = ''
# run-as is available only on this developer-signed, debuggable app. No broader
# storage permissions, exported activity extras or changes to user saves are needed.
try {
    $null = Invoke-Device @('shell', 'run-as', $packageName, 'mkdir', '-p', 'files')
    $null = Invoke-Device @('shell', 'run-as', $packageName, 'rm', '-f', 'files/package-probe.json')
    $null = Invoke-Device @('shell', 'run-as', $packageName, 'touch', 'files/package-probe.request')
    $null = Invoke-Device @('shell', 'am', 'start', '-n', $launcherComponent)
    $probePid = ((& $adb -s $Serial shell pidof $packageName) -join '').Trim()
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    $result = $null
    do {
        Start-Sleep -Milliseconds 500
        & $adb -s $Serial shell pidof $packageName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            # A successful probe also quits. Read its report below before
            # deciding whether the missing process was an early crash.
            & $adb -s $Serial shell run-as $packageName test -f files/package-probe.json
            if ($LASTEXITCODE -ne 0) { throw "Android exited before producing its report. See diagnostics in $deviceReports." }
        }
        # A missing report is expected while the probe is running. Test before
        # reading so Windows PowerShell does not promote native stderr to an error.
        & $adb -s $Serial shell run-as $packageName test -f files/package-probe.json
        if ($LASTEXITCODE -eq 0) {
            $json = Invoke-Device @('shell', 'run-as', $packageName, 'cat', 'files/package-probe.json')
            try { $result = ($json -join "`n") | ConvertFrom-Json } catch { $result = $null }
        }
    } while ($null -eq $result -and [DateTime]::UtcNow -lt $deadline)
    if ($null -eq $result) { throw 'Android probe did not finish within 60 seconds.' }
    $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $deviceReports 'package-probe.json') -Encoding UTF8
    $details = @{
        model = (Invoke-Device @('shell', 'getprop', 'ro.product.model')) -join ''
        android_api = (Invoke-Device @('shell', 'getprop', 'ro.build.version.sdk')) -join ''
        checked_utc = [DateTime]::UtcNow.ToString('o')
        bluetooth_pair_tested = $false
    }
    $details | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $deviceReports 'device.json') -Encoding UTF8
    if ($result.failures.Count -gt 0) { throw "Android probe failed: $($result.failures -join ', ')" }
    Write-Output "Android package probe passed $($result.checks) checks. Bluetooth pair verification remains separate."
} finally {
    # Capture the tested process before restarting. Android 11+ records ANR,
    # native-crash and memory-related exit reasons even after logcat PID exits.
    try {
        if ($probePid -match '^\d+$') {
            & $adb -s $Serial logcat -d -v threadtime "--pid=$probePid" |
                Set-Content -LiteralPath (Join-Path $deviceReports 'logcat.txt') -Encoding UTF8
        }
        & $adb -s $Serial shell dumpsys activity exit-info $packageName |
            Set-Content -LiteralPath (Join-Path $deviceReports 'exit-info.txt') -Encoding UTF8
    } catch { Write-Warning "Could not collect all Android diagnostics: $_" }
    & $adb -s $Serial shell run-as $packageName rm -f files/package-probe.request 2>$null | Out-Null
    & $adb -s $Serial shell am force-stop $packageName 2>$null | Out-Null
    & $adb -s $Serial shell am start -n $launcherComponent 2>$null | Out-Null
}
