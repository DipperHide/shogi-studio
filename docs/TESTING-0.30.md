# 0.30 分析导入验证

本轮新执行 **858 项检查**，最终记录无失败。范围包括棋谱导入、编码、界面入口、变化会话和成品回归；不表示完整复刻或保证没有 bug。

| 验证项 | 检查数 |
|---|---:|
| `import-core.json` | 28 |
| `java-decoder.json` | 14 |
| `ui/ui-tests.json` | 130 |
| `chessis25/ui-tests.json` | 108 |
| `chessis11/ui-tests.json` | 95 |
| `chessis29/ui-tests.json` | 267 |
| `package/windows-package-probe.json` | 118 |
| `package/verification.json` | 61 |
| `interchange-core` | 37 |

界面检查覆盖 360×760、393×852、852×393、1100×800 和明暗主题；输入、粘贴、清空、页签、帮助、最近棋谱与文件入口。触摸与键盘使用真实输入事件；桌面文件路径通过选择器信号送入，Android 回调采用测试替身，并未冒称手机系统选择器实测。窗口适应键盘的检查使用模拟键盘高度。

长 JSON 中有 17,500 字注释，最后一手另有注释，载入后全部保留；预览截短不会截短实际棋谱。UTF-8/BOM、CP932、编码错误、字节上限和超限保留旧输入均有检查。JVM 的 14 项检查覆盖完整文件、分段读取、I/O 异常、CP932 扩展字和并发解码；它验证纯 Java 读取器，不能代替 Android 桥接与生命周期测试。

校验期间保留原对局、注释和变化会话；无效数据保留原状态，成功后才结束旧变化会话。历史大赛也检查从变化分析中载入。测试同时覆盖关闭后旧文件回调、旧校验结果丢弃，返回／取消后可重新选择文件。真实本地引擎评价导入局面，回放记录包含 17 个实际绘制完成的帧样本，有起点、中间过程和终点。

首轮核心测试有两项夹具失败：长文本原本未达到 16,000 字，KIF 注释自带尾部换行；原记录保留在 `review/app/chessis30/import-core-first-attempt.*`。首轮和第二轮 UI 各有两项失败，最终定位并修复空搜索条件把全部最近棋谱过滤掉的问题；记录保留在 `ui-first-attempt`、`ui-second-attempt`。视觉检查另修复浅色输入卡片和只读文本颜色，补查修复返回键取消文件选择后的等待状态。没有删掉失败断言。

Windows 成品通过 118 项检查，首帧棋盘 2313 毫秒；成品内实际运行输入、异步解析、完整注释、返回键重试、引擎、教程、报告与动画。APK 检查包括 ARM64、签名、16 KiB 对齐、更新后的原生文件桥接与 CP932 解码器；没有会员或测试数据入包。两种安装文件均以 SHA-256 绑定发行清单。

本轮没有全量重跑规则和 195 局历史棋谱的每一手；相关解析器、规则、动画时钟与赛事数据保持原哈希，延用前版记录，不计入本轮数量。2026-09-11T01:06:29.867303+00:00 再次读取官方目录，仍为 26 局，与内置目录逐项一致。尚未开始的 9 月 15 日棋谱地址返回 404，未收入目录。

CI 已加入导入核心、JVM 和虚拟显示器入口；Linux 虚拟显示器流程明确跳过本机 Windows 引擎两项检查，不冒充引擎验收。GitHub 登录仍失效，仓库、Release、远程 CI 和每日工作流尚未发布／运行。Android 真机、蓝牙双机和后台恢复仍待测试；Windows 已知绘制停顿未在本轮重新做性能基准，也未宣称已解决。

运行：`./scripts/test_chessis30.ps1`；核心：`./scripts/test_chessis30.ps1 -CoreOnly`；JVM：`python scripts/test_import30_java.py`；回归：`./scripts/test_chessis30.ps1 -Probes chessis25,chessis11,chessis29`。脚本自动准备长文本与 CP932 测试文件。成品：`./scripts/test_package.ps1 -ReportDirectory review/app/chessis30/package -Executable builds/windows-0.30.0/Shogi.exe`。

详见 [使用说明](ANALYSIS-IMPORT.md)、[机器可读记录](releases/v0.30.0-validation.json) 和 [实现差距](CHESSIS-PARITY.md)。
