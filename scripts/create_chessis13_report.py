"""Verify this release's evidence and publish the local review, without old results."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import html
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis13'
release = json.loads((OUT / 'release.json').read_text('utf-8'))
assert release['version'] == '0.13.0' and release['android_version_code'] == 31
proofs = {
    'practice-core.json': '题目筛选、完整历史指纹、非法答案／线路、记录读取',
    'ui/results.json': '真实引擎出题、触控判答、提示、打入、升变、动画、计时／存档隔离和四种窗口尺寸',
    'coach-replay-ui/ui-tests.json': '悔棋、持驹比例、回放、续下、教程和真实引擎坏棋提醒',
    'report-ui/results.json': '真实历史对局报告、准确率／阶段、停止续跑与主题布局',
    'regression/results.json': '既有编辑、备份、分析、对弈与界面流程',
    'motion/telemetry.json': '三维移动、拖动、吃子／打入、节点连续性与阴影同步',
    'package/windows-package-probe.json': '实际 Windows 成品的引擎、练习、报告、课程与历史棋谱',
    'package/verification.json': 'APK 版本、签名、16 KB 对齐、原生引擎和资源',
}
counts = {}
for path in proofs:
    data = json.loads((OUT / path).read_text('utf-8-sig'))
    assert not data['failures'], path
    counts[path] = len(data['checks']) if isinstance(data['checks'], list) else int(data['checks'])
for path in OUT.glob('*.err'):
    assert not path.read_text('utf-8-sig').strip(), path
assert not (OUT / 'package/package-stderr.log').read_text('utf-8-sig').strip()
for path in ['build-android.log', 'build-windows.log', 'practice-core.log']:
    log = (OUT / path).read_text('utf-8-sig')
    assert 'SCRIPT ERROR' not in log and 'ERROR:' not in log, path
probe = json.loads((OUT / 'package/windows-package-probe.json').read_text('utf-8'))


def sha(data):
    return hashlib.sha256(data).hexdigest()


for record in release['runtime_sources'] + release['artifacts']:
    assert sha((ROOT / record['path']).read_bytes()) == record['sha256'], record['path']
apk_record = next(a for a in release['artifacts'] if a['path'].endswith('.apk'))
zip_record = next(a for a in release['artifacts'] if a['path'].endswith('.zip'))
with ZipFile(ROOT / apk_record['path']) as archive:
    for relative in ['assets/brand/studio-icon.svg', 'config/membership.json']:
        assert archive.read('assets/' + relative) == (ROOT / 'godot' / relative).read_bytes()
    compiled = {}
    for name in ['shogi_mistake_practice', 'shogi_app', 'shogi_chessis_menu', 'shogi_report_metrics', 'shogi_report_phases']:
        data = archive.read('assets/scripts/' + name + '.gdc')
        assert len(data) > 100
        compiled[name] = sha(data)
with ZipFile(ROOT / zip_record['path']) as archive:
    assert sha(archive.read('Shogi.exe')) == probe['executable_sha256']
    assert sha((ROOT / 'builds/windows-0.13.0/Shogi.exe').read_bytes()) == probe['executable_sha256']

receipt = {'checks': counts, 'compiled_android_scripts': compiled,
           'apk_icon_and_config_match_source': True, 'windows_zip_matches_tested_executable': True,
           'runtime_sources_match_release_receipt': True, 'android_device_tested': False,
           'real_payments_tested': False}
(OUT / 'artifact-checks.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2), 'utf-8')
table = '\n'.join(f'| {proofs[p]} | {n} | [{p}]({p}) |' for p, n in counts.items())
artifacts = '\n'.join(f"- `{a['path']}`：{a['bytes']:,} 字节，SHA-256 `{a['sha256']}`。" for a in release['artifacts'])
report = f'''# 将棋 0.13.0 验证记录

本轮继续对照用户提供的 Chessis 20.9 APK，把“复习失误”补成可以在主棋盘上答题的练习流程：棋手和类别筛选、默认跳过已尝试、自动判答、两级提示、揭晓、最佳线路动画回放、重试／下一题和分类完成统计。

练习使用独立棋局，活动对局的棋谱和计时余额保持不变；退出恢复原局和报告选中手。支持持驹打入、升变、后手翻转、落子确认，以及二维／三维棋盘。查看提示、答错后完成、直接揭晓均不计作独立答对。练习进度沿用既有学习备份和原子保存。

参考静态代码、判答和持久化细节见 [MISTAKE-PRACTICE.md](../../../docs/MISTAKE-PRACTICE.md)。判答只接受该次报告的引擎首选，其他走法提示“这不是报告中的最佳着”；浅层首选不等于已经证明的唯一最优解。

## 本轮验证

| 范围 | 检查数 | 证据 |
|---|---:|---|
{table}

合计 {sum(counts.values())} 项检查，结果均来自本轮运行。`ui/real-engine-report.json` 保存真实 YaneuraOu 送飞车局面的完整输入和结果；打入、升变及后手题明确使用合法性夹具，不把夹具分数作为真实分析结果。四种窗口尺寸为 360×760、393×852、852×393、1100×800。

首次视觉检查发现窄屏练习标题逐字竖排，已修复为单行标题；筛选弹窗增加尺寸约束，玩家条区分答题方和对方。测试同时修正了两处断言问题：打开页面本来就会暂停原局时钟，比较时应保留计时余额检查、独立检查暂停状态；JSON 读取会规范化数字类型，应比较规范化后的数据。一次 Windows 测试窗口未按指定尺寸缩放，现强制窗口模式并断言真实窗口尺寸后再点击。最终所有检查通过，日志没有脚本错误。

实际导出的 Windows 程序首张棋盘在 {probe['first_board_frame_ms']} 毫秒绘制。它独立加载引擎生成真实题目、判答并动画播放答案线路、写入专用测试学习记录、返回原报告，验证全过程不改用户学习记录。APK 中练习和报告脚本字节码存在，龙王 SVG／会员配置与源码逐字节一致；Windows ZIP 内的程序与实际受测程序散列相同。详见 `artifact-checks.json`。

## 成品

{artifacts}

Android 包名 `org.shogistudio.artpreview`，版本 0.13.0，versionCode 31，沿用原开发签名与数据目录。Windows 导出至独立目录 `builds/windows-0.13.0`，没有覆盖正在运行的旧版程序。

## 尚未完成

完整复制目标继续进行。本轮没有更改六类着手算法，精彩／锐利、遗漏取胜等十类分类、跨棋谱练习题库、估计 Elo、完整故事引擎仍待完成。其余差距见 [CHESSIS-PARITY.md](../../../docs/CHESSIS-PARITY.md)。原 APK 缺少运行分包，仍只有静态对照，不能宣称逐屏完全一致。

真实支付仍缺渠道、商户和订单后台，本版不能实际收款。ADB 设备列表为空，新 APK 尚未在 Android 真机验收；既有真机测试不计入本轮结果。
'''
(OUT / 'REPORT.md').write_text(report, 'utf-8')
cards = [('ui/retry-settings.png', '按棋手和着手类别筛选'),
         ('ui/guess-best.png', '真实引擎题目：从失误之前开始'),
         ('ui/move-hint.png', '第二次提示显示完整着手'),
         ('ui/correct-assisted.png', '区分独立答对与辅助完成'),
         ('ui/wood-practice-852x393.png', '三维棋盘横屏练习'),
         ('ui/practice-complete.png', '揭晓答案计入独立类别'),
         ('package/mistake-practice.png', '实际导出的 Windows 程序')]
body = ''.join(f'<figure><img src="{p}" loading="lazy"><figcaption>{html.escape(c)}</figcaption></figure>' for p, c in cards)
page = f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>将棋 0.13 验证</title>
<style>body{{margin:0;background:#17100b;color:#f8efe2;font:16px/1.6 system-ui}}main{{max-width:1100px;margin:auto;padding:30px}}h1{{font-size:28px}}a{{color:#82bdff}}section{{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:22px}}figure{{margin:0;background:#292019;padding:12px;border-radius:12px}}img{{display:block;width:100%;max-height:710px;object-fit:contain}}figcaption{{margin-top:10px}}small{{color:#cebaa5}}</style>
<main><h1>将棋 0.13 · 复习失误</h1><p>在棋盘上找出最佳着，用提示和动画线路复盘，退出后回到原局。</p><p><a href="REPORT.md">验证记录</a> · <a href="release.json">安装包与源文件散列</a></p><p><small>截图来自本轮真实运行；标注“测试夹具”的局面只验证将棋规则和交互。真实支付与 Android 真机验收尚未完成。</small></p><section>{body}</section></main></html>'''
(OUT / 'index.html').write_text(page, 'utf-8')
print(json.dumps({'checks': counts, 'total': sum(counts.values()), 'report': str(OUT / 'REPORT.md')}, ensure_ascii=False))
