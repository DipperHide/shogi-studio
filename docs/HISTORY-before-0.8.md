# 将棋（Android / Windows 0.7.1）

以雏鹤爱主题首页、奶白与深蓝灰配色、清晰二维木纹棋盘构成的新界面。首页、学习、棋谱、设置共用导航；对局隐藏主导航，以「悔棋／棋谱／更多」操作栏和紧凑玩家信息优先展示棋盘。经典平面、三维木制与菱湖棋字继续可选，切换外观保留同一局的方向、手数、持驹、用时、回放位置和网络连接。

## 运行

- Windows：解压 `builds/Shogi-0.7.1-windows-x64.zip`，运行其中的 `Shogi.exe`。保留随包提供的 `engines` 目录；专业引擎、NNUE、许可证与源码随包提供。
- Android ARM64：安装 `builds/Shogi-0.7.1-android-arm64.apk`。沿用包名 `org.shogistudio.artpreview`、原开发签名与数据目录，versionCode 为 25，可覆盖更新。此前系统启动页等待和 Android 引擎路径修复继续保留。
- 开发：Godot 4.7.2 打开 `godot/project.godot`，按 F5。工具链位置见 `DEV_ENVIRONMENT.md`。

启动恢复存档并显示主题首页，有进行中的棋局时可一键继续。新用户默认清晰木纹、明朝棋字、人机、玩家先手、普通难度、不限时。旧极简设置迁移到新默认，旧三维选择保留。Godot 启动图标已关闭，界面先绘制，引擎随后初始化；Android 系统启动过渡由系统自动结束。

## 对弈与设置

点击自己的棋子，再点合法落点；鼠标和触屏也可拖动棋子或持驹。方向键移动焦点，回车／空格选择或落子，Tab 选择持驹。返回键逐级关闭弹窗、软键盘和页面，返回首页保留棋局；在首页返回不会退出应用。页面可从按钮或下拉框上起手滚动，滑动不会执行按钮操作。升变面板显示棋子预览；设置中的「落子前确认」默认关闭，开启时确认前不会改变棋局或发送网络落子。

二维、三维、教程及回放均依据当前显示局面标出受将军的王／玉：持续红色棋格和边框优先于选择、上一手标记，解将后立即移除。对局状态同时显示「将军」。

人机与同机双人均提供先后手配置、六档电脑难度和六种用时。菜单包含 YaneuraOu 多候选分析、CSA 27 点入玉宣言、认输与棋谱。本地对局在菜单、独立棋谱查看或应用失焦时暂停计时；网络计时由创建对局的一方管理。

界面语言可即时切换简体中文、日文和英文，棋子字面保持日本字形。共享设计组件统一奶白、深蓝文字、浅木与柔粉点缀；深色使用深蓝灰背景。默认跟随系统，可固定明暗，木制模式同步调整照明。

上一手起点角框、终点底色及打入的持驹来源持续保留，直到下一手。取放与回放过渡约 220 毫秒。电脑落子节奏为快／标准／慢，最短等待 0.3／0.8／1.5 秒，默认标准；时间紧张时优先落子，网络同步不增加等待。声音、音量、试听、合法落点提示、上一手标记、坐标和同机自动转向共用。

## 棋谱与迁移

当前棋局保存在 `user://active-game.json`，带临时文件与上一个有效版本备份。棋谱库在 `user://records/`，支持重命名、删除、本应用 JSON 导入导出、逐手和任意步回放。

打开棋谱使用独立查看状态，返回棋盘恢复原局。选择「继续此局」会先成功归档当前棋局；从中间步继续会建立该位置的分支。写入失败保留内存状态并提示重试。

首次统一迁移读取可访问数据目录中的 `minimal-game.json` 与 `current-game.json`，合法旧档归入棋谱库，最近修改的一局作为续局，原文件保留。Windows 数据目录仍为 `%APPDATA%/ShogiStudio`，Android 仍为主应用私有数据目录。

旧木制 Android 独立包名为 `org.shogistudio.classic`。Android 不允许主应用直接读取另一个包的私有数据；这类旧档需导出 JSON 后导入，不能宣称已经自动跨包迁移。调试版旧包可用 `scripts/export_android_legacy.py` 在已授权 ADB 的设备上导出，原存档不变。

## 连接

保留现有 IP／端口直连和 Android 蓝牙。六位连接认证码与原协议兼容；悔棋、和棋、再战及重连沿用协商规则。新增可选消息原因标识，双方按自己的界面语言显示。没有新增网络房间服务、匹配大厅或服务器。

2026-09-07 已用电脑 Wi-Fi 和手机移动数据实测公网直连：当前网络环境下连接及原生 TCP 探测均超时，未进入对战。六位码只负责连接后的认证，不能代替可达的公网地址与端口，也不提供穿透或中转；记录见 `review/app/cross-device/REPORT.md`。

联机存档原子写入 `user://network-game.json`，同时保留上一个有效备份。应用重启后恢复对局身份、协议状态和完整合法棋谱，等待重新连接；损坏的主文件可从备份恢复。主动退出连接会清除该联机恢复记录。已连接时再次点重连会保持当前连接。

## 互动教程

从菜单或主页进入「互动教程」。两本教材各有章节、课节和原页出处；课程正文为中文，教程导航支持中日英。课程存放于 `godot/courses/`，版本清单中的逐页覆盖与散列用于核对成品。

每课组合讲解、选择题、棋盘移动、保护关系选格和连续实战。棋图保留原书实际出现的棋子和持驹，局部图不补入虚构的玉。棋盘与当前对局相互独立，网络对战期间先完成对局或退出连接再学习。

答错或查看答案会进入待复习；重新独立做对后才记为掌握。答案可从起局逐手回放，支持返回上一步、重练、继续上次学习和重置进度。学习记录独立保存在 `user://tutorial-progress.json`，写入失败可重试，损坏记录不会被静默覆盖。课程更新后通过题目内容指纹识别已有进度，修改过的题目需重新练习。

用户提供的 EPUB、扫描图和 OCR 保留在本地 `course_sources/`，不包含在安装包内。完整制作与逐页核验状态见 `IMPLEMENTATION.md` 和 `review/app/complete/tutorial-*-coverage.md`。

## 验证

0.7.1 的滚动、返回、横竖屏适配和主要页面修订验收见 `review/app/ui08/REPORT.md`；前后对比位于同目录 `comparison.html`。0.7.0 的历史完整功能与局域网结果保留在 `review/app/ui07/REPORT.md`，不能替代本版的新实测。

统一界面截图与日志位于 `review/app/unified/`，教程检查位于 `review/app/tutorial/`，0.6.1 最终成品与存档恢复证据位于 `review/app/complete/`。此前桌面模拟触控检查不等同于手机实测；0.6.3 新增的 Android 14 真机启动、引擎、木制资源、教程、触屏落子和后台返回证据位于 `review/app/android-startup-fix/device/`。2026-09-07 Windows 当前源码作为主机与 Android 0.6.3 真机局域网对战通过，覆盖双向落子、吃子升变、打入、悔棋、手动重连和和棋，证据位于 `review/app/lan-device/`；公网直连在当前网络下失败。实时系统主题切换、原生文件选择器、蓝牙两机及反向建房仍待验收。

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test_unified.ps1
powershell -ExecutionPolicy Bypass -File scripts/test_unified_network.ps1
powershell -ExecutionPolicy Bypass -File scripts/test_complete_ui.ps1
powershell -ExecutionPolicy Bypass -File scripts/test_minimal.ps1
powershell -ExecutionPolicy Bypass -File scripts/test_network.ps1
powershell -ExecutionPolicy Bypass -File scripts/test_network_ui.ps1
powershell -ExecutionPolicy Bypass -File scripts/test_tutorial.ps1
python scripts/check_rules_oracle.py
powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1
powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1
powershell -ExecutionPolicy Bypass -File scripts/test_package.ps1 -ReportDirectory review/app/complete/build
.venv/Scripts/python.exe scripts/verify_complete_build.py
```

规则、计时、宣言、动画、USI 与网络计时单元测试在 `godot/tests/`，用 Godot `--headless --path godot --script res://tests/<name>_test.gd` 运行。历史美术与实现说明保留在 `docs/HISTORY-before-0.6.md`；历史测试结果不作为新版验收。

## 结构与素材

- `shogi_app.gd`：统一对局控制、输入、引擎任务、计时、保存、查看状态与联机。
- `shogi_board_view.gd` / `shogi_wood_view.gd`：二维绘制与木制场景、坐标映射和动画。
- `shogi_menu.gd`：共用页面；`shogi_preferences.gd` / `shogi_i18n.gd`：偏好和三语显示。
- `shogi_game.gd` / `shogi_rules.gd`：合法着手、历史和稳定的终局原因、胜方。
- `shogi_records.gd`：独立棋谱库、导入导出与迁移。
- `shogi_match_session.gd` / `shogi_link.gd`：原有直连与蓝牙同步协议。
- `shogi_network_store.gd`：联机状态原子保存、合法备份与恢复。
- `shogi_tutorial*.gd`：课程、独立练习棋盘、答案回放与学习记录。
- `android-plugin/`：Android 蓝牙、文件选择与主题。

雏鹤爱图标与首页插画为此次生成的同人视觉，素材和提示词记录见 `godot/assets/brand/README.md`。棋字来自 LuffyKudo 的 Ryoko（CC BY-SA 4.0）；Noto Sans SC/JP、Noto Serif JP 与 Yuji Syuku 使用 SIL OFL。字面来源、变换及散列在 `godot/assets/glyphs/provenance.json`，许可证与引擎源码声明在 `godot/assets/licenses/`，可从「引擎与署名」查看。
