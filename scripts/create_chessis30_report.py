"""Validate release provenance and record bounded analysis-import coverage."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis30'


def read(path):
    return json.loads(path.read_text('utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


release = read(OUT / 'release.json')
assert release['version'] == '0.30.0' and release['android_version_code'] == 48
counts = {}
for name in ['import-core.json', 'java-decoder.json', 'ui/ui-tests.json', 'chessis25/ui-tests.json',
             'chessis11/ui-tests.json', 'chessis29/ui-tests.json', 'package/windows-package-probe.json',
             'package/verification.json']:
    data = read(OUT / name)
    assert not data['failures'], name
    counts[name] = len(data['checks']) if isinstance(data['checks'], list) else int(data['checks'])
core = (OUT / 'interchange-core.log').read_text('utf-8-sig')
assert 'failures: []' in core and 'SCRIPT ERROR' not in core
counts['interchange-core'] = int(re.search(r'CHESSIS CORE: (\d+) checks', core).group(1))
for name in ['chessis30', 'chessis25', 'chessis11', 'chessis29']:
    assert (OUT / f'{name}.exit').read_text('utf-8-sig').strip() == '0'
    assert not (OUT / f'{name}.err').read_text('utf-8-sig').strip()
for name in ['build-android.log', 'build-windows.log', 'package/package-stderr.log', 'import-core.log']:
    assert not re.search(r'SCRIPT ERROR|ERROR:|FAILED', (OUT / name).read_text('utf-8-sig')), name
for item in release['runtime_sources'] + release['artifacts']:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']
(ROOT / 'builds/SHA256SUMS-0.30.0.txt').write_text(
    ''.join(item['sha256'] + '  ' + Path(item['path']).name + '\n' for item in release['artifacts']), encoding='utf-8')

motion = read(OUT / 'ui/motion-frames.json')
assert motion[0] == 0 and motion[-1] == 1 and sum(0 < value < 1 for value in motion) >= 8
assert all(0 <= b-a <= .30 for a, b in zip(motion, motion[1:]))
probe = read(OUT / 'package/windows-package-probe.json')
assert 'imported-record' in probe['motion_frames']
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
    modules = ['shogi_analysis_import', 'shogi_import_draft', 'shogi_import_job', 'shogi_chessis_menu', 'shogi_rendered_tween']
    compiled = {name: hashlib.sha256(archive.read(f'assets/scripts/{name}.gdc')).hexdigest() for name in modules}
    for name in ['config/tournaments.json', 'assets/data/tournament-index.json', 'assets/brand/studio-icon.svg']:
        assert archive.read('assets/' + name) == (ROOT / 'godot' / name).read_bytes()
    dex = b''.join(archive.read(name) for name in archive.namelist() if name.endswith('.dex'))
    assert all(name in dex for name in [b'pickAnalysisRecord', b'analysis_record_imported', b'AnalysisRecordText', b'windows-31j'])
fresh = read(OUT / 'fresh-tournament-index.json')
assert fresh['games'] == read(ROOT / 'godot/assets/data/tournament-index.json')['games']
prior = read(ROOT / 'review/app/chessis29/release.json')
changed = {'shogi_app.gd', 'shogi_chessis_menu.gd', 'shogi_preferences.gd', 'shogi_package_probe.gd'}
unchanged = [item for item in prior['runtime_sources'] if item['path'].startswith('godot/scripts/') and Path(item['path']).name not in changed]
unchanged += [item for item in prior['runtime_sources'] if item['path'].startswith(('godot/assets/data/', 'godot/config/'))]
for item in unchanged:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']
reference_paths = ['res/layout/dialog_analyze_game.xml', 'res/layout/tab_content_pgn.xml',
                   'java/sources/p174X2/C1565c.java', 'java/sources/p174X2/C1567e.java',
                   'java/sources/p174X2/C1569g.java', 'java/sources/p174X2/ViewOnClickListenerC1568f.java',
                   'java/sources/p252h2/C3459e.java', 'java/sources/p373y3/RunnableC4917d.java']
references = [{'path': name, 'sha256': sha(ROOT / '.work/chessis-reference' / name)} for name in reference_paths]
attempts = [{'directory': name, **read(OUT / name / 'evidence/ui-tests.json')}
            for name in ['ui-first-attempt', 'ui-second-attempt']]
validation = {'version': '0.30.0', 'functional_checks': counts, 'functional_total': sum(counts.values()), 'failures': [],
              'ui_motion': motion, 'package_motion': probe['motion_frames'], 'reference_evidence': references,
              'source_apk_sha256': '14df01b58e777a130aee977c51a9b7823c8c8ada31479843b2f01b765b49f111',
              'initial_ui_attempts': attempts, 'initial_core_attempt': read(OUT / 'import-core-first-attempt.json'),
              'fixed_issues': ['empty query excluded every saved game', 'input card and read-only ink did not follow light theme',
                               'Back hid file dialog without clearing pending request', 'prior variation remained active when loading a tournament record'],
              'fixture_corrections': ['length fixture originally shorter than 16000', 'legacy KIF parser retains trailing newline in comments'],
              'prior_evidence': {'release': '0.29.0', 'source_commit': 'b3549ed', 'full_rules_and_history_rerun': False,
                                 'unchanged_sources': unchanged, 'report': 'docs/releases/v0.29.0-validation.json',
                                 'report_sha256': sha(ROOT / 'docs/releases/v0.29.0-validation.json')},
              'tournaments': {'checked_utc': fresh['updated_utc'], 'games': len(fresh['games']), 'same_games_as_bundled': True},
              'android_device_tested': False, 'github_published': False, 'remote_ci_executed': False,
              'rendering_stalls_resolved': False, 'artifacts': release['artifacts'],
              'packaged_import_modules': compiled, 'first_board_frame_ms': probe['first_board_frame_ms']}
encoded = json.dumps(validation, ensure_ascii=False, indent=2) + '\n'
(OUT / 'artifact-checks.json').write_text(encoded, encoding='utf-8')
(ROOT / 'docs/releases/v0.30.0-validation.json').write_text(encoded, encoding='utf-8')
for source, target in [('analysis-input-dark-393.png', 'import30-portrait.png'), ('analysis-input-light-852.png', 'import30-landscape.png'), ('analysis-recent.png', 'import30-recent.png')]:
    shutil.copy2(OUT / 'ui' / source, ROOT / 'docs/images' / target)
rows = '\n'.join(f'| `{name}` | {count} |' for name, count in counts.items())
text = f'''# 0.30 分析导入验证

本轮新执行 **{sum(counts.values())} 项检查**，最终记录无失败。范围包括棋谱导入、编码、界面入口、变化会话和成品回归；不表示完整复刻或保证没有 bug。

| 验证项 | 检查数 |
|---|---:|
{rows}

界面检查覆盖 360×760、393×852、852×393、1100×800 和明暗主题；输入、粘贴、清空、页签、帮助、最近棋谱与文件入口。触摸与键盘使用真实输入事件；桌面文件路径通过选择器信号送入，Android 回调采用测试替身，并未冒称手机系统选择器实测。窗口适应键盘的检查使用模拟键盘高度。

长 JSON 中有 17,500 字注释，最后一手另有注释，载入后全部保留；预览截短不会截短实际棋谱。UTF-8/BOM、CP932、编码错误、字节上限和超限保留旧输入均有检查。JVM 的 14 项检查覆盖完整文件、分段读取、I/O 异常、CP932 扩展字和并发解码；它验证纯 Java 读取器，不能代替 Android 桥接与生命周期测试。

校验期间保留原对局、注释和变化会话；无效数据保留原状态，成功后才结束旧变化会话。历史大赛也检查从变化分析中载入。测试同时覆盖关闭后旧文件回调、旧校验结果丢弃，返回／取消后可重新选择文件。真实本地引擎评价导入局面，回放记录包含 {len(motion)} 个实际绘制完成的帧样本，有起点、中间过程和终点。

首轮核心测试有两项夹具失败：长文本原本未达到 16,000 字，KIF 注释自带尾部换行；原记录保留在 `review/app/chessis30/import-core-first-attempt.*`。首轮和第二轮 UI 各有两项失败，最终定位并修复空搜索条件把全部最近棋谱过滤掉的问题；记录保留在 `ui-first-attempt`、`ui-second-attempt`。视觉检查另修复浅色输入卡片和只读文本颜色，补查修复返回键取消文件选择后的等待状态。没有删掉失败断言。

Windows 成品通过 {counts['package/windows-package-probe.json']} 项检查，首帧棋盘 {probe['first_board_frame_ms']} 毫秒；成品内实际运行输入、异步解析、完整注释、返回键重试、引擎、教程、报告与动画。APK 检查包括 ARM64、签名、16 KiB 对齐、更新后的原生文件桥接与 CP932 解码器；没有会员或测试数据入包。两种安装文件均以 SHA-256 绑定发行清单。

本轮没有全量重跑规则和 195 局历史棋谱的每一手；相关解析器、规则、动画时钟与赛事数据保持原哈希，延用前版记录，不计入本轮数量。{fresh['updated_utc']} 再次读取官方目录，仍为 26 局，与内置目录逐项一致。尚未开始的 9 月 15 日棋谱地址返回 404，未收入目录。

CI 已加入导入核心、JVM 和虚拟显示器入口；Linux 虚拟显示器流程明确跳过本机 Windows 引擎两项检查，不冒充引擎验收。GitHub 登录仍失效，仓库、Release、远程 CI 和每日工作流尚未发布／运行。Android 真机、蓝牙双机和后台恢复仍待测试；Windows 已知绘制停顿未在本轮重新做性能基准，也未宣称已解决。

运行：`./scripts/test_chessis30.ps1`；核心：`./scripts/test_chessis30.ps1 -CoreOnly`；JVM：`python scripts/test_import30_java.py`；回归：`./scripts/test_chessis30.ps1 -Probes chessis25,chessis11,chessis29`。脚本自动准备长文本与 CP932 测试文件。成品：`./scripts/test_package.ps1 -ReportDirectory review/app/chessis30/package -Executable builds/windows-0.30.0/Shogi.exe`。

详见 [使用说明](ANALYSIS-IMPORT.md)、[机器可读记录](releases/v0.30.0-validation.json) 和 [实现差距](CHESSIS-PARITY.md)。
'''
(ROOT / 'docs/TESTING-0.30.md').write_text(text, encoding='utf-8')
(OUT / 'REPORT.md').write_text(text, encoding='utf-8')
print(json.dumps({'checks': sum(counts.values()), 'failures': [], 'first_board_frame_ms': probe['first_board_frame_ms']}, ensure_ascii=False))
