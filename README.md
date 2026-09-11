# 将棋 · Shogi Studio

[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md)

面向 Android 和 Windows 的免费将棋对弈、复盘与学习应用，使用 Godot 4.7.2 和 YaneuraOu 本地引擎。当前版本 **0.31.0**，**所有功能免费开放，没有会员、购买入口或付费解锁**。

![木制棋盘](docs/images/board-0.20.png)

## 安装

本地安装包已生成；GitHub 仓库与 Release 尚未发布，需要先恢复维护者本机的 GitHub 登录。

从 [Releases](https://github.com/DipperHide/shogi-studio/releases) 下载 `Shogi-0.31.0-android-arm64.apk`，适用于 ARM64 Android 设备。Windows 下载 `Shogi-0.31.0-windows-x64.zip`，解压后运行 `Shogi.exe`，保留同目录的 `engines` 文件夹。

Android 包名 `org.shogistudio.artpreview`，versionCode 49。使用 release 导出模板，沿用前版开发签名以便覆盖升级；私钥不在仓库中。安装不同签名的构建前请导出备份。

## 功能

- 六档电脑、同机双人、电脑互战、IP 直连和 Android 蓝牙；升变、持驹打入和将棋禁手校验。
- 二维／三维棋盘、明暗主题、自定义颜色、翻转、拖动、坐标、固定比例持驹。0.20 加宽并调亮木制棋盘。
- 主界面悔棋、带移动动画的逐手／自动回放、分析快照、候选线路预览，从任意选定局面继续下。
- 本地引擎、1–5 条候选线路、快速／深度整局报告、好棋线路、坏棋提醒、局面胜率估计、失误练习和阶段统计。
- 0.21 调整阶段报告：棋手独立成行、胜者奖杯、按手数分配的评分条与可换行摘要；支持触摸及键盘打开详情。等级分尚未校准，显示“—”。
- JSON／KIF／CSA／USI／SFEN 棋谱交换、局面编辑、互动教程、棋谱库、备份与恢复。图标为龙王「龍」。
- 0.22 评分图区分双方优势底色，标出妙手、锐利及严重失误，支持图标点击、键盘与拖动定位；阶段标题与曲线分界对齐。
- 0.23 分类表按需展开，质量环形图标明加权占比；支持点击说明、旋转、键盘操作和从分类返回棋盘连续定位。
- 0.24 快速切换回放时从当前画面继续移动，保留棋子的位置、大小和升变翻面；支持吃子、打入、反向回放和翻转棋盘。
- 0.25 支持同一棋谱内的嵌套变化、两行着手条、长按提升主线、删除撤销与分支注释；可保留主线或自动替换。完整变化使用 JSON 保存、导出和备份。
- 0.26 新增带刻度、评分和深度的评价条，支持智能／左侧／底部位置与连续动画；报告回放保留实际詰手数，左侧也能直接续下。
- 0.27 局面编辑新增独立评价、暂停、拖动摆子、独立撤销／重做、保存局面导航和 SFEN 剪贴板，取消／完成固定在屏幕底部。修复窄屏持驹输入撑宽页面的问题。
- 0.28 棋子先显示起点再移动，绘制停顿后继续播放剩余动作；覆盖主棋盘、分析回放与教程。低帧率时播放时间会延长，Windows 绘制停顿本身仍未解决。
- 0.29 开局与围玉增加分类／先后手筛选、中英日别名搜索和独立动画预览。预览不替换原棋谱，确认载入时保留选中位置；横屏完整显示棋盘。仍为九条教学示例，无大师胜率数据。
- 0.30 分析导入改为内嵌输入、粘贴／文件卡片、来源页签和最近棋谱列表；异步校验保留完整长注释，支持 UTF-8／CP932。载入直接进入分析，取消和过期回调不会替换当前棋谱。
- 0.31 历史大赛使用完整木纹列表、底部筛选面板和赛事多选；整行载入，显示单局下载与缓存状态。近期／离线会话内分别保留筛选和列表位置；独立线程校验，过期结果不会替换当前棋局。

[变化分析用法](docs/VARIATIONS.md) · [0.31 测试结果](docs/TESTING-0.31.md) · [Evaluation bar / 評価バー / 评价条](docs/EVALUATION-BAR.md) · [Position editor / 局面編集 / 局面编辑](docs/POSITION-EDITOR.md) · [Opening preview / 戦法プレビュー / 开局预览](docs/OPENING-PREVIEW.md) · [Analysis import / 棋譜入力 / 分析导入](docs/ANALYSIS-IMPORT.md) · [Tournament archive / 大会棋譜 / 大赛棋谱](docs/TOURNAMENT-ARCHIVE.md)

主要页面和教程文字以中文为主，基础导航支持中、英、日文。三语 README 不代表应用全部页面已完整翻译。

## 持续更新日本赛事

“分析棋谱 → 历史大赛”提供“近期赛事”和“离线历史”。近期目录收录 **26 局**，目前最新为 **2026 年 9 月 8–9 日王位战第六局，140 手**；离线历史库另有 **195 局、23,115 手**。

[更新工作流](.github/workflows/update-tournaments.yml) 每天约北京时间 05:23 检查官方站点。应用进入近期赛事时每天检查一次 HTTPS 目录，也可手动刷新，无需为新比赛重新安装 APK。GitHub 调度可能延迟，工作流须在默认分支启用。

公开目录只包含棋手、赛事、日期、官方链接和着手校验值。选择一局后从官方公开 KIF 下载，识别 UTF-8／CP932，去掉讲解，核对着手哈希并逐手验证合法性，成功后保存到本机供离线复盘。损坏、未结束或不匹配的棋谱不会覆盖已有数据；断网时仍可使用离线历史和已下载棋谱。

覆盖取决于官方公开情况。目前检查王位、王座、棋王、棋圣、叡王和龙王战入口，部分入口没有可读取的近期完整棋谱；不代表覆盖所有日本赛事，也不提供付费来源或实时直播。参见 [官方赛事列表](https://www.shogi.or.jp/match/) 和 [更新维护说明](docs/TOURNAMENT-UPDATES.md)。

## 开发与构建

使用 Windows、Python 3.11+、Godot **4.7.2** 及对应导出模板、JDK 17、Android SDK 36／Build Tools 36.0.0／NDK 28.1.13356709。按本机路径填写 [toolchain.example.json](toolchain.example.json)，保存为 `%USERPROFILE%/Development/toolchain.json`。

```powershell
python -m venv .venv
./.venv/Scripts/python.exe -m pip install -r requirements-dev.txt
./scripts/build_android.ps1
./scripts/build_windows.ps1 -OutputDirectory builds/windows-0.31.0
```

用 Godot 打开 `godot/project.godot` 可开发桌面版。运行素材、引擎和 NNUE 已包含；构建脚本会从同梱源码包恢复引擎源码目录。release APK 需在本机设置 `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`、`GODOT_ANDROID_KEYSTORE_RELEASE_USER`、`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 后运行 `./scripts/build_android.ps1 -Release`。不要提交 keystore 或密码。

## 测试

```powershell
./scripts/test_chessis20.ps1
./scripts/test_chessis20.ps1 -CoreOnly
./scripts/test_chessis20.ps1 -CoreOnly -Network
./scripts/test_chessis23.ps1
./scripts/test_chessis24.ps1
./scripts/test_chessis31.ps1 -CoreOnly
./scripts/test_chessis31.ps1
./scripts/test_package.ps1 -ReportDirectory review/app/chessis31/package -Executable builds/windows-0.31.0/Shogi.exe
```

[CI](.github/workflows/ci.yml) 在 push／PR 时运行核心测试。本地另测四种尺寸、两个方向、明暗模式、持驹、吃子／升变／打入动画和实际引擎。结果见 [0.23 分类统计验证](docs/TESTING-0.23.md) 和 [0.20 棋盘／赛事验证](docs/TESTING-0.20.md)。测试降低已覆盖场景的回归风险，不能保证绝对没有 bug；本轮未连接 Android 真机，蓝牙双机和系统后台恢复仍需设备验收。

本机 Windows 空窗口也出现约 450 毫秒的绘制停顿，尚未解决；不能据此宣称所有设备上的动画始终流畅。详见 [0.24 动画验证](docs/TESTING-0.24.md)。

## 数据与来源

存档使用原来的 `ShogiStudio` 用户目录，Android 使用应用私有目录。赛事缓存位于 `user://tournaments/`；更新不会上传个人棋局。

这是独立的将棋界面适配工程，与 Chessis、日本将棋联盟及赛事主办方无隶属关系，也未宣称原应用的所有功能与 UI 已完整复刻。见 [实现对照](docs/CHESSIS-PARITY.md)。YaneuraOu 随发行包附带 GPL 对应源码；棋字、字体、评价模型和参考 UI 保留各自来源，不重新许可为 MIT。见 [第三方说明](THIRD_PARTY_NOTICES.md)。
