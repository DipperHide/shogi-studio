"""Verify the 0.15 build against this run's engine, UI and packaged evidence."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import html
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis15'
release = json.loads((OUT / 'release.json').read_text('utf-8'))
assert release['version'] == '0.15.0' and release['android_version_code'] == 33
proofs = {
    'story-core.json': '原 DEX 候选边界、转折排序、部分分析与终局状态',
    'ui/results.json': '真实历史摘要、后台更新、展开、触控定位、说明与多尺寸布局',
    'report-ui/results.json': '真实历史对局、准确率与阶段、战术复核和图表',
    'classification-ui/results.json': '十类统计、说明、筛选与好棋练习',
    'practice-ui/results.json': '提示、打入、升变、动画、计时与原局隔离',
    'coach-replay-ui/ui-tests.json': '悔棋、持驹比例、回放、续下、教程与真实坏棋提醒',
    'regression/results.json': '编辑、备份、触控棋盘、注释、分析与电脑互战',
    'package/windows-package-probe.json': '实际 Windows 成品的引擎、摘要、卡片、分类与练习',
    'package/verification.json': 'APK 版本、签名、16 KB 对齐、原生引擎与资源',
}
counts = {}
for path in proofs:
    data = json.loads((OUT / path).read_text('utf-8-sig'))
    assert not data['failures'], path
    counts[path] = len(data['checks']) if isinstance(data['checks'], list) else int(data['checks'])
for path in [*OUT.glob('*.err'), OUT / 'package/package-stderr.log']:
    assert not path.read_text('utf-8-sig').strip(), path
for name in ['build-android.log', 'build-windows.log', 'story15_test.log']:
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
    for name in ['shogi_report_story', 'shogi_report_story_view', 'shogi_report_eval_marker', 'shogi_report_chart', 'shogi_report', 'shogi_chessis_menu', 'shogi_move_classification', 'shogi_mistake_practice']:
        data = archive.read('assets/scripts/' + name + '.gdc')
        assert len(data) > 100
        compiled[name] = sha(data)
with ZipFile(ROOT / zip_record['path']) as archive:
    assert sha(archive.read('Shogi.exe')) == probe['executable_sha256']
    assert sha((ROOT / 'builds/windows-0.15.0/Shogi.exe').read_bytes()) == probe['executable_sha256']
actual = json.loads((OUT / 'ui/actual-report.json').read_text('utf-8'))
assert actual['story']['complete'] and actual['story']['closed']
for moment in actual['story']['moments']:
    assert moment['before'] == actual['samples'][moment['ply'] - 1]
    assert moment['after'] == actual['samples'][moment['ply']]
assert not json.loads((ROOT / 'godot/config/membership.json').read_text('utf-8'))['enabled']
receipt = {'checks': counts, 'compiled_android_scripts': compiled, 'matched_raw_assets': len(raw_assets),
           'matched_imported_icons': imported_icons,
           'windows_zip_matches_tested_executable': True, 'runtime_sources_match_release_receipt': True,
           'android_device_tested': False, 'real_payments_tested': False}
(OUT / 'artifact-checks.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2), 'utf-8')
table = '\n'.join(f'| {proofs[p]} | {n} | [{p}]({p}) |' for p, n in counts.items())
artifacts = '\n'.join(f"- `{a['path']}`：{a['bytes']:,} 字节，SHA-256 `{a['sha256']}`。" for a in release['artifacts'])
report = f'''# 将棋 0.15.0 验证记录

本轮继续对照用户给出的 Chessis 20.9 APK，将报告顶部改为走势摘要与关键时刻卡片。默认一条、展开最多十条；每条包含分类图标、实际着手、前后评分、双色评分示意和转折原因。点击选中对应曲线和着手详情，说明弹窗返回后保留选中手及展开状态。

候选筛选核对原始 DEX，排除已经明显落败后继续变差的普通波动。摘要根据已分析局面区分双方机会、逆转、持续优势、和棋，以及棋盘评价和超时／实际结果不同；未完成分析不借用后续终局结果。打开的报告随引擎进度更新。算法与原版尚有差距，见 [REPORT-STORY.md](../../../docs/REPORT-STORY.md)。

## 本轮验证

| 范围 | 检查数 | 证据 |
|---|---:|---|
{table}

合计 {sum(counts.values())} 项检查。`ui/actual-report.json` 保存本轮重新分析的完整 140 手历史棋谱、引擎原始数据和摘要；每条卡片的前后数据均与对应局面逐项核对。原有分类界面回归复用已核验的 0.14 银将双攻真实引擎夹具，未将其称为本轮新搜索结果；新增摘要和报告回归均重新运行引擎。

评分边界单元测试使用明确标记的合成评分；新界面截图使用本轮真实历史对局。四种尺寸为 360×760、393×852、852×393、1100×800，同时覆盖深浅主题。完整历史报告的检查数随实际战术复核数量略有变化。

第一次真实界面回归暴露评分曲线过零处极窄三角形被多边形剖分器拒绝。现直接绘制已有凸三角形／梯形的三角面，保留填充面积和颜色，最终长棋谱及多尺寸检查没有绘制错误。前后评分最初共用节点名称，第二个名称被 Godot 自动改写导致测试找不到，现分别标识 Before／After。修正后全部相关检查通过。

实际 Windows 成品首张棋盘在 {probe['first_board_frame_ms']} 毫秒绘制，并独立执行摘要、默认关键卡片、触控回调、说明返回、真实银将双攻与练习流程。APK 包含新摘要、卡片和图表脚本字节码；龙王图标与会员配置逐字节核对，33 枚 UI 纹理与源 SVG 的导入散列对应。Windows ZIP 与实际受测程序散列相同，详见 `artifact-checks.json`。

## 成品

{artifacts}

Android 包名 `org.shogistudio.artpreview`，versionCode 33，沿用既有签名和数据目录。Windows 导出至独立目录 `builds/windows-0.15.0`。

## 尚未完成

本轮接入主要故事模式，尚未复制原版所有阶段评语、补充转折与特殊摘要分支。完整战术条件、估计 Elo、账号／在线服务等其他差距见 [CHESSIS-PARITY.md](../../../docs/CHESSIS-PARITY.md)。所给原 APK 缺运行分包，仍未动态逐屏对照，不能宣称已经完全复制。

真实支付仍待渠道、商户和订单后台接入。ADB 未连接设备，Android 新版尚未真机验收。三维渲染代码本轮未变，既有连续帧基线未计入本轮检查数。
'''
(OUT / 'REPORT.md').write_text(report, 'utf-8')
cards = [('ui/story-dark-393x852.png', '真实历史对局的摘要与默认关键时刻'),
         ('ui/expanded-moments.png', '展开最多十条有实际评分的转折'),
         ('ui/partial-story.png', '部分分析不提前使用终局结果'),
         ('ui/selected-moment.png', '点击卡片定位对应着手'),
         ('ui/key-moments-help.png', '关键时刻说明，返回保留状态'),
         ('ui/story-light-1100x800.png', '宽屏报告布局'),
         ('package/verified-sharp-move.png', '实际 Windows 成品报告')]
body = ''.join(f'<figure><img src="{p}" loading="lazy"><figcaption>{html.escape(c)}</figcaption></figure>' for p, c in cards)
page = f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>将棋 0.15 验证</title>
<style>body{{margin:0;background:#17100b;color:#f8efe2;font:16px/1.6 system-ui}}main{{max-width:1100px;margin:auto;padding:30px}}h1{{font-size:28px}}a{{color:#82bdff}}section{{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:22px}}figure{{margin:0;background:#292019;padding:12px;border-radius:12px}}img{{display:block;width:100%;max-height:710px;object-fit:contain}}figcaption{{margin-top:10px}}small{{color:#cebaa5}}</style>
<main><h1>将棋 0.15 · 报告摘要</h1><p>走势摘要、可展开的关键时刻、前后评分与点击定位。</p><p><a href="REPORT.md">验证记录</a> · <a href="release.json">安装包及源文件散列</a></p><p><small>主要摘要模式已迁移，原版完整故事分支仍有缺口。真实支付与 Android 真机验收尚未完成。</small></p><section>{body}</section></main></html>'''
(OUT / 'index.html').write_text(page, 'utf-8')
print(json.dumps({'checks': counts, 'total': sum(counts.values()), 'report': str(OUT / 'REPORT.md')}, ensure_ascii=False))
