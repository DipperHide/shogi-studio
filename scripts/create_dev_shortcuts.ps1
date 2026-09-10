$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$devRoot = Join-Path $env:USERPROFILE 'Development'
$config = Get-Content -LiteralPath (Join-Path $devRoot 'toolchain.json') -Raw | ConvertFrom-Json
$launchers = Join-Path $devRoot 'Launchers'
New-Item -ItemType Directory -Force -Path $launchers | Out-Null
$studioProperties = Join-Path $devRoot 'android-studio.properties'
@"
idea.config.path=$($devRoot.Replace('\','/'))/AndroidStudio/config
idea.system.path=$($devRoot.Replace('\','/'))/AndroidStudio/system
idea.plugins.path=$($devRoot.Replace('\','/'))/AndroidStudio/plugins
idea.log.path=$($devRoot.Replace('\','/'))/AndroidStudio/log
"@ | Set-Content -LiteralPath $studioProperties -Encoding utf8
@"
@echo off
set "ANDROID_HOME=$($config.sdk)"
set "ANDROID_SDK_ROOT=$($config.sdk)"
set "STUDIO_PROPERTIES=$studioProperties"
start "" "$($config.studio)" %*
"@ | Set-Content -LiteralPath (Join-Path $launchers 'Android Studio.cmd') -Encoding ascii
$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$links = @(
    @{Name='Godot - Shogi'; Target=$config.godot; Args='--editor --path "' + (Join-Path $taskRoot 'godot') + '"'; Icon=$config.godot},
    @{Name='Blender - Shogi'; Target=$config.blender; Args='"' + (Join-Path $taskRoot 'models\shogi-scene.blend') + '"'; Icon=$config.blender},
    @{Name='Android Studio - Shogi'; Target=(Join-Path $launchers 'Android Studio.cmd'); Args=''; Icon=$config.studio}
)
foreach ($entry in $links) {
    $shortcutPath = Join-Path $desktop ($entry.Name + '.lnk')
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $entry.Target
    $shortcut.Arguments = $entry.Args
    $shortcut.IconLocation = $entry.Icon
    $shortcut.WorkingDirectory = $taskRoot
    $shortcut.Description = 'Shogi development environment'
    $shortcut.Save()
    Write-Output $shortcutPath
}
# Android's environment is added only if the user has no existing SDK setting.
if (-not [Environment]::GetEnvironmentVariable('ANDROID_HOME','User')) {
    [Environment]::SetEnvironmentVariable('ANDROID_HOME',$config.sdk,'User')
}
Write-Output 'Shortcuts and isolated Android Studio configuration created.'
