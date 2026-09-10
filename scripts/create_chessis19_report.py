"""Verify the 0.19 build against this run's engine, UI and packaged evidence."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import html
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis19'
release = json.loads((OUT / 'release.json').read_text('utf-8'))
assert release['version'] == '0.19.0' and release['android_version_code'] == 37
proofs = {
    'story-core.json': '阶段表现、稳定获胜、结果状态与数值边界',
    'story-dex-oracle.json': '原始 DEX 有限分支解释执行及真实历史输入核对',
    'ui/results.json': '实际历史摘要、四尺寸两主题、触控与明确标记的分支布局',
    'metrics-regression/metrics.json': '准确率和阶段聚合回归',
    'story-regression/story-core.json': '既有关键时刻、排序、部分报告和终局回归',
    'report-ui/results.json': '完整报告、筛选与阶段入口回归',
    'phase-ui/results.json': '双方阶段卡片、定式与唯一合法着回归',
    'selection-ui/results.json': '候选根局面、动画、详情预览与续下回归',
    'package/windows-package-probe.json': '实际 Windows 成品的新摘要输入与卡片布局',
    'package/verification.json': 'APK 版本、签名、16 KB 对齐、引擎与资源',
}
counts = {}
for path in proofs:
    data = json.loads((OUT / path).read_text('utf-8-sig'))
    assert not data['failures'], path
    counts[path] = len(data['checks']) if isinstance(data['checks'], list) else int(data['checks'])
for path in [*OUT.glob('*.err'), OUT / 'package/package-stderr.log']:
    assert not path.read_text('utf-8-sig').strip(), path
for name in ['build-android.log', 'build-windows.log', 'story19_test.log']:
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
    for name in ['shogi_report_phase_story', 'shogi_phase_accuracy_view', 'shogi_accuracy_insight', 'shogi_accuracy_insight_view', 'shogi_accuracy_chart', 'shogi_report_phases', 'shogi_report_move', 'shogi_report_move_card', 'shogi_rules', 'shogi_usi_codec', 'shogi_report_story', 'shogi_report_story_view', 'shogi_report_eval_marker', 'shogi_report_chart', 'shogi_report', 'shogi_chessis_menu', 'shogi_move_classification', 'shogi_mistake_practice']:
        data = archive.read('assets/scripts/' + name + '.gdc')
        assert len(data) > 100
        compiled[name] = sha(data)
with ZipFile(ROOT / zip_record['path']) as archive:
    assert sha(archive.read('Shogi.exe')) == probe['executable_sha256']
    assert sha((ROOT / 'builds/windows-0.19.0/Shogi.exe').read_bytes()) == probe['executable_sha256']

actual=json.loads((OUT/'ui/actual-report.json').read_text('utf-8'))
assert len(actual['source']['moves'])==140 and len(actual['samples'])==141
assert actual['story']['model']=='shogi-story-19-reference-adapted'
assert actual['story']['phase_context']['sample_count']==141
core=json.loads((OUT/'story-core.json').read_text('utf-8'))
oracle=json.loads((OUT/'story-dex-oracle.json').read_text('utf-8'))
assert not oracle['failures'] and len(oracle['original_dex_results'])==len(core['cases'])
assert all(c['original_dex']['reference']==c['actual']['reference'] for c in oracle['original_dex_results'])
for name,digest in oracle['dex_sha256'].items():
    assert sha((ROOT/f'.work/chessis-reference/dex-evidence/a2-p-{name}.txt').read_bytes())==digest
assert not json.loads((ROOT/'godot/config/membership.json').read_text('utf-8'))['enabled']
receipt={'checks':counts,'compiled_android_scripts':compiled,'matched_raw_assets':len(raw_assets),
         'matched_imported_icons':imported_icons,'original_dex_branch_comparisons':len(core['cases']),
         'reference_summary_branches':len({c['result']['reference'] for c in core['cases']}),
         'windows_zip_matches_tested_executable':True,'runtime_sources_match_release_receipt':True,
         'android_device_tested':False,'real_payments_tested':False}
(OUT/'artifact-checks.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),'utf-8')
table='\n'.join(f'| {proofs[p]} | {n} | [{p}]({p}) |' for p,n in counts.items())
artifacts='\n'.join(f"- `{a['path']}`：{a['bytes']:,} 字节，SHA-256 `{a['sha256']}`。" for a in release['artifacts'])
report=f'''# 将棋 0.19.0 验证记录

报告顶部补齐无明显转折时的阶段表现、持续优势和失误累积摘要。按真实已分析前缀判断哪一方在哪个阶段表现较好、优势是否从早期保持至终局，以及对手是细小不精确、单次还是多次严重失误。没有可计分阶段时不生成阶段优劣结论。

结果判断先区分棋盘胜势与实际胜者、均势下的认输／超时，以及尚未结束的棋谱。未完成分析不借用未来胜者。原版关键时刻卡片补上 12×12 先后手标记，说明左缩进 24，展开按钮居中并保留蓝字、透明底色；修复通用样式覆盖这些颜色的问题。面板内边距和正文行距也按静态布局调整。依据见 [报告摘要说明](../../../docs/REPORT-STORY.md)。

## 本轮验证

| 范围 | 检查数 | 证据 |
|---|---:|---|
{table}

共 {sum(counts.values())} 项检查通过。原始 DEX 的 `a2/p.c` 在 `0356..06e4` 的无关键时刻分支，以及 `I/N/p/j` 助手方法，由有限操作码解释器离线核对；{receipt['original_dex_branch_comparisons']} 个输入覆盖 {receipt['reference_summary_branches']} 个原版摘要资源，先后手镜像、阶段分差、五种错误概况、优势起点和最低评分边界均匹配。实际 140 手棋谱的前缀上下文和阶段优劣计数也与相应指令结果相符。解释器不运行完整 APK，不代替 Android 原版动态验收。

阶段比较使用项目已保存的一位小数分数，以整数十分位计算差距，明确修正 8.2−3.2 可能因二进制精度低于 5.0 的边界问题；此项不声称与原版浮点偶然误差逐位一致。原版条件倒置以原始指令核验，未直接照搬 Java 反编译中的错误分支。

完整官方历史棋谱由真实 YaneuraOu 再次分析，原始样本、着手及摘要保存在 `ui/actual-report.json`。真实界面覆盖 360×760、393×852、852×393、1100×800 四尺寸和明暗两主题、停止／续跑、展开／收起、触摸定位、说明返回及原局隔离。额外四种阶段摘要用明确标記的合成评分检查 360×760 与 852×393 布局，截图标明“非引擎测量”，不会把这些测试数值当作棋力结果。

原阶段弹窗、准确率计算、关键时刻排序、报告筛选、保存候选、二维／三维动画及从当前局面续下均已回归。没有修改三维渲染，本轮不重复计入旧版连续姿态测试。

## 安装包

{artifacts}

Android 包名 `org.shogistudio.artpreview`，versionCode 37，沿用既有签名与用户数据目录。Windows 新目录 `builds/windows-0.19.0` 保留此前成品。

实际 Windows 成品首帧棋盘在 {probe['first_board_frame_ms']} 毫秒绘制；新摘要模型、真实样本上下文、先后手标记与说明缩进另在成品运行验证。APK 新增阶段走势模型字节码，龙王图标及会员配置逐字节核对，{len(imported_icons)} 枚 UI 纹理与源 SVG 导入散列匹配。Windows ZIP 中程序与实际受测程序散列相同，详见 `artifact-checks.json`。

## 尚未完成

已有关键时刻的复杂组合摘要、补充转折重选和额外评语尚未全部迁移；估计 Elo、连续王手循环权重及在线服务等也仍有差距，见 [实现对照](../../../docs/CHESSIS-PARITY.md)。没有原版缺失的运行分包，不能声称逐屏像素一致或完整复制。

真实支付仍需渠道、商户和订单后台，本版不能实际收费。本轮没有连接 Android 真机。
'''
(OUT/'REPORT.md').write_text(report,'utf-8')
cards=[('ui/story-dark-360x760.png','真实历史摘要与固定尺寸先后手标记'),
       ('ui/story-light-393x852.png','明亮主题下的报告'),
       ('ui/expanded-moments.png','居中展开并查看关键时刻'),
       ('ui/fixture-phase_neutral-360x760.png','阶段比较分支 · 合成评分测试'),
       ('ui/fixture-phase_win_all_slips-852x393.png','持续阶段优势 · 合成评分测试'),
       ('ui/fixture-phase_draw_plain-360x760.png','阶段表现与和棋 · 合成评分测试'),
       ('ui/fixture-dominant_win_slips-360x760.png','早期优势保持 · 合成评分测试'),
       ('package/verified-sharp-move.png','实际 Windows 成品的报告布局')]
for path,_ in cards: assert (OUT/path).is_file(),path
body=''.join(f'<figure><img src="{p}" loading="lazy"><figcaption>{html.escape(c)}</figcaption></figure>' for p,c in cards)
page=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>将棋 0.19 验证</title>
<style>body{{margin:0;background:#17100b;color:#f8efe2;font:16px/1.6 system-ui}}main{{max-width:1100px;margin:auto;padding:30px}}h1{{font-size:28px}}a{{color:#82bdff}}section{{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:22px}}figure{{margin:0;background:#292019;padding:12px;border-radius:12px}}img{{display:block;width:100%;max-height:710px;object-fit:contain}}figcaption{{margin-top:10px}}small{{color:#cebaa5}}</style>
<main><h1>将棋 0.19 · 阶段走势摘要</h1><p>阶段表现、持续优势、失误累积和结果状态；关键时刻卡片补齐先后手标记与布局细节。</p><p><a href="REPORT.md">验证记录</a> · <a href="release.json">安装包及源文件散列</a></p><p><small>标明合成评分的截图仅用于测试分支。完整复刻、真实支付与 Android 真机验收尚未完成。</small></p><section>{body}</section></main></html>'''
(OUT/'index.html').write_text(page,'utf-8')
print(json.dumps({'checks':counts,'total':sum(counts.values()),'report':str(OUT/'REPORT.md')},ensure_ascii=False))

