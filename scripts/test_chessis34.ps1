param([string[]]$Probes = @('chessis34'))
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskChain = Get-Content -LiteralPath "$env:USERPROFILE/Development/toolchain.json" -Raw | ConvertFrom-Json
$taskGodot = $taskChain.godot -replace '_win64.exe$', '_win64_console.exe'
$taskOutput = Join-Path $taskRoot 'review/app/chessis34'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
& $taskGodot --headless --path (Join-Path $taskRoot 'godot') --editor --import --quit *> (Join-Path $taskOutput 'import.log')
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskOutput 'import.log') -Raw) -match 'SCRIPT ERROR|ERROR:') { throw 'Godot import failed.' }
foreach ($taskName in $Probes) {
$taskArgs = @('--path', ('"' + (Join-Path $taskRoot 'godot') + '"'), '--', '--unified-test', ('--' + $taskName), '--chessis34-regression')
$taskProcess = Start-Process -FilePath $taskGodot -ArgumentList $taskArgs -WindowStyle Hidden -RedirectStandardOutput (Join-Path $taskOutput ($taskName + '.log')) -RedirectStandardError (Join-Path $taskOutput ($taskName + '.err')) -PassThru
$null = $taskProcess.Handle
while (-not $taskProcess.WaitForExit(1000)) {
    if ((Get-Date) - $taskProcess.StartTime -gt [TimeSpan]::FromSeconds(270)) { $taskProcess.Kill(); throw 'UI regression timed out.' }
}
$taskProcess.WaitForExit(); $taskProcess.Refresh()
[string]$taskProcess.ExitCode | Set-Content -LiteralPath (Join-Path $taskOutput ($taskName + '.exit'))
if ($taskProcess.ExitCode -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskOutput ($taskName + '.err')) -Raw) -match 'SCRIPT ERROR|ERROR:|UNIFIED FAIL') { throw "UI regression $taskName failed; inspect its log and err files." }
Get-Content -LiteralPath (Join-Path $taskOutput ($taskName + '.log')) -Tail 1

}
