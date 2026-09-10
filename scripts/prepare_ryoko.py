"""Prepare attributed, reproducible glyph-only SVGs; retain untouched originals.

The derivative glyph artwork and resulting face atlas are CC BY-SA 4.0.
This script edits SVG structure, not the user's photographs or screenshots.
"""
from pathlib import Path
import copy
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/calligraphy/ryoko'
SVG = 'http://www.w3.org/2000/svg'
ET.register_namespace('', SVG)

def clean(node):
    for child in list(node):
        tag = child.tag.split('}')[-1]
        if tag not in ('g', 'path'):
            node.remove(child)
        elif tag == 'path' and 'fill:#000000' not in child.get('style', ''):
            node.remove(child)
        else:
            clean(child)
    for key in list(node.attrib):
        if key.startswith('{'):
            del node.attrib[key]

files = []
(DEST / 'glyphs').mkdir(exist_ok=True)
for path in sorted((DEST / 'source').glob('*.svg')):
    original = ET.parse(path).getroot()
    _, _, w, h = map(float, original.get('viewBox').split())
    content = copy.deepcopy(original)
    clean(content)
    # The source set includes a wooden body and, on kings, a small inscription
    # on its bottom edge. The playable top-face glyph excludes that edge.
    root = ET.Element(f'{{{SVG}}}svg', {'viewBox': f'0 0 {w} {h*.82}', 'width': '1024', 'height': str(round(1024*h*.82/w))})
    for child in content:
        root.append(child)
    derived = DEST / 'glyphs' / path.name
    ET.ElementTree(root).write(derived, encoding='utf-8', xml_declaration=True)
    files.append({'file': str(path.relative_to(DEST)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                  'glyph': str(derived.relative_to(DEST)), 'glyph_sha256': hashlib.sha256(derived.read_bytes()).hexdigest()})

receipt = {'name':'Ryoko style shogi face glyphs', 'author':'LuffyKudo', 'license':'CC-BY-SA-4.0',
           'license_url':'https://creativecommons.org/licenses/by-sa/4.0/',
           'source':'https://github.com/LuffyKudo/Shogi-Themes/tree/af44470b85b160fa01e23b2a63d8a91232cf34c3/Ryoko',
           'source_commit':'af44470b85b160fa01e23b2a63d8a91232cf34c3',
           'modifications':'Removed illustrated wooden body and edge inscription; retained original black glyph outlines; fitted to project piece geometry and composited onto original wood.',
           'files':files}
(DEST/'provenance.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'Prepared {len(files)} glyphs; source hashes and attribution retained.')
