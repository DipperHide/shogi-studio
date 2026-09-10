"""Render a local evidence gallery; all pictures come from the running Godot app."""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis10'
ui = json.loads((OUT/'ui/results.json').read_text('utf8'))
engine = json.loads((OUT/'report-engine.json').read_text('utf8'))
regression = json.loads((OUT/'regression/results.json').read_text('utf8'))
package = json.loads((OUT/'package/windows-package-probe.json').read_text('utf-8-sig'))
verification = json.loads((OUT/'package/verification.json').read_text('utf8'))
release = json.loads((OUT/'release.json').read_text('utf8'))
for result in [ui, engine, regression, package, verification]:
    assert not result['failures'], result['failures']
names = {
    'settings-default': '分析设置 · 原 APK 默认值',
    'settings-time-picker': '编辑每步分析时间',
    'settings-configured': '分别设置两种报告',
    'settings-light': '浅色分析设置',
    'report-overview': '全屏木纹报告',
    'report-selected-move': '图表选中着手与候选线路',
    'report-candidate-preview': '独立候选线路预览',
    'report-pies': '双方分类统计与饼图',
    'report-category': '饼图筛选',
    'settings-360x760': '窄屏设置',
    'settings-852x393': '横屏设置',
    'settings-1100x800': '桌面设置',
    'report-light': '浅色主题下保留木纹报告',
}
cards = ''.join(f'<figure><a href="ui/{name}.png"><img loading="lazy" src="ui/{name}.png" alt="{html.escape(names.get(name,name))}"></a><figcaption>{html.escape(names.get(name,name))}</figcaption></figure>' for name in ui['screenshots'])
links = ''.join(f'<li><a href="../../../{a["path"]}">{Path(a["path"]).name}</a> · {a["bytes"]/1024/1024:.1f} MiB<small>SHA-256 {a["sha256"]}</small></li>' for a in release['artifacts'])
page = '''<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>将棋 0.10 分析验收</title><style>body{font-family:system-ui,sans-serif;background:#181818;color:#eee;max-width:1260px;margin:30px auto;padding:0 22px;line-height:1.7}h1{font-size:30px}a{color:#81b8ff}small{display:block;color:#aaa;overflow-wrap:anywhere}section{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:20px}figure{margin:0;background:#232323;border-radius:12px;padding:12px}img{width:100%;height:520px;object-fit:contain;object-position:top;background:#111}figcaption{color:#bbb;padding-top:8px}p{max-width:950px}</style>'''
page += '<h1>将棋 0.10 · 分析设置与整局报告</h1><p>依据原 APK 布局及已确认控制逻辑，补齐独立时间/深度模式、深度候选数量、智能分析与停止续跑；详细报告恢复全屏木纹与分区，支持曲线选点、候选预览返回和分类饼图筛选。</p>'
page += f'<p>真实引擎 {engine["checks"]} 项、新界面 {ui["checks"]} 项、综合回归 {regression["checks"]} 项、成品运行 {package["checks"]} 项通过；完整打包校验 {verification["checks"]} 项通过。另有 311 项 USI 与 37 项棋谱互换回归。</p>'
page += '<p>0.9 的三维修复与 195 局历史库保留。完整复刻仍在推进，原版实机逐屏对照与本轮 Android 真机验收尚未完成；十类高级判定、准确率、阶段分析等仍有缺口。</p><p><a href="REPORT.md">核验说明</a> · <a href="report-engine.json">实际引擎样本</a> · <a href="package/verification.json">成品校验</a> · <a href="../../../docs/CHESSIS-PARITY.md">完整实现对照</a></p>'
page += '<ul>'+links+'</ul><section>'+cards+'</section></html>'
(OUT/'index.html').write_text(page,encoding='utf8')
print(json.dumps({'ui':ui['checks'],'engine':engine['checks'],'regression':regression['checks'],'package':package['checks'],'verification':verification['checks']},ensure_ascii=False))
