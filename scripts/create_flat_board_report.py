"""Bind 0.35.0 navigation, visual and package checks to release artifacts."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis350'
read = lambda p: json.loads(p.read_text('utf-8-sig'))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
release = read(OUT / 'release.json')
assert release['version'] == '0.35.0' and release['android_version_code'] == 55
for item in release['runtime_sources'] + release['artifacts']:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']
counts = {}
for name in ['live-navigation', 'board-hud', 'chessis34']:
    path = OUT / (name + '.log')
    result = json.loads(path.read_text('utf-8-sig').rsplit('UNIFIED_TESTS: ', 1)[1].splitlines()[0])
    assert not result['failures'] and not path.with_suffix('.err').read_text('utf-8-sig').strip()
    counts[name] = result['checks']
for name in ['windows-package-probe', 'verification']:
    result = read(OUT / 'package' / (name + '.json'))
    assert not result['failures']
    counts[name] = result['checks']
device_path = OUT / 'android-device/validation.json'
device = read(device_path) if device_path.exists() else {'status': 'pending'}
if device['status'] == 'passed':
    apk = next(a for a in release['artifacts'] if a['path'].endswith('.apk'))
    assert device['installed_apk_sha256'] == apk['sha256'] and not device['failures']
    for item in device['evidence']:
        assert sha(device_path.parent / item['file']) == item['sha256']
report = {'version': '0.35.0', 'checked_utc': datetime.now(timezone.utc).isoformat(),
          'checks': counts, 'total': sum(counts.values()), 'failures': [],
          'artifacts': release['artifacts'], 'android_validation': device}
(ROOT / 'docs/releases/v0.35.0-validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
(ROOT / 'builds/SHA256SUMS-0.35.0.txt').write_text(''.join(a['sha256'] + '  ' + Path(a['path']).name + '\n' for a in release['artifacts']), encoding='utf-8')
for mode in ['light', 'dark']:
    shutil.copy2(ROOT / ('review/app/live-navigation/anime2d-' + mode + '-393.png'), ROOT / ('docs/images/board350-' + mode + '.png'))
device_note = ('Android 14 已安装最终发布 APK并完成所列实机检查，详见下方验证记录。' if device['status'] == 'passed' else '本版手机安装或验收尚未完成。')
(ROOT / 'docs/TESTING-0.35.0.md').write_text(f'''# 0.35.0 二维棋盘与回放验证

本地 **{sum(counts.values())} 项断言通过**：回放与正常对局 {counts['live-navigation']} 项，棋盘、三语和布局 {counts['board-hud']} 项，保存与历史续下 {counts['chessis34']} 项，Windows 成品 {counts['windows-package-probe']} 项，APK {counts['verification']} 项。

通过实际工具栏与棋盘触摸检查：回退两手再前进到最新，立即继续落子并悔棋；停在历史第一手时悔棋撤销当前对局最后一手并恢复正常对局；自动回放到末尾停止；手动翻阅暂停自动播放。人机对局保持原执棋方和成对悔棋规则。导入棋谱的末尾仍保持独立回放，不会误悔当前对局。二维与立体均覆盖。

二维保留与原 3D 棋盘一致的背景。浅色、深色、横屏、竖屏以及书法平面模式截图已检查；棋字由可变字体默认 200 字重改为 600，棋子、持驹计数、行棋方及工具栏同步调整。

{device_note} 实机与本地验证范围分别记录，未宣称全部功能均在手机逐项测试。

![二维浅色](images/board350-light.png)

![二维深色](images/board350-dark.png)

运行 `Godot --path godot --resolution 360x760 -- --unified-test --live-navigation`，布局与保存回归分别使用 `--board-hud`、`--chessis34`。详细结果见 [验证记录](releases/v0.35.0-validation.json)。
''', encoding='utf-8')
print(json.dumps({'checks': sum(counts.values()), 'android_status': device['status']}))
