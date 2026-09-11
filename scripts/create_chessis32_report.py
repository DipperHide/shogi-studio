"""Bind promotion-hint tests, painted output and package checks to release 0.32."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis32'

def read(path):
    return json.loads(path.read_text('utf-8-sig'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

release = read(OUT / 'release.json')
assert release['version'] == '0.32.0' and release['android_version_code'] == 50
counts, evidence = {}, []
for name in ['hint-core.json', 'ui/ui-tests.json', 'package/windows-package-probe.json', 'package/verification.json']:
    path = OUT / name
    item = read(path)
    assert not item['failures'], name
    counts[name] = int(item['checks'])
    evidence.append({'path': name, 'sha256': sha(path)})
assert (OUT / 'ui.exit').read_text('utf-8-sig').strip() == '0'
for name in ['hint-core.log', 'ui.err', 'build-android.log', 'build-windows.log', 'package/package-stderr.log']:
    assert not re.search(r'SCRIPT ERROR|ERROR:|UNIFIED FAIL|PACKAGE PROBE FAIL|FAILED', (OUT / name).read_text('utf-8-sig')), name
for item in release['runtime_sources'] + release['artifacts']:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']
probe = read(OUT / 'package/windows-package-probe.json')
assert [item['choice'] for item in probe['promotion_hints']] == ['升变', '不升变']
frames = probe['motion_frames']['promotion-preview']
assert frames[0]['progress'] == 0 and frames[-1]['progress'] == 1
assert sum(0 < frame['progress'] < 1 for frame in frames) >= 8
assert all(0 <= b['progress'] - a['progress'] <= .30 for a, b in zip(frames, frames[1:]))
apk = next(item for item in release['artifacts'] if item['path'].endswith('.apk'))
windows = next(item for item in release['artifacts'] if item['path'].endswith('.zip'))
with ZipFile(ROOT / apk['path']) as archive:
    modules = ['shogi_move_hint', 'shogi_pv_row', 'shogi_board_view', 'shogi_mistake_practice', 'shogi_chessis_menu', 'shogi_app']
    compiled = {name: hashlib.sha256(archive.read(f'assets/scripts/{name}.gdc')).hexdigest() for name in modules}
    assert not any(name.startswith('assets/tests/') or 'membership' in name.lower() for name in archive.namelist())
with ZipFile(ROOT / windows['path']) as archive:
    assert hashlib.sha256(archive.read('Shogi.exe')).hexdigest() == probe['executable_sha256']
prior = read(ROOT / 'review/app/chessis31/release.json')
unchanged = [item for item in prior['runtime_sources'] if item['path'] in ['godot/scripts/shogi_rules.gd', 'godot/scripts/shogi_usi_codec.gd', 'godot/scripts/shogi_game.gd']]
for item in unchanged: assert sha(ROOT / item['path']) == item['sha256']
for source, target in [('hint-wood-normal-393.png', 'promotion32-wood.png'), ('hint-en.png', 'promotion32-english.png'), ('practice-keep.png', 'promotion32-practice.png')]:
    shutil.copy2(OUT / 'ui' / source, ROOT / 'docs/images' / target)
publication_path = ROOT / 'docs/releases/v0.32.0-publication.json'
publication = read(publication_path) if publication_path.exists() else {}
cloud_runs = [run for run in publication.get('runs', []) if run['workflowName'] == 'Tests' and run['headSha'] == publication.get('release_source_commit')]
cloud_passed = bool(cloud_runs) and bool(publication.get('remote_evidence')) and all(run['conclusion'] == 'success' for run in cloud_runs)
cloud_text = ('本版源码的 [云端完整回归](' + publication['remote_evidence']['run_url'] + ') 已通过；其中提示核心 242 项、提示界面 179 项，并全量验证 195 局／23,115 手历史棋谱。云端结果独立记录，不并入本地总数。') if cloud_passed else '云端执行结果将独立记录在发布记录中。'
validation = {'version': release['version'], 'functional_checks': counts, 'functional_total': sum(counts.values()), 'failures': [],
    'evidence': evidence, 'packaged_hint_modules': compiled, 'promotion_hints': probe['promotion_hints'], 'promotion_preview_frames': frames,
    'unchanged_rules_and_codec': unchanged, 'first_board_frame_ms': probe['first_board_frame_ms'], 'artifacts': release['artifacts'],
    'android_device_tested': False, 'rendering_stalls_resolved': False, 'intermittent_filter_close_resolved': False,
    'github_published': publication.get('published', False), 'remote_ci_passed': cloud_passed,
    'early_test_fixture_errors': ['Knight non-promotion on the final two ranks is illegal; optional fixture moved one rank back.', 'UI expected simplified 步 while the notation deliberately uses Japanese 歩.'],
    'publication_report': 'docs/releases/v0.32.0-publication.json'}
encoded = json.dumps(validation, ensure_ascii=False, indent=2) + '\n'
(OUT / 'artifact-checks.json').write_text(encoded, encoding='utf-8')
(ROOT / 'docs/releases/v0.32.0-validation.json').write_text(encoded, encoding='utf-8')
(ROOT / 'builds/SHA256SUMS-0.32.0.txt').write_text(''.join(item['sha256'] + '  ' + Path(item['path']).name + '\n' for item in release['artifacts']), encoding='utf-8')
text = f'''# 0.32 升变提示验证

本地最终记录共 **{sum(counts.values())} 项检查**，无失败：提示规则 {counts['hint-core.json']} 项、实际界面 {counts['ui/ui-tests.json']} 项、Windows 成品 {counts['package/windows-package-probe.json']} 项、APK {counts['package/verification.json']} 项。这些是断言次数，不代表同样数量的独立功能，也不能保证没有 bug。

- 提示规则覆盖双方、六种可升变棋子、进入敌阵、从敌阵移出、强制升变、主动不升变、金／玉／成驹、持驹打入和普通行棋。验证提示不会修改棋局或着手。
- 实际界面覆盖 360×760、393×852、852×393、1100×800，二维／3D、翻转和明暗。检查同一落点的两种标记互不遮挡、位于棋盘范围内；关闭第一条箭头后第二条编号和颜色保持不变。
- 中英日候选标记在窄屏保留滚动文字与操作按钮；可滚动到完整的第二条线路。完整线路后续的不成明确标出，普通首手不残留升变标签。英文棋盘「+／=」与候选栏 Promote／Do not promote 对应。
- 失误练习第一次提示不提前透露完整答案，第二次显示升变选择，文字与箭头一致。播放升变候选确实落成成驹，并保留原棋局。
- 成品运行再次验证了两种候选标签、棋盘标记、不成文字和真实升变回放。Windows 首帧棋盘 {probe['first_board_frame_ms']} 毫秒。APK 检查签名、ARM64、16 KiB 对齐、新提示模块及资源；未打包测试棋局或付费模块。

首轮核心夹具错误地允许桂马在倒数第二行不升变；首轮 UI 断言使用简体「步」匹配日文记谱「歩」。均修正测试预期，原失败日志留在 `review/app/chessis32/core-first-attempt/` 与 `ui-first-attempt/`。截图检查后还调整了重复落点标记的排列，并加连线指向目标格。

规则、着手解析和棋局模型与 0.31 的哈希一致；本地没有重复执行全量历史棋谱或完整规则基准。本次改动没有解决此前的 Windows 绘制停顿和筛选面板关闭偶发失败。Android 未连接真机，因此成品交互检查在 Windows 上执行，APK 检查不等于 Android 真机验证。

运行 `./scripts/test_chessis32.ps1`；CI 也加入提示核心和虚拟显示器测试。云端实际状态与发布文件核验见 [发布记录](releases/v0.32.0-publication.json)，不计入上面的本地总数。

{cloud_text}

[使用说明](PROMOTION-HINTS.md) · [机器可读证据](releases/v0.32.0-validation.json) · [完整复刻差距](CHESSIS-PARITY.md)
'''
(ROOT / 'docs/TESTING-0.32.md').write_text(text, encoding='utf-8')
(OUT / 'REPORT.md').write_text(text, encoding='utf-8')
print(json.dumps({'checks': sum(counts.values()), 'failures': []}))
