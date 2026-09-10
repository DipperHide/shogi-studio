"""Verify the 0.17 build against this run's engine, UI and packaged evidence."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import html
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis17'
release = json.loads((OUT / 'release.json').read_text('utf-8'))
assert release['version'] == '0.17.0' and release['android_version_code'] == 35
proofs = {
    'accuracy-core.json': '逐手筛选、原手数、局势边界、饱和准确率与高亮排序',
    'gote-core.json': '实际引擎的后手先行 SFEN、原手数与评分对齐',
    'accuracy-oracle.json': 'Python 独立聚合、每个实际图点与默认高亮对照',
    'ui/results.json': '真实完整历史、四尺寸明暗主题、点击／滑动／键盘与空态',
    'engine-regression/report-engine.json': '引擎预算、候选、停止与恢复',
    'metrics-regression/metrics.json': '既有准确率与阶段计算',
    'report-ui/results.json': '真实历史报告、独立准确率／阶段入口、筛选与主题',
    'selection-ui/results.json': '紧凑卡片、保存候选、动画、详情预览与续下',
    'story-ui/results.json': '历史摘要、后台更新、关键时刻和点击定位',
    'regression/results.json': '编辑、备份、触控棋盘、注释、分析与电脑互战',
    'package/windows-package-probe.json': '实际 Windows 成品的准确率详情、定位、阶段和 ACPL',
    'package/verification.json': 'APK 版本、签名、16 KB 对齐、引擎与资源',
}
counts = {}
for path in proofs:
    data = json.loads((OUT / path).read_text('utf-8-sig'))
    assert not data['failures'], path
    counts[path] = len(data['checks']) if isinstance(data['checks'], list) else int(data['checks'])
for path in [*OUT.glob('*.err'), OUT / 'package/package-stderr.log']:
    assert not path.read_text('utf-8-sig').strip(), path
for name in ['build-android.log', 'build-windows.log', 'accuracy17_test.log']:
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
    for name in ['shogi_accuracy_insight', 'shogi_accuracy_insight_view', 'shogi_accuracy_chart', 'shogi_report_phases', 'shogi_report_move', 'shogi_report_move_card', 'shogi_rules', 'shogi_usi_codec', 'shogi_report_story', 'shogi_report_story_view', 'shogi_report_eval_marker', 'shogi_report_chart', 'shogi_report', 'shogi_chessis_menu', 'shogi_move_classification', 'shogi_mistake_practice']:
        data = archive.read('assets/scripts/' + name + '.gdc')
        assert len(data) > 100
        compiled[name] = sha(data)
with ZipFile(ROOT / zip_record['path']) as archive:
    assert sha(archive.read('Shogi.exe')) == probe['executable_sha256']
    assert sha((ROOT / 'builds/windows-0.17.0/Shogi.exe').read_bytes()) == probe['executable_sha256']
actual = json.loads((OUT / 'ui/actual-report.json').read_text('utf-8'))
assert len(actual['source']['moves']) == 140 and len(actual['samples']) == 141
for name, side in [('sente', 1), ('gote', -1)]:
    model = actual['insights'][name]
    assert model['model'] == 'shogi-accuracy-insight-17-reference-adapted'
    assert len(model['points']) == model['overall']['evaluated']
    assert model['side'] == side and model['player']
    for point in model['points']:
        assert point['before'] == actual['samples'][point['ply'] - 1]
        assert point['after'] == actual['samples'][point['ply']]
oracle = json.loads((OUT / 'accuracy-oracle.json').read_text('utf-8'))
assert not oracle['failures']
assert all(oracle['independent_impact_results'][name] == actual['insights'][name]['impact'] for name in ['sente', 'gote'])
gote = json.loads((OUT / 'gote-core.json').read_text('utf-8'))
assert gote['gote']['points'][0]['ply'] == 1 and gote['sente']['points'][0]['ply'] == 2
assert not json.loads((ROOT / 'godot/config/membership.json').read_text('utf-8'))['enabled']
receipt = {'checks':counts, 'compiled_android_scripts':compiled, 'matched_raw_assets':len(raw_assets),
           'matched_imported_icons':imported_icons, 'independent_accuracy_oracle_matches':True,
           'windows_zip_matches_tested_executable':True, 'runtime_sources_match_release_receipt':True,
           'android_device_tested':False, 'real_payments_tested':False}
(OUT / 'artifact-checks.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),'utf-8')
table = '\n'.join(f'| {proofs[p]} | {n} | [{p}]({p}) |' for p,n in counts.items())
artifacts = '\n'.join(f"- `{a['path']}`：{a['bytes']:,} 字节，SHA-256 `{a['sha256']}`。" for a in release['artifacts'])
report = f'''# 将棋 0.17.0 验证记录

本轮补齐原版独立“准确率”详情：玩家、整局数值、基准虚线、每手表现图及点击后出现的着手卡片。长图横向滚动，点击卡片定位对应棋盘并显示保存的候选线路。关闭详情返回报告，保留之前选中的手数。

原版准确率、阶段条及 ACPL 分别打开不同内容。现在准确率进入逐手详情，阶段条继续进入阶段统计；开启 ACPL 后它有独立点击目标与说明。阶段详情由全屏改为屏宽 92%、最大 440 的居中木纹弹窗，背景按原版裁切圆角。原始资源及控制代码依据见 [ACCURACY-INSIGHT.md](../../../docs/ACCURACY-INSIGHT.md)。

## 本轮验证

| 范围 | 检查数 | 证据 |
|---|---:|---|
{table}

合计 {sum(counts.values())} 项检查通过。新界面重新分析官方完整 140 手历史棋谱，保留原始数据、逐手指标及双方详情模型于 `ui/actual-report.json`。Python 独立重算整局聚合、每一个图点和逐次剔除一手的默认高亮，全部匹配。默认高亮遵循参考的提升量、单手准确率与原手数排序；不把最深的图点简单当成贡献最大的一手。

覆盖部分报告、停止／续跑、先后手、四种窗口尺寸（360×760、393×852、852×393、1100×800）、明暗主题、实际触摸点选与拖动、键盘首尾和滚动定位。后手先行 SFEN 另由实际引擎分析，验证第 1 手为后手、第 2 手为先手的原编号与前后评分。

定式与唯一合法着不生成评分点。只有定式的真实短棋谱显示 `—` 和空态，未完成的后续手不造占位值。评分饱和为 100 的坏棋按参考显示“局面已定”的不适用说明。每次打开详情固定使用当时的分析快照；探索详情、阶段或跳回棋盘均未改变当前对局和原历史棋谱。

相邻版本的紧凑卡片、候选根局面、二维／三维报告动画、详情预览及续下已复测；三维渲染本轮未修改，没有把旧版 2,180 项连续姿态测试重复计入本轮数量。现有阶段卡片的全部表现评语仍有差距。

## 成品

{artifacts}

Android 包名 `org.shogistudio.artpreview`，versionCode 35，沿用既有签名和数据目录。Windows 新目录为 `builds/windows-0.17.0`。

实际 Windows 成品首帧棋盘在 {probe['first_board_frame_ms']} 毫秒绘制，独立运行准确率弹窗、真实图点、评分变化、卡片定位、保存候选、阶段与 ACPL 返回，并保留既有引擎、报告、练习及教程检查。APK 包含新模型、图表和详情脚本字节码；龙王图标及会员配置逐字节相同，33 枚 UI 纹理与源 SVG 导入散列对应；Windows ZIP 内程序与实际受测程序散列相同。详见 `artifact-checks.json`。

## 尚未完成

当前是按用户 APK 的静态资源和控制代码继续迁移，原 APK 缺运行分包，尚无原版动态逐屏对照。完整阶段评语、复杂战术／故事分支、连续王手循环权重、估计 Elo、在线服务等仍未全部迁移，见 [CHESSIS-PARITY.md](../../../docs/CHESSIS-PARITY.md)。没有套用原版国际象棋的棋力准确率基准作为将棋测量结果。

会员真实支付仍需接入渠道、商户和订单后台；本版不能实际收费。本轮没有 Android 真机验收，不能宣称所有功能和 UI 已完全复制。
'''
(OUT / 'REPORT.md').write_text(report,'utf-8')
cards = [('ui/accuracy-dark-1-393x852.png','先手准确率与每手表现'),
         ('ui/selected-accuracy-move.png','点击棋点查看实际评分变化'),
         ('ui/scrolled-accuracy.png','横向滚动并定位原第 140 手'),
         ('ui/accuracy-to-board.png','从详情直接回到对应棋盘'),
         ('ui/accuracy-light--1-1100x800.png','宽屏仍使用居中木纹弹窗'),
         ('ui/bounded-phase-detail.png','阶段统计的独立入口'),
         ('ui/empty-accuracy.png','真实定式棋谱的无评分状态'),
         ('package/accuracy-selected-move.png','实际 Windows 成品的图点详情')]
for path,_ in cards: assert (OUT/path).is_file(),path
body = ''.join(f'<figure><img src="{p}" loading="lazy"><figcaption>{html.escape(c)}</figcaption></figure>' for p,c in cards)
page = f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>将棋 0.17 验证</title>
<style>body{{margin:0;background:#17100b;color:#f8efe2;font:16px/1.6 system-ui}}main{{max-width:1100px;margin:auto;padding:30px}}h1{{font-size:28px}}a{{color:#82bdff}}section{{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:22px}}figure{{margin:0;background:#292019;padding:12px;border-radius:12px}}img{{display:block;width:100%;max-height:710px;object-fit:contain}}figcaption{{margin-top:10px}}small{{color:#cebaa5}}</style>
<main><h1>将棋 0.17 · 准确率详情</h1><p>独立准确率弹窗、可横向滚动的每手表现图、点击定位，以及独立的阶段和 ACPL 入口。</p><p><a href="REPORT.md">验证记录</a> · <a href="release.json">安装包及源文件散列</a></p><p><small>完整复刻、真实支付与 Android 真机验收尚未完成。</small></p><section>{body}</section></main></html>'''
(OUT / 'index.html').write_text(page,'utf-8')
print(json.dumps({'checks':counts,'total':sum(counts.values()),'report':str(OUT/'REPORT.md')},ensure_ascii=False))
