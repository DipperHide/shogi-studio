"""Fit licensed vector outlines using the existing raster alpha bounds.

Only SVG metadata is edited; source geometry and all original files are retained.
"""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
ET.register_namespace('', 'http://www.w3.org/2000/svg')
receipts=[]
for original in (ROOT/'assets/calligraphy/ryoko/glyphs').glob('*.svg'):
    image=Image.open(ROOT/'assets/calligraphy/ryoko/masks'/f'{original.stem}.png')
    bounds=image.getchannel('A').getbbox()
    assert bounds
    tree=ET.parse(original); root=tree.getroot()
    x,y,w,h=map(float,root.attrib['viewBox'].split())
    left,top,right,bottom=bounds
    padx=w*.012;pady=h*.012
    view=[x+left/image.width*w-padx,y+top/image.height*h-pady,(right-left)/image.width*w+padx*2,(bottom-top)/image.height*h+pady*2]
    root.set('viewBox',' '.join(f'{v:.8f}' for v in view))
    root.set('width','512');root.set('height',str(round(512*view[3]/view[2])))
    root.set('fill','#ffffff')
    for node in root.iter():
        if 'style' in node.attrib: node.set('style',node.attrib['style'].replace('#000000','#ffffff'))
    output=ROOT/'godot/assets/glyphs'/original.name
    tree.write(output,encoding='utf-8',xml_declaration=True)
    config=Path(str(output)+'.import')
    if config.exists(): config.write_text(config.read_text().replace('mipmaps/generate=false','mipmaps/generate=true'),encoding='utf-8')
    receipts.append({'name':original.stem,'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'viewbox':view})
(ROOT/'godot/assets/glyphs/provenance.json').write_text(json.dumps({'author':'LuffyKudo','license':'CC-BY-SA-4.0','source':'https://github.com/LuffyKudo/Shogi-Themes/tree/af44470b85b160fa01e23b2a63d8a91232cf34c3/Ryoko','modifications':'Cropped SVG viewBox to existing alpha bounds, white fill for theme tinting, mipmapped display. Outlines unchanged.','glyphs':receipts},indent=2),encoding='utf-8')
print(f'Prepared {len(receipts)} fitted vector faces')
