$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '.NET Framework C# compiler is required to build the Windows engine host.' }
& $compiler /nologo /target:exe /optimize+ /platform:x64 ("/out:" + (Join-Path $taskRoot 'engines\yaneuraou\EngineHost.exe')) (Join-Path $taskRoot 'engines\yaneuraou\EngineHost.cs')
if ($LASTEXITCODE -ne 0) { throw 'EngineHost compilation failed' }
