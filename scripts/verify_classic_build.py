"""Record the classic build's completed tool and renderer verification."""
from pathlib import Path
import hashlib
import json
import shutil
import struct
import zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'review/app/v044'
SNAPSHOT=json.loads((OUT/'classic-source-snapshot.json').read_text(encoding='utf-8-sig'))
PROJECT=Path(SNAPSHOT['project'])
artifacts=[]
for rel in ['builds/classic-0.4.4/shogi-classic.apk','builds/classic-0.4.4/windows/ShogiClassic.exe']:
    path=ROOT/rel
    artifacts.append({'file':str(path),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
elf=[]
with zipfile.ZipFile(ROOT/'builds/classic-0.4.4/shogi-classic.apk') as archive:
    licenses=[n for n in archive.namelist() if 'CC-BY-SA-4.0-Ryoko' in n or 'ARTWORK-NOTICE' in n]
    assert len(licenses)==2, licenses
    for name in archive.namelist():
        if not name.endswith('.so'): continue
        data=archive.read(name)
        assert data[:4]==b'\x7fELF' and data[4]==2
        phoff=struct.unpack_from('<Q',data,32)[0]
        entsize,num=struct.unpack_from('<HH',data,54)
        alignment=[struct.unpack_from('<Q',data,phoff+i*entsize+48)[0] for i in range(num) if struct.unpack_from('<I',data,phoff+i*entsize)[0]==1]
        assert alignment and all(a>=16384 for a in alignment)
        elf.append({'file':name,'load_segment_alignment':alignment,'supports_16kb':True})
for name in ['rules-tests.json','history-motion-tests.json']:
    shutil.copy2(PROJECT.parent/'review/app'/name,OUT/name)
ui=json.loads((OUT/'ui-tests.json').read_text(encoding='utf-8-sig'))
assert ui['failures']==[] and ui['checks']==172
signature=(OUT/'apk-signature.log').read_text(encoding='utf-8-sig')
assert 'v2 scheme (APK Signature Scheme v2): true' in signature
assert 'v3 scheme (APK Signature Scheme v3): true' in signature
assert 'Verification successful' in (OUT/'apk-alignment.log').read_text(encoding='utf-8-sig')
assert 'SHOGI_SMOKE_OK' in (OUT/'windows-smoke.log').read_text(encoding='utf-8-sig')
assert not (OUT/'windows-smoke-errors.log').read_text(encoding='utf-8-sig').strip()
oracle=json.loads((OUT/'oracle-tests.json').read_text(encoding='utf-8-sig'))
assert oracle['failures']==[]
models=json.loads((ROOT/'review/validation.json').read_text(encoding='utf-8-sig'))
assert all(model['errors']==0 and model['warnings']==0 for model in models)
shutil.copy2(ROOT/'review/validation.json',OUT/'model-validation.json')
for name in ['main.gd','scripts/shogi_hand_layout.gd','scripts/shogi_history_motion.gd','assets/materials/quiet_wood.gdshader','assets/materials/polished_boxwood.gdshader','assets/materials/piece-ink.png','assets/shogi-scene.glb','assets/audio/wood-place.wav','assets/audio/wood-place.wav.import']:
    assert (PROJECT/name).read_bytes()==(ROOT/'godot'/name).read_bytes(),name
# Freeze the final exported source, including the corrected floating-point
# assertion and final artwork metadata, but excluding import caches.
SNAPSHOT['files']=[{'file':p.relative_to(PROJECT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(PROJECT.rglob('*')) if p.is_file() and '.godot' not in p.relative_to(PROJECT).parts]
(OUT/'classic-source-snapshot.json').write_text(json.dumps(SNAPSHOT,ensure_ascii=False,indent=2),encoding='utf-8')
material_dir=ROOT/'assets/materials/piece-v043'
materials=[{'file':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(material_dir.glob('*.png'))]
piece_audit=json.loads((ROOT/'review/app/v043/piece-material-audit.json').read_text(encoding='utf-8'))
assert piece_audit['failures']==[]
previous=json.loads((ROOT/'review/app/v043/classic-source-snapshot.json').read_text(encoding='utf-8'))
expected_glb=next(file['sha256'] for file in previous['files'] if file['file']=='assets/shogi-scene.glb')
assert hashlib.sha256((PROJECT/'assets/shogi-scene.glb').read_bytes()).hexdigest()==expected_glb
audio=json.loads((OUT/'audio-checks.json').read_text(encoding='utf-8'))
assert audio['clipped_samples']==0
assert hashlib.sha256((PROJECT/'assets/audio/wood-place.wav').read_bytes()).hexdigest()==audio['output_sha256']
report={'version':'0.4.4','edition':'将棋 · 木作','artifacts':artifacts,
    'source_snapshot':'classic-source-snapshot.json','isolated_from_portrait_app':True,
    'android':{'package':'org.shogistudio.classic','version_code':17,'debug_signature_verified':True,'signature_schemes':['v2','v3'],
        'alignment_16kb_verified':True,'elf':elf,'architectures':['arm64-v8a'],'min_sdk':24,'target_sdk':36,'device_tested':False,
        'bundled_artwork_license_files':licenses},
    'windows_smoke_passed':True,'rules_checks':671,'ui_checks':ui['checks'],'history_motion_checks':213,'oracle_positions':oracle['positions'],'oracle_moves':oracle['legal_moves_compared'],
    'models':{'count':len(models),'errors':0,'warnings':0},'calligraphy_faces':15,'art_captures':9,'ui_captures':ui['captures'],
    'piece_material_audit':'../v043/piece-material-audit.json','model_validation_reused_from':'0.4.3; identical GLB SHA-256','piece_atlas':[4096,4096],'face_tile':[1024,1024],'lossless_piece_color_and_ink':True,'triangles_per_piece':240,
    'hand_display':'Full board-size model per kind (1.0, formerly 0.65); a single numeral for quantities >= 2; all logical token identities retained',
    'generated_materials':materials,'material_prompts':'assets/materials/piece-v043/prompt.txt',
    'visual_references':['C:/Temp/codex-clipboard-6672e558-6797-456f-881f-17e92ab20893.png','C:/Temp/codex-clipboard-f1b81812-fbbe-4cbb-ac39-000a0afa12e1.png'],'reference_position_capture':'art-reference-position.png',
    'audio_sha256':hashlib.sha256((PROJECT/'assets/audio/wood-place.wav').read_bytes()).hexdigest(),
    'audio_validation':'audio-checks.json','audio_level_change_db':audio['level_change_db_equal_window'],'audio_duration_ms':audio['duration_ms'],
    'limits':['No Android device test','No direct listening test; sample-02 received targeted EQ, lower gain, shorter decay and lossless PCM import',
        'Reference-guided generated wood, original geometry and licensed Ryoko glyphs; visual fidelity judged from Windows captures, not claimed photo-identical',
        'Longitudinal and end-grain textures do not guarantee anatomical continuity across cuts',
        'GLES contact shadows use lightweight projected penumbrae, not ray tracing']}
(OUT/'build-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'version':report['version'],'artifacts':artifacts,'ui_checks':ui['checks']},ensure_ascii=True,indent=2))
