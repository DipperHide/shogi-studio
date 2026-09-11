"""Verify the release and record bounded opening UI coverage, without zero-bug claims."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis29'


def read(path):
    return json.loads(path.read_text('utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


release = read(OUT / 'release.json')
assert release['version'] == '0.29.0' and release['android_version_code'] == 47
names = ['openings-core.json', 'ui/ui-tests.json', 'chessis25/ui-tests.json', 'chessis11/ui-tests.json',
         'package/windows-package-probe.json', 'package/verification.json']
counts = {}
for name in names:
    data = read(OUT / name)
    assert not data['failures'], name
    counts[name] = len(data['checks']) if isinstance(data['checks'], list) else int(data['checks'])
core = (OUT / 'interchange-core.log').read_text('utf-8-sig')
assert 'failures: []' in core and 'SCRIPT ERROR' not in core
counts['interchange-core'] = int(re.search(r'CHESSIS CORE: (\d+) checks', core).group(1))
for name in ['chessis29', 'chessis25', 'chessis11']:
    assert (OUT / f'{name}.exit').read_text('utf-8-sig').strip() == '0'
    assert not (OUT / f'{name}.err').read_text('utf-8-sig').strip()
for name in ['build-android.log', 'build-windows.log', 'package/package-stderr.log', 'openings-core.log']:
    assert not re.search(r'SCRIPT ERROR|ERROR:|FAILED', (OUT / name).read_text('utf-8-sig')), name
for item in release['runtime_sources'] + release['artifacts']:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']
(ROOT / 'builds/SHA256SUMS-0.29.0.txt').write_text(
    ''.join(item['sha256'] + '  ' + Path(item['path']).name + '\n' for item in release['artifacts']), encoding='utf-8')

motion = read(OUT / 'ui/motion-frames.json')
assert len(motion) == 6
for row in motion:
    assert row['values'][0] == 0 and row['values'][-1] == 1
    assert any(0 < value < 1 for value in row['values'])
probe = read(OUT / 'package/windows-package-probe.json')
assert 'opening-preview' in probe['motion_frames']
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
    modules = ['shogi_opening_view', 'shogi_opening_preview', 'shogi_opening_board', 'shogi_openings', 'shogi_rendered_tween']
    compiled = {name: hashlib.sha256(archive.read(f'assets/scripts/{name}.gdc')).hexdigest() for name in modules}
    for name in ['config/tournaments.json', 'assets/data/tournament-index.json', 'assets/brand/studio-icon.svg']:
        assert archive.read('assets/' + name) == (ROOT / 'godot' / name).read_bytes()
fresh = read(OUT / 'fresh-tournament-index.json')
assert fresh['games'] == read(ROOT / 'godot/assets/data/tournament-index.json')['games']
prior = read(ROOT / 'review/app/chessis28/release.json')
changed = {'shogi_app.gd', 'shogi_chessis_menu.gd', 'shogi_openings.gd', 'shogi_package_probe.gd'}
unchanged = [item for item in prior['runtime_sources'] if item['path'].startswith('godot/scripts/') and Path(item['path']).name not in changed]
unchanged += [item for item in prior['runtime_sources'] if item['path'].startswith(('godot/assets/data/', 'godot/config/'))]
for item in unchanged:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']
reference_paths = ['res/layout/dialog_opening_list.xml', 'res/layout/dialog_opening_list_item.xml', 'res/layout/dialog_opening_info.xml',
                   'java/sources/p167W2/C1501b.java', 'java/sources/p159V2/C1447i.java',
                   'java/sources/p159V2/ViewOnLongClickListenerC1441c.java', 'java/sources/p159V2/ViewOnClickListenerC1439a.java']
references = [{'path': name, 'sha256': sha(ROOT / '.work/chessis-reference' / name)} for name in reference_paths]
attempts = [{'directory': name, 'failures': read(OUT / name / 'ui/ui-tests.json')['failures']} for name in ['first-attempt', 'second-attempt']]
validation = {'version': '0.29.0', 'functional_checks': counts, 'functional_total': sum(counts.values()), 'failures': [],
              'ui_motion': motion, 'package_motion': probe['motion_frames'], 'reference_evidence': references,
              'source_apk_sha256': '14df01b58e777a130aee977c51a9b7823c8c8ada31479843b2f01b765b49f111',
              'initial_attempts': attempts, 'initial_test_fixture_errors': ['missing inherited practice object', 'programmatic LineEdit insertion emitted no user text-change signal', 'initial logical viewport differed from native event coordinates'],
              'initial_package_attempt': {key: read(OUT / 'package-first-attempt/evidence/windows-package-probe.json')[key] for key in ['checks', 'failures', 'executable_sha256', 'viewport']},
              'prior_evidence': {'release': '0.28.0', 'source_commit': '94e088d', 'rerun': False, 'unchanged_sources': unchanged,
                                 'report': 'docs/releases/v0.28.0-validation.json', 'report_sha256': sha(ROOT / 'docs/releases/v0.28.0-validation.json')},
              'tournaments': {'checked_utc': fresh['updated_utc'], 'games': len(fresh['games']), 'same_games_as_bundled': True},
              'android_device_tested': False, 'github_published': False, 'rendering_stalls_resolved': False,
              'artifacts': release['artifacts'], 'packaged_opening_modules': compiled, 'first_board_frame_ms': probe['first_board_frame_ms']}
encoded = json.dumps(validation, ensure_ascii=False, indent=2) + '\n'
(OUT / 'artifact-checks.json').write_text(encoded, encoding='utf-8')
(ROOT / 'docs/releases/v0.29.0-validation.json').write_text(encoded, encoding='utf-8')
for source, target in [('opening-preview-dark-393.png', 'opening29-portrait.png'), ('opening-preview-light-852.png', 'opening29-landscape.png'), ('opening-list-dark-360.png', 'opening29-list.png')]:
    shutil.copy2(OUT / 'ui' / source, ROOT / 'docs/images' / target)
rows = '\n'.join(f'| `{name}` | {count} |' for name, count in counts.items())
text = f'''# 0.29 开局预览验证

本轮新执行 **{sum(counts.values())} 项检查**，记录中无失败。另有六组实际绘制帧记录。范围是九条既有开局、独立预览及相关菜单回归；不表示完整复刻或保证没有 bug。

| 验证项 | 检查数 |
|---|---:|
{rows}

界面测试使用真正的触摸事件，覆盖 360×760、393×852、852×393、1100×800、明暗模式，测试输入筛选、列表位置恢复、原棋谱与注释保留、翻转、播放暂停、长按首尾、快速定位、关闭时释放计时器、显式载入和继续对弈入口。竖屏载入按钮固定；横屏完整显示棋盘。六组动画包含正反向、吃子、升变、打入，取样来自实际绘制完成事件。

首次尝试的四项失败和测试脚本异常、第二次尝试的两项失败均保留在本地 `review/app/chessis29/first-attempt`、`second-attempt`。测试夹具补齐了继承字段，改用真实键盘输入；启动时明确原生窗口与逻辑视口一致，避免把逻辑坐标当作窗口输入坐标。另修复横屏预览需滚动才能看全棋盘的问题，随后每个尺寸均实际点击翻转按钮验证。没有删除断言或强制结束动画。

首次 Windows 成品探针在载入函数返回的同一时刻检查“从这里下”，早于菜单下一帧更新可见性，产生一项失败。保留 `package-first-attempt` 原始结果与 EXE 哈希；探针改为观察实际绘制后的按钮，再重新构建 Android 和 Windows。应用交互不因该测试修改。

Windows 成品通过 {counts['package/windows-package-probe.json']} 项检查，第一帧棋盘为 {probe['first_board_frame_ms']} 毫秒；启动、实际引擎、教程、报告、回放与开局预览均来自打包后的 EXE。APK 检查 ARM64、签名、16 KiB 对齐及资源；确认开局模块随包、会员和测试数据未入包。两种文件的 SHA-256 与发行清单一致。

此前的完整规则、195 局历史棋谱逐手回放、评价和动画压力测试**没有在本轮全量重跑**，不计入上述数量；保留 0.28 的证据并核对相关未改动脚本与数据哈希。所有历史库数据和比赛更新代码保持不变；{fresh['updated_utc']} 再次读取官方目录，仍是 26 局，条目与内置目录一致。

仍未连接 Android 设备，未进行真机、蓝牙双机和后台恢复验收；Windows 已知绘制停顿仍存在，本轮没有重新做性能基准。GitHub 凭据失效，仓库、Release、远程 CI 和每日更新工作流均未发布／启用。

运行：`./scripts/test_chessis29.ps1`；核心：`./scripts/test_chessis29.ps1 -CoreOnly`。成品：`./scripts/test_package.ps1 -ReportDirectory review/app/chessis29/package -Executable builds/windows-0.29.0/Shogi.exe`。

详见 [开局预览](OPENING-PREVIEW.md)、[机器可读记录](releases/v0.29.0-validation.json) 与 [实现差距](CHESSIS-PARITY.md)。
'''
(ROOT / 'docs/TESTING-0.29.md').write_text(text, encoding='utf-8')
(OUT / 'REPORT.md').write_text(text, encoding='utf-8')
print(json.dumps({'checks': sum(counts.values()), 'failures': [], 'first_board_frame_ms': probe['first_board_frame_ms']}, ensure_ascii=False))
