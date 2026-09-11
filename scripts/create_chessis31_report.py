"""Bind tournament archive evidence to the exact Android and Windows release."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis31'


def read(path):
    return json.loads(path.read_text('utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


release = read(OUT / 'release.json')
assert release['version'] == '0.31.0' and release['android_version_code'] == 49
counts = {}
for name in ['tournament-core.json', 'tournament-sync-tests.json', 'import-core.json', 'ui/ui-tests.json',
             'chessis20/ui-tests.json', 'chessis30/ui-tests.json', 'sheet-stress.json',
             'package/windows-package-probe.json', 'package/verification.json']:
    data = read(OUT / name)
    assert not data['failures'], name
    counts[name] = int(data['checks'])
core = (OUT / 'chessis_core_test.log').read_text('utf-8-sig')
assert 'failures: []' in core and 'SCRIPT ERROR' not in core
counts['interchange-core'] = int(re.search(r'CHESSIS CORE: (\d+) checks', core).group(1))
for name in ['chessis31', 'chessis20', 'chessis30']:
    assert (OUT / f'{name}.exit').read_text('utf-8-sig').strip() == '0'
    assert not (OUT / f'{name}.err').read_text('utf-8-sig').strip()
for name in ['build-android.log', 'build-windows.log', 'package/package-stderr.log',
             'tournament31_test.log', 'tournament_sync20_test.log', 'import30_test.log', 'sheet-stress.err']:
    assert not re.search(r'SCRIPT ERROR|ERROR:|FAILED', (OUT / name).read_text('utf-8-sig')), name
stress = (OUT / 'sheet-stress.log').read_text('utf-8-sig')
assert len(re.findall(r'SHEET TAP \d+ signal=1 closing=true', stress)) == 24
for item in release['runtime_sources'] + release['artifacts']:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']
(ROOT / 'builds/SHA256SUMS-0.31.0.txt').write_text(
    ''.join(item['sha256'] + '  ' + Path(item['path']).name + '\n' for item in release['artifacts']), encoding='utf-8')
motion = read(OUT / 'ui/motion-frames.json')['replay']
assert motion[0] == 0 and motion[-1] == 1 and sum(0 < value < 1 for value in motion) >= 8
assert all(0 <= b-a <= .30 for a,b in zip(motion,motion[1:]))
probe = read(OUT / 'package/windows-package-probe.json')
assert {'tournament-filter','tournament-replay'} <= set(probe['motion_frames'])
for frames in probe['motion_frames'].values():
    assert frames[0]['progress'] == 0 and frames[-1]['progress'] == 1
    assert sum(0 < frame['progress'] < 1 for frame in frames) >= 8
    assert all(0 <= b['progress'] - a['progress'] <= .30 for a,b in zip(frames,frames[1:]))
windows = next(item for item in release['artifacts'] if item['path'].endswith('.zip'))
apk = next(item for item in release['artifacts'] if item['path'].endswith('.apk'))
with ZipFile(ROOT / windows['path']) as archive:
    assert hashlib.sha256(archive.read('Shogi.exe')).hexdigest() == probe['executable_sha256']
with ZipFile(ROOT / apk['path']) as archive:
    assert not any('membership' in name.lower() or name.startswith('assets/tests/') for name in archive.namelist())
    modules = ['shogi_tournament_view','shogi_tournament_filter','shogi_tournament_job','shogi_tournament_status','shogi_tournament_sync','shogi_import_job','shogi_rendered_tween']
    compiled = {name: hashlib.sha256(archive.read(f'assets/scripts/{name}.gdc')).hexdigest() for name in modules}
    for name in ['config/tournaments.json','assets/data/tournament-index.json','assets/data/historic-games.json','assets/brand/studio-icon.svg']:
        assert archive.read('assets/' + name) == (ROOT / 'godot' / name).read_bytes()
fresh = read(OUT / 'fresh-tournament-index.json')
assert fresh['games'] == read(ROOT / 'godot/assets/data/tournament-index.json')['games']
official = read(OUT / 'ui/official-download.json')
assert official['id'] == fresh['games'][0]['id'] and official['plies'] == fresh['games'][0]['plies'] and official['cached']
assert official['moves_sha256'] == fresh['games'][0]['moves_sha256']
prior = read(ROOT / 'review/app/chessis30/release.json')
changed = {'shogi_app.gd','shogi_chessis_menu.gd','shogi_analysis_import.gd','shogi_package_probe.gd','shogi_tournament_sync.gd'}
unchanged = [item for item in prior['runtime_sources'] if item['path'].startswith('godot/scripts/') and Path(item['path']).name not in changed]
unchanged += [item for item in prior['runtime_sources'] if item['path'].startswith(('godot/assets/data/','godot/config/'))]
for item in unchanged: assert sha(ROOT / item['path']) == item['sha256'], item['path']
paths = ['res/layout/dialog_recent_games.xml','res/layout/view_gm_games_archive_content.xml','res/layout/dialog_gm_games_item.xml','res/layout/dialog_gm_games_filter.xml',
         'java/sources/p079K2/C0678g.java','java/sources/p079K2/C0674c.java','java/sources/p079K2/C0680i.java','java/sources/p207b3/C2252w.java']
references = [{'path':name,'sha256':sha(ROOT / '.work/chessis-reference' / name)} for name in paths]
intermittent = (OUT / 'ui-second-attempt/chessis31.err').read_text('utf-8-sig')
assert 'filter closes back to archive' in intermittent
publication_path = ROOT / 'docs/releases/v0.31.0-publication.json'
publication = read(publication_path) if publication_path.exists() else {}
validation = {'version':'0.31.0','functional_checks':counts,'functional_total':sum(counts.values()),'failures':[],
              'reference_evidence':references,'source_apk_sha256':'14df01b58e777a130aee977c51a9b7823c8c8ada31479843b2f01b765b49f111',
              'initial_core_attempt':read(OUT / 'core-first-attempt/tournament-core.json'),
              'initial_visual_issues':['header title collapsed into a vertical column','shared icon helper erased footer labels','default unchecked event indicator invisible on dark theme'],
              'intermittent_close':{'initial_errors':intermittent,'resolved':False,'later_stress_cycles':24,'later_stress_failed':False,'later_full_ui_failed':False},
              'ui_motion':motion,'package_motion':probe['motion_frames'],'official_download':official,
              'tournaments':{'checked_utc':fresh['updated_utc'],'games':len(fresh['games']),'same_games_as_bundled':True},
              'prior_evidence':{'release':'0.30.0','source_commit':'af9a688','local_full_rules_and_history_rerun':False,'unchanged_sources':unchanged,
                                'report':'docs/releases/v0.30.0-validation.json','report_sha256':sha(ROOT / 'docs/releases/v0.30.0-validation.json')},
              'android_device_tested':False,'github_published':publication.get('published',False),
              'remote_ci_executed':any(run['workflowName']=='Tests' and run['status']!='queued' for run in publication.get('runs',[])),
              'remote_ci_passed':bool(publication.get('remote_evidence')) and all(run['conclusion']=='success' for run in publication.get('runs',[]) if run['workflowName']=='Tests'),
              'publication_report':'docs/releases/v0.31.0-publication.json' if publication else None,'rendering_stalls_resolved':False,
              'artifacts':release['artifacts'],'packaged_tournament_modules':compiled,'first_board_frame_ms':probe['first_board_frame_ms']}
encoded = json.dumps(validation,ensure_ascii=False,indent=2)+'\n'
(OUT / 'artifact-checks.json').write_text(encoded,encoding='utf-8')
(ROOT / 'docs/releases/v0.31.0-validation.json').write_text(encoded,encoding='utf-8')
for source,target in [('archive-dark-393.png','tournament31-list.png'),('archive-filter-light-360.png','tournament31-filter.png'),('archive-downloading.png','tournament31-downloading.png')]:
    shutil.copy2(OUT / 'ui' / source, ROOT / 'docs/images' / target)
rows = '\n'.join(f'| `{name}` | {count} |' for name,count in counts.items())
text = f'''# 0.31 大赛棋谱库验证

最终新执行的验证记录共 **{sum(counts.values())} 项检查**，记录内无失败。包含 24 次连续开关筛选面板的 103 项检查；这些是场景断言次数，不代表同样数量的独立功能，也不能保证没有 bug。

| 验证项 | 检查数 |
|---|---:|
{rows}

四种尺寸（360×760、393×852、852×393、1100×800）与明暗模式下，检查完整列表、紧凑单行标题、底部筛选、可见复选框、带文字的固定操作、赛事多选、关键词／年份、取消／重置、逐批显示与列表位置。整行载入、取消旧下载、缓存损坏与重试使用实际界面事件；延迟和错误 HTTP 响应通过测试替身控制。

另外实际下载官方 `{official['id']}`，逐手校验并载入 {int(official['plies'])} 手，来源和着手哈希与目录相符，形成可重新离线读取的缓存。{fresh['updated_utc']} 再次核对官方目录，仍为 26 局，与内置条目一致。

首次核心测试暴露 PackedStringArray 没有 `all()` 方法的实现错误，已修复为显式 Array，原日志和失败断言保留在 `review/app/chessis31/core-first-attempt/`。首轮界面断言通过，但截图揭示标题挤成竖排、图标助手抹掉按钮文字；随后又发现深色主题默认未勾选图标不可见。均已修复并补充尺寸、文本和实际图像像素断言；保留首轮截图。

**一次偶发关闭失败仍待查因。** 在一次四尺寸回归中，关闭筛选后未返回列表，后续断言失败并触发空控件访问；原始日志保留在 `ui-second-attempt/`，该次运行没有有效的最终完成报告，目录中复制的旧 JSON 不作为该次通过证据。随后八次尺寸／主题开关、24 次连续开关及完整最终回归未复现。没有通过自动重试或删除断言把它当作已解决；测试现在会在再次失败时记录动画、窗口和控件状态。

完整棋谱解析移入私有线程；已测试本地校验中离开页面，以及在线下载中关闭、重新打开列表，旧结果均不能替换当前棋局。后台下载仍可保存缓存。缓存标记检查本地着手哈希；打开时仍进行全局合法性检查。

3D 棋盘重新执行 1,353 项相关检查，含四尺寸／明暗／翻转的格点命中、宽度和投影比例、实际亮度；保留持驹与棋盘布局。历史回放记录包含 {len(motion)} 个真实绘制帧样本。Windows 成品 {counts['package/windows-package-probe.json']} 项检查通过，首帧棋盘 {probe['first_board_frame_ms']} 毫秒；安装包实际运行筛选滑入、异步载入、回放、引擎和报告。APK 核对签名、ARM64、16 KiB 对齐、新模块和资源，未包含会员或测试数据。

本地验证没有全量重跑 195 局／23,115 手以及完整规则基准，相关规则、解析器和数据哈希与前版一致，保留历史证据且不计入本地总数。发布后云端补跑的结果独立记录在发布记录中。Windows 原有绘制停顿未做新的性能基准，不能据功能断言声称完全消除抖动。Android 设备列表仍为空，真机、系统选择器与后台恢复未实测。

运行 `./scripts/test_chessis31.ps1 -CoreOnly`、`./scripts/test_chessis31.ps1 -Network`、`./scripts/test_chessis31.ps1 -Probes chessis20,chessis30`。CI 包含核心和虚拟显示器入口。GitHub 发布、远端文件哈希、每日更新和云端测试的实际结果另见 [发布记录](releases/v0.31.0-publication.json)；上表仅统计本地构建验证。

详见 [使用说明](TOURNAMENT-ARCHIVE.md)、[机器可读记录](releases/v0.31.0-validation.json) 与 [完整差距](CHESSIS-PARITY.md)。
'''
(ROOT / 'docs/TESTING-0.31.md').write_text(text,encoding='utf-8')
(OUT / 'REPORT.md').write_text(text,encoding='utf-8')
print(json.dumps({'checks':sum(counts.values()),'failures':[],'intermittent_close_resolved':False},ensure_ascii=False))
