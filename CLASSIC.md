# 将棋 · 木作 0.4.4

本版调低落子声，并放大持驹台上的棋子。声音保留用户选定的 sample-02，削弱尖锐频段、收短尾音并降低增益，整体电平约下降 5 dB；导入改为无压缩 PCM。持驹从棋盘棋子的 65% 改为 100%，重新安排三列间距及数量标记，拖动打入时保持相同尺寸。试听：`review/app/v044/wood-place.wav`；持驹截图：`review/app/v044/art-hands-18.png`。

棋子保留专用细密黄杨木纹、4096 × 4096 无损字面图集（每面 1024 × 1024）、从矢量重绘的独立漆字遮罩及多段细圆倒角。棋子正面、侧面、木质和漆字分别表现。棋子近景见 `review/app/v044/art-piece-closeup.png`；素材与提示词见 `assets/materials/piece-v043/`。

同类持驹改为一枚实体加一个数量：单枚不显示数字，两枚起显示实际数量，包括十八枚步兵。内部保留每枚棋子的身份和棋谱，旧存档无需迁移。项目同时开发另一款竖屏文字界面，本版本使用独立构建与 Android 包名。

- Windows：`builds/classic-0.4.4/windows/ShogiClassic.exe`
- Android：`builds/classic-0.4.4/shogi-classic.apk`，包名 `org.shogistudio.classic`，显示名「将棋 · 木作」，版本代码 17，可与「将棋 · 静棋」并存。
- 对照截图：`review/app/v044/art-reference-position.png`
- 十八枚持驹：`review/app/v044/art-hands-18.png`
- 主页：`review/app/v044/art-home.png`
- 独立构建项目：`.classic-build-orgi6a6e/godot/project.godot`，默认进入木质主页。
- 当前共享项目也保留木质场景 `godot/main.tscn`；共享项目的默认入口由竖屏版任务维护。

木材使用以用户实物照片为参考生成的纵向木纹与端面年轮贴图，替换原先的数学条纹。棋盘、棋子、持驹台分别校正木色；取消统一压暗和偏褐处理，保留柔和宽反光和清晰漆字。略微倾斜的俯视角露出棋盘前缘与棋子斜边。草席沿用当前编织素材。素材、完整提示词与来源保存在 `assets/materials/photographic-v042/`。

通过 671 项规则检查、213 项历史/布局检查、172 项交互检查；独立规则库对照 280 个局面与 8932 个合法走法。模型与 0.4.3 相同，保留该版 13 个 GLB 无错误/警告及 15 个字面的验证，并比对源文件哈希。保存 18 张交互截图及 9 张画面检查截图。声音没有削波，波形/频谱检查与运行时 PCM 导入检查通过。构建校验记录见 `review/app/v044/build-verification.json`。

书法采用 LuffyKudo 的菱湖体 SVG，授权 CC BY-SA 4.0，源文件、衍生文件与完整署名在 `assets/calligraphy/`；应用设置内也有署名入口。

生成贴图是参考实物制作的近似材质，并非摄影测量；端面与纵面不保证年轮在切面之间连续。采用轻量投影接触阴影及低强度宽反光，尚不能等同真实照片的光学表现。未进行 Android 真机验收。落子声基于原 sample-02 处理，没有重新合成；目前无法直接听辨，听感需以试听为准。

重建两端安装包：`powershell -ExecutionPolicy Bypass -File scripts/build_classic.ps1`。脚本从共享木质场景创建新的独立项目，不修改竖屏版的入口或版本号。
