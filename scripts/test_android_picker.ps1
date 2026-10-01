param([string]$ReportDirectory = 'review/app/chu37/android-picker')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskAdb = Join-Path $taskChain.sdk 'platform-tools/adb.exe'
$taskPackage = 'org.shogistudio.artpreview'
$taskOutput = Join-Path $taskRoot $ReportDirectory
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
function Device([string[]]$Arguments) {
    $value = & $taskAdb @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ADB failed: $value" }
    return $value
}
$null = Device @('shell','am','force-stop',$taskPackage)
$null = Device @('shell','run-as',$taskPackage,'rm','-f','files/package-probe.json','files/native-picker-ready.json')
$null = Device @('shell','run-as',$taskPackage,'touch','files/package-probe.request','files/native-picker.request')
$null = Device @('shell','am','start','-n',"$taskPackage/com.godot.game.GodotAppLauncher")
try {
    foreach ($attempt in @(1,2)) {
        $deadline = [DateTime]::UtcNow.AddSeconds(40)
        $seen = $false
        do {
            Start-Sleep -Milliseconds 500
            & $taskAdb shell run-as $taskPackage test -f files/native-picker-ready.json
            if ($LASTEXITCODE -eq 0) {
                $ready = ((Device @('shell','run-as',$taskPackage,'cat','files/native-picker-ready.json')) -join "`n") | ConvertFrom-Json
                $focus = (Device @('shell','dumpsys','window')) -join "`n"
                $seen = $ready.attempt -eq $attempt -and $focus -match 'mCurrentFocus=.*documentsui'
            }
        } while (-not $seen -and [DateTime]::UtcNow -lt $deadline)
        if (-not $seen) { throw "Native DocumentsUI did not open on attempt $attempt" }
        $focus.Split("`n") | Where-Object { $_ -match 'mCurrentFocus' } | Set-Content (Join-Path $taskOutput "focus-$attempt.txt")
        $null = Device @('shell','input','keyevent','4')
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 500
        & $taskAdb shell run-as $taskPackage test -f files/package-probe.json
    } while ($LASTEXITCODE -ne 0 -and [DateTime]::UtcNow -lt $deadline)
    $json = (Device @('shell','run-as',$taskPackage,'cat','files/package-probe.json')) -join "`n"
    $json | Set-Content (Join-Path $taskOutput 'native-picker.json') -Encoding utf8
    $result = $json | ConvertFrom-Json
    if ($result.failures.Count) { throw ($result.failures -join ', ') }
    Write-Output "Android native picker: $($result.checks) checks passed; opened and cancelled twice."
} finally {
    & $taskAdb shell run-as $taskPackage rm -f files/package-probe.request files/native-picker.request | Out-Null
    & $taskAdb shell am force-stop $taskPackage | Out-Null
    & $taskAdb shell am start -n "$taskPackage/com.godot.game.GodotAppLauncher" | Out-Null
}
