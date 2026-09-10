"""Create a fresh classic-only export project without changing the shared app.

The shared directory also contains an independently developed portrait app.
Every run uses a fresh staging directory, so parallel exports cannot collide.
"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.4.4'
stage = Path(tempfile.mkdtemp(prefix='.classic-build-',dir=ROOT))
project = stage/'godot'
shutil.copytree(ROOT/'godot',project,ignore=shutil.ignore_patterns('.godot','android','addons','minimal.tscn*','shogi_minimal.gd*','minimal_test.gd*'))
config = project/'project.godot'
text = config.read_text(encoding='utf-8-sig')
text = re.sub(r'run/main_scene="[^"]+"','run/main_scene="res://main.tscn"',text)
text = re.sub(r'config/name="[^"]+"','config/name="将棋 · 木作"',text)
for key,value in {'viewport_width':1280,'viewport_height':720,'window_width_override':1280,'window_height_override':720,'min_width':960,'min_height':540}.items():
    text = re.sub(r'window/size/'+key+r'=\d+',f'window/size/{key}={value}',text)
text = re.sub(r'window/handheld/orientation=\d+','window/handheld/orientation=0',text)
text = re.sub(r'\[editor_plugins\][\s\S]*?(?=\[|\Z)','',text)
config.write_text(text,encoding='utf-8')
presets = project/'export_presets.cfg'
text = presets.read_text(encoding='utf-8-sig')
text = re.sub(r'gradle_build/use_gradle_build=true','gradle_build/use_gradle_build=false',text)
text = text.replace(',assets/engine/*.bin','').replace('exclude_filter="tests/*"','exclude_filter="tests/*,assets/engine/*"')
text = re.sub(r'version/code=\d+','version/code=17',text)
text = re.sub(r'version/name="[^"]+"',f'version/name="{VERSION}"',text)
text = re.sub(r'application/(file|product)_version="[^"]+"',lambda m:f'application/{m[1]}_version="{VERSION}.0"',text)
text = re.sub(r'package/unique_name="[^"]+"','package/unique_name="org.shogistudio.classic"',text)
text = re.sub(r'package/name="[^"]+"','package/name="将棋 · 木作"',text)
presets.write_text(text,encoding='utf-8')
report = ROOT/'review/app/v044'
report.mkdir(parents=True,exist_ok=True)
for filename in ['art_review.gd','ui_test.gd']:
    path = project/'tests'/filename
    path.write_text(path.read_text(encoding='utf-8-sig').replace('res://../review/app/v044',report.as_posix()),encoding='utf-8')
(stage/'review/app').mkdir(parents=True,exist_ok=True)
snapshot = {'project':str(project),'files':[{'file':p.relative_to(project).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(project.rglob('*')) if p.is_file()]}
(report/'classic-source-snapshot.json').write_text(json.dumps(snapshot,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'project':str(project),'version':VERSION,'output':str(ROOT/'builds'/f'classic-{VERSION}')},ensure_ascii=True))
