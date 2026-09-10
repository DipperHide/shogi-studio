"""Verify the 0.18 build against this run's engine, UI and packaged evidence."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import html
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis18'
release = json.loads((OUT / 'release.json').read_text('utf-8'))
assert release['version'] == '0.18.0' and release['android_version_code'] == 36
proofs = {
    'ui/results.json': '实际完整历史、双方、四尺寸两主题、续跑、定式与唯一合法着',
    'phase-oracle.json': 'Python 独立核对阶段手数、分类计数与无额外惩罚的评分',
    'metrics-regression/metrics.json': '准确率聚合、计分排除与将棋阶段划分',
    'report-ui/results.json': '报告筛选、阶段入口、选中手数与布局回归',
    'accuracy-ui/results.json': '准确率图、触摸滚动、卡片定位及空态回归',
    'selection-ui/results.json': '候选根局面、动画、着手详情、预览与续下回归',
    'package/windows-package-probe.json': '实际 Windows 成品的紧凑阶段卡片与现有功能',
    'package/verification.json': 'APK 版本、签名、16 KB 对齐、引擎与资源',
}
counts = {}
for path in proofs:
    data = json.loads((OUT / path).read_text('utf-8-sig'))
    assert not data['failures'], path
    counts[path] = len(data['checks']) if isinstance(data['checks'], list) else int(data['checks'])
for path in [*OUT.glob('*.err'), OUT / 'package/package-stderr.log']:
    assert not path.read_text('utf-8-sig').strip(), path
for name in ['build-android.log', 'build-windows.log', 'report12_test.log']:
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
    for name in ['shogi_phase_accuracy_view', 'shogi_accuracy_insight', 'shogi_accuracy_insight_view', 'shogi_accuracy_chart', 'shogi_report_phases', 'shogi_report_move', 'shogi_report_move_card', 'shogi_rules', 'shogi_usi_codec', 'shogi_report_story', 'shogi_report_story_view', 'shogi_report_eval_marker', 'shogi_report_chart', 'shogi_report', 'shogi_chessis_menu', 'shogi_move_classification', 'shogi_mistake_practice']:
        data = archive.read('assets/scripts/' + name + '.gdc')
        assert len(data) > 100
        compiled[name] = sha(data)
with ZipFile(ROOT / zip_record['path']) as archive:
    assert sha(archive.read('Shogi.exe')) == probe['executable_sha256']
    assert sha((ROOT / 'builds/windows-0.18.0/Shogi.exe').read_bytes()) == probe['executable_sha256']

actual=json.loads((OUT/'ui/actual-report.json').read_text('utf-8'))
assert len(actual['source']['moves'])==140 and len(actual['samples'])==141
assert all(len(actual['phases'][name]['phases'])==3 for name in ['sente','gote'])
oracle=json.loads((OUT/'phase-oracle.json').read_text('utf-8'))
assert not oracle['failures'] and oracle['actual_game_plies']==140
assert 'ic_circle_check.svg' in imported_icons
assert not json.loads((ROOT/'godot/config/membership.json').read_text('utf-8'))['enabled']
receipt={'checks':counts,'compiled_android_scripts':compiled,'matched_raw_assets':len(raw_assets),
         'matched_imported_icons':imported_icons,'independent_phase_oracle_matches':True,
         'windows_zip_matches_tested_executable':True,'runtime_sources_match_release_receipt':True,
         'android_device_tested':False,'real_payments_tested':False}
(OUT/'artifact-checks.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),'utf-8')
table='\n'.join(f'| {proofs[p]} | {n} | [{p}]({p}) |' for p,n in counts.items())
artifacts='\n'.join(f"- `{a['path']}`：{a['bytes']:,} 字节，SHA-256 `{a['sha256']}`。" for a in release['artifacts'])
report=f'''# 将棋 0.18.0 验证记录

阶段准确率改为原版对应的紧凑只读卡片：玩家及整局评分胶囊、开局／中局／终局的本方手数、阶段评分和实际错误图标。错误只显示非零项，顺序为错失胜机、漏着、失误、不精确；有评分但没有错误时显示绿色勾号。

手机竖屏能同时显示三阶段。弹窗保持屏宽 92%、最大 440，木纹、圆角和固定尺寸图标；未分析的未来阶段不提前出现。原先额外添加的长说明、零计数行及阶段复盘按钮已移出弹窗；报告图表和着手卡片继续提供定位、线路预览及续下。关闭阶段弹窗保留原选中手数。参考证据见 [阶段弹窗说明](../../../docs/PHASE-ACCURACY.md)。

## 本轮验证

| 范围 | 检查数 | 证据 |
|---|---:|---|
{table}

合计 {sum(counts.values())} 项检查通过。完整 140 手官方历史棋谱由实际引擎重新分析，双方各 70 手按阶段核对；原始数据在 `ui/actual-report.json`。Python 独立核对每阶段手数、分类计数、排除定式／唯一合法着后的样本数，并重算不叠加整局错误惩罚的阶段准确率。

新界面覆盖 360×760、393×852、852×393、1100×800 四尺寸、明暗两主题和先后手，截图经人工目视核对。部分报告继续分析保留此前真实结果；阶段入口和关闭保留当前选中手。完整历史的开局还覆盖绿色“没有失误”状态，终局覆盖四种错误胶囊。

真实的一手定式棋谱显示“定式”，整局数值为 `—`；后手尚未行棋时显示空态。另用 SFEN `k6r1/9/9/9/9/9/6b2/9/8K b - 1` 验证唯一合法着 `1i1h`：真实引擎输入只有一个合法选择，阶段不计分并显示 `—`，不误标为定式或满分。数据见 `ui/forced-report.json`。

准确率图、触摸滚动、着手详情、保存候选根局面、二维／三维回放动画和从所选局面续下已回归。首轮新增动画检查在前一次定位动画尚未结束时立即发起下一步，补上等待定位完成后通过；未为此修改生产动画代码。当前对局和历史源棋谱保持完整。本轮未修改三维渲染，不重复计入旧版的连续姿态测试。

## 安装包

{artifacts}

Android 包名 `org.shogistudio.artpreview`，versionCode 36，沿用既有签名与用户数据目录。Windows 使用新目录 `builds/windows-0.18.0`，此前版本保留。

实际 Windows 成品首帧棋盘在 {probe['first_board_frame_ms']} 毫秒绘制，已运行新阶段视图、手数和定式标签、评分胶囊、只读卡片及既有引擎／报告／教程／练习检查。APK 包含阶段视图等脚本字节码、龙王图标和会员配置；{len(imported_icons)} 枚参考 UI 纹理与源 SVG 导入散列一致。Windows ZIP 中的程序与实际受测程序散列相同，详见 `artifact-checks.json`。

## 尚未完成

原 APK 缺少运行分包，本轮仍按静态资源与控制代码迁移，未进行原版动态逐屏对照。阶段统计弹窗与走势摘要中的阶段表现分支是不同功能，后者仍未全部迁移。复杂战术／故事分支、连续王手循环权重、估计 Elo、在线服务等差距继续记录于 [实现对照](../../../docs/CHESSIS-PARITY.md)。

真实会员支付尚需渠道、商户和订单后台，本版不能实际收费。本轮没有 Android 真机验收，不能宣称所有功能和 UI 已完全复制。
'''
(OUT/'REPORT.md').write_text(report,'utf-8')
cards=[('ui/phase-dark-1-393x852.png','先手三阶段与紧凑评分胶囊'),
       ('ui/phase-light--1-360x760.png','小屏后手统计与实际错误数量'),
       ('ui/phase-dark-1-852x393.png','横屏布局'),
       ('ui/phase-light--1-1100x800.png','宽屏居中弹窗'),
       ('ui/partial-phase.png','部分分析只显示已经分析的阶段'),
       ('ui/book-phase.png','真实定式阶段'),
       ('ui/forced-phase.png','唯一合法着不冒充定式或满分'),
       ('ui/empty-player.png','本方尚无已分析着手'),
       ('package/compact-phase.png','实际 Windows 成品中的阶段卡片')]
for path,_ in cards: assert (OUT/path).is_file(),path
body=''.join(f'<figure><img src="{p}" loading="lazy"><figcaption>{html.escape(c)}</figcaption></figure>' for p,c in cards)
page=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>将棋 0.18 验证</title>
<style>body{{margin:0;background:#17100b;color:#f8efe2;font:16px/1.6 system-ui}}main{{max-width:1100px;margin:auto;padding:30px}}h1{{font-size:28px}}a{{color:#82bdff}}section{{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:22px}}figure{{margin:0;background:#292019;padding:12px;border-radius:12px}}img{{display:block;width:100%;max-height:710px;object-fit:contain}}figcaption{{margin-top:10px}}small{{color:#cebaa5}}</style>
<main><h1>将棋 0.18 · 紧凑阶段统计</h1><p>本方手数、彩色评分胶囊、实际错误图标，以及定式和无评分空态。</p><p><a href="REPORT.md">验证记录</a> · <a href="release.json">安装包及源文件散列</a></p><p><small>完整复刻、真实支付与 Android 真机验收尚未完成。</small></p><section>{body}</section></main></html>'''
(OUT/'index.html').write_text(page,'utf-8')
print(json.dumps({'checks':counts,'total':sum(counts.values()),'report':str(OUT/'REPORT.md')},ensure_ascii=False))
