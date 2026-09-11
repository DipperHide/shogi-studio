"""Bind the personal archive tests and packaged artifacts to release 0.33."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis33'

def read(path):
    return json.loads(path.read_text('utf-8-sig'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

release = read(OUT / 'release.json')
assert release['version'] == '0.33.0' and release['android_version_code'] == 51
counts, evidence = {}, []
for name in ['archive-core.json', 'ui/ui-tests.json', 'regression/import-core.json', 'regression/variation-core.json', 'regression/hint-core.json',
             'regression/import-ui/ui-tests.json', 'regression/tournament-ui/ui-tests.json', 'regression/opening-ui/ui-tests.json',
             'regression/hint-ui/ui-tests.json', 'package/windows-package-probe.json', 'package/verification.json']:
    path = OUT / name
    data = read(path)
    assert not data['failures'], name
    counts[name] = data['checks']
    evidence.append({'path': name, 'sha256': sha(path)})
for prefix in ['', 'regression/']:
    for path in (OUT / prefix).glob('*.exit'):
        assert path.read_text('utf-8-sig').strip() == '0', path
for name in ['ui.err', 'archive-core.log', 'variation25_test.log', 'hint32_test.log', 'build-android.log', 'build-windows.log', 'package/package-stderr.log']:
    assert not re.search(r'SCRIPT ERROR|ERROR:|UNIFIED FAIL|PACKAGE PROBE FAIL|FAILED', (OUT / name).read_text('utf-8-sig')), name
for path in (OUT / 'regression').glob('*.err'):
    assert not path.read_text('utf-8-sig').strip(), path
for item in release['runtime_sources'] + release['artifacts']:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']
probe = read(OUT / 'package/windows-package-probe.json')
frames = probe['motion_frames']['personal-archive-preview']
assert any(0 < frame['progress'] < 1 for frame in frames) and frames[-1]['progress'] == 1
apk = next(item for item in release['artifacts'] if item['path'].endswith('.apk'))
windows = next(item for item in release['artifacts'] if item['path'].endswith('.zip'))
with ZipFile(ROOT / apk['path']) as archive:
    modules = ['shogi_archive_model', 'shogi_archive_view', 'shogi_archive_job', 'shogi_records', 'shogi_backup', 'shogi_opening_preview']
    compiled = {name: hashlib.sha256(archive.read(f'assets/scripts/{name}.gdc')).hexdigest() for name in modules}
    assert not any(name.startswith('assets/tests/') or 'membership' in name.lower() for name in archive.namelist())
with ZipFile(ROOT / windows['path']) as archive:
    assert hashlib.sha256(archive.read('Shogi.exe')).hexdigest() == probe['executable_sha256']
for source, target in [('archive-filtered.png', 'archive33-list.png'), ('preview-852.png', 'archive33-landscape.png'), ('preview-promoted-drop.png', 'archive33-preview.png')]:
    shutil.copy2(OUT / 'ui' / source, ROOT / 'docs/images' / target)
publication_path = ROOT / 'docs/releases/v0.33.0-publication.json'
publication = read(publication_path) if publication_path.exists() else {}
cloud_passed = bool(publication.get('remote_evidence')) and all(run['conclusion'] == 'success' for run in publication.get('runs', []))
validation = {'version': '0.33.0', 'functional_checks': counts, 'functional_total': sum(counts.values()), 'failures': [],
              'evidence': evidence, 'packaged_archive_modules': compiled, 'archive_preview_frames': frames,
              'first_board_frame_ms': probe['first_board_frame_ms'], 'artifacts': release['artifacts'],
              'android_device_tested': False, 'rendering_stalls_resolved': False, 'intermittent_filter_close_resolved': False,
              'github_published': publication.get('published', False), 'remote_ci_passed': cloud_passed,
              'publication_report': 'docs/releases/v0.33.0-publication.json'}
encoded = json.dumps(validation, ensure_ascii=False, indent=2) + '\n'
(OUT / 'artifact-checks.json').write_text(encoded, encoding='utf-8')
(ROOT / 'docs/releases/v0.33.0-validation.json').write_text(encoded, encoding='utf-8')
(ROOT / 'builds/SHA256SUMS-0.33.0.txt').write_text(''.join(item['sha256'] + '  ' + Path(item['path']).name + '\n' for item in release['artifacts']), encoding='utf-8')
cloud_text = ('本版源码的 [云端完整回归](' + publication['remote_evidence']['run_url'] + ') 已通过，另行验证 195 局／23,115 手历史棋谱和完整规则基准。') if cloud_passed else '云端运行结果将在发布记录中单独记录。'
text = f'''# 0.33 个人棋谱库验证

本地最终记录共 **{sum(counts.values())} 项检查**，无失败。核心：档案 48、棋谱导入 28、变化存档 67、升变提示 242；实际界面：档案 167、导入 132、大赛 171、开局预览 267、升变提示 179；Windows 成品 {counts['package/windows-package-probe.json']}、APK {counts['package/verification.json']}。这是断言次数，不代表同样数量的独立功能，不能保证没有 bug。

- 档案核心验证旧数据迁移、收藏和标签持久化、普通保存和重命名保留元数据、过期写入拒绝、无效／过大数据不覆盖存档、多条件筛选、添加时间排序和完整合法局面搜索。
- 实际界面在 360×760、393×852、852×393、1100×800 和明暗主题下验证页签、分页、底部导入、筛选应用与取消、信息展开、编辑保存。测试实际触摸派发，不只直接调用按钮回调。
- 独立预览从初始局面开始；吃子升变和持驹打入具有中间绘制帧，横屏棋盘与持驹区完整可见。载入保留选中手数、成驹和续下入口；浏览不修改原对局。
- 备份包含收藏、标签和添加时间，支持旧备份；无效元数据在写入前拒绝。取消文件选择、错误文件和过期后台结果不会替换当前棋谱。文件夹导入校验成功后才归档。
- 成品再次验证后台索引、收藏写入、独立预览动画和选中手数载入。Windows 首帧棋盘 {probe['first_board_frame_ms']} 毫秒。APK 检查签名延续、ARM64、16 KiB 对齐及档案模块，未打包测试夹具或付费模块。

开发测试发现并修复：搜索在分词前移除了空格；筛选项未转换为显式字符串数组；预览导航空回调报错与横屏边距；从导入帮助返回误用保存的大赛页签。首轮 UI 夹具也补充了明确的窗口尺寸和失败截图。原失败输出保存在 `review/app/chessis33/first-core-attempt`、`first-ui-attempt`、`second-ui-attempt`、`third-ui-attempt` 和 `import-regression-attempt`，未将失败结果计入通过数。

Android 设备列表为空，未进行本次真机交互验证。既有 Windows 绘制停顿和大赛筛选关闭偶发失败仍未确认解决。批量棋谱操作、已分析筛选和跨棋谱练习尚缺。

运行 `./scripts/test_chessis33.ps1`；完整 CI 包含核心档案和虚拟显示器测试。{cloud_text} 云端检查不并入本地总数。

[用法](PERSONAL-ARCHIVE.md) · [机器可读验证](releases/v0.33.0-validation.json) · [发布记录](releases/v0.33.0-publication.json) · [复刻差距](CHESSIS-PARITY.md)
'''
(ROOT / 'docs/TESTING-0.33.md').write_text(text, encoding='utf-8')
(OUT / 'REPORT.md').write_text(text, encoding='utf-8')
print(json.dumps({'checks': sum(counts.values()), 'failures': []}))
