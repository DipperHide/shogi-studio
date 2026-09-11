"""Bind the 0.34.1 typography and hint-toggle checks to shipped artifacts."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis341'


def read(path):
    return json.loads(path.read_text('utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


release = read(OUT / 'release.json')
assert release['version'] == '0.34.1' and release['android_version_code'] == 53
for item in release['runtime_sources'] + release['artifacts']:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']
counts, evidence = {}, []
logs = {'fonts-hints': ROOT / 'review/app/fonts-hints/test.log'}
logs.update({name: OUT / (name + '.log') for name in ['board-hud', 'chessis32', 'chessis34']})
for name, path in logs.items():
    data = json.loads(path.read_text('utf-8-sig').rsplit('UNIFIED_TESTS: ', 1)[1].splitlines()[0])
    assert not data['failures'] and not path.with_suffix('.err').read_text('utf-8-sig').strip(), name
    counts[name] = data['checks']
    evidence.append({'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(path)})
for name in ['windows-package-probe', 'verification']:
    path = OUT / 'package' / (name + '.json')
    data = read(path)
    assert not data['failures'], name
    counts[name] = data['checks']
    evidence.append({'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(path)})
device = read(OUT / 'android-device/validation.json')
apk = next(item for item in release['artifacts'] if item['path'].endswith('.apk'))
device_validated = device.get('status') == 'passed'
if device_validated:
    assert device['apk_sha256'] == device['installed_apk_sha256'] == apk['sha256'] and not device['failures']
    for item in device['evidence']:
        assert sha(OUT / 'android-device' / item['file']) == item['sha256']
device_note = ('Android 14 实机验证最终 APK 的日文菜单、教程目录及推荐开关，安装包哈希与发布包一致。'
               if device_validated else
               '本版 Android 实机验收尚未完成：安装被手机系统拒绝（User rejected permissions）。本地真实引擎、界面测试及发布安装包校验已通过，不能将此前版本的实测计为本版已验收。')
publication_path = ROOT / 'docs/releases/v0.34.1-publication.json'
publication = read(publication_path) if publication_path.exists() else {}
report = {'version': '0.34.1', 'checked_utc': datetime.now(timezone.utc).isoformat(),
          'functional_checks': counts, 'functional_total': sum(counts.values()), 'failures': [],
          'evidence': evidence, 'artifacts': release['artifacts'], 'android_device_tested': device_validated, 'android_validation': device,
          'github_published': publication.get('published', False), 'all_lessons_translated': False}
(ROOT / 'docs/releases/v0.34.1-validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
(ROOT / 'builds/SHA256SUMS-0.34.1.txt').write_text(''.join(item['sha256'] + '  ' + Path(item['path']).name + '\n' for item in release['artifacts']), encoding='utf-8')
for source, dest in [('japanese-menu.png', 'menu341-japanese.png'), ('japanese-tutorial-chapters.png', 'tutorial341-fonts.png')]:
    shutil.copy2(ROOT / 'review/app/fonts-hints' / source, ROOT / 'docs/images' / dest)
text = f'''# 0.34.1 日文字体与推荐好手验证

本地共 **{sum(counts.values())} 项检查通过**：字体与推荐开关 {counts['fonts-hints']}、棋盘和三语界面 {counts['board-hud']}、升变提示 {counts['chessis32']}、保存流程 {counts['chessis34']}、Windows 成品 {counts['windows-package-probe']}、APK {counts['verification']}。这是断言次数，不代表独立功能数量。

日文字体主字形使用 400 字重，而缺少字形时原来会落到默认 100 的中文备用字体。修复后，实际排版出的中日文混排字形在正文中全部使用 400，在标题中全部使用 600。菜单“局面编辑”和“关于”补齐翻译；已有标题随语言切换更新。菜单、教程目录与章节截图已检查。

真实引擎与实际触摸测试验证“推荐好手”第二次点击会停止分析，移除候选行及棋盘箭头；搜索和推荐入口可交替开关，迟到回调不恢复已隐藏提示。候选预览中再次点击会退出预览并关闭推荐，原对局和棋谱库不变。

{device_note} 验证范围见 [机器可读记录](releases/v0.34.1-validation.json)。课程正文仍包含未翻译的中文，未宣称完整日文翻译或全功能实机验收。

![日文菜单](images/menu341-japanese.png)

![教程字重](images/tutorial341-fonts.png)

运行 `Godot --path godot -- --unified-test --fonts-hints`；CI 同时覆盖既有核心回归、菜单冷启动、三语界面、升变及保存流程。
'''
(ROOT / 'docs/TESTING-0.34.1.md').write_text(text, encoding='utf-8')
print(json.dumps({'checks': sum(counts.values()), 'failures': []}))
