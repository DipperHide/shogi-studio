"""Package the verified unified app; retain earlier builds and all source data."""
import hashlib
import argparse
import json
import re
import shutil
import zipfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--report-directory', default='review/app/unified')
parser.add_argument('--windows-directory', default='builds/windows')
arguments = parser.parse_args()
report_directory = ROOT / arguments.report_directory
report_directory.mkdir(parents=True, exist_ok=True)
VERSION = re.search(r'config/version="([^"]+)"', (ROOT/'godot/project.godot').read_text('utf-8')).group(1)
VERSION_CODE = int(re.search(r'version/code=(\d+)', (ROOT/'godot/export_presets.cfg').read_text('utf-8')).group(1))
output = ROOT/'builds'
windows = ROOT/arguments.windows_directory
archive = output/f'Shogi-{VERSION}-windows-x64.zip'
android = output/f'Shogi-{VERSION}-android-arm64.apk'
shutil.copy2(output/'shogi-playable.apk', android)
(windows/'README.txt').write_text('''将棋 · 静棋 / Shogi Studio

运行 Shogi.exe。请保留 engines 文件夹，专业引擎与 NNUE 需要它。
Run Shogi.exe. Keep the engines folder beside it.

菜单 > 设置：切换极简／木制、明暗、中／日／英文与落子节奏。
Menu > Settings: appearance, color mode, language and move pace.
点击或拖动棋子；方向键与回车也可行棋。Esc 打开菜单。
Click or drag a piece; arrow keys and Enter also work. Esc opens the menu.

菜单 > 互动教程：按基础入门、开局进阶学习，支持移动练习、动画示范与错题复习。
Menu > Lessons: interactive exercises and replay. Lesson text is in Chinese.

当前对局与棋谱保存在原来的 ShogiStudio 用户数据目录。
Saved games remain in the ShogiStudio user data directory.
作品、字体和引擎署名可从菜单 > 设置 > 引擎与署名查看。
Attributions are available in Settings > Engine & credits.
''',encoding='utf-8')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
    for path in sorted(windows.rglob('*')):
        if path.is_file() and path.name != 'Shogi.console.exe':
            bundle.write(path, path.relative_to(windows).as_posix())
with zipfile.ZipFile(archive) as bundle:
    assert bundle.testzip() is None
    for required in ['Shogi.exe', 'engines/yaneuraou/YaneuraOu.exe', 'engines/yaneuraou/EngineHost.exe', 'engines/yaneuraou/eval/nn.bin', 'engines/yaneuraou/yaneuraou-source.zip']:
        assert required in bundle.namelist(), required
with zipfile.ZipFile(android) as apk:
    assert apk.testzip() is None
    native = [x for x in apk.namelist() if x.startswith('lib/')]
    assert native and all(x.startswith('lib/arm64-v8a/') for x in native)
    assert 'lib/arm64-v8a/libyaneuraou.so' in native

def receipt(path):
    return {'path':path.relative_to(ROOT).as_posix(), 'bytes':path.stat().st_size, 'sha256':hashlib.file_digest(path.open('rb'),'sha256').hexdigest()}

source_paths = [ROOT/'godot/project.godot', ROOT/'godot/export_presets.cfg', ROOT/'godot/minimal.tscn']
source_paths += sorted((ROOT/'godot/scripts').glob('*.gd'))
source_paths += sorted((ROOT/'android-plugin/src').rglob('*.java'))
source_paths += sorted((ROOT/'godot/assets/locales').glob('*.json'))
source_paths += sorted((ROOT/'godot/courses').glob('*.json'))
source_paths += sorted((ROOT/'godot/assets/data').glob('*.json'))
source_paths += sorted((ROOT/'godot/assets/data').glob('*.txt'))
source_paths += sorted((ROOT/'godot/assets/reference-ui').glob('*.json'))
source_paths += sorted((ROOT/'godot/assets/reference-ui').glob('*.svg'))
source_paths += sorted((ROOT/'godot/assets/reference-ui').glob('*.png'))
source_paths += sorted((ROOT/'godot/config').glob('*.json'))
source_paths += sorted((ROOT/'godot/assets/brand').glob('*.svg'))
source_paths += sorted((ROOT/'godot/assets/brand').glob('*.png'))
report={'version':VERSION, 'created_utc':datetime.now(timezone.utc).isoformat(), 'android_package':'org.shogistudio.artpreview', 'android_version_code':VERSION_CODE, 'android_device_tested':False, 'artifacts':[receipt(archive),receipt(android)], 'runtime_sources':[receipt(p) for p in source_paths]}
(report_directory/'release.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
for artifact in report['artifacts']: print(json.dumps(artifact,ensure_ascii=True))
