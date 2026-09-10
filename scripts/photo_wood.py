"""Reference-guided image textures, with deterministic color/crop preparation.

No synthetic sine grain or painted lighting is added. User-authorized cropping
and color normalization preserve the generated wood's photographic structure.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'assets/materials/photographic-v042'

def material(name, size, base, contrast=1.0, crop=None):
    image = Image.open(SOURCE/name).convert('RGB')
    if crop:
        image = image.crop(crop)
    image = image.resize(size, Image.Resampling.LANCZOS)
    rgb = np.asarray(image).astype(np.float32)
    # Separate material color from generated exposure. Preserve fine fibers
    # and natural chroma variation instead of tinting everything with sepia.
    mean = rgb.mean(axis=(0,1))
    detail = rgb-mean
    return Image.fromarray(np.clip(np.array(base)+detail*contrast,0,255).astype('uint8'))

def wood(w, h, base, seed, contrast=1.0):
    # Different clean areas of one continuous photographed surface per face.
    rng = np.random.default_rng(seed)
    width, height = Image.open(SOURCE/'kaya-long-grain.png').size
    fraction = 0.65 if seed >= 100 else 1.0
    cw, ch = int(width*fraction), int(height*fraction)
    x, y = int(rng.integers(0,width-cw+1)), int(rng.integers(0,height-ch+1))
    return material('kaya-long-grain.png',(w,h),base,contrast,(x,y,x+cw,y+ch))

def board_side_atlas():
    # End cuts occupy front/back; longitudinal cuts occupy left/right.
    # Same color calibration keeps the four cuts part of one solid block.
    atlas = Image.new('RGB',(2048,512))
    end = material('kaya-end-grain.png',(512,512),(188,148,88),0.9)
    long = material('kaya-long-grain.png',(512,512),(188,148,88),0.9)
    for face, image in enumerate([end,long,ImageOps.mirror(end),ImageOps.mirror(long)]):
        atlas.paste(image,(face*512,0))
    return atlas
