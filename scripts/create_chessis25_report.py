"""Verify 0.25 release evidence without treating timing misses as functional passes."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis25'

def read(path):
    return json.loads(path.read_text('utf-8-sig'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

release = read(OUT / 'release.json')
assert release['version'] == '0.25.0' and release['android_version_code'] == 43
proofs = {
    'variation-core.json': '嵌套变化、合法性、保存、转置局面与损坏数据',
    'ui/ui-tests.json': '变化界面、实际触摸、备份、保存失败及真实引擎报告',
    'animation/ui-tests.json': '回放衔接、棋子身份、模型释放及中间帧',
    'chessis16_test/results.json': '真实引擎报告、候选线路、回放与续下',
    'chessis13_test/results.json': '失误练习、动画、原局恢复与学习保存',
    'chessis11_test/ui-tests.json': '四尺寸棋盘、悔棋、教程、坏棋提醒与好棋线路',
    'package/windows-package-probe.json': 'Windows 成品启动、引擎和资源',
    'package/verification.json': 'APK 架构、签名、对齐和内容',
}
counts = {}
for name in proofs:
    result = read(OUT / name)
    assert not result['failures'], name
    counts[name] = len(result['checks']) if isinstance(result['checks'], list) else int(result['checks'])
for name in ['chessis25', 'chessis24', 'chessis16', 'chessis13', 'chessis11']:
    assert (OUT / f'{name}.exit').read_text('utf-8-sig').strip() == '0', name
    assert not (OUT / f'{name}.err').read_text('utf-8-sig').strip(), name
for name in ['build-android.log', 'build-windows.log', 'package/package-stderr.log']:
    assert not re.search(r'SCRIPT ERROR|ERROR:|FAILED', (OUT / name).read_text('utf-8-sig')), name
core_patterns = {
    'rules_test': r'"checks":(\d+)',
    'chessis_core_test': r'CHESSIS CORE: (\d+) checks',
    'report12_test': r'REPORT 12: (\d+) checks',
    'story19_test': r'STORY 19: (\d+) checks',
    'tournament_sync20_test': r'"checks":(\d+)',
}
for name, pattern in core_patterns.items():
    log = (OUT / f'{name}.log').read_text('utf-8-sig')
    assert not re.search(r'SCRIPT ERROR|ERROR:|FAIL:', log), name
    counts[name] = int(re.search(pattern, log)[1])
    proofs[name] = {'rules_test': '规则与存档', 'chessis_core_test': '棋谱格式与局面编辑', 'report12_test': '报告评价与阶段聚合', 'story19_test': '走势摘要与终局边界', 'tournament_sync20_test': '赛事目录、下载校验及恢复'}[name]
historic_log = (OUT / 'historic_games_test.log').read_text('utf-8-sig')
assert 'HISTORIC: 195 games, 23115 plies, failures: []' in historic_log
collector = (OUT / 'collector-tests.log').read_text('utf-8-sig')
assert 'Ran 8 tests' in collector and collector.rstrip().endswith('OK')
for item in release['runtime_sources'] + release['artifacts']:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']

continuity = read(OUT / 'animation/continuity.json')
assert len(continuity) == 36
assert all(row['piece_count'] == 40 and row['max_rect_jump_px'] < 0.001 and row['max_world_jump'] < 0.00001 for row in continuity)
timing = read(OUT / 'animation/timing.json')['measurements']
assert len(timing) == 22
missed = [row['scenario'] for row in timing if not row['within_frame_budget']]
windows = next(item for item in release['artifacts'] if item['path'].endswith('.zip'))
apk = next(item for item in release['artifacts'] if item['path'].endswith('.apk'))
probe = read(OUT / 'package/windows-package-probe.json')
with ZipFile(ROOT / windows['path']) as archive:
    assert hashlib.sha256(archive.read('Shogi.exe')).hexdigest() == probe['executable_sha256']
with ZipFile(ROOT / apk['path']) as archive:
    assert not any('membership' in name.lower() or name.startswith('assets/tests/') for name in archive.namelist())
    compiled = {name: hashlib.sha256(archive.read(f'assets/scripts/{name}.gdc')).hexdigest() for name in [
        'shogi_app', 'shogi_chessis_menu', 'shogi_game', 'shogi_variation_tree', 'shogi_variation_study', 'shogi_variation_view']}
    for name in ['config/tournaments.json', 'assets/data/tournament-index.json', 'assets/brand/studio-icon.svg']:
        assert archive.read('assets/' + name) == (ROOT / 'godot' / name).read_bytes(), name
fresh = read(OUT / 'fresh-tournament-index.json')
assert fresh['games'] == read(ROOT / 'godot/assets/data/tournament-index.json')['games']
validation = {
    'version': '0.25.0', 'functional_checks': counts, 'functional_total': sum(counts.values()), 'failures': [],
    'collector_tests': 8, 'historic_games_replayed': 195, 'historic_plies': 23115,
    'interruption_scenarios': continuity,
    'timing': [{'scenario': row['scenario'], 'max_gap_ms': row['max_gap'], 'within_50_ms_budget': row['within_frame_budget']} for row in timing],
    'missed_frame_budget_scenarios': missed, 'render_stall_resolved': False,
    'android_device_tested': False, 'github_ci_executed_locally': False,
    'recent_games': len(fresh['games']), 'catalog_checked_utc': fresh['updated_utc'],
    'artifacts': release['artifacts'], 'compiled_android_scripts': compiled,
    'runtime_sources_match_release_receipt': True, 'windows_zip_matches_tested_executable': True,
}
if (OUT / 'portable-ui/ui-tests.json').exists():
    portable = read(OUT / 'portable-ui/ui-tests.json')
    assert not portable['failures'] and not (OUT / 'portable.err').read_text('utf-8-sig').strip()
    validation['portable_test_mode_on_windows'] = {'checks': portable['checks'], 'failures': [], 'included_in_functional_total': False}
for destination in [OUT / 'artifact-checks.json', ROOT / 'docs/releases/v0.25.0-validation.json']:
    destination.write_text(json.dumps(validation, ensure_ascii=False, indent=2) + '\n', 'utf-8')
rows = '\n'.join(f'| {proofs[name]} | {count} |' for name, count in counts.items())
report = f'''# 0.25 验证结果

本轮功能断言 **{sum(counts.values())} 项通过**，另有赛事采集器 8 个单元测试，以及 195 局完整历史棋谱、23,115 手的合法回放。逐帧、逐枚棋子检查均计入断言数，不等同于独立场景数量；测试不能保证绝对没有 bug。

| 验证范围 | 功能断言 |
|---|---:|
{rows}

变化核心覆盖同一棋谱的嵌套分支、主线提升／替换、删除撤销、独立注释和绘图、转置路径、千日手、非法数据及文件大小限制。界面测试通过实际触摸和长按，检查横竖屏、两种外观、完整 JSON 导出、备份恢复、保存失败后重试、实际引擎分支报告、候选返回和从分支继续下棋。详细边界见 [变化分析](VARIATIONS.md)。

原有回放的 36 次中途切换保持 40 枚棋子的姿态连续。22 段计时中仍有 **{len(missed)} 段超过 50 毫秒目标**，最大 **{max(row['max_gap'] for row in timing):.3f} 毫秒**；本轮核心回归与界面测试有并行时段，不能把该计时当作独立性能基准。上一版空窗口也出现绘制停顿，原因仍未解决，见 [动画衔接说明](ANIMATION-CONTINUITY.md)。

Windows 成品通过 {counts['package/windows-package-probe.json']} 项检查，首次棋盘绘制 {probe['first_board_frame_ms']} 毫秒。APK 使用 release 模板、versionCode 43、原包名与开发签名，ARM64／16 KiB 对齐；没有会员模块或测试夹具。发布文件哈希、源文件清单与受测 Windows 程序已校验。

赛事来源本日复查仍为 26 局，最新为 2026 年 9 月 8–9 日王位战第六局。每日工作流需发布到 GitHub 默认分支后启用。本轮未连接 Android 真机；Linux／GitHub CI 未执行，不计为通过。

复现：`./scripts/test_chessis25.ps1 -CoreOnly`、`./scripts/test_chessis25.ps1`。机器数据见 [v0.25.0-validation.json](releases/v0.25.0-validation.json)，本机日志位于 `review/app/chessis25/`。
'''
for destination in [OUT / 'REPORT.md', ROOT / 'docs/TESTING-0.25.md']:
    destination.write_text(report, 'utf-8')
(ROOT / 'builds/SHA256SUMS-0.25.0.txt').write_text(''.join(f"{item['sha256']}  {Path(item['path']).name}\n" for item in release['artifacts']), 'utf-8')
for filename in ['minimal-variations-393.png', 'wood-branch-393.png']:
    shutil.copy2(OUT / 'ui' / filename, ROOT / 'docs/images' / ('variation25-' + filename))
print(json.dumps({'functional_checks': sum(counts.values()), 'collector_tests': 8, 'historical_games': 195, 'frame_budget_misses': len(missed)}, ensure_ascii=False))
