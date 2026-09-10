"""Verify and summarize the 0.22 artifacts and the current successful test runs."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis22'
release = json.loads((OUT / 'release.json').read_text('utf-8'))
assert release['version'] == '0.22.0' and release['android_version_code'] == 40
proofs = {
    'chart-core.json': '坐标、图标密集排列、命中边界与部分报告',
    'chart-dex-oracle.json': '原始 DEX 图标排列分支独立执行核对',
    'ui/ui-tests.json': '真实评分图、四尺寸两主题、触摸键盘与拖动',
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
for name in ['chessis22', 'chessis21', 'chessis12', 'chessis16', 'chessis19']:
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
    assert sha((ROOT / 'builds/windows-0.22.0/Shogi.exe').read_bytes()) == probe['executable_sha256']
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
        'shogi_report_phases', 'shogi_report_chart', 'shogi_report_chart_model', 'shogi_chessis_menu', 'shogi_package_probe']}
    for source in ['config/tournaments.json', 'assets/data/tournament-index.json', 'assets/brand/studio-icon.svg']:
        assert archive.read('assets/' + source) == (ROOT / 'godot' / source).read_bytes(), source

engine = json.loads((OUT / 'ui/engine-report.json').read_text('utf-8'))
assert len(engine['source']['moves']) == 140 and len(engine['samples']) == 141 and len(engine['rows']) == 140
geometry = json.loads((OUT / 'ui/geometry.json').read_text('utf-8'))
assert len(geometry) == 8
reference = ROOT / '.work/chessis-reference'
reference_files = ['res/layout/dialog_game_report.xml', 'java/sources/p328r2/C4566d.java',
                   'java/sources/p328r2/C4570h.java', 'java/sources/p254h4/RunnableC3483A.java',
                   'java/sources/com/chessimprovement/chessis/common/abstractclasses/CustomLineChart.java',
                   'dex-evidence/com-chessimprovement-chessis-common-abstractclasses-CustomLineChart-onDraw.txt']
reference_hashes = {name: sha((reference / name).read_bytes()) for name in reference_files}
oracle = json.loads((OUT / 'chart-dex-oracle.json').read_text('utf-8'))
assert oracle['dex_sha256'] == reference_hashes[reference_files[-1]]
assert oracle['checks'] == 1080 and oracle['cases'] == 18
validation = {
    'version': release['version'], 'checks': counts, 'total': sum(counts.values()), 'failures': [],
    'real_engine_report_plies': len(engine['rows']), 'geometry': geometry,
    'artifacts': release['artifacts'], 'compiled_android_scripts': compiled,
    'matched_imported_icons': imports, 'reference_source_sha256': reference_hashes,
    'dex_layout_comparisons': oracle['checks'], 'dex_layout_cases': oracle['cases'],
    'runtime_sources_match_release_receipt': True, 'windows_zip_matches_tested_executable': True,
    'first_board_frame_ms': probe['first_board_frame_ms'], 'android_device_tested': False,
}
(OUT / 'artifact-checks.json').write_text(json.dumps(validation, ensure_ascii=False, indent=2), 'utf-8')
(ROOT / 'docs/releases/v0.22.0-validation.json').write_text(json.dumps(validation, ensure_ascii=False, indent=2), 'utf-8')
table = '\n'.join(f'| {proofs[path]} | {count} |' for path, count in counts.items())
report = f'''# 0.22 验证记录

评分图改为原版的双方优势底色、12 像素关键着手图标及连线；密集的同方图标错行，上下两方独立排列。选中时显示横纵定位线。图表和阶段标题使用相同的左右 8 像素边距，分界线对应同一手数位置。

共 **{sum(counts.values()):,} 项检查通过，0 项失败**。计数包括逐图标、逐尺寸断言，以及针对同一布局输入的独立 DEX 核对，不代表相同数量的独立用户场景。

| 范围 | 检查数 |
|---|---:|
{table}

实际 YaneuraOu 重新分析完整 140 手历史棋谱。图表在四种尺寸和明暗两主题检查：800 ms 渐进展开、实际分类图标、先后手位置、阶段边界、颜色像素、图标扩展命中、键盘首尾／左右和拖动选择着手。部分报告只展示已分析范围，不显示未来评分或分类。

原始 DEX 的 `CustomLineChart.onDraw` 在 `00ff..0195` 的算术与分支由有限解释器执行，18 组布局共 1,080 个标记位置、排列行数和连线条件与实现一致。Java 反编译错误地反转了邻近图标条件；实现按 DEX 的“小于 14 像素时错行”处理。解释器不运行 Android 或完整原 APK。

回放回归的固定 50 ms 取样曾错过中间状态，已改为逐个渲染帧采集进度，并要求至少实际绘制一个中间状态，结果写入 `chessis16_test/replay-motion.json`。该检查没有放宽为只验证动画启动或最终位置。候选根局面、分析详情、续下、原局隔离、阶段和摘要均已回归。

Windows 实际成品通过 {counts['package/windows-package-probe.json']} 项探测，首帧棋盘在 {probe['first_board_frame_ms']} 毫秒绘制。APK 为 release、versionCode 40、同包名同签名、ARM64／16 KB 对齐；37 枚参考图标的导入纹理逐项一致，新增图表模型与脚本已编译。Windows ZIP 与受测程序散列相同。会员配置仍不存在。

证据位于本机 `review/app/chessis22/`，公开摘要为 `docs/releases/v0.22.0-validation.json`。参考与适配边界见 `docs/REPORT-CHART.md`。此前 3D 动画／赛事网络结果见 `docs/TESTING-0.20.md`，不重复计入本轮。

尚未连接 Android 真机，缺少分包的原版 APK 也未动态逐屏比较。原代码配置了 800 ms 的图表展开，但优化后的 DEX 未保留对应动画属性；本项目实现该配置效果，不据此声称原版运行效果已核验。测试不能保证绝对零 bug，完整功能／UI 复刻仍未完成。
'''
(OUT / 'REPORT.md').write_text(report, 'utf-8')
(ROOT / 'docs/TESTING-0.22.md').write_text(report, 'utf-8')
shutil.copy2(OUT / 'ui/chart-dark-393x852.png', ROOT / 'docs/images/report-0.22.png')
checksums = ''.join(item['sha256'] + '  ' + Path(item['path']).name + '\n' for item in release['artifacts'])
(ROOT / 'builds/SHA256SUMS-0.22.0.txt').write_text(checksums, 'utf-8')
print(json.dumps({'checks': counts, 'total': sum(counts.values()), 'artifacts': release['artifacts']}, ensure_ascii=False))
