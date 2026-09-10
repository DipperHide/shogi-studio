"""Record the actual delivered piece images and embedded glTF resources."""
from pathlib import Path
from PIL import Image
import hashlib, io, json, struct

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'review/app/v043'
OUT.mkdir(parents=True,exist_ok=True)
raw=(ROOT/'models/shogi-scene.glb').read_bytes()
json_size=struct.unpack_from('<I',raw,12)[0]
doc=json.loads(raw[20:20+json_size])
binary=raw[28+json_size:]
embedded=[]
for item in doc['images']:
    if 'Boxwood' not in item['name']: continue
    view=doc['bufferViews'][item['bufferView']]
    data=binary[view['byteOffset']:view['byteOffset']+view['byteLength']]
    image=Image.open(io.BytesIO(data))
    assert image.format=='PNG',item['name']
    if 'calligraphy' in item['name']: assert image.size==(4096,4096)
    embedded.append({'name':item['name'],'format':image.format,'size':list(image.size),'sha256':hashlib.sha256(data).hexdigest()})
assert len(embedded)==2
mask=Image.open(ROOT/'godot/assets/materials/piece-ink.png')
assert mask.size==(4096,4096)
faces=[]
for index in range(16):
    tile=mask.crop((index%4*1024,index//4*1024,index%4*1024+1024,index//4*1024+1024))
    bounds=tile.getbbox()
    if index==15:
        assert bounds is None
        continue
    assert bounds and bounds[0]>0 and bounds[1]>0 and bounds[2]<1024 and bounds[3]<1024
    faces.append({'face':index,'ink_bounds':list(bounds),'sha256':hashlib.sha256(tile.tobytes()).hexdigest()})
assert len({face['sha256'] for face in faces})==15
counts={mesh['name']:sum(doc['accessors'][p['attributes']['POSITION']]['count']//3 for p in mesh['primitives']) for mesh in doc['meshes'] if mesh['name'].startswith('Piece_')}
report={'source_texture':'assets/materials/piece-v043/tsuge-fine-grain.png','embedded_images':embedded,'atlas_pixels':4096*4096,'face_pixels':1024*1024,'faces':faces,'piece_triangles':counts,'failures':[]}
(OUT/'piece-material-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'lossless_images':len(embedded),'distinct_faces':len(faces),'atlas_size':4096,'piece_triangles':counts}))
