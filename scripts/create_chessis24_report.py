"""Check 0.24 release receipts; keep functional checks and frame budgets separate."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis24'


def read(path):
    return json.loads(path.read_text('utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


release = read(OUT / 'release.json')
assert release['version'] == '0.24.0' and release['android_version_code'] == 42
proofs = {
    'candidate/ui-tests.json': '回放衔接、物理棋子身份、模型释放及实际中间帧',
    'chessis16_test/results.json': '实际引擎报告、当前手候选、回放与续下',
    'chessis13_test/results.json': '失误练习、动画预览、原局恢复与学习保存',
    'chessis11_test/ui-tests.json': '四尺寸棋盘、回放、悔棋、教程、坏棋提醒与好棋线路',
    'package/windows-package-probe.json': 'Windows 成品启动、引擎和界面资源',
    'package/verification.json': 'APK 架构、签名、对齐和内容',
}
counts = {}
for name in proofs:
    result = read(OUT / name)
    assert not result['failures'], name
    counts[name] = len(result['checks']) if isinstance(result['checks'], list) else int(result['checks'])
for name in ['chessis24', 'chessis16', 'chessis13', 'chessis11']:
    assert (OUT / f'{name}.exit').read_text('utf-8-sig').strip() == '0', name
    assert not (OUT / f'{name}.err').read_text('utf-8-sig').strip(), name
for name in ['build-android.log', 'build-windows.log', 'package/package-stderr.log']:
    assert not re.search(r'SCRIPT ERROR|ERROR:|FAILED', (OUT / name).read_text('utf-8-sig')), name
for item in release['runtime_sources'] + release['artifacts']:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']

continuity = read(OUT / 'candidate/continuity.json')
assert len(continuity) == 36
assert {(row['appearance'], row['flipped']) for row in continuity} == {('minimal', False), ('minimal', True), ('wood', False), ('wood', True)}
assert all(row['piece_count'] == 40 and row['max_rect_jump_px'] < 0.001 and row['max_world_jump'] < 0.00001 for row in continuity)
timing = read(OUT / 'candidate/timing.json')['measurements']
assert len(timing) == 22
assert all(row['within_frame_budget'] == (row['max_gap'] <= row['frame_budget_ms']) for row in timing)
missed = [row['scenario'] for row in timing if not row['within_frame_budget']]
empty = {}
for driver in ['opengl3', 'angle', 'vulkan']:
    frames = read(OUT / f'empty-{driver}.json')[5:]
    assert len(frames) > 100
    empty[driver] = {'frames': len(frames), 'max_gap_ms': max(row['gap_ms'] for row in frames), 'max_render_ms': max(row['render_ms'] for row in frames)}

windows = next(item for item in release['artifacts'] if item['path'].endswith('.zip'))
apk = next(item for item in release['artifacts'] if item['path'].endswith('.apk'))
probe = read(OUT / 'package/windows-package-probe.json')
with ZipFile(ROOT / windows['path']) as archive:
    assert hashlib.sha256(archive.read('Shogi.exe')).hexdigest() == probe['executable_sha256']
    assert sha(ROOT / 'builds/windows-0.24.0/Shogi.exe') == probe['executable_sha256']
with ZipFile(ROOT / apk['path']) as archive:
    assert not any('membership' in name.lower() or name.startswith('assets/tests/') for name in archive.namelist())
    compiled = {name: hashlib.sha256(archive.read(f'assets/scripts/{name}.gdc')).hexdigest() for name in [
        'shogi_app', 'shogi_board_view', 'shogi_wood_view', 'shogi_chessis_menu', 'shogi_history_motion']}
    for name in ['config/tournaments.json', 'assets/data/tournament-index.json', 'assets/brand/studio-icon.svg']:
        assert archive.read('assets/' + name) == (ROOT / 'godot' / name).read_bytes(), name

fresh = read(OUT / 'fresh-tournament-index.json')
current = read(ROOT / 'godot/assets/data/tournament-index.json')
assert fresh['games'] == current['games']
collector = (OUT / 'tournaments-test.log').read_text('utf-8-sig')
assert 'Ran 8 tests' in collector and collector.rstrip().endswith('OK')
validation = {
    'version': '0.24.0', 'functional_checks': counts, 'functional_total': sum(counts.values()), 'failures': [],
    'collector_tests': 8, 'interruption_scenarios': continuity,
    'timing': [{'scenario': row['scenario'], 'input_ms': row['input_ms'], 'max_gap_ms': row['max_gap'], 'within_50_ms_budget': row['within_frame_budget']} for row in timing],
    'missed_frame_budget_scenarios': missed, 'empty_window_controls': empty,
    'render_stall_resolved': False, 'android_device_tested': False, 'github_ci_executed_locally': False,
    'recent_games': len(fresh['games']), 'catalog_facts_unchanged': True, 'catalog_checked_utc': fresh['updated_utc'],
    'artifacts': release['artifacts'], 'compiled_android_scripts': compiled,
    'runtime_sources_match_release_receipt': True, 'windows_zip_matches_tested_executable': True,
}
(ROOT / 'docs/releases/v0.24.0-validation.json').write_text(json.dumps(validation, ensure_ascii=False, indent=2) + '\n', 'utf-8')
(OUT / 'artifact-checks.json').write_text(json.dumps(validation, ensure_ascii=False, indent=2) + '\n', 'utf-8')
rows = '\n'.join(f'| {proofs[name]} | {count} |' for name, count in counts.items())
report = f'''# 0.24 验证结果

功能断言共 **{sum(counts.values())} 项通过**；另有赛事采集器 8 个单元测试通过。次数包含同一场景内逐枚棋子的姿态和逐帧断言，不代表这么多个独立用例。**帧时间目标尚未全部通过**，不能据此声称没有 bug 或动画已在所有设备完全流畅。

| 验证范围 | 功能断言 |
|---|---:|
{rows}

36 次中途切换覆盖 2D／3D、两个方向、正反回放、吃子、升变、打入及再次选择同一步，每次比较 40 枚实体棋子。切换瞬间的位置跳变量为 0，缩放、朝向及升变棋面保持连续，最终回到合法目标局面并释放临时模型。修复前专门重现了 3D 角交换中两枚棋子的姿态跳变。

22 段真实绘制计时中有 **{len(missed)} 段超过 50 毫秒帧间隔目标**，最大间隔 **{max(row['max_gap'] for row in timing):.3f} 毫秒**。空窗口对照同样出现约 450 毫秒的绘制停顿。没有更换渲染后端、关闭无障碍支持或把该指标混入通过的功能检查。原因和复现方法见 [动画衔接说明](ANIMATION-CONTINUITY.md)。

实际 Windows 成品通过 {counts['package/windows-package-probe.json']} 项检查，首帧棋盘 {probe['first_board_frame_ms']} 毫秒；APK 为 release、versionCode 42、原包名与开发签名、ARM64／16 KB 对齐。发行文件散列、受测 Windows 程序以及打包的运行时源码一致。APK 不包含测试夹具或会员模块。

官方来源复查仍为 26 局，最新为 2026 年 9 月 8–9 日王位战第六局；本次没有发现新增可读取的完整棋谱。定时任务需要 GitHub 仓库默认分支发布并启用。本机未连接 Android 真机，未在本机执行 Linux／GitHub CI；这些均不计为通过。

复现：`./scripts/test_chessis24.ps1`。详细机器数据见 [v0.24.0-validation.json](releases/v0.24.0-validation.json)，本机完整日志在 `review/app/chessis24/`。既有棋盘亮度、宽度、免费功能与赛事库检查见 [0.20 验证](TESTING-0.20.md)。
'''
(ROOT / 'docs/TESTING-0.24.md').write_text(report, 'utf-8')
(OUT / 'REPORT.md').write_text(report, 'utf-8')
(ROOT / 'builds/SHA256SUMS-0.24.0.txt').write_text(''.join(f"{item['sha256']}  {Path(item['path']).name}\n" for item in release['artifacts']), 'utf-8')
print(json.dumps({'functional_checks': sum(counts.values()), 'collector_tests': 8, 'interruption_scenarios': len(continuity), 'frame_budget_misses': len(missed), 'max_frame_gap_ms': max(row['max_gap'] for row in timing)}, ensure_ascii=False))
