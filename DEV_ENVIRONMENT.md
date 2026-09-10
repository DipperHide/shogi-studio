# 将棋开发环境

配置日期：2026-09-06。全部安装在当前用户可写目录，未替换已有 Java 19。

| 组件 | 版本 / 位置 |
|---|---|
| Godot 标准版 | 4.7.2；`C:\Users\jinda\Development\Tools\Godot` |
| Godot 导出模板 | 同版 Android / Windows；Godot 自包含的 `editor_data/export_templates/4.7.2.stable` |
| Blender LTS | 4.5.13；`C:\Users\jinda\Development\Tools\blender-4.5.13-windows-x64` |
| Android Studio | Quail 4 / 2026.1.4；`C:\Users\jinda\Development\Tools\android-studio` |
| JDK | Temurin 17.0.20.1；`C:\Users\jinda\Development\Tools\jdk-17.0.20.1+1` |
| Android SDK | `C:\Users\jinda\Development\AndroidSDK` |
| SDK Platforms | Android API 35、36；Godot 当前默认 target 为 36 |
| Build Tools | 35.0.1、36.0.0 |
| Platform Tools | 37.0.1，包含 ADB |
| Android NDK | 28.1.13356709（r28b） |
| CMake | 3.10.2.4988404 |
| Python 资产环境 | 项目 `.venv`；Python 3.11.4、NumPy 2.2.6、Pillow 11.3.0 |

## 打开项目

桌面已创建三个快捷方式：

- **Godot - Shogi**：直接打开 `godot/project.godot`，按 F6 或 F5 运行可玩对局。
- **Blender - Shogi**：直接打开 `models/shogi-scene.blend`，可编辑模型。
- **Android Studio - Shogi**：通过配置好 SDK 路径的启动器打开 Android Studio。

Godot 是自包含安装，SDK、Java 和 Blender 路径已存入编辑器设置。Android Studio 通过 `C:\Users\jinda\Development\Launchers\Android Studio.cmd` 启动，使用独立配置目录 `Development/AndroidStudio`；首次启动可能仍显示欢迎页或隐私偏好选项。

Godot 项目已升级为 0.3.0：主页、开局配置、极简棋盘、拖动落子、木片音效、离线 AI、同机双人、续局和回放均已接入。棋盘使用固定倾斜镜头，通过对局菜单翻转；旧的自由旋转美术预览仍由 `npm run serve` 提供。具体能力和限制见 README.md。

## 构建

在项目目录的 PowerShell 中执行：

```powershell
& .\scripts\build_android.ps1
```

生成 `builds/shogi-playable.apk`，为 ARM64 调试签名版本，目标 Android API 36。开发用签名不用于正式上架。Windows 版运行 `scripts/build_windows.ps1`，生成 `builds/windows/Shogi.exe`。

重新生成 GLB 美术资产：

```powershell
npm run build:art
```

重新生成后，需要把 `models/shogi-scene.glb` 复制到 `godot/assets/shogi-scene.glb`，使 Godot 示例同步更新。

## 验证记录

- 所有下载软件均比对官方发布的 SHA-256 / SHA-512 校验值。
- Blender 成功导入 54 个网格对象，并保存为 `.blend`。
- Godot 成功导入资源并执行场景启动检查。
- Android SDK、ADB、NDK 编译器与 CMake 均可执行。
- Godot 已完成 APK 导出、调试签名和签名验证；另行使用 zipalign 检查 16 KB 页对齐。
- 当前未连接安卓设备，因此尚未进行手机安装、画面与性能验收。

工具清单：`C:\Users\jinda\Development\toolchain.json`。下载缓存：`C:\Users\jinda\Development\Downloads`。安装与构建日志：项目 `environment-logs/`。

## 手机连接

打开手机开发者选项与 USB 调试，用数据线连接后，在手机上同意调试授权。检查设备：

```powershell
& 'C:\Users\jinda\Development\AndroidSDK\platform-tools\adb.exe' devices
```

SDK 位于独立路径，以避免打包桌面应用的 AppData 重定向造成路径不一致。构建脚本只在当前进程设置 JDK 17；系统原有 Java 配置保持可用。
