# 0.29 开局预览验证

本轮新执行 **754 项检查**，记录中无失败。另有六组实际绘制帧记录。范围是九条既有开局、独立预览及相关菜单回归；不表示完整复刻或保证没有 bug。

| 验证项 | 检查数 |
|---|---:|
| `openings-core.json` | 80 |
| `ui/ui-tests.json` | 267 |
| `chessis25/ui-tests.json` | 108 |
| `chessis11/ui-tests.json` | 95 |
| `package/windows-package-probe.json` | 108 |
| `package/verification.json` | 59 |
| `interchange-core` | 37 |

界面测试使用真正的触摸事件，覆盖 360×760、393×852、852×393、1100×800、明暗模式，测试输入筛选、列表位置恢复、原棋谱与注释保留、翻转、播放暂停、长按首尾、快速定位、关闭时释放计时器、显式载入和继续对弈入口。竖屏载入按钮固定；横屏完整显示棋盘。六组动画包含正反向、吃子、升变、打入，取样来自实际绘制完成事件。

首次尝试的四项失败和测试脚本异常、第二次尝试的两项失败均保留在本地 `review/app/chessis29/first-attempt`、`second-attempt`。测试夹具补齐了继承字段，改用真实键盘输入；启动时明确原生窗口与逻辑视口一致，避免把逻辑坐标当作窗口输入坐标。另修复横屏预览需滚动才能看全棋盘的问题，随后每个尺寸均实际点击翻转按钮验证。没有删除断言或强制结束动画。

首次 Windows 成品探针在载入函数返回的同一时刻检查“从这里下”，早于菜单下一帧更新可见性，产生一项失败。保留 `package-first-attempt` 原始结果与 EXE 哈希；探针改为观察实际绘制后的按钮，再重新构建 Android 和 Windows。应用交互不因该测试修改。

Windows 成品通过 108 项检查，第一帧棋盘为 2224 毫秒；启动、实际引擎、教程、报告、回放与开局预览均来自打包后的 EXE。APK 检查 ARM64、签名、16 KiB 对齐及资源；确认开局模块随包、会员和测试数据未入包。两种文件的 SHA-256 与发行清单一致。

此前的完整规则、195 局历史棋谱逐手回放、评价和动画压力测试**没有在本轮全量重跑**，不计入上述数量；保留 0.28 的证据并核对相关未改动脚本与数据哈希。所有历史库数据和比赛更新代码保持不变；2026-09-11T00:26:31.454380+00:00 再次读取官方目录，仍是 26 局，条目与内置目录一致。

仍未连接 Android 设备，未进行真机、蓝牙双机和后台恢复验收；Windows 已知绘制停顿仍存在，本轮没有重新做性能基准。GitHub 凭据失效，仓库、Release、远程 CI 和每日更新工作流均未发布／启用。

运行：`./scripts/test_chessis29.ps1`；核心：`./scripts/test_chessis29.ps1 -CoreOnly`。成品：`./scripts/test_package.ps1 -ReportDirectory review/app/chessis29/package -Executable builds/windows-0.29.0/Shogi.exe`。

详见 [开局预览](OPENING-PREVIEW.md)、[机器可读记录](releases/v0.29.0-validation.json) 与 [实现差距](CHESSIS-PARITY.md)。
