from pathlib import Path
import base64
ROOT=Path(__file__).resolve().parents[1]
fragment=(ROOT/'review/shogi-review.template.html').read_text(encoding='utf8')
fragment=fragment.replace('__MODEL_BASE64__',base64.b64encode((ROOT/'models/shogi-scene.glb').read_bytes()).decode())
target=Path(r'C:\Users\jinda\.codex\visualizations\2026\09\06\01a074c2-1e06-7980-8ef4-0de21831acc8\shogi-model-review.html')
target.parent.mkdir(parents=True,exist_ok=True)
target.write_text(fragment,encoding='utf8')
assert target.stat().st_size<1000000
# A local companion for offline inspection of the exact same review fragment.
local=fragment.replace('https://esm.sh/three@0.180.0/examples/jsm/','/node_modules/three/examples/jsm/').replace('https://esm.sh/three@0.180.0','/node_modules/three/build/three.module.js')
shell='''<!doctype html><html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>将棋模型审核 · v1</title><script type="importmap">{"imports":{"three":"/node_modules/three/build/three.module.js"}}</script><style>body{margin:0;padding:24px;background:#f1eee7;color:#39362e;font:15px/1.5 system-ui,"Microsoft YaHei",sans-serif}#shogi-art-v1{max-width:1280px;margin:auto}.viz-controls,.viz-row{display:flex;align-items:center;gap:12px;flex-wrap:wrap}.viz-row{justify-content:space-between}.btn,.form-select{font:inherit;padding:9px 16px;border:1px solid #c8c2b6;border-radius:6px;background:#fffdf7;color:#39362e;cursor:pointer}.btn[aria-pressed=true]{background:#454e36;color:white;border-color:#454e36}.form-label{display:flex;align-items:center;gap:8px}.text-small{font-size:13px;color:#696658}@media(max-width:500px){body{padding:12px}.viz-controls{gap:6px}.btn{padding:9px 10px}}</style></head><body>'''
(ROOT/'review/index.html').write_text(shell+local+'</body></html>',encoding='utf8')
print(f'Inline review: {target.stat().st_size} bytes')
