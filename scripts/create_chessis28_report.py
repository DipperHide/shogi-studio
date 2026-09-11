"""Verify 0.28 motion changes, keeping rendering delays and prior checks separate."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis28'


def read(path):
    return json.loads(path.read_text('utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


release = read(OUT / 'release.json')
assert release['version'] == '0.28.0' and release['android_version_code'] == 46
proofs = {
    'motion-clock-core.json': '起始绘制门控、暂停、时钟与停顿增量限制',
    'ui/ui-tests.json': '真实绘制帧、停顿注入、不同速度和教程',
    'editor/ui-tests.json': '编辑器触摸、拖动、保存和独立引擎',
    'evaluation/ui-tests.json': '评价条、实际引擎报告、动画与续下',
    'variations/ui-tests.json': '嵌套变化、触摸、保存、备份与报告',
    'animation/ui-tests.json': '中断回放、棋子身份、模型释放及中间帧',
    'chessis16_test/results.json': '报告、候选线路、回放与续下',
    'chessis13_test/results.json': '失误练习、动画、原局恢复与学习保存',
    'chessis11_test/ui-tests.json': '四尺寸棋盘、悔棋、教程与对弈辅助',
    'package/windows-package-probe.json': 'Windows 成品启动、引擎与资源',
    'package/verification.json': 'APK 架构、签名、对齐和内容',
}
counts = {}
for name in proofs:
    result = read(OUT / name)
    assert not result['failures'], name
    counts[name] = len(result['checks']) if isinstance(result['checks'], list) else int(result['checks'])
for name in ['chessis28', 'chessis27', 'chessis26', 'chessis25', 'chessis24', 'chessis16', 'chessis13', 'chessis11']:
    assert (OUT / f'{name}.exit').read_text('utf-8-sig').strip() == '0', name
    assert not (OUT / f'{name}.err').read_text('utf-8-sig').strip(), name
for name in ['build-android.log', 'build-windows.log', 'package/package-stderr.log', 'motion_clock28_test.log']:
    assert not re.search(r'SCRIPT ERROR|ERROR:|FAILED', (OUT / name).read_text('utf-8-sig')), name
for item in release['runtime_sources'] + release['artifacts']:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']

before = read(OUT / 'baseline/motion-frames.json')
after = read(OUT / 'ui/motion-frames.json')
# The initial baseline captured this timestamp before its pre-draw await.
# Preserve its value under an accurate label; frame timestamps are unchanged.
for case in before:
    case['pre_draw_wait_and_call_ms'] = case.pop('call_ms')
assert len(before) == 22 and len(after) == 25
assert all(case['frames'][0]['progress'] == 0 and case['frames'][-1]['progress'] == 1 and case['intermediate_frames'] >= 8 and case['max_progress_step'] <= .30 for case in after)
assert sum(case['injected_stall_ms'] == 400 for case in before) == 18
assert sum(case['injected_stall_ms'] == 400 for case in after) == 19
paired = []
for old in before:
    new = next(case for case in after if case['scenario'] == old['scenario'])
    paired.append({'scenario': old['scenario'], 'injected_stall_ms': old['injected_stall_ms'],
                   'before_max_progress_step': old['max_progress_step'], 'after_max_progress_step': new['max_progress_step'],
                   'before_intermediate_frames': old['intermediate_frames'], 'after_intermediate_frames': new['intermediate_frames']})
continuity = read(OUT / 'animation/continuity.json')
assert len(continuity) == 36
assert all(row['piece_count'] == 40 and row['max_rect_jump_px'] < .001 and row['max_world_jump'] < .00001 for row in continuity)
timing = read(OUT / 'animation/timing.json')['measurements']
assert len(timing) == 22
missed = [row['scenario'] for row in timing if not row['within_frame_budget']]

prior_path = ROOT / 'docs/releases/v0.27.0-validation.json'
prior = read(prior_path)
prior_release = read(ROOT / 'review/app/chessis27/release.json')
unchanged = [item for item in prior_release['runtime_sources'] if item['path'].startswith('godot/scripts/') and item['path'] not in ['godot/scripts/shogi_app.gd', 'godot/scripts/shogi_tutorial_board.gd']]
unchanged += [item for item in prior_release['runtime_sources'] if item['path'].startswith('godot/assets/data/') or item['path'].startswith('godot/config/')]
for item in unchanged:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']
subprocess.run(['git', 'diff', '--exit-code', '17e07a6', '--', 'scripts/update_tournaments.py', 'scripts/test_tournaments.py'], cwd=ROOT, check=True)
prior_names = ['editor-core.json', 'evaluation-core.json', 'variation-core.json', 'rules_test', 'chessis_core_test', 'report12_test', 'story19_test', 'tournament_sync20_test']
prior_count = sum(prior['functional_checks'][name] for name in prior_names)
assert prior_count == 1000
retained = {'version': '0.27.0', 'source_commit': '17e07a6', 'validation_path': str(prior_path.relative_to(ROOT)), 'validation_sha256': sha(prior_path),
            'rerun_this_release': False, 'prior_core_checks': prior_count, 'historic_games_replayed': 195, 'historic_plies': 23115,
            'collector_tests': 8, 'unchanged_sources': unchanged}

probe = read(OUT / 'package/windows-package-probe.json')
for frames in probe['motion_frames'].values():
    assert frames[0]['progress'] == 0 and frames[-1]['progress'] == 1
    assert sum(0 < frame['progress'] < 1 for frame in frames) >= 8
    assert all(0 <= b['progress'] - a['progress'] <= .30 for a, b in zip(frames, frames[1:]))
windows = next(item for item in release['artifacts'] if item['path'].endswith('.zip'))
apk = next(item for item in release['artifacts'] if item['path'].endswith('.apk'))
with ZipFile(ROOT / windows['path']) as archive:
    assert hashlib.sha256(archive.read('Shogi.exe')).hexdigest() == probe['executable_sha256']
with ZipFile(ROOT / apk['path']) as archive:
    assert not any('membership' in name.lower() or name.startswith('assets/tests/') for name in archive.namelist())
    compiled = {name: hashlib.sha256(archive.read(f'assets/scripts/{name}.gdc')).hexdigest() for name in [
        'shogi_app', 'shogi_motion_clock', 'shogi_rendered_tween', 'shogi_tutorial_board', 'shogi_package_probe']}
    for name in ['config/tournaments.json', 'assets/data/tournament-index.json', 'assets/brand/studio-icon.svg']:
        assert archive.read('assets/' + name) == (ROOT / 'godot' / name).read_bytes(), name
initial = [read(OUT / f'chessis11-{attempt}-attempt/ui-tests.json')['failures'] for attempt in ['first', 'second']]
validation = {'version': '0.28.0', 'functional_checks': counts, 'functional_total': sum(counts.values()), 'failures': [],
              'baseline_animation_source_commit': '17e07a6', 'baseline_executed_before_clock_change': True,
              'prior_unchanged_core_evidence': retained, 'motion_comparison': paired, 'motion_before': before, 'motion_after': after,
              'interruption_scenarios': continuity, 'natural_render_timing': timing, 'missed_frame_budget_scenarios': missed,
              'initial_ui11_fixed_wait_failures': initial, 'render_stall_resolved': False,
              'animation_may_take_longer_under_stalls': True, 'android_device_tested': False, 'github_ci_executed': False,
              'packaged_motion_frames': probe['motion_frames'], 'artifacts': release['artifacts'], 'compiled_android_scripts': compiled,
              'runtime_sources_match_release_receipt': True, 'windows_zip_matches_tested_executable': True}
for path in [OUT / 'artifact-checks.json', ROOT / 'docs/releases/v0.28.0-validation.json']:
    path.write_text(json.dumps(validation, ensure_ascii=False, indent=2) + '\n', 'utf-8')
rows = '\n'.join(f'| {proofs[name]} | {count} |' for name, count in counts.items())
report = f'''# 0.28 验证结果

本轮重新执行的功能断言 **{sum(counts.values())} 项通过**。逐帧和逐枚棋子检查计入断言数，不等同于独立场景数量；不是零 bug 保证。

| 本轮验证 | 断言 |
|---|---:|
{rows}

25 项实际绘制场景覆盖二维／三维、普通移动、反向回放、吃子、升变、打入、快速／慢速和教程，其中 19 项确实注入 400 毫秒停顿。每项首个绘制帧的动画进度为 0，至少出现 {min(case['intermediate_frames'] for case in after)} 个中间帧，最终完成；单帧进度最大增量从基线的 {max(case['max_progress_step'] for case in before):.2%} 降为 {max(case['max_progress_step'] for case in after):.2%}。另测关动画、暂停恢复、连续 24 次切换后的控制器释放和页面关闭清理。参见 [动画计时](ANIMATION-CLOCK.md)。

![实际绘制比较](images/motion28-progress.png)

原有 36 次中断回放继续保留 40 枚棋子的姿态。自然运行的 22 段计时仍有 **{len(missed)} 段超过 50 毫秒帧间隔目标**，最大 **{max(row['max_gap'] for row in timing):.3f} 毫秒**。时间戳和自然停顿全部保留；通过限制单帧推进避免吞掉移动过程，但这会延长低帧率下的实际播放时间，不能宣称渲染停顿消失。

两轮旧界面检查分别遇到「固定等待后还未完成」与「固定时点未取到中间帧」。记录保存在 `initial_ui11_fixed_wait_failures`。界面测试改为读取实际绘制帧、等待真实完成，同时独立保留帧耗时判定；没有通过强制结束动画或跳过场景来通过检查。

Windows 成品通过 {counts['package/windows-package-probe.json']} 项检查，首次棋盘绘制 {probe['first_board_frame_ms']} 毫秒。成品中三种回放／练习路径均验证首帧、至少八个中间进度、最大进度增量和最终完成。APK 通过 {counts['package/verification.json']} 项签名、架构、16 KiB 对齐、版本与内容检查，versionCode 46，沿用原开发签名；没有会员模块或测试夹具。源码清单、APK 模块哈希与受测 Windows 程序一致。

规则、棋谱解析、报告数学、变化树和赛事代码没有修改。与 0.27 发行清单逐文件比较，确认原有 78 份相关脚本及目录数据哈希一致；该版的 1,000 项核心断言、8 个采集器测试和 195 局／23,115 手历史回放保留为历史证据，**没有重复执行，也没有计入本轮通过数**。近期赛事目录仍沿用本日已核验的 26 局；GitHub 每日工作流须在发布后启用。

未连接 Android 真机，Linux／GitHub CI 未执行，不计为通过。完整原版 UI、扫描模块、在线后台等仍有差距，见 [实现对照](CHESSIS-PARITY.md)。本机结果位于 `review/app/chessis28/`；可执行 `./scripts/test_chessis28.ps1` 复现界面回归，`-CoreOnly` 可重跑全部核心测试。机器数据见 [v0.28.0-validation.json](releases/v0.28.0-validation.json)。
'''
for path in [OUT / 'REPORT.md', ROOT / 'docs/TESTING-0.28.md']:
    path.write_text(report, 'utf-8')
(ROOT / 'builds/SHA256SUMS-0.28.0.txt').write_text(''.join(f"{item['sha256']}  {Path(item['path']).name}\n" for item in release['artifacts']), 'utf-8')
for phase in ['start', 'middle', 'end']:
    shutil.copy2(OUT / 'ui' / f'wood-clock-{phase}.png', ROOT / 'docs/images' / f'motion28-{phase}.png')
print(json.dumps({'functional_checks': sum(counts.values()), 'retained_prior_core_checks': prior_count, 'natural_frame_budget_misses': len(missed),
                  'max_progress_step_before': max(c['max_progress_step'] for c in before), 'max_progress_step_after': max(c['max_progress_step'] for c in after)}, ensure_ascii=False))
