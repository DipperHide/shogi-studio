# 棋子字面

0.4.1 起采用 LuffyKudo 绘制的菱湖体将棋字面（CC BY-SA 4.0）。[作者原始项目](https://github.com/LuffyKudo/Shogi-Themes/tree/af44470b85b160fa01e23b2a63d8a91232cf34c3/Ryoko)。固定提交、源文件及 SHA-256 见 `ryoko/provenance.json`；授权全文见 `ryoko/source/LICENSE.txt`。

修改：移除原插图木胎及底边铭文，保留完整书法轮廓，等比排入本项目木胎，与原创木纹合成。衍生 SVG、遮罩及 `assets/textures/pieces.jpg` 字面图集同样采用 CC BY-SA 4.0。应用内「偏好设置 → 书法与素材署名」可查看署名；发行包内包含完整许可证。

王将、玉将、飛車、角行、金将、銀将、桂馬、香車使用双字；歩、龍、馬、と使用单字；成银、成桂、成香使用各自的传统草写金字。完整名称与显示字面分离。旧 `promoted-11/12/13.svg` 为历史原创资产，当前不使用。

重建：`scripts/prepare_ryoko.py` → Godot `tests/rasterize_ryoko.gd` → `scripts/build_models.py`。常规重建直接使用已保存的遮罩，无需下载源文件。

Yuji Syuku 仍用于界面坐标，OFL 授权见 `assets/fonts/OFL.txt`。
