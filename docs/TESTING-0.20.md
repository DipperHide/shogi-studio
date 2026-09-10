# 0.20.0 验证记录 / Validation / 検証

验证环境：Windows 11、Godot 4.7.2、NVIDIA OpenGL 3.3、JDK 17、Android ARM64 release 模板。

本轮完成 **5,259 项检查，0 失败**。计数包含逐格、多尺寸与逐帧断言，不代表相同数量的独立用户场景。规则另与独立 python-shogi 1.1.1 对照 **280 个局面、8,932 个合法着手**，无差异。

| 检查范围 | 通过项数 |
|---|---:|
| 采集器 Python 测试 | 8 |
| Android 启动模板回归 | 5 |
| 规则与确定性对局 | 671 |
| USI 与实际引擎 | 311 |
| 棋谱交换／基础功能 | 37 |
| 目录校验／缓存／失败恢复 | 38 |
| 26 局官方近期棋谱联网校验 | 78 |
| 报告统计 | 35 |
| 报告摘要 | 68 |
| 四种尺寸／明暗／反转／点击／近期棋谱 UI | 1,356 |
| 3D 连续帧移动／吃子／升变／打入 | 2,180 |
| 悔棋／续下／教程／坏棋提醒 UI | 95 |
| 报告选中着手／候选线路 UI | 92 |
| 报告摘要 UI | 142 |
| Windows 成品探测 | 84 |
| APK 内容／签名／架构／对齐 | 59 |

另外逐手解析并验证了 **195 局离线历史棋谱、23,115 手**，以及 **26 局官方近期棋谱、3,092 手**。最后一局取自 2026 年 9 月 8–9 日王位战第六局，140 手。

## 本轮发现与修复

- 深色模式照明过低；将棋盘照明与深色界面分开处理。实测无子格平均渲染亮度从 0.422 提升到 0.735，木纹仍保留。
- 调整正交相机视角和取景：棋盘顶部占分配宽度约 97.5%，投影宽高接近 1:1；棋子本身的物理比例不变。
- 官方 KIF 的「手合割：平手」后有全角空格，导致被误判为让子棋谱。已修复边界空白处理，并添加专门回归。
- 「同　銀」包含全角空格；规范化时保留完整棋子与起点，避免误删成「同」。
- 删除会员页面、购买／恢复接口、权益模块及配置；深度分析、多候选与棋盘颜色无需解锁。

## 验证证据

本机原始记录保存在 `review/app/chessis20/`。该目录包含临时存档、截图和本地日志，不进入 Git；摘要、成品校验值及选定截图进入仓库。

- 新测试：`godot/tests/tournament_sync20_test.gd`、`tournament_network20_test.gd`、`chessis20_test.gd`、`scripts/test_tournaments.py`。
- 规则对照：`scripts/check_rules_oracle.py`。
- 回归入口：`scripts/test_chessis20.ps1`；联网检查需 `-CoreOnly -Network`。
- 额外执行的近期下载 UI 检查：应用以 `--unified-test --chessis20 --tournament-ui-network --chessis20-regression` 参数启动，验证最新棋谱下载、打开、原局隔离、动画和离线缓存。
- 成品检查：`scripts/test_package.ps1`、`scripts/verify_complete_build.py`。Windows 成品首次棋盘帧为 2,329 ms，早于引擎启动。

## 成品

- `Shogi-0.20.0-windows-x64.zip`：150,150,718 bytes；SHA-256 `c103f66df772112b5a6307ea9ba514426a662d59138845a3083993a5a9396dac`。
- `Shogi-0.20.0-android-arm64.apk`：136,111,104 bytes；SHA-256 `a75a16247d9797b2e28e6b9579cff87d41923e82f05f63a2ac7aabacd0c25d87`。

Android 为不可调试的 release APK，包名 `org.shogistudio.artpreview`，versionCode 38，使用原签名，v2 签名校验通过；ARM64 原生库 16 KB 对齐通过。对应引擎源码、UTF-8／CP932 字符表、近期赛事目录均已确认打包，会员资源已确认不存在。

## 尚未验证的范围

本轮未连接 Android 真机，因此没有声称完成 Android 实机触控、蓝牙双机、厂商后台限制或系统文件选择器验收。GitHub Actions 需要仓库上传成功后才会运行；本地通过不能冒充远端 CI 已通过。测试不能保证绝对没有 bug。比赛完整覆盖和参考应用全部功能/UI 的复刻亦未完成。
