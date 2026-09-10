"""Check release evidence and write the 0.27 report, including timing failures."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis27'


def read(path):
    return json.loads(path.read_text('utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


release = read(OUT / 'release.json')
assert release['version'] == '0.27.0' and release['android_version_code'] == 45
proofs = {
    'editor-core.json': '编辑历史、设置持久化、请求隔离和故障重试',
    'ui/ui-tests.json': '编辑器真实触摸、拖动、键盘、保存及独立引擎',
    'variation-core.json': '嵌套变化、合法性、保存、转置与损坏数据',
    'evaluation-core.json': '评价条刻度、先后手、詰与设置持久化',
    'evaluation/ui-tests.json': '评价条布局、真实引擎、键盘、过渡和续下',
    'variations/ui-tests.json': '变化界面、实际触摸、备份、保存失败与报告',
    'animation/ui-tests.json': '回放衔接、棋子身份、模型释放与中间帧',
    'chessis16_test/results.json': '真实引擎报告、候选线路、回放与续下',
    'chessis13_test/results.json': '失误练习、动画、原局恢复与学习保存',
    'chessis11_test/ui-tests.json': '四尺寸棋盘、悔棋、教程与对弈辅助',
    'package/windows-package-probe.json': 'Windows 成品启动、引擎和资源',
    'package/verification.json': 'APK 架构、签名、对齐和内容',
}
counts = {}
for name in proofs:
    result = read(OUT / name)
    assert not result['failures'], name
    counts[name] = len(result['checks']) if isinstance(result['checks'], list) else int(result['checks'])
for name in ['chessis27', 'chessis26', 'chessis25', 'chessis24', 'chessis16', 'chessis13', 'chessis11']:
    assert (OUT / f'{name}.exit').read_text('utf-8-sig').strip() == '0', name
    assert not (OUT / f'{name}.err').read_text('utf-8-sig').strip(), name
for name in ['build-android.log', 'build-windows.log', 'package/package-stderr.log']:
    assert not re.search(r'SCRIPT ERROR|ERROR:|FAILED', (OUT / name).read_text('utf-8-sig')), name
patterns = {
    'rules_test': (r'"checks":(\d+)', '规则与存档'),
    'chessis_core_test': (r'CHESSIS CORE: (\d+) checks', '棋谱格式与局面校验'),
    'report12_test': (r'REPORT 12: (\d+) checks', '报告评价与阶段聚合'),
    'story19_test': (r'STORY 19: (\d+) checks', '走势摘要与终局边界'),
    'tournament_sync20_test': (r'"checks":(\d+)', '赛事目录、下载校验及恢复'),
}
for name, (pattern, label) in patterns.items():
    log = (OUT / f'{name}.log').read_text('utf-8-sig')
    assert not re.search(r'SCRIPT ERROR|ERROR:|FAIL:', log), name
    counts[name] = int(re.search(pattern, log)[1])
    proofs[name] = label
assert 'HISTORIC: 195 games, 23115 plies, failures: []' in (OUT / 'historic_games_test.log').read_text('utf-8-sig')
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
assert set(probe['motion_frames']) == {'replay', 'practice-answer', 'cached-report'}
for frames in probe['motion_frames'].values():
    assert any(0 < frame['progress'] < 1 for frame in frames)
    assert frames[-1]['progress'] == 1
    assert all(a['elapsed_ms'] <= b['elapsed_ms'] and a['progress'] <= b['progress'] for a, b in zip(frames, frames[1:]))
with ZipFile(ROOT / windows['path']) as archive:
    assert hashlib.sha256(archive.read('Shogi.exe')).hexdigest() == probe['executable_sha256']
with ZipFile(ROOT / apk['path']) as archive:
    assert not any('membership' in name.lower() or name.startswith('assets/tests/') for name in archive.namelist())
    compiled = {name: hashlib.sha256(archive.read(f'assets/scripts/{name}.gdc')).hexdigest() for name in [
        'shogi_app', 'shogi_chessis_menu', 'shogi_position_editor', 'shogi_editor_history', 'shogi_editor_analysis',
        'shogi_editor_layout', 'shogi_editor_input', 'shogi_editor_cell', 'shogi_editor_eval_bar', 'shogi_package_probe']}
    for name in ['config/tournaments.json', 'assets/data/tournament-index.json', 'assets/brand/studio-icon.svg']:
        assert archive.read('assets/' + name) == (ROOT / 'godot' / name).read_bytes(), name
fresh = read(OUT / 'fresh-tournament-index.json')
assert fresh['games'] == read(ROOT / 'godot/assets/data/tournament-index.json')['games']
validation = {
    'version': '0.27.0', 'functional_checks': counts, 'functional_total': sum(counts.values()), 'failures': [],
    'collector_tests': 8, 'historic_games_replayed': 195, 'historic_plies': 23115,
    'interruption_scenarios': continuity,
    'timing': [{'scenario': row['scenario'], 'max_gap_ms': row['max_gap'], 'within_50_ms_budget': row['within_frame_budget']} for row in timing],
    'missed_frame_budget_scenarios': missed, 'render_stall_resolved': False,
    'android_device_tested': False, 'github_ci_executed_locally': False,
    'recent_games': len(fresh['games']), 'catalog_checked_utc': fresh['updated_utc'],
    'artifacts': release['artifacts'], 'compiled_android_scripts': compiled,
    'reference_evidence': read(OUT / 'reference-evidence.json'),
    'runtime_sources_match_release_receipt': True, 'windows_zip_matches_tested_executable': True,
    'packaged_motion_frames': probe['motion_frames'],
}
retry_note = ''
first_path = OUT / 'package-first-attempt/windows-package-probe.json'
if first_path.exists():
    first = read(first_path)
    second = read(OUT / 'package-second-attempt/windows-package-probe.json')
    assert first['executable_sha256'] == second['executable_sha256']
    validation['initial_package_probe_failures'] = first['failures']
    validation['initial_package_probe_sha256'] = first['executable_sha256']
    validation['second_package_probe_failures'] = second['failures']
    validation['package_probe_change'] = 'Rebuilt after replacing single 50/60 ms timer snapshots with actual rendered-frame observations. Animation implementation and speed were not changed.'
    retry_note = '\n初始成品连续两次未通过「缓存报告回放显示中间帧」检查，失败和原文件哈希保留在验证 JSON 中。旧诊断在固定等待 50 毫秒后取样；改为记录每个实际绘制帧并检查出现中间进度且最终完成后，重新构建成品验证。该修改仅在命令行诊断中生效，没有手动推进动画或修改动画速度。最终逐帧记录公开在 `packaged_motion_frames`；回放仍可能只出现少量中间帧，后续通过不代表绘制停顿已解决。\n'
for path in [OUT / 'artifact-checks.json', ROOT / 'docs/releases/v0.27.0-validation.json']:
    path.write_text(json.dumps(validation, ensure_ascii=False, indent=2) + '\n', 'utf-8')
rows = '\n'.join(f'| {proofs[name]} | {count} |' for name, count in counts.items())
report = f'''# 0.27 验证结果

本轮功能断言 **{sum(counts.values())} 项通过**，另有赛事采集器 8 个单元测试，以及 195 局完整历史棋谱、23,115 手的合法回放。逐帧、逐枚棋子检查计入断言数，不等同于独立场景数量；测试不能保证绝对没有 bug。

| 验证范围 | 功能断言 |
|---|---:|
{rows}

编辑器新增 {counts['editor-core.json']} 项核心断言及 {counts['ui/ui-tests.json']} 项界面断言，覆盖四尺寸、明暗主题、固定底部按钮、方形格子、实际屏幕边界、触摸摆子和拖动、升变笔、取消拖动、持驹键盘输入、独立撤销／重做、保存导航、剪贴板、无效 SFEN、保存失败、备份、回放上下文和终局。实际本地引擎检查包含评分、暂停释放进程、恢复、故障注入、延迟重试和关闭释放。完整说明见 [局面编辑](POSITION-EDITOR.md)。

开发过程的交互测试发现持驹输入框撑宽了整个页面，将撤销按钮推到屏幕外。修复最小字符宽度与焦点样式内边距后，重新以实际视口边界检查，真实点击撤销、计数文本恢复和复制结果均通过。另修复浅色主题下选中按钮文字、横屏棋盘截断和升变笔拖动丢失升变状态。

评价条、嵌套变化、报告、失误练习、教程、主界面悔棋、推荐线路与直接续下完成本轮回归。36 次回放中断切换保持 40 枚棋子姿态连续。22 段计时仍有 **{len(missed)} 段超过 50 毫秒目标**，最大 **{max(row['max_gap'] for row in timing):.3f} 毫秒**。动画探针在构建和核心回归前执行；此前空窗口也出现停顿，原因未解决，不能据此推断 Android 表现。见 [动画衔接说明](ANIMATION-CONTINUITY.md)。

Windows 成品通过 {counts['package/windows-package-probe.json']} 项检查，首次棋盘绘制 {probe['first_board_frame_ms']} 毫秒。APK 使用 release 模板、versionCode 45、原包名与开发签名，ARM64／16 KiB 对齐；没有会员模块或测试夹具。发布文件哈希、运行源码清单、打包的编辑器模块和受测 Windows 程序已校验。
{retry_note}
赛事采集器本轮复查仍为 26 局，最新为 2026 年 9 月 8–9 日王位战第六局。每日工作流需发布到 GitHub 默认分支后启用。未连接 Android 真机；Linux／GitHub CI 未执行，不计为通过。原 APK 仅作静态资源与控制代码检查，未进行可运行版本的逐屏像素比对。

复现：`./scripts/test_chessis27.ps1 -CoreOnly`、`./scripts/test_chessis27.ps1`。机器数据见 [v0.27.0-validation.json](releases/v0.27.0-validation.json)，本机日志位于 `review/app/chessis27/`。
'''
for path in [OUT / 'REPORT.md', ROOT / 'docs/TESTING-0.27.md']:
    path.write_text(report, 'utf-8')
(ROOT / 'builds/SHA256SUMS-0.27.0.txt').write_text(''.join(f"{item['sha256']}  {Path(item['path']).name}\n" for item in release['artifacts']), 'utf-8')
for filename in ['editor-dark-393.png', 'editor-light-360.png', 'editor-hand-undo.png']:
    shutil.copy2(OUT / 'ui' / filename, ROOT / 'docs/images' / filename.replace('editor-', 'editor27-'))
print(json.dumps({'functional_checks': sum(counts.values()), 'collector_tests': 8, 'historical_games': 195, 'frame_budget_misses': len(missed)}, ensure_ascii=False))
