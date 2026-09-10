"""Collect 0.12 evidence without reusing old releases' test results."""
from pathlib import Path
import hashlib
import html
import json
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis12'
release = json.loads((OUT / 'release.json').read_text('utf-8'))
assert release['version'] == '0.12.0'
proofs = {
    'metrics.json': '准确率公式、空样本、先后手对称、定式／唯一合法着排除、将棋阶段边界',
    'ui/results.json': '140 手历史对局真实引擎报告、阶段点击、暂停续跑、四种尺寸与明暗主题',
    'engine-regression/report-engine.json': 'USI 时间／深度预算、多候选、停止／继续与原局隔离',
    'report-ui/results.json': '旧报告设置、候选预览、曲线选择和分类筛选',
    'coach-replay-ui/ui-tests.json': '悔棋、持驹比例、回放动画、续下、教程、实际坏棋提醒与线路',
    'regression/results.json': '既有界面与对弈流程',
    'package/windows-package-probe.json': '实际导出 Windows 程序的引擎、课程、历史棋谱、报告与阶段明细',
    'package/verification.json': 'APK 签名、16 KB 对齐、版本、原生引擎和课程资源',
}
counts = {}
for path in proofs:
    data = json.loads((OUT / path).read_text('utf-8-sig'))
    assert not data['failures'], path
    counts[path] = len(data['checks']) if isinstance(data['checks'], list) else int(data['checks'])
for path in OUT.glob('*.err'):
    assert not path.read_text('utf-8-sig').strip(), path
assert not (OUT / 'package/package-stderr.log').read_text('utf-8-sig').strip()
probe = json.loads((OUT / 'package/windows-package-probe.json').read_text('utf-8'))

def sha(data):
    return hashlib.sha256(data).hexdigest()

for record in release['runtime_sources'] + release['artifacts']:
    assert sha((ROOT / record['path']).read_bytes()) == record['sha256'], record['path']
apk_record = next(a for a in release['artifacts'] if a['path'].endswith('.apk'))
zip_record = next(a for a in release['artifacts'] if a['path'].endswith('.zip'))
with ZipFile(ROOT / apk_record['path']) as archive:
    for relative in ['assets/brand/studio-icon.svg', 'config/membership.json']:
        assert archive.read('assets/' + relative) == (ROOT / 'godot' / relative).read_bytes()
    compiled = {}
    for name in ['shogi_report', 'shogi_report_metrics', 'shogi_report_phases', 'shogi_report_chart']:
        data = archive.read('assets/scripts/' + name + '.gdc')
        assert len(data) > 100
        compiled[name] = sha(data)
with ZipFile(ROOT / zip_record['path']) as archive:
    assert sha(archive.read('Shogi.exe')) == probe['executable_sha256']
    assert sha((ROOT / 'builds/windows-0.12.0/Shogi.exe').read_bytes()) == probe['executable_sha256']

receipt = {'checks': counts, 'compiled_android_reports': compiled,
           'apk_icon_and_config_match_source': True, 'windows_zip_matches_tested_executable': True,
           'runtime_sources_match_release_receipt': True, 'android_device_tested': False,
           'real_payments_tested': False}
(OUT / 'artifact-checks.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2), 'utf-8')
table = '\n'.join(f'| {proofs[p]} | {n} | [{p}]({p}) |' for p, n in counts.items())
artifacts = '\n'.join(f"- `{a['path']}`：{a['bytes']:,} 字节，SHA-256 `{a['sha256']}`。" for a in release['artifacts'])
report = f'''# 将棋 0.12.0 验证记录

本轮继续对照用户提供的 Chessis 20.9 APK，完成与图表对齐的开局／中局／终局评分条、双方准确率、可点击的阶段明细、阶段复盘入口、可选 ACPL，以及报告 JSON 中的计算输入与汇总。

“最佳”现在要求实际着手与引擎首选一致。原始分数变化保留为 observed_loss；最佳着不再因不同局面搜索结果的波动被列为失误。关键时刻按实际胜率损失排序。图表增加双方明暗面积、中央线与阶段分界。木纹报告在切换明暗主题后保留文字对比度。

准确率聚合沿用可核实的参考公式，评分尺度与阶段判断显式适配将棋。排除内置定式示例的实际匹配前缀与唯一合法着；无有效样本显示 `—`。将棋持驹不会因盘上子力减少而被误判成国际象棋残局。计算与参考边界见 [REPORT-ANALYSIS.md](../../../docs/REPORT-ANALYSIS.md)。

## 本轮验证

| 范围 | 检查数 | 证据 |
|---|---:|---|
{table}

上述结果均为本轮执行。UI 新报告使用离线赛事库中的实际 140 手对局和 YaneuraOu 深度 3 搜索，测试的是数据流与交互；截图中的分数不是棋手水平评定。完整逐手引擎结果、统计与棋谱来源见 `ui/actual-report.json`。产品默认快速报告深度仍为 14。

第一次界面检查发现阶段分数在窄屏按字符换行，已修复为保留宽度的单行数字。后手准确率点击的首次测试在布局结束前滚动，点击落在可视区域之外；测试现在等待布局，并断言目标确实位于滚动窗口内。最终全部检查通过，所有最终 UI／成品日志没有脚本错误。

Windows 成品首张棋盘在 {probe['first_board_frame_ms']} 毫秒绘制；实际引擎返回合法着手。APK 报告脚本字节码存在、龙王 SVG／会员配置与源码逐字节匹配、Windows ZIP 内程序与实际测试程序散列一致，详见 `artifact-checks.json`。

## 成品

{artifacts}

包名 `org.shogistudio.artpreview`，版本 0.12.0，versionCode 30，沿用原开发签名与数据目录。Windows 使用独立目录 `builds/windows-0.12.0`。

## 尚未完成

完整复制目标仍在进行。当前是六类着手，尚未迁移精彩／锐利、遗漏取胜、完整循环权重、估计 Elo 和完整故事引擎；全部缺口见 [CHESSIS-PARITY.md](../../../docs/CHESSIS-PARITY.md)。原版只做了静态检查，没有可运行分包进行逐屏验收。

会员功能仍缺支付渠道、商户与订单后台，当前不能实际收款。本轮没有连接 Android 设备，APK 尚未真机实测；历史真机结果不计作本轮验收。
'''
(OUT / 'REPORT.md').write_text(report, 'utf-8')
cards = [('ui/report-acpl.png', '真实历史对局：曲线、阶段和双方准确率'),
         ('ui/phase-detail-sente.png', '阶段明细与复盘入口'),
         ('ui/phase-detail-gote.png', '后手阶段明细'),
         ('ui/partial-phase-detail.png', '部分分析：不虚构尚未分析阶段的分数'),
         ('coach-replay-ui/bad-move-warning.png', '既有真实引擎坏棋提醒回归'),
         ('package/report-phase.png', '实际导出的 Windows 成品')]
body = ''.join(f'<figure><img src="{p}" loading="lazy"><figcaption>{html.escape(c)}</figcaption></figure>' for p, c in cards)
page = f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>将棋 0.12 验证</title>
<style>body{{margin:0;background:#17100b;color:#f8efe2;font:16px/1.6 system-ui}}main{{max-width:1100px;margin:auto;padding:30px}}h1{{font-size:28px}}a{{color:#82bdff}}section{{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:22px}}figure{{margin:0;background:#292019;padding:12px;border-radius:12px}}img{{display:block;width:100%;max-height:710px;object-fit:contain}}figcaption{{margin-top:10px}}small{{color:#cebaa5}}</style>
<main><h1>将棋 0.12 · 阶段报告</h1><p>可点击的双方准确率、按同一横轴排列的阶段评分和阶段复盘入口。</p><p><a href="REPORT.md">验证记录</a> · <a href="release.json">安装包与源文件散列</a></p><p><small>截图来自本轮真实 Godot 运行。准确率与阶段是将棋分析估计；真实支付与 Android 真机验收尚未完成。</small></p><section>{body}</section></main></html>'''
(OUT / 'index.html').write_text(page, 'utf-8')
print(json.dumps({'checks': counts, 'total': sum(counts.values()), 'report': str(OUT / 'REPORT.md')}, ensure_ascii=False))
