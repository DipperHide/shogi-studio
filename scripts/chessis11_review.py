"""Assemble evidence for the shipped usability update, without claiming live payments."""
from pathlib import Path
import hashlib
import html
import json
import zipfile

root = Path(__file__).resolve().parents[1]
out = root / 'review/app/chessis11'
for name in ['chessis11.err', 'chessis.err', 'chessis10.err', 'motion-final.err', 'package/package-stderr.log']:
    text = (out / name).read_text(encoding='utf8')
    assert not any(marker in text for marker in ['SCRIPT ERROR', 'ERROR:', 'UNIFIED FAIL']), name
results = {}
for name in ['ui/ui-tests.json', 'regression/results.json', 'report-ui/results.json', 'membership-tests.json', 'package/windows-package-probe.json']:
    data = json.loads((out / name).read_text(encoding='utf8'))
    assert not data['failures'], name
    results[name] = data['checks']
assert '2180 checks, 0 failures' in (out / 'motion-final.log').read_text(encoding='utf8')
release = json.loads((out / 'release.json').read_text(encoding='utf8'))
with zipfile.ZipFile(root / 'builds/shogi-playable.apk') as apk:
    for name in ['config/membership.json', 'assets/brand/studio-icon.svg']:
        assert apk.read('assets/' + name) == (root / 'godot' / name).read_bytes(), name
    assert 'dragon-king' in apk.read('assets/assets/brand/studio-icon.svg').decode()
    assert not json.loads(apk.read('assets/config/membership.json'))['enabled']
zip_path = root / next(item['path'] for item in release['artifacts'] if item['path'].endswith('.zip'))
with zipfile.ZipFile(zip_path) as archive:
    digest = hashlib.sha256(archive.read('Shogi.exe')).hexdigest()
    probe = json.loads((out / 'package/windows-package-probe.json').read_text(encoding='utf8'))
    assert digest == probe['executable_sha256']
    assert not any(name.endswith('.tmp') for name in archive.namelist())
(out / 'artifact-checks.json').write_text(json.dumps({'checks': results, 'motion_checks': 2180, 'apk_icon_and_config_match_source': True, 'windows_zip_matches_tested_executable': True, 'android_device_tested': False, 'real_payments_tested': False}, ensure_ascii=False, indent=2), encoding='utf8')
titles = {
    'anime2d-393x852': '主棋盘：悔棋与好棋线路', 'anime2d-852x393': '横屏持驹比例',
    'wood-393x852': '三维棋盘', 'wood-capture-reverse-motion': '三维回放中间帧',
    'tutorial-catalog': '教程目录', 'tutorial-topics': '学习主题', 'tutorial-lessons': '课程列表',
    'tutorial-board': '互动练习', 'tutorial-motion': '教程回放动画',
    'bad-move-warning': '真实引擎坏棋提醒', 'better-line': '改进线路',
    'good-line-preview': '线路预览', 'good-line-startpos': '实时好棋线路',
    'membership': '会员：购买尚未开放',
}
cards = ''.join(f'<figure><img loading="lazy" src="ui/{name}.png"><figcaption>{html.escape(title)}</figcaption></figure>' for name, title in titles.items())
(out / 'index.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>将棋 0.11 验证</title><style>body{background:#181818;color:#eee;font:16px system-ui;margin:28px}p{line-height:1.8;max-width:850px}.grid{display:flex;flex-wrap:wrap;gap:20px}figure{margin:0;width:310px}img{width:100%;border-radius:12px}figcaption{padding:12px 0}</style><h1>将棋 0.11</h1><p>主界面悔棋、持驹比例、回放与教程动画、复盘续下、真实引擎提醒、好棋线路、胜率估计和龙王图标。桌面界面 95 项、既有界面 57 项、报告 26 项、三维 2180 项、会员状态机 18 项、打包程序 32 项检查通过。实际付款未接通，Android 尚未真机验证。</p><div class="grid">''' + cards + '</div></html>', encoding='utf8')
artifacts = '\n'.join(f"- `{a['path']}`：{a['bytes']:,} 字节，SHA-256 `{a['sha256']}`。" for a in release['artifacts'])
(out / 'REPORT.md').write_text('''# 将棋 0.11.0 验证记录

本轮按最新用户反馈完成主界面悔棋、持驹等比例绘制、分析／回放动画、直接从复盘局面续下、教程主题目录与动画、真实引擎坏棋提醒、好棋线路、局面胜率估计、龙王图标。

教程保留原始课程数据与进度 ID，产品目录不再出现书名；非教学导读、作者介绍和无关文化专栏隐藏，来源移到“关于”。已有练习继续可用。

坏棋测试使用局面 `8k/9/4p4/9/4R4/9/9/9/K8 b - 1` 的 `5e5d`，实际 YaneuraOu 分析检测到送飞车，并返回可播放的改进线路。原始通信见 `ui/coach-usi.txt`。胜率是引擎评分换算的估计，不是用户获胜概率的实测值。

## 验证

- `ui/ui-tests.json`：95 项。二维／三维四种窗口尺寸、持驹比例、前进／后退／连续跳步／自动回放、续下与原局隔离、教程交互和回放、真实坏棋检测与线路。
- `regression/results.json`：57 项原有界面与对弈流程。
- `report-ui/results.json`：26 项真实报告与候选线路交互。
- `motion-final.log`：2,180 项三维节点、阴影、静止棋子、相机和拖动姿态检查。
- `membership-tests.json`：18 项。本地临时测试密钥验证购买／取消／恢复、签名篡改、商品／安装不匹配、到期与持久化；没有调用真实支付。
- `package/windows-package-probe.json`：32 项实际导出的 Windows 程序检查，包含原有引擎、NNUE、历史棋谱、课程和本轮回放、会员配置。
- `package/verification.json`：53 项 APK 签名、对齐、版本与资源检查。
- `artifact-checks.json`：确认 APK 龙王 SVG 与会员配置逐字节等于源码，Windows ZIP 中程序与实际测试程序 SHA-256 相同。

首次三维拖动回归受隐藏测试窗口失焦影响，测试驱动已明确设置对局激活状态后重跑；生产中的失焦暂停规则保持不变。最终三维检查和程序日志均无脚本错误。

## 安装包

''' + artifacts + '''

包名 `org.shogistudio.artpreview`，版本 0.11.0，versionCode 29，沿用开发签名和 ShogiStudio 数据目录。Windows 输出到独立的 `builds/windows-0.11.0`，未终止用户运行中的旧版。

## 明确未完成

支付渠道、价格、商户与订单服务器未提供。会员界面、权益门禁与签名适配接口已实现，但当前版本不能实际收款；测试版开放现有功能，不伪造付款成功。接入契约见 `docs/MEMBERSHIP-INTEGRATION.md`。

没有连接 Android 真机，因此本轮 APK 尚未真机实测。完整复制原版全部功能的目标仍未完成，原版高级分类、变化树、扫描和外部服务等缺口仍见 `docs/CHESSIS-PARITY.md`。
''', encoding='utf8')
print(json.dumps({'verified': True, 'report': str(out / 'REPORT.md')}, ensure_ascii=False))
