"""Bind replay continuation acceptance to the 0.34.2 release artifacts."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis342'
read = lambda p: json.loads(p.read_text('utf-8-sig'))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
release = read(OUT / 'release.json')
assert release['version'] == '0.34.2'
for item in release['runtime_sources'] + release['artifacts']:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']
log = OUT / 'chessis34.log'
tests = json.loads(log.read_text('utf-8-sig').rsplit('UNIFIED_TESTS: ', 1)[1].splitlines()[0])
assert not tests['failures'] and not log.with_suffix('.err').read_text('utf-8-sig').strip()
counts = {'saving_and_replay_continuation': tests['checks']}
for name in ['windows-package-probe', 'verification']:
    result = read(OUT / 'package' / (name + '.json'))
    assert not result['failures']
    counts[name] = result['checks']
device_file = OUT / 'android-device/validation.json'
device = read(device_file) if device_file.exists() else {'status': 'pending'}
if device['status'] == 'passed':
    apk = next(a for a in release['artifacts'] if a['path'].endswith('.apk'))
    assert device['installed_apk_sha256'] == apk['sha256'] and not device['failures']
    for item in device['evidence']:
        assert sha(device_file.parent / item['file']) == item['sha256']
report = {'version': '0.34.2', 'checked_utc': datetime.now(timezone.utc).isoformat(),
          'checks': counts, 'total': sum(counts.values()), 'failures': [],
          'artifacts': release['artifacts'], 'android_validation': device}
(ROOT / 'docs/releases/v0.34.2-validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
(ROOT / 'builds/SHA256SUMS-0.34.2.txt').write_text(''.join(a['sha256'] + '  ' + Path(a['path']).name + '\n' for a in release['artifacts']), encoding='utf-8')
shutil.copy2(ROOT / 'review/app/chessis34/ui/replay-continuation-zh.png', ROOT / 'docs/images/replay342-confirmation.png')
device_note = ('Android 14 手机已安装最终 APK，文件哈希与发布包一致；实机确认续下入口及返回回放保留进度。手机对局未用于落子测试。'
               if device['status'] == 'passed' else 'Android 14 手机安装或验收尚未完成，不能计为实机通过。')
(ROOT / 'docs/TESTING-0.34.2.md').write_text(f'''# 0.34.2 回放续下验证

本地 **{sum(counts.values())} 项断言通过**：保存、回放与续下 {tests['checks']} 项，Windows 成品 {counts['windows-package-probe']} 项，APK {counts['verification']} 项。

复现了旧版取消续下会退出历史回放、丢失所选进度的问题。修复后的触摸测试从工具栏连续回退，再点击“从这里下”：返回回放保留原局面；不保存续下后能通过实际棋盘点击走出下一手；保存续下会保留原棋谱的完整后续着手。原棋谱对象不变，续下停止自动播放。中、日、英文确认框已检查。

{device_note}

![续下确认](images/replay342-confirmation.png)

完整回归：`Godot --path godot -- --unified-test --chessis34`。单独续下验证追加 `--replay-continuation`。详细结果见 [验证记录](releases/v0.34.2-validation.json)。
''', encoding='utf-8')
print(json.dumps({'checks': sum(counts.values()), 'android_status': device['status']}))
