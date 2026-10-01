param([string]$ReportDirectory='review/app/chu37/android')
$ErrorActionPreference='Stop'
$tc=Get-Content "$env:USERPROFILE/Development/toolchain.json" -Raw|ConvertFrom-Json
$adb=Join-Path $tc.sdk 'platform-tools/adb.exe'
$pkg='org.shogistudio.artpreview'
New-Item -ItemType Directory -Force $ReportDirectory|Out-Null
$rotation=(& $adb shell settings get system user_rotation)-join ''
try {
 foreach($mode in @(@{name='portrait';rotation=0},@{name='landscape';rotation=1})) {
  & $adb shell am force-stop $pkg|Out-Null
  & $adb shell settings put system user_rotation $mode.rotation
  & $adb shell run-as $pkg rm -f files/chu-probe.json
  & $adb shell run-as $pkg touch files/chu-probe.request
  & $adb shell am start -n "$pkg/com.godot.game.GodotAppLauncher"|Out-Null
  $deadline=[DateTime]::UtcNow.AddSeconds(40)
  do { Start-Sleep -Milliseconds 500; & $adb shell run-as $pkg test -f files/chu-probe.json } while ($LASTEXITCODE -ne 0 -and [DateTime]::UtcNow-lt $deadline)
  $json=(& $adb shell run-as $pkg cat files/chu-probe.json)-join "`n"
  $json|Set-Content "$ReportDirectory/chu-$($mode.name).json" -Encoding utf8
  $r=$json|ConvertFrom-Json
  if($r.failures.Count){throw ($r.failures-join ', ')}
  "Android Chu $($mode.name): $($r.checks) checks, viewport $($r.viewport -join 'x')"
 }
}finally{
 & $adb shell settings put system user_rotation $rotation
 & $adb shell run-as $pkg rm -f files/chu-probe.request|Out-Null
 & $adb shell am force-stop $pkg|Out-Null
 & $adb shell am start -n "$pkg/com.godot.game.GodotAppLauncher"|Out-Null
}
