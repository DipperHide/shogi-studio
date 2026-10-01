param([switch]$CoreOnly)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskGodot = $taskChain.godot -replace '_win64.exe$', '_win64_console.exe'
$taskReports = Join-Path $taskRoot 'review/app/chu37'
New-Item -ItemType Directory -Force -Path $taskReports | Out-Null
foreach ($taskName in @('chu_rules_test','chu_storage_test','chu_network_test','chu_bluetooth_test')) {
    $taskLog = Join-Path $taskReports "$taskName.log"
    & $taskGodot --headless --path (Join-Path $taskRoot 'godot') --script "res://tests/$taskName.gd" *> $taskLog
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $taskLog -Raw) -match 'SCRIPT ERROR|ERROR:') { throw "Chu regression failed: $taskName" }
    Get-Content -LiteralPath $taskLog -Tail 1
}
if ($CoreOnly) { return }
foreach ($taskResolution in @('360x760','852x393')) {
    $taskLog = Join-Path $taskReports "ui-$taskResolution.log"
    $taskErr = Join-Path $taskReports "ui-$taskResolution.err"
    $taskArgs = @('--path',('"' + (Join-Path $taskRoot 'godot') + '"'),'--resolution',$taskResolution,'--','--chu-probe')
    $taskProcess = Start-Process -FilePath $taskGodot -ArgumentList $taskArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput $taskLog -RedirectStandardError $taskErr
    $null = $taskProcess.Handle
    if (-not $taskProcess.WaitForExit(45000)) { $taskProcess.Kill(); throw 'Chu UI probe timeout' }
    $taskProcess.WaitForExit(); $taskProcess.Refresh()
    if ($taskProcess.ExitCode -ne 0 -or (Get-Content -LiteralPath $taskErr -Raw) -match 'SCRIPT ERROR|ERROR:') { throw "Chu UI probe failed: $taskResolution" }
    Copy-Item -LiteralPath "$env:APPDATA/ShogiStudio/chu-probe.png" -Destination (Join-Path $taskReports "chu-$taskResolution.png")
    Copy-Item -LiteralPath "$env:APPDATA/ShogiStudio/chu-probe.json" -Destination (Join-Path $taskReports "chu-$taskResolution.json")
    Get-Content -LiteralPath $taskLog -Tail 1
}
