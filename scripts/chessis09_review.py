"""Build a local, self-contained gallery from actual Godot test evidence."""
import hashlib
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis09'
ui = json.loads((OUT/'ui/results.json').read_text(encoding='utf8'))
motion = json.loads((OUT/'motion-after/telemetry.json').read_text(encoding='utf8'))
historic = json.loads((OUT/'historic-validation.json').read_text(encoding='utf8'))
releases = []
for name in ['Shogi-0.9.0-android-arm64.apk', 'Shogi-0.9.0-windows-x64.zip']:
    path = ROOT/'builds'/name
    if path.exists():
        releases.append({'name':name,'size':path.stat().st_size,'sha256':hashlib.file_digest(path.open('rb'),'sha256').hexdigest()})
(OUT/'release.json').write_text(json.dumps({'version':'0.9.0','artifacts':releases,'ui_checks':ui['checks'],'motion_checks':motion['checks'],'historic_games':historic['games'],'historic_plies':historic['plies']},indent=2),encoding='utf8')
cards = []
for name in ui['screenshots']:
    cards.append(f'<figure><a href="ui/{name}.png"><img loading="lazy" src="ui/{name}.png" alt="{name}"></a><figcaption>{name}</figcaption></figure>')
for name in ['2-commit','2-frame-25','2-frame-50','2-frame-75','2-landed','drag-release','drag-settle']:
    cards.append(f'<figure><a href="motion-after/{name}.png"><img loading="lazy" src="motion-after/{name}.png" alt="{name}"></a><figcaption>3D · {name}</figcaption></figure>')
links = ''.join(f'<li><a href="../../../builds/{r["name"]}">{r["name"]}</a> · {r["size"]/1024/1024:.1f} MiB<small>{r["sha256"]}</small></li>' for r in releases)
page = '''<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>将棋 0.9 验收</title><style>body{font-family:system-ui,sans-serif;background:#181818;color:#eee;max-width:1300px;margin:32px auto;padding:0 22px;line-height:1.7}h1{font-size:32px}a{color:#77b2ff}small{display:block;overflow-wrap:anywhere;color:#aaa}section{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:22px}figure{margin:0;background:#232323;border-radius:12px;padding:12px}img{display:block;width:100%;height:510px;object-fit:contain;object-position:top;background:#111}figcaption{color:#aaa;font-size:13px;padding-top:10px}p{max-width:950px}</style>'''
page += f'<h1>将棋 0.9 · 分析、3D 与历史赛事</h1><p>候选线路逐行显示并可独立预览；整局报告保留在棋盘下方。历史库包含 {historic["games"]} 局完整官方对局，{historic["plies"]:,} 手全部通过规则和终局校验。</p><p>{ui["checks"]} 项新版界面检查、{motion["checks"]:,} 项动画检查通过。完整复刻仍在推进；原版实机逐屏比对及 Android 真机验收尚未完成。</p><p><a href="REPORT.md">核验说明</a> · <a href="historic-validation.json">逐局来源与最终局面</a> · <a href="motion-after/telemetry.json">连续帧遥测</a> · <a href="package/windows-package-probe.json">成品运行检查</a></p><ul>{links}</ul><section>'+''.join(cards)+'</section></html>'
(OUT/'index.html').write_text(page,encoding='utf8')
print(json.dumps({'ui_checks':ui['checks'],'motion_checks':motion['checks'],'games':historic['games'],'artifacts':len(releases)},ensure_ascii=False))
