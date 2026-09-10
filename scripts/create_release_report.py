"""Assemble the current run's evidence, screenshots and explicitly pending checks."""
import html
import json
import zipfile
from datetime import datetime
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'review/app/unified'
release=json.loads((OUT/'release.json').read_text('utf-8'))
ui=json.loads((OUT/'ui-tests.json').read_text('utf-8'))
package=json.loads((OUT/'windows-package.json').read_text('utf-8'))
localization=json.loads((OUT/'localization-tests.json').read_text('utf-8'))
assert not ui['failures'] and not package['failures'] and not localization['failures']
with zipfile.ZipFile(ROOT/release['artifacts'][1]['path']) as apk:
    dex=b''.join(apk.read(name) for name in apk.namelist() if name.endswith('.dex'))
    assert b'isBoardFrameReady' not in dex and b'boardReady' not in dex
    assert b'android.intent.action.OPEN_DOCUMENT' in dex and b'android.intent.action.CREATE_DOCUMENT' in dex

stamp=datetime.now().astimezone().isoformat(timespec='seconds')
rows=[
('统一外观与功能',ui['checks'],'ui-tests.json','48 张实际 Godot 截图；两种外观、三语、两主题、横竖屏、升变、打入、拖动、悔棋、独立回放、迁移、损坏恢复、保存失败、过期引擎、落子节奏'),
('翻译与字体',localization['checks'],'localization-tests.json','三语目录非空、所有界面字符覆盖、日文明朝体全部棋字'),
('原极简输入回归',191,'../minimal/ui-tests.json','点选、模拟触控、多指取消、键盘、升变、打入、满持驹、后台引擎'),
('公共菜单功能回归',30,'../complete/ui-tests.json','六档设置、真实电脑应手、分析、回放、认输、计时、声明入口'),
('网络操作界面',27,'../complete/network-ui-tests.json','直连、协商、拒绝／同意悔棋、断线重连、蓝牙平台入口'),
('不同外观／语言双客户端',61,'peer-host.json','两个独立进程、IPv4 回环；日文和英文；升变、吃子、打入、钟面更新和待确认着手中切换外观'),
('原网络协议回归',47,'../complete/network-host.json','独立进程实际套接字，拒绝非法着手、断线恢复、协商、换先再战与认输'),
('将棋规则',671,'rules-tests.log','初始局面、合法着手、终局与存档；另对照 python-shogi 280 局面、8932 个合法着手'),
('计时',25,'clock-tests.log','主用时、每手读秒与超时'),
('入玉宣言',25,'declaration-tests.log','CSA 27 点门槛及声明判定'),
('动作与实体回放',213,'history_motion-tests.log','吃子、打入、回放中的实体身份与方向'),
('USI 引擎',311,'usi-tests.log','真实 YaneuraOu 初始化、搜索、取消、边界与结果处理'),
('网络计时',21,'network_clock-tests.log','权威时钟、同步、协商及终局'),
('Windows 成品',package['checks'],'windows-package.json','资源已打入包；棋盘先于引擎；引擎与 NNUE 可用；实际返回 7g7f；木制资源可加载'),
]
table='\n'.join(f'| {name} | {count} | 通过 | [{detail}]({path}) |' for name,count,path,detail in rows)
artifacts='\n'.join(f"- [{a['path'].split('/')[-1]}](../../../{a['path']})：{a['bytes']/1024/1024:.1f} MiB；SHA-256 `{a['sha256']}`" for a in release['artifacts'])
report=f'''# 统一版 0.6.0 验收记录

生成时间：{stamp}。本记录采用本次重新执行的结果与截图；历史美术报告未计入新版验收。

## 交付

{artifacts}

Windows 为 x64 便携包，解压后运行 Shogi.exe，并保留 engines 目录。Android 为 ARM64，版本名 0.6.0、versionCode 20，包名 org.shogistudio.artpreview，minSdk 24 / targetSdk 36。APK v2 签名验证通过，与原主应用的证书 SHA-256 一致。Windows 的 ShogiStudio 与 Android 主应用私有数据目录保持不变。ZIP、APK 均逐项校验 CRC，Windows 引擎、NNUE 和源码包齐全。

文件散列与运行代码快照见 [release.json](release.json)。APK 证据见 [包信息](android-badging.txt)、[签名](android-signature.txt)、[Manifest](android-manifest.txt)。

## 已实现与验证

极简与木制均由同一控制层管理规则、引擎、计时、保存、查看状态与连接。切换外观保留同一局、持驹、用时、回放位置及待升变选择；客户端正在等待着手确认时切换也只提交一次。极简不实例化木制模型。

两种外观共用配置、操作、分析、计时、声明与棋谱页。简体中文、日文和英文界面可保存并即时切换；棋子字面使用日本字形。极简菱湖字面以原 SVG 轮廓裁切、启用 mipmap，明朝体可选。浅色暖纸色、深色墨绿灰背景贯穿菜单、弹窗和分析；木制照明随之调整。上一手起点、终点及打入来源持续标记，动作约 220 毫秒，电脑应手节奏支持 0.3 / 0.8 / 1.5 秒，临近超时不继续等待。

棋谱支持重命名、删除、JSON 导入导出和任意步查看。独立查看不替换当前局；明确继续时先归档当前局，写入失败则保留原状态。可访问目录中的两类合法旧档合入棋谱库，原文件保留，损坏当前档可从备份恢复。

| 检查 | 数量 | 结果 | 证据与范围 |
|---|---:|---|---|
{table}

测试中更新了旧用例对音效、220 毫秒动画及失焦取消搜索的预期；新增用例验证对应行为。窗口尺寸覆盖 360×800、480×800、800×480、1280×720，旧触控回归另覆盖 320×480、360×640、390×844、768×1024 和 844×390。截图包含满持驹、升变选择、声明页、长英文设置、回放与分析。

## 启动

Windows 成品诊断确认默认直接进入棋盘，无主页或木制模型；Godot 启动图标关闭。本次成品测量的首次棋盘绘制时间为 Godot 启动计时 {package['first_board_frame_ms']} ms，此时尚未启动引擎。随后启动内置 YaneuraOu / NNUE，返回合法着手，再成功加载木制外观。截图：[棋盘首屏](startup-board.png)、[成品木制日文](startup-wood-ja.png)。

Android 导出启用传感器方向，不通过外观切换强制旋转。启动 Activity 使用保存的明暗或系统主题，系统状态不可用时使用深色；系统过渡自动结束，不再通过阻止首帧绘制的条件等待棋盘通知。APK DEX 已检查旧通知方法不再存在，原生 JSON 文档选择接口仍在。机制说明见 [Android 启动屏幕 API](https://developer.android.com/reference/androidx/core/splashscreen/SplashScreen)。

## 待设备或外部环境验收

- [ADB 清单](android-devices.txt)为空：没有把 Android 编译、签名或桌面模拟触控标记为真机通过。Android 安装、实际首帧、旋转、后台恢复、原生文件选择、实时系统主题切换仍需连接设备检查。
- 两台 Android 的蓝牙权限、发现、连接、断线恢复、计时与跨外观同步尚未实测。现有实现和菜单入口保留。
- TCP 双客户端使用本机 IPv4 回环，公网、防火墙、路由器 NAT 与不同设备网络未实测。
- 旧独立木制 APK 使用 org.shogistudio.classic，Android 应用沙箱禁止统一主包直接读取它的存档。提供 [只读 ADB 导出脚本](../../../scripts/export_android_legacy.py)，连接已授权设备后导出 JSON，再在统一版导入；该跨包导出脚本通过语法检查，尚无设备执行结果。
- 系统主题读取与固定深浅模式已实现；此次没有改动主机系统主题去模拟实时切换。

教程未改动，未新增房间服务、匹配大厅或服务器。

## 实际画面

[完整截图索引](index.html) · [极简深色](minimal-zh-dark.png) · [日文浅色](minimal-ja-light.png) · [英文深色设置](minimal-en-dark-settings.png) · [木制满持驹](wood-full-hands.png) · [木制分析](wood-english-analysis.png)

![极简深色实际 Godot 画面](minimal-zh-dark.png)
'''
(OUT/'REPORT.md').write_text(report,encoding='utf-8')
images=ui['screenshots']+['peer-host-ja','peer-guest-en','startup-board','startup-wood-ja']
cards=''.join(f'<figure><a href="{html.escape(name)}.png"><img loading="lazy" src="{html.escape(name)}.png" alt="{html.escape(name)}"></a><figcaption>{html.escape(name)}</figcaption></figure>' for name in images)
(OUT/'index.html').write_text(f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>静棋 0.6.0 · 实际画面</title><style>body{{margin:0;background:#191c1b;color:#e0dccf;font:16px/1.6 system-ui,sans-serif}}header{{padding:32px;max-width:900px}}h1{{font-weight:500}}a{{color:#b2c2a8}}main{{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:24px;padding:0 32px 32px}}figure{{margin:0;background:#242925;border:1px solid #424b42;border-radius:12px;overflow:hidden}}img{{display:block;width:100%;height:560px;object-fit:contain;background:#191c1b}}figcaption{{padding:12px 16px;overflow-wrap:anywhere}}@media(max-width:600px){{main{{padding:0 12px 16px}}header{{padding:20px}}}}</style><header><h1>静棋 0.6.0 · 实际画面</h1><p>统一版的两种外观、三种语言、深浅主题与横竖屏。以下为 Godot 实际渲染和 Windows 成品截图；Android 真机验证待连接设备。</p><p>{ui['checks']} 项统一功能检查、{localization['checks']} 项翻译／字形检查通过。<a href="REPORT.md">验收记录</a> · <a href="release.json">交付散列</a></p></header><main>{cards}</main></html>''',encoding='utf-8')
print(f'Wrote current acceptance report and {len(images)} image gallery entries.')
