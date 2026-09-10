"""Verify and summarize the 0.23 artifacts and the current successful test runs."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis23'
release = json.loads((OUT / 'release.json').read_text('utf-8'))
assert release['version'] == '0.23.0' and release['android_version_code'] == 41
proofs = {
    'quality-core.json': '加权分组、取整、折叠、分类导航与环形命中',
    'ui/ui-tests.json': '真实统计、四尺寸两主题、触摸键盘、旋转与棋盘衔接',
    'chessis22_test/ui-tests.json': '评分图、重要图标、阶段分界与曲线导航',
    'chessis21_test/ui-tests.json': '阶段条、长姓名、比例与入口回归',
    'chessis12_test/results.json': '完整报告、筛选、阶段与准确率入口',
    'chessis16_test/results.json': '选中着手、候选根局面、动画与续下',
    'chessis19_test/results.json': '报告摘要、停止续跑和关键时刻',
    'package/windows-package-probe.json': 'Windows 成品、引擎与新阶段条',
    'package/verification.json': 'APK 内容、签名、架构与对齐',
}
counts = {}
for path in proofs:
    result = json.loads((OUT / path).read_text('utf-8-sig'))
    assert not result['failures'], path
    counts[path] = len(result['checks']) if isinstance(result['checks'], list) else int(result['checks'])
for name in ['chessis23', 'chessis22', 'chessis21', 'chessis12', 'chessis16', 'chessis19']:
    assert not (OUT / f'{name}.err').read_text('utf-8-sig').strip(), name
for path in [OUT / 'build-android.log', OUT / 'build-windows.log', OUT / 'package/package-stderr.log']:
    content = path.read_text('utf-8-sig')
    assert not re.search(r'SCRIPT ERROR|ERROR:|FAILED', content), path


def sha(data):
    return hashlib.sha256(data).hexdigest()


for item in release['runtime_sources'] + release['artifacts']:
    assert sha((ROOT / item['path']).read_bytes()) == item['sha256'], item['path']
apk = next(item for item in release['artifacts'] if item['path'].endswith('.apk'))
windows = next(item for item in release['artifacts'] if item['path'].endswith('.zip'))
probe = json.loads((OUT / 'package/windows-package-probe.json').read_text('utf-8'))
with ZipFile(ROOT / windows['path']) as archive:
    assert sha(archive.read('Shogi.exe')) == probe['executable_sha256']
    assert sha((ROOT / 'builds/windows-0.23.0/Shogi.exe').read_bytes()) == probe['executable_sha256']
with ZipFile(ROOT / apk['path']) as archive:
    assert not any('membership' in name.lower() for name in archive.namelist())
    imports = {}
    for source in sorted((ROOT / 'godot/assets/reference-ui').glob('*.svg')):
        packed_import = archive.read('assets/assets/reference-ui/' + source.name + '.import').decode('utf-8')
        imported_path = re.search(r'path="res://([^"]+)"', packed_import)[1]
        local = ROOT / 'godot' / imported_path
        source_md5 = re.search(r'source_md5="([a-f0-9]+)"', local.with_suffix('.md5').read_text('utf-8'))[1]
        assert hashlib.md5(source.read_bytes()).hexdigest() == source_md5, source
        assert archive.read('assets/' + imported_path) == local.read_bytes(), source
        imports[source.name] = sha(local.read_bytes())
    assert len(imports) == 37
    compiled = {name: sha(archive.read('assets/scripts/' + name + '.gdc')) for name in [
        'shogi_report_phases', 'shogi_report_chart', 'shogi_report_chart_model', 'shogi_report_quality', 'shogi_report_pie', 'shogi_report_statistics', 'shogi_chessis_menu', 'shogi_package_probe']}
    for source in ['config/tournaments.json', 'assets/data/tournament-index.json', 'assets/brand/studio-icon.svg']:
        assert archive.read('assets/' + source) == (ROOT / 'godot' / source).read_bytes(), source

engine = json.loads((OUT / 'ui/engine-report.json').read_text('utf-8'))
assert len(engine['source']['moves']) == 140 and len(engine['samples']) == 141 and len(engine['rows']) == 140
geometry = json.loads((OUT / 'ui/geometry.json').read_text('utf-8'))
assert len(geometry) == 8
reference = ROOT / '.work/chessis-reference'
reference_files = ['res/layout/dialog_game_report.xml', 'java/sources/p328r2/C4566d.java',
                   'java/sources/p328r2/C4570h.java', 'java/sources/p197a2/C1735i.java',
                   'java/sources/com/google/android/gms/internal/measurement/C2713z1.java',
                   'java/sources/p328r2/ViewOnClickListenerC4569g.java',
                   'java/sources/com/github/mikephil/charting/charts/PieChart.java']
reference_hashes = {name: sha((reference / name).read_bytes()) for name in reference_files}
from collections import Counter
expected = {}
for side, key in [(1, 'sente'), (-1, 'gote')]:
    raw = Counter(row['category'] for row in engine['rows'] if row['side'] == side)
    expected[key] = [raw['漏着'] + raw['错失胜机'], (raw['不精确'] + 1) // 2 + raw['失误'], sum(raw[name] for name in ['定式', '妙手', '锐利', '最佳', '优秀', '好棋'])]
    assert all(case[key] == expected[key] for case in geometry)
rotation = json.loads((OUT / 'ui/rotation.json').read_text('utf-8'))
assert rotation['released_speed'] > rotation['after_speed'] >= 0
validation = {
    'version': release['version'], 'checks': counts, 'total': sum(counts.values()), 'failures': [],
    'real_engine_report_plies': len(engine['rows']), 'geometry': geometry,
    'artifacts': release['artifacts'], 'compiled_android_scripts': compiled,
    'matched_imported_icons': imports, 'reference_source_sha256': reference_hashes,
    'weighted_groups_from_actual_engine': expected, 'touch_rotation': rotation,
    'runtime_sources_match_release_receipt': True, 'windows_zip_matches_tested_executable': True,
    'first_board_frame_ms': probe['first_board_frame_ms'], 'android_device_tested': False,
}
(OUT / 'artifact-checks.json').write_text(json.dumps(validation, ensure_ascii=False, indent=2), 'utf-8')
(ROOT / 'docs/releases/v0.23.0-validation.json').write_text(json.dumps(validation, ensure_ascii=False, indent=2), 'utf-8')
table = '\n'.join(f'| {proofs[path]} | {count} |' for path, count in counts.items())
report = f'''# 0.23 验证记录

分类统计改为默认折叠、十类真实计数及三组加权质量环形图。质量图点选显示一位小数占比说明，自动滚到说明卡；支持触摸旋转、惯性衰减和键盘选择。点击分类返回原始棋谱位置，棋盘分类按钮连续定位，并保留正在下的原局。

共 **{sum(counts.values()):,} 项检查通过，0 项失败**。计数包含逐尺寸、逐分类和逐图标断言，不代表相同数量的独立用户场景。

| 范围 | 检查数 |
|---|---:|
{table}

实际 YaneuraOu 重新分析完整 140 手棋谱，分组权重额外由 Python 对实际分类计数独立计算，并核对四种尺寸和明暗主题的结果。核心覆盖半次取整边界、空报告、双方／单方分类循环、旋转后的命中、内孔和图外无效点击。UI 另测只有一种质量分组的实际整环像素，避免只验证几何数据。

触摸旋转测试记录释放时的非零速度，并要求随后速度减小；最终结果为 {rotation['released_speed']:.3f} → {rotation['after_speed']:.3f} rad/s。测试在最后一次拖动后立即松手，避免测试计时停顿被误当成用户静止停留；没有将零速度视为衰减通过。返回棋盘后核对原局对象、着手、元数据和计时余额，分类按钮的两行文字位于容器高度内。

Windows 实际成品通过 {counts['package/windows-package-probe.json']} 项探测，首帧棋盘在 {probe['first_board_frame_ms']} 毫秒绘制。APK 为 release、versionCode 41、同包名同签名、ARM64／16 KB 对齐；37 枚参考图标导入纹理一致，质量模型、统计组件、环形图及菜单脚本已编译。Windows ZIP 中的程序散列与受测程序一致。

证据保存在本机 `review/app/chessis23/`，公开摘要为 `docs/releases/v0.23.0-validation.json`。参考算法、布局与适配边界见 `docs/REPORT-STATISTICS.md`。原有评分图、阶段条、分析详情、续下和故事摘要已回归。此前棋盘照明、比例、赛事网络与付费移除检查见 `docs/TESTING-0.20.md`，不计入本轮次数。

未连接 Android 真机，也未动态运行缺少分包的参考 APK。测试不能保证绝对没有 bug，完整功能／UI 复刻尚未完成。赛事工作流需要仓库发布到默认分支并启用后才会持续运行。
'''
(OUT / 'REPORT.md').write_text(report, 'utf-8')
(ROOT / 'docs/TESTING-0.23.md').write_text(report, 'utf-8')
shutil.copy2(OUT / 'ui/quality-selected.png', ROOT / 'docs/images/report-0.23.png')
checksums = ''.join(item['sha256'] + '  ' + Path(item['path']).name + '\n' for item in release['artifacts'])
(ROOT / 'builds/SHA256SUMS-0.23.0.txt').write_text(checksums, 'utf-8')
print(json.dumps({'checks': counts, 'total': sum(counts.values()), 'artifacts': release['artifacts']}, ensure_ascii=False))
