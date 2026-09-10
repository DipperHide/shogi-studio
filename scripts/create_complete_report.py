"""Summarize actual final artifacts and tests without inferring device results."""
from datetime import datetime
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/complete'

def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8-sig'))

release = read('review/app/complete/build/release.json')
verified = read('review/app/complete/build/verification.json')
probe = read('review/app/complete/build/windows-package-probe.json')
tutorial = read('review/app/tutorial/tests.json')
locale = read('review/app/complete/tutorial-localization-tests.json')
store = read('review/app/complete/network-store-tests.json')
restore = read('review/app/complete/network-restore-tests.json')
for report in [verified, probe, tutorial, locale, store, restore]:
    assert report['failures'] == []
assert all(book['complete'] for book in verified['courses'])
books = [read('godot/courses/' + book['file']) for book in verified['courses']]
book_rows = '\n'.join(
    f"| {data['title']} | {meta['lessons']} | {meta['steps']} | {meta['interactive_steps']} | "
    f"{meta['coverage']['authored_verified']} | {meta['coverage']['noninstructional_verified']} |"
    for data, meta in zip(books, verified['courses']))
artifacts = '\n'.join(
    f"- [{Path(item['path']).name}](../../../{item['path']})：{item['bytes']/1024/1024:.1f} MiB，"
    f"SHA-256 `{item['sha256']}`" for item in release['artifacts'])
text = f'''# 将棋 · 静棋 {release['version']} 完成情况与验收

生成于 {datetime.now().astimezone().isoformat(timespec='seconds')}。本次在统一版上补齐两本书的互动教程，并修复联机恢复、蓝牙失败连接资源释放、切换字形和教程答案回放。

## 安装包

{artifacts}

Windows 解压后运行 `Shogi.exe`，保留旁边的 `engines` 文件夹。Android 为 ARM64，版本号 {release['android_version_code']}，主包名仍为 `org.shogistudio.artpreview`，可以覆盖安装同签名的原主应用。

## 教程

两本书共 454 张源页逐页登记，教学页均映射到实际课程；无待制作页或未核对草稿。课程正文为中文，导航支持中日英。课程从菜单与主页进入。

| 教材 | 课数 | 总步骤 | 互动题 | 教学页 | 非教学页 |
|---|---:|---:|---:|---:|---:|
{book_rows}

入门册包含基本走法与规则、攻守与围玉、两盘从初形到将死的完整实战、12 道诘题及原书 24 条错解分支、97 个附录术语。序盘册包含棋子联系、攻守布阵、各围玉和战法的原图、主要变化及反例，逐手操作保留完整持驹；局部图不补造玉。

源图物料说明：序盘册源页索引 98 的示意图少一枚步；索引 160 的第 8 图盘上含成步共 15 枚步，双方又各持步二，合计 19 枚。两次独立目视复核确认这些原图不符合标准物料总数。课程忠实保留示意并记录异常，不能将其视作可从初形到达的实战局面；正常对局规则没有因此改变。

支持选择题、移动/升变/打入、保护关系选格与连续行棋。答案可逐手回放；答错或查看答案进入待复习，重新独立做对才记录为掌握。学习与当前对局相互独立。进度支持续学、保存失败重试、损坏保护和重置备份，修改过的题目通过内容指纹重新安排练习。

- [入门册逐页核验](tutorial-intro-coverage.md)
- [序盘册逐页核验](tutorial-opening-coverage.md)
- [完整课程验证](../tutorial/tests.json)：{tutorial['source_steps']} 步逐一验证，实际完成 {tutorial['source_simulated']} 道互动题；另有 {tutorial['checks']} 项框架、输入、回放、进度、三语和小屏检查，均通过。
- [课程字体检查](tutorial-localization-tests.json)：{locale['checks']} 项通过；日文界面优先使用日文字形，并为中文课程补齐字体回退。

## 本轮修补与成品证据

| 项目 | 结果 |
|---|---|
| 联机原子保存与备份 | {store['checks']} 项通过；只保留经过合法棋谱验证的备份，坏主文件不覆盖好备份 |
| 实际 TCP 重启恢复 | {restore['checks']} 项通过；恢复身份与棋谱、重连后继续走棋，主动退出不恢复旧连接，重复重连不拆掉正常连接 |
| Windows 成品 | {probe['checks']} 项通过；棋盘先于引擎绘制，实际 YaneuraOu / NNUE 初始化并返回合法着手；木制资源及两本教程可打开、示范与保存进度 |
| APK 与最终课程 | {verified['checks']} 项通过；v2 签名、16 KB 对齐、ARM64 原生引擎和源码、模型、课程散列与 Windows 成品及实际测试版本一致 |

成品首次棋盘绘制在 Godot 启动计时 {probe['first_board_frame_ms']} ms，引擎在其后初始化。源码、课程、成品散列见 [release.json](build/release.json) 与 [verification.json](build/verification.json)。

已有统一层回归记录保留在 [0.6.0 统一界面报告](../unified/REPORT.md)：339 项界面、1688 项翻译与字体、671 项规则、311 项 USI、计时/宣言/实际双客户端协议等。其测试范围与日期按原报告保留，不把本轮新增测试与旧截图混淆。

## 尚需真实设备或外部网络

- 当前 ADB 未识别到授权的 Android 手机。APK 已编译并静态验证，但 Android 安装启动、实际引擎、系统文档选择器、权限、触屏和后台恢复尚未真机验收。已准备 `scripts/test_android_device.ps1`，未在设备执行。
- 用户目前只有一台手机，双机蓝牙发现、连接、断线恢复和整局对战仍待第二台设备。蓝牙插件已编译；此事实不等于蓝牙双机通过。
- 网络实测为本机真实 TCP 套接字与两个独立客户端。不同局域网设备及跨公网、路由器 NAT/防火墙的直连尚未实测。应用保留 IP/端口直连，不增加匹配大厅或服务器。

这些项目仍属于原目标的验收缺口，没有标记为全部完成。

## 实际画面

![成品极简首屏](build/startup-board.png)

![成品教程目录](build/tutorial-catalog.png)

![课程练习](../tutorial/book-before.png)

![小屏选格](../tutorial/portrait-280.png)
'''
(OUT / 'REPORT.md').write_text(text, encoding='utf-8')
print(OUT / 'REPORT.md')
