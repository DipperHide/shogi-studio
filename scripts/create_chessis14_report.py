"""Verify the 0.14 build against this run's engine, UI and packaged evidence."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import html
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis14'
release = json.loads((OUT / 'release.json').read_text('utf-8'))
assert release['version'] == '0.14.0' and release['android_version_code'] == 32
proofs = {
    'classification-core.json': '评分分支、将棋交换、战术候选与复核拒绝条件',
    'engine/results.json': '真实银将双攻、错失胜机、同深度双候选与复核暂停续跑',
    'ui/results.json': '十类统计、彩色说明、筛选、好棋练习与四种窗口尺寸',
    'engine-regression/report-engine.json': '真实 USI 报告预算、候选线路与停止续跑',
    'metrics-regression/metrics.json': '准确率、胜率、聚合与阶段边界',
    'report-ui/results.json': '完整历史对局、真实特殊分类证据与阶段单调性',
    'practice-ui/results.json': '练习提示、打入、升变、动画、计时与原局隔离',
    'coach-replay-ui/ui-tests.json': '悔棋、持驹比例、回放、续下、教程与真实坏棋提醒',
    'regression/results.json': '编辑、备份、触控棋盘、注释、分析与电脑互战',
    'package/windows-package-probe.json': '实际 Windows 成品的引擎、分类、练习、课程和历史棋谱',
    'package/verification.json': 'APK 版本、签名、16 KB 对齐、原生引擎与资源',
}
counts = {}
for path in proofs:
    data = json.loads((OUT / path).read_text('utf-8-sig'))
    assert not data['failures'], path
    counts[path] = len(data['checks']) if isinstance(data['checks'], list) else int(data['checks'])
for path in [*OUT.glob('*.err'), OUT / 'package/package-stderr.log']:
    assert not path.read_text('utf-8-sig').strip(), path
for name in ['build-android.log', 'build-windows.log', 'classification14_test.log', 'classification14_engine_test.log']:
    value = (OUT / name).read_text('utf-8-sig')
    assert 'SCRIPT ERROR' not in value and 'ERROR:' not in value, name


def sha(data):
    return hashlib.sha256(data).hexdigest()


for item in release['runtime_sources'] + release['artifacts']:
    assert sha((ROOT / item['path']).read_bytes()) == item['sha256'], item['path']
probe = json.loads((OUT / 'package/windows-package-probe.json').read_text('utf-8'))
apk_record = next(a for a in release['artifacts'] if a['path'].endswith('.apk'))
zip_record = next(a for a in release['artifacts'] if a['path'].endswith('.zip'))
with ZipFile(ROOT / apk_record['path']) as archive:
    raw_assets = [ROOT / 'godot/assets/brand/studio-icon.svg', ROOT / 'godot/config/membership.json']
    for path in raw_assets:
        assert archive.read('assets/' + path.relative_to(ROOT / 'godot').as_posix()) == path.read_bytes(), path
    imported_icons = {}
    for path in sorted((ROOT / 'godot/assets/reference-ui').glob('*.svg')):
        packed_import = archive.read('assets/' + path.relative_to(ROOT / 'godot').as_posix() + '.import').decode('utf-8')
        texture = re.search(r'path="res://([^"]+)"', packed_import)[1]
        local_texture = ROOT / 'godot' / texture
        source_digest = re.search(r'source_md5="([a-f0-9]+)"', local_texture.with_suffix('.md5').read_text('utf-8'))[1]
        assert hashlib.md5(path.read_bytes()).hexdigest() == source_digest, path
        packed = archive.read('assets/' + texture)
        assert packed == local_texture.read_bytes(), path
        imported_icons[path.name] = {'source_sha256': sha(path.read_bytes()), 'texture_sha256': sha(packed)}
    compiled = {}
    for name in ['shogi_move_classification', 'shogi_report_tactics', 'shogi_report', 'shogi_report_metrics', 'shogi_mistake_practice', 'shogi_chessis_menu', 'shogi_usi_engine', 'shogi_usi_codec']:
        data = archive.read('assets/scripts/' + name + '.gdc')
        assert len(data) > 100
        compiled[name] = sha(data)
with ZipFile(ROOT / zip_record['path']) as archive:
    assert sha(archive.read('Shogi.exe')) == probe['executable_sha256']
    assert sha((ROOT / 'builds/windows-0.14.0/Shogi.exe').read_bytes()) == probe['executable_sha256']
actual = json.loads((OUT / 'engine/actual-fork.json').read_text('utf-8'))
sharp = actual['rows'][2]
assert sharp['category'] == '锐利' and sharp['classification']['verification']['accepted']
assert not json.loads((ROOT / 'godot/config/membership.json').read_text('utf-8'))['enabled']
receipt = {'checks': counts, 'compiled_android_scripts': compiled, 'matched_raw_assets': len(raw_assets),
           'matched_imported_icons': imported_icons,
           'windows_zip_matches_tested_executable': True, 'runtime_sources_match_release_receipt': True,
           'android_device_tested': False, 'real_payments_tested': False}
(OUT / 'artifact-checks.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2), 'utf-8')
table = '\n'.join(f'| {proofs[p]} | {n} | [{p}]({p}) |' for p, n in counts.items())
artifacts = '\n'.join(f"- `{a['path']}`：{a['bytes']:,} 字节，SHA-256 `{a['sha256']}`。" for a in release['artifacts'])
report = f'''# 将棋 0.14.0 验证记录

本轮继续对照所给 Chessis 20.9 APK，加入十类着手统计、十一枚原版彩色图标、分类说明、计数筛选、错失胜机跳转，以及妙手／锐利练习。窄屏分类名称保持单行，棋盘下方统计可以横向滚动。

普通分类沿原 DEX 分支迁移评分尺度，考虑优势幅度、阶段、胜率和詰み变化。原报告首选中的子力牺牲／多子攻击候选，另经实际 100 毫秒双候选搜索验证，只有同一完成深度的无界限评分、首选身份和候选差距都满足条件才保留特殊分类。复核可以停止和继续，原报告数据不被覆盖。导出包含完整复核证据。

原始分支依据、将棋适配与未覆盖条件见 [MOVE-CLASSIFICATION.md](../../../docs/MOVE-CLASSIFICATION.md)。当前候选识别是原版复杂算法的子集，不是完整等价实现。

## 本轮验证

| 范围 | 检查数 | 证据 |
|---|---:|---|
{table}

合计 {sum(counts.values())} 项检查，来自本轮运行。完整历史棋谱报告重新分析并核查每个特殊分类的真实双候选证据；测试数量随实际特殊着手数变化，不把分类数量当作固定性能指标。四种界面尺寸为 360×760、393×852、852×393、1100×800。

`engine/actual-fork.json` 使用合法银将双攻局面，真实引擎确认 `5e4d` 为锐利；`actual-lost-win.json` 的送飞车着手被识别为错失胜机。新分类界面截图直接使用本轮引擎结果。规则和练习中的其他确定性夹具只验证交互与合法性。

短复核最初只能收到混合深度／界限输出，定位到默认 `PvInterval=300` 超过复核时间预算；报告现请求每轮输出，再选择最高完整深度，没有放宽评分验证。视觉检查修复了统计与操作栏重叠、分类名称竖排。旧触控测试首次失败后补充了后台测试窗口的前台状态设置与棋子选中断言，最终通过；本轮未修改棋盘输入逻辑。最终日志没有脚本错误。

实际导出的 Windows 程序在 {probe['first_board_frame_ms']} 毫秒绘制首张棋盘，并独立完成真实银将双攻复核、十类报告、说明页及练习流程。APK 含新增分类和战术脚本字节码，龙王 SVG 与会员配置同源码逐字节一致；{len(imported_icons)} 枚 UI 图标的导入纹理与本地文件逐字节匹配，并核验源 SVG 的导入散列。Windows ZIP 与受测程序散列一致。精确收据见 `artifact-checks.json` 和 `release.json`。

## 成品与边界

{artifacts}

Android 包名仍为 `org.shogistudio.artpreview`，versionCode 32，沿用原开发签名和数据目录。Windows 位于独立目录 `builds/windows-0.14.0`。

完整复制目标仍未完成：全量战术条件、连续王手循环权重、完整故事摘要、估计 Elo、跨棋谱题库等差距见 [CHESSIS-PARITY.md](../../../docs/CHESSIS-PARITY.md)。所给 APK 缺运行分包，尚无原版逐屏动态核验。

真实支付仍缺渠道、商户及订单后台，本版不能实际收款。ADB 未连接设备，新 APK 尚未在 Android 真机验收。三维渲染代码本轮未改变，其连续帧证据沿用 0.13 基线，未计入本轮检查数。
'''
(OUT / 'REPORT.md').write_text(report, 'utf-8')
cards = [('ui/classification-help.png', '十类分类与唯一合法着说明'),
         ('ui/sharp-filter.png', '点击真实分类计数筛选着手'),
         ('ui/report-dark-360x760.png', '真实引擎确认的银将双攻'),
         ('ui/inline-ten-categories.png', '棋盘下方横向分类统计'),
         ('ui/sharp-practice-settings.png', '筛选报告中的好棋进行练习'),
         ('ui/sharp-practice-solved.png', '在原着之前找出银将双攻'),
         ('package/verified-sharp-move.png', '实际 Windows 成品的复核报告')]
body = ''.join(f'<figure><img src="{p}" loading="lazy"><figcaption>{html.escape(c)}</figcaption></figure>' for p, c in cards)
page = f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>将棋 0.14 验证</title>
<style>body{{margin:0;background:#17100b;color:#f8efe2;font:16px/1.6 system-ui}}main{{max-width:1100px;margin:auto;padding:30px}}h1{{font-size:28px}}a{{color:#82bdff}}section{{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:22px}}figure{{margin:0;background:#292019;padding:12px;border-radius:12px}}img{{display:block;width:100%;max-height:710px;object-fit:contain}}figcaption{{margin-top:10px}}small{{color:#cebaa5}}</style>
<main><h1>将棋 0.14 · 着手分类</h1><p>十类统计、真实战术复核、分类说明与好棋练习。</p><p><a href="REPORT.md">验证记录</a> · <a href="release.json">安装包及源文件散列</a></p><p><small>当前战术识别为原版复杂算法的将棋子集。真实支付与 Android 真机验收尚未完成。</small></p><section>{body}</section></main></html>'''
(OUT / 'index.html').write_text(page, 'utf-8')
print(json.dumps({'checks': counts, 'total': sum(counts.values()), 'report': str(OUT / 'REPORT.md')}, ensure_ascii=False))
