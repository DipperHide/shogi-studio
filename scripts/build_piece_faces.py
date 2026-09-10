"""Composite licensed Ryoko face outlines onto original boxwood textures.

Glyph outlines and the derived atlas: LuffyKudo, CC BY-SA 4.0.
See assets/calligraphy/ryoko/provenance.json and source/LICENSE.txt.
"""
from PIL import Image, ImageOps
import numpy as np

TILE = 1024
ATLAS = TILE*4

def boxwood(root, index, size=(TILE,TILE)):
    source = Image.open(root/'assets/materials/piece-v043/tsuge-fine-grain.png').convert('RGB')
    # Every face keeps dense miniature-scale fibers; never stretch board grain
    # across a piece. Rotate no faces: fibers follow the long axis of the wood.
    width, height = source.size
    span = int(min(width,height)*0.88)
    x = (index*53) % (width-span+1)
    y = (index*29) % (height-span+1)
    tile = source.crop((x,y,x+span,y+span)).resize(size,Image.Resampling.LANCZOS)
    rgb = np.asarray(tile).astype(np.float32)
    tone = (index*7 % 5)-2
    rgb = np.array([207+tone,182+tone,144+tone])+(rgb-rgb.mean(axis=(0,1)))*0.78
    return Image.fromarray(np.clip(rgb,0,255).astype('uint8'))

FACES = ['Ousho','Gyokusho','Hisha','Kakugyo','Kinsho','Ginsho','Keima',
         'Kyosha','Fu','Ryu','Uma','Narigin','Narikei','Narikyo','Tokin',None]

def piece_atlas(root, font_path, wood):
    atlas = Image.new('RGB', (ATLAS,ATLAS))
    ink_atlas = Image.new('L', (ATLAS,ATLAS))
    for index, name in enumerate(FACES):
        tile = boxwood(root,index)
        face = Image.new('L', (TILE,TILE))
        if name:
            mask = Image.open(root/'assets/calligraphy/ryoko/masks'/f'{name}.png').getchannel('A')
            assert mask.getbbox(), f'Missing glyph: {name}'
            mask = mask.crop(mask.getbbox())
            # Keep each calligrapher-drawn face as a whole, preserving the
            # relationship between characters and their original outlines.
            max_w, max_h = (664,730) if index < 8 else (660,694)
            factor = min(max_w/mask.width, max_h/mask.height)
            mask = mask.resize((round(mask.width*factor),round(mask.height*factor)),Image.Resampling.LANCZOS)
            face.paste(mask,((TILE-mask.width)//2,round(536-mask.height/2)))
        tile.paste((19,13,8),(0,0),face)
        pos = ((index%4)*TILE,(index//4)*TILE)
        atlas.paste(tile,pos)
        ink_atlas.paste(face,pos)
    return atlas, ink_atlas
