param([string]$ReportDirectory = '', [string]$Executable = 'builds/windows/Shogi.exe')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$reports = if ($ReportDirectory) { $ReportDirectory } else { Join-Path $taskRoot 'review\app\unified' }
if (-not [System.IO.Path]::IsPathRooted($reports)) { $reports = Join-Path $taskRoot $reports }
$reports = [System.IO.Path]::GetFullPath($reports)
New-Item -ItemType Directory -Force -Path $reports | Out-Null
$probeOutput = Join-Path $reports $(if ($ReportDirectory) { 'windows-package-probe.json' } else { 'windows-package.json' })
if (Test-Path -LiteralPath $probeOutput) { Remove-Item -LiteralPath $probeOutput }
$qa = Start-Process -FilePath (Join-Path $taskRoot $Executable) -ArgumentList @('--', '--package-probe', ('--probe-output="' + $probeOutput + '"')) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $reports 'package-stdout.log') -RedirectStandardError (Join-Path $reports 'package-stderr.log') -PassThru
$null = $qa.Handle
if (-not $qa.WaitForExit(50000)) { $qa.Kill(); throw 'Package probe timeout' }
$qa.WaitForExit()
$qa.Refresh()
$report = Get-Content -LiteralPath $probeOutput -Raw -Encoding UTF8 | ConvertFrom-Json
$errors = Get-Content -LiteralPath (Join-Path $reports 'package-stderr.log') -Raw -Encoding UTF8
if ($qa.ExitCode -ne 0 -or $report.failures.Count -ne 0 -or $errors -match 'SCRIPT ERROR|ERROR:') { throw "Windows package probe failed: $errors" }
Write-Output "Windows package: $($report.checks) checks passed; board drawn at $($report.first_board_frame_ms) ms before engine startup."
