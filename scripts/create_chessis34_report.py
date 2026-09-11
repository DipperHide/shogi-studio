"""Bind optional saving, multilingual board QA and final packages to release 0.34."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis34'


def read(path):
    return json.loads(path.read_text('utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


release = read(OUT / 'release.json')
assert release['version'] == '0.34.0' and release['android_version_code'] == 52
counts, evidence = {}, []
for name in ['variation-core', 'import-core', 'hint-core', 'archive-core']:
    path = OUT / 'core' / (name + '.json')
    data = read(path)
    assert not data['failures'], path
    counts[name] = data['checks']
    evidence.append({'path': str(path.relative_to(OUT)), 'sha256': sha(path)})
for name in ['chessis34', 'board-hud', 'chessis25', 'chessis33', 'chessis30', 'chessis29', 'chessis32', 'chessis31']:
    path = OUT / (name + '.log')
    log = path.read_text('utf-8-sig')
    data = json.loads(log.rsplit('UNIFIED_TESTS: ', 1)[1].splitlines()[0])
    assert not data['failures'], name
    assert (OUT / (name + '.exit')).read_text('utf-8-sig').strip() == '0', name
    assert not (OUT / (name + '.err')).read_text('utf-8-sig').strip(), name
    counts[name] = data['checks']
    destination = OUT / 'regression' / (name + '.json')
    destination.parent.mkdir(exist_ok=True)
    destination.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    evidence.append({'path': str(destination.relative_to(OUT)), 'sha256': sha(destination)})
for name in ['windows-package-probe', 'verification']:
    path = OUT / 'package' / (name + '.json')
    data = read(path)
    assert not data['failures'], name
    counts[name] = data['checks']
    evidence.append({'path': str(path.relative_to(OUT)), 'sha256': sha(path)})
for name in ['build-android.log', 'build-windows.log', 'package/package-stderr.log']:
    assert not re.search(r'SCRIPT ERROR|ERROR:|UNIFIED FAIL|PACKAGE PROBE FAIL|FAILED', (OUT / name).read_text('utf-8-sig')), name
for item in release['runtime_sources'] + release['artifacts']:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']
apk = next(item for item in release['artifacts'] if item['path'].endswith('.apk'))
windows = next(item for item in release['artifacts'] if item['path'].endswith('.zip'))
probe = read(OUT / 'package/windows-package-probe.json')
with ZipFile(ROOT / apk['path']) as archive:
    modules = ['shogi_board_hud', 'shogi_record_changes', 'shogi_variation_study', 'shogi_variation_view', 'shogi_i18n', 'shogi_board_view', 'shogi_chessis_menu']
    compiled = {name: hashlib.sha256(archive.read(f'assets/scripts/{name}.gdc')).hexdigest() for name in modules}
    assert not any(name.startswith('assets/tests/') or 'membership' in name.lower() for name in archive.namelist())
with ZipFile(ROOT / windows['path']) as archive:
    assert hashlib.sha256(archive.read('Shogi.exe')).hexdigest() == probe['executable_sha256']
phone_path = OUT / 'android-device/validation.json'
phone = read(phone_path) if phone_path.exists() else None
if phone is not None:
    assert phone['apk_sha256'] == apk['sha256'] and not phone['failures']
    for item in phone['evidence']:
        assert sha(OUT / 'android-device' / item['file']) == item['sha256']
phone_summary = ('已在 Android 14 实机安装本次 APK 并检查英文、日文界面；准确范围和截图摘要见 [实机报告](ANDROID-DEVICE-BASELINE.md)。实际手机检查独立于上面的断言计数。'
                 if phone is not None else
                 '本机保留了 Android 安装日志和界面截图，但上次任务中断前未完成本版实机验证汇总；本报告不将其计为已通过的实机验收。此前 0.33 的实测见 [实机报告](ANDROID-DEVICE-BASELINE.md)。')
for source, target in [('en-wood-360.png', 'board34-english.png'), ('ja-wood-852.png', 'board34-japanese-landscape.png'), ('en-save-choice.png', 'save34-english.png')]:
    shutil.copy2(OUT / 'visual' / source, ROOT / 'docs/images' / target)
publication_path = ROOT / 'docs/releases/v0.34.0-publication.json'
publication = read(publication_path) if publication_path.exists() else {}
validation = {'version': release['version'], 'functional_checks': counts, 'functional_total': sum(counts.values()), 'failures': [],
              'evidence': evidence, 'packaged_modules': compiled, 'first_board_frame_ms': probe['first_board_frame_ms'],
              'artifacts': release['artifacts'], 'android_device_tested': phone is not None, 'android_validation': phone,
              'rendering_stalls_resolved': False, 'all_ui_translated': False, 'full_chessis_parity': False,
              'github_published': publication.get('published', False), 'publication_report': 'docs/releases/v0.34.0-publication.json'}
encoded = json.dumps(validation, ensure_ascii=False, indent=2) + '\n'
(OUT / 'artifact-checks.json').write_text(encoded, encoding='utf-8')
(ROOT / 'docs/releases/v0.34.0-validation.json').write_text(encoded, encoding='utf-8')
(ROOT / 'builds/SHA256SUMS-0.34.0.txt').write_text(''.join(item['sha256'] + '  ' + Path(item['path']).name + '\n' for item in release['artifacts']), encoding='utf-8')
text = f'''# 0.34 棋盘、多语言与保存流程验证

本地最终记录共 **{sum(counts.values())} 项检查**，无失败。核心规则周边 {sum(counts[n] for n in ['variation-core', 'import-core', 'hint-core', 'archive-core'])} 项；保存流程 {counts['chessis34']}、棋盘与多语言 {counts['board-hud']}；变化 {counts['chessis25']}、档案 {counts['chessis33']}、导入 {counts['chessis30']}、开局 {counts['chessis29']}、提示 {counts['chessis32']}、大赛 {counts['chessis31']}；Windows 成品 {counts['windows-package-probe']}、APK {counts['verification']}。这些是断言次数，不代表独立功能数量，不能保证没有 bug。

- 棋盘画面覆盖中、英、日三种语言，2D / 3D、360×760 / 393×852 / 852×393，另检查浅色棋盘及保存界面。持驹宽高比例固定；姓名、计时和头像互不覆盖；菜单覆盖棋盘时保持棋盘尺寸。英文、日文设置与常驻控件会随语言刷新。
- 保存测试通过实际触摸事件验证继续编辑、放弃、保存及写入失败重试。纯回放不新增棋谱；旧棋谱的未保存注释不会覆盖原文件；文件导入可以只载入；续下保留手数、升变状态；异步等待保存选择后继续操作一次。
- 升变和不升变提示、合法打入、变化持久化、档案预览、导入错误恢复及官方大赛缓存仍通过对应回归。
- 成品再次验证保存选择、实际引擎与预览动画。Windows 首张棋盘 {probe['first_board_frame_ms']} 毫秒。APK 验证延续签名、ARM64、16 KiB 对齐及新增模块，未包含测试夹具或付费模块。
- {phone_summary}

截图检查发现并修复了英文 Board 按钮断词、部分文案漏译和长英文标题导致保存对话框过高。首轮保存布局及快速注释编辑的过期滚动目标问题也已修复。测试夹具中的外语已翻译表头识别误报单独修正，失败尝试不计入通过数。

运行 `./scripts/test_chessis34.ps1 -Probes board-hud,chessis34,chessis25,chessis33,chessis30,chessis29,chessis32,chessis31`。CI 包含三语绘制测试和现有核心回归。

高级报告、部分导入说明和课程仍有中文，不能称为完整三语翻译。未保存的变化仍仅驻留内存；进程被系统杀死时不能恢复。Windows 绘制停顿、双机蓝牙及完整 Chessis 功能对齐仍未验收。

![英文 3D 棋盘](images/board34-english.png)

[保存用法](OPTIONAL-SAVING.md) · [机器可读结果](releases/v0.34.0-validation.json) · [复刻差距](CHESSIS-PARITY.md)
'''
(ROOT / 'docs/TESTING-0.34.md').write_text(text, encoding='utf-8')
(OUT / 'REPORT.md').write_text(text, encoding='utf-8')
print(json.dumps({'checks': sum(counts.values()), 'failures': []}))
