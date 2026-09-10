"""Create a local QA gallery and release hashes; never modifies user data."""
from pathlib import Path
import hashlib, html, json
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis'
report = json.loads((OUT / 'results.json').read_text('utf8'))
labels = {'board-393x852':'竖屏棋盘','board-360x760':'小屏棋盘','board-1100x800':'桌面棋盘','board-852x393':'横屏棋盘','capture-drop':'吃子 / 升变 / 打入','replay-annotation':'回放与标记','drawer':'侧栏','play':'对局模式','bots':'六档电脑','setup':'开局设置','settings':'设置','board-settings':'外观设置','engine-settings':'引擎设置','editor':'局面编辑','openings':'开局练习','more':'更多操作','export':'棋谱导出','backup':'备份','game-report':'整局报告','live-analysis':'实时分析','board-light':'浅色棋盘','settings-light':'浅色设置'}
cards = ''.join(f'<figure><figcaption>{html.escape(labels.get(name,name))}</figcaption><a href="{name}.png"><img src="{name}.png" alt="{html.escape(labels.get(name,name))}" loading="lazy"></a></figure>' for name in report['screenshots'])
(OUT/'index.html').write_text('''<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>将棋 0.8 · 验证画面</title><style>body{margin:0;background:#eeeae4;color:#302820;font:16px system-ui}header{padding:36px 5vw;background:#25180f;color:#f3ede4}h1{font-size:28px;margin:0 0 12px}p{max-width:950px;line-height:1.7}main{padding:24px 4vw;display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px}figure{margin:0;padding:16px;background:#fffaf3;border-radius:12px}figcaption{margin-bottom:12px;font-weight:600}img{display:block;width:100%;max-height:660px;object-fit:contain;object-position:top}a{color:#238cd4}</style><header><h1>将棋 0.8 · 界面与功能验证</h1><p>本页为 Windows 渲染的响应式界面截图，不能替代手机实测或原版逐屏对照。参考为 Chessis 20.9 的 APK 布局资源；当前仍有未复制功能。</p><p>''' + str(report['checks']) + ' 项交互检查；失败 ' + str(len(report['failures'])) + '。<a href="../../../docs/CHESSIS-PARITY.md">实现差距对照</a></p></header><main>' + cards + '</main></html>',encoding='utf8')
hashes = {}
for file in (ROOT/'builds').glob('Shogi-0.8.0-*'):
    if not file.is_file(): continue
    sha = hashlib.sha256()
    with file.open('rb') as stream:
        while chunk := stream.read(1024*1024): sha.update(chunk)
    hashes[file.name] = {'bytes':file.stat().st_size,'sha256':sha.hexdigest()}
(OUT/'release-manifest.json').write_text(json.dumps(hashes,indent=2),encoding='utf8')
print(json.dumps(hashes,indent=2))
