from pathlib import Path
import zipfile, shutil, json, re
root=Path.home()/'Development';tools=root/'Tools';sdk=root/'AndroidSDK'
def extract(archive,dest,prefix,allowed=None):
    dest.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            if not info.filename.startswith(prefix):continue
            name=info.filename[len(prefix):]
            if not name or (allowed and not any(name.startswith(x) for x in allowed)):continue
            if '..' in Path(name).parts or Path(name).is_absolute():raise ValueError(name)
            target=dest/name
            if info.is_dir():target.mkdir(parents=True,exist_ok=True);continue
            target.parent.mkdir(parents=True,exist_ok=True)
            with z.open(info) as src,target.open('wb') as out:shutil.copyfileobj(src,out)
manifest=json.loads((root/'toolchain-install.json').read_text())
ver=manifest['godotVersion']
extract(next((root/'Downloads').glob('commandlinetools-win-*.zip')),sdk/'cmdline-tools/latest','cmdline-tools/')
extract(root/f'Downloads/Godot_v{ver}-stable_export_templates.tpz',tools/f'Godot/editor_data/export_templates/{ver}.stable','templates/',['android','windows','version.txt'])
jdk=next(tools.glob('jdk-17*'))
settings=tools/f'Godot/editor_data/editor_settings-{ver.rsplit(".",1)[0]}.tres'
s=settings.read_text(encoding='utf8')
values={'export/android/java_sdk_path':jdk.as_posix(),'export/android/android_sdk_path':sdk.as_posix(),'filesystem/import/blender/blender_path':(tools/f'blender-{manifest["blenderVersion"]}-windows-x64').as_posix()}
for key,val in values.items():
    line=key+' = '+json.dumps(val)
    if re.search('^'+re.escape(key)+' = .*$',s,re.M):s=re.sub('^'+re.escape(key)+' = .*$',lambda m:line,s,flags=re.M)
    else:s+='\n'+line+'\n'
settings.write_text(s,encoding='utf8')
manifest.update(sdk=str(sdk),jdk=str(jdk),godot=str(tools/f'Godot/Godot_v{ver}-stable_win64.exe'),blender=str(tools/f'blender-{manifest["blenderVersion"]}-windows-x64/blender.exe'),studio=str(tools/'android-studio/bin/studio64.exe'))
(root/'toolchain.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
print('Configured SDK, JDK, Godot self-contained templates and Blender path.')
