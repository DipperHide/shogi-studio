"""Verify the 0.16 build against this run's engine, UI and packaged evidence."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import html
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis16'
release = json.loads((OUT / 'release.json').read_text('utf-8'))
assert release['version'] == '0.16.0' and release['android_version_code'] == 34
proofs = {
    'move-core.json': '参考局势边界、变动原因与将死评分',
    'usi-move-core.json': '单手规则与全盘生成器穷举差分、真实线路格式化',
    'rules-core.json': '既有规则、走法计数、存档与终局',
    'usi-core.json': '既有 USI 编解码及实际引擎',
    'engine-regression/report-engine.json': '独立报告预算、候选线路、停止与恢复',
    'metrics-regression/metrics.json': '准确率与阶段计算',
    'ui/results.json': '紧凑卡片、多尺寸触控、候选根局面、预览、动画与续下',
    'report-settings-ui/results.json': '报告设置、选中着手和三条候选入口',
    'story-ui/results.json': '真实历史摘要、后台更新、展开和关键时刻',
    'report-ui/results.json': '真实历史对局、准确率与阶段、战术复核和图表',
    'classification-ui/results.json': '十类统计、说明、筛选与好棋练习',
    'practice-ui/results.json': '提示、打入、升变、动画、计时与原局隔离',
    'coach-replay-ui/ui-tests.json': '悔棋、持驹比例、回放、续下、教程与真实坏棋提醒',
    'regression/results.json': '编辑、备份、触控棋盘、注释、分析与电脑互战',
    'motion/telemetry.json': '三维吃子、打入、升变、节点稳定和同帧阴影',
    'package/windows-package-probe.json': '实际 Windows 成品的引擎、卡片、定位、动画与详情返回',
    'package/verification.json': 'APK 版本、签名、16 KB 对齐、原生引擎与资源',
}
for log, path, marker in [('rules_test.log', 'rules-core.json', ''), ('usi_test.log', 'usi-core.json', 'USI_TESTS: ')]:
    line = (OUT / log).read_text('utf-8-sig').strip().splitlines()[-1]
    data = json.loads(line.removeprefix(marker))
    (OUT / path).write_text(json.dumps(data, ensure_ascii=False, indent=2), 'utf-8')
counts = {}
for path in proofs:
    data = json.loads((OUT / path).read_text('utf-8-sig'))
    assert not data['failures'], path
    counts[path] = len(data['checks']) if isinstance(data['checks'], list) else int(data['checks'])
for path in [*OUT.glob('*.err'), OUT / 'package/package-stderr.log']:
    assert not path.read_text('utf-8-sig').strip(), path
for name in ['build-android.log', 'build-windows.log', 'report_move16_test.log']:
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
    for name in ['shogi_report_move', 'shogi_report_move_card', 'shogi_rules', 'shogi_usi_codec', 'shogi_report_story', 'shogi_report_story_view', 'shogi_report_eval_marker', 'shogi_report_chart', 'shogi_report', 'shogi_chessis_menu', 'shogi_move_classification', 'shogi_mistake_practice']:
        data = archive.read('assets/scripts/' + name + '.gdc')
        assert len(data) > 100
        compiled[name] = sha(data)
with ZipFile(ROOT / zip_record['path']) as archive:
    assert sha(archive.read('Shogi.exe')) == probe['executable_sha256']
    assert sha((ROOT / 'builds/windows-0.16.0/Shogi.exe').read_bytes()) == probe['executable_sha256']
actual = json.loads((OUT / 'ui/actual-report.json').read_text('utf-8'))
assert len(actual['source']['moves']) == 5 and len(actual['samples']) == 6 and len(actual['rows']) == 5
assert all(len(s['candidates']) == 3 for s in actual['samples'])
assert actual['source']['metadata']['先手'] == '报告先手'
rules = json.loads((OUT / 'usi-move-core.json').read_text('utf-8'))
assert rules['comparisons'] == 205335
benchmark = rules['benchmark']
assert benchmark['full_generator']['labels'] == benchmark['single_move']['labels']
assert not json.loads((ROOT / 'godot/config/membership.json').read_text('utf-8'))['enabled']
receipt = {'checks': counts, 'legal_move_comparisons': rules['comparisons'], 'compiled_android_scripts': compiled,
           'matched_raw_assets': len(raw_assets), 'matched_imported_icons': imported_icons,
           'windows_zip_matches_tested_executable': True, 'runtime_sources_match_release_receipt': True,
           'android_device_tested': False, 'real_payments_tested': False}
(OUT / 'artifact-checks.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2), 'utf-8')
table = '\n'.join(f'| {proofs[p]} | {n} | [{p}]({p}) |' for p, n in counts.items())
artifacts = '\n'.join(f"- `{a['path']}`：{a['bytes']:,} 字节，SHA-256 `{a['sha256']}`。" for a in release['artifacts'])
report = f'''# 将棋 0.16.0 验证记录

选中着手改为参考 APK 对应的紧凑卡片：分类图标、单行着手、前后局势和评分、可选变化原因。点击整卡在棋盘查看该手，关闭只取消选中。初始局面不生成假着手卡片；双方统计使用实际棋手名称。

从报告回到棋盘后，保存的候选线路随当前手更新，保持原报告的线路数且不重新启动引擎。新增“本手解析”，保留分类说明、战术复核数据、行棋前候选预览与直接续下。预览后返回相同详情或棋盘，退出报告回放清理旧线路和箭头。

## 本轮验证

| 范围 | 检查数 | 证据 |
|---|---:|---|
{table}

合计 {sum(counts.values())} 项检查通过，规则差分内另含 {rules['comparisons']:,} 次走法比较，不把每次比较当成独立界面检查。新界面使用本轮引擎实际分析的五手升变、吃子与打入棋谱，原始结果在 `ui/actual-report.json`。四种尺寸为 360×760、393×852、852×393、1100×800，同时覆盖深浅主题。摘要和报告回归重新分析完整历史棋谱；分类界面复用已验证的 0.14 实际引擎夹具，没有冒称是本轮新搜索。

## 回放停顿定位与修复

第一次新增界面检查发现回放开始后仍停在动画起点。计时显示，一次保存线路刷新占用约 160–220 毫秒。原 USI 解析为线路中每一手枚举整盘全部合法走法，阻塞了动画帧。

现仅检查该手的移动、障碍、升变、持驹、二步、死格、王安全与打步诘。原全盘生成器保持原算法，作为差分基准；穷举历史多个阶段及先后手专门禁手局面，单手结果与它全部一致。原规则 671 项及 USI 311 项也通过。相同真实三条线路的格式化，在本机从 {benchmark['full_generator']['milliseconds']:.1f} 毫秒降至 {benchmark['single_move']['milliseconds']:.1f} 毫秒，两种方式的完整着手文字相同。这是本机格式化测量，不能当作 Android 帧率。

新增回放测试保留实际中间动画帧检查，修复后通过。三维连续姿态回归重新运行，吃子、升变、持驹打入、拖动、节点身份、相机与阴影共 2,180 项通过；二维／三维报告导航及快速跳步也通过。

## 成品

{artifacts}

Android 包名 `org.shogistudio.artpreview`，versionCode 34，沿用既有签名和数据目录。Windows 导出至独立目录 `builds/windows-0.16.0`。

实际 Windows 成品首次棋盘在 {probe['first_board_frame_ms']} 毫秒绘制，并运行保存报告定位、候选根局面、动画中间帧、详情预览返回、真实战术复核及教程流程。APK 检查新着手卡片、规则和 USI 等脚本字节码，龙王图标与会员配置逐字节相同，33 枚 UI 纹理与源 SVG 导入散列对应。Windows ZIP 内程序与实际受测程序散列相同，见 `artifact-checks.json`。

## 尚未完成

本轮依据原版静态布局及控制代码，原 APK 仍缺运行分包，没有进行可运行原版的逐屏或逐像素比较。完整故事分支、复杂战术算法、账号／在线服务等差距见 [CHESSIS-PARITY.md](../../../docs/CHESSIS-PARITY.md)。具体交互、评分尺度及证据见 [REPORT-MOVE.md](../../../docs/REPORT-MOVE.md)。

真实支付待渠道、商户和订单后台接入；会员界面及接口已有，本版不能实际收费。本轮没有 Android 设备连接和真机验收，不能宣称全部功能及 UI 已完成复制。
'''
(OUT / 'REPORT.md').write_text(report, 'utf-8')
cards = [('ui/selected-dark-360x760.png', '紧凑选中卡片：前后局势与评分'),
         ('ui/selected-light-1100x800.png', '宽屏报告与真实选手名称'),
         ('ui/report-board-lines.png', '该手之后保存的候选线路'),
         ('ui/move-details.png', '本手解析：比较行棋前的候选'),
         ('ui/move-details-light.png', '浅色主题下的本手解析'),
         ('ui/detail-alternative.png', '预览后返回同一个着手详情'),
         ('ui/wood-report-animation.png', '三维报告回放'),
         ('package/report-board-snapshot.png', '实际 Windows 成品的保存报告局面')]
for path, _ in cards: assert (OUT / path).is_file(), path
body = ''.join(f'<figure><img src="{p}" loading="lazy"><figcaption>{html.escape(c)}</figcaption></figure>' for p, c in cards)
page = f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>将棋 0.16 验证</title>
<style>body{{margin:0;background:#17100b;color:#f8efe2;font:16px/1.6 system-ui}}main{{max-width:1100px;margin:auto;padding:30px}}h1{{font-size:28px}}a{{color:#82bdff}}section{{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:22px}}figure{{margin:0;background:#292019;padding:12px;border-radius:12px}}img{{display:block;width:100%;max-height:710px;object-fit:contain}}figcaption{{margin-top:10px}}small{{color:#cebaa5}}</style>
<main><h1>将棋 0.16 · 着手详情与回放</h1><p>紧凑着手卡片、保存线路随手数定位、本手解析与直接续下；修复线路格式化阻塞动画。</p><p><a href="REPORT.md">验证记录</a> · <a href="release.json">安装包及源文件散列</a></p><p><small>原版完整复刻、真实支付与 Android 真机验收尚未完成。</small></p><section>{body}</section></main></html>'''
(OUT / 'index.html').write_text(page, 'utf-8')
print(json.dumps({'checks':counts,'total':sum(counts.values()),'report':str(OUT / 'REPORT.md')},ensure_ascii=False))
