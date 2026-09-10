# 将棋 · 静棋 — 极简模式 0.5.0

Godot 4.7.2 将棋 App，支持 Android ARM64 与 Windows。现在默认直接进入竖屏极简对局：白底、9×9 正方形格线、格内普通黑字，没有实体棋子、贴图、音效、主页或常驻菜单。下方先手由玩家操作，上方后手由离线电脑操作。

点一下自己的文字，再点目标格落子；选中格反白，再次点击取消。对方文字旋转 180° 区分归属。吃到的持驹才在棋盘上下以文字和数量显示，点击自己的持驹后再点空格打入。可选升变时，落点附近两个格子临时显示「升变／不变」，点击选择；点外面取消，强制升变自动完成。终局出现「再来一局」文字，点击开始下一局。

每手自动保存在独立的 `user://minimal-game.json`，下次启动自动继续，不覆盖经典模式存档。桌面也支持方向键和回车／空格落子、Tab 切换持驹、Esc 取消。原有横屏 3D 经典模式保留在 `godot/main.tscn`，开发时单独运行该场景，或运行 `Shogi.exe -- --classic`。

极简模式复用已有规则、终局判断、存档校验和离线 AI。只加载二维绘制与字体，不实例化 3D 模型。截图和触控验证报告位于 `review/app/minimal/`，运行 `npm run test:minimal` 可重现。

## 直接试玩

- 安卓：安装 `builds/shogi-playable.apk`。沿用预览版包名，版本号提升为 15（0.5.0），可覆盖旧版；无需网络权限，固定竖屏。
- Windows：双击 `builds/windows/Shogi.exe`，资源已嵌入可执行文件。
- 开发：用 Godot 打开 `godot/project.godot`，按 F5。
- 极简画面：`review/app/minimal/01-board.png`；点选、升变、满持驹和终局截图也在同一目录。

## 经典模式

通过 `--classic` 启动后进入原有主页，选择「人机对弈」「同机对弈」或继续上次对局。人机开局前可选择先手、后手、随机，以及入门 / 标准难度；同机对弈可选择自动转向。电脑在主页和菜单中暂停行棋。

对局页只显示棋盘、棋子、持驹台和左上角菜单入口。点击菜单可以悔棋、翻转、查看棋谱、更改偏好、返回主页或认输。支持鼠标与单指拖动落子，也保留点选后点击目标格；持驹可点击后点目标格，也可直接从木台上拖入。非法落点、拖出棋盘、系统取消触控会恢复棋子，不改变局面。

## 已实现

- 0.4.1 视觉：按最新参考改为近正俯视的正交镜头，前后棋格大小一致；持驹台改为近方形并紧靠棋盘两角。草席转为横向织带、纵向细草纤维，重新匹配左右明暗和色温。盘面、棋子及持驹台采用较沉稳的木色，棋线加入细亮边；取放中的接触阴影随棋子高度变化，避免 GLES 阴影斜纹。对照局面见 `review/app/v041/art-reference-position.png`。

- 0.4.0 主页：上方随模式变化的介绍卡和实景预览，下方「继续对局／人机对弈／同机对弈」三组原创立体物件、红色选择环和柔和投影；点一下选择，再点进入，也支持触屏滑动。配置与设置统一卡片风格。独立展示场景在进入对局时释放，对局模型在主页中隐藏。
- 0.4.0 实物结构：加厚棋盘与离地高度，八瓣车木底脚、持驹台立柱和底座；场景模型、拾取与动画共用尺寸源。盘面和四个侧面采样同一个木材生长纹理场，漆字有独立材质遮罩；草席保留纤维而降低远处细纹对比。
- 0.4.1 书法：采用 LuffyKudo 绘制的菱湖体完整字面（CC BY-SA 4.0），保留笔画与双字之间的自然比例。歩、龍、馬、と采用单字，成银／成桂／成香使用不同草写金字。来源、源文件及散列记录在 `assets/calligraphy/ryoko/`，应用内可查看署名。
- 0.4.0 持驹：逐枚实体按种类固定分组，轻微扇形重叠。步兵多时在最后一行分为最多三个矮扇形，4 枚起显示一个数量。点击任一组员都选取顶层实体，支持点选或拖入；新吃到的棋子放在最上方。
- 0.4.0 取放：普通落子、打入、吃子、悔棋和回放共用实体姿态与动作。吃子先清空目标再移动进攻棋子，悔棋顺序相反；取放过程中翻面、改变归属、调整同组间距，保持准确落点。存档格式不变，实体身份和入台顺序均从棋谱重建。

- 0.3.8 悔棋与回放：棋子先抬起、平移，再落下并播放落子音；还原吃子时从持驹台取回棋子并恢复归属、升变面，撤销打入时送回持驹台。人机两手悔棋顺序还原。回放上一手、下一手、跳转指定手数、返回当前局面均通过实体棋子位置过渡；远距离跳转一次完成摆局。动画期间锁定对局输入与 AI，落定后恢复。
- 0.3.6 持驹点选：点击自己持驹台上的棋子，棋子抬起并显示底部高亮，再点击合法空格即可打入；再次点击同一持驹取消选择。鼠标与触屏均可使用，保留拖动，新增点选打入、翻转视角、关闭提示、非法目标和取消选择的交互验证。
- 0.3.7 草席：按用户照片参考制作细蔺草席纹理，使用内置 ImageGen 生成的 `godot/assets/materials/igusa-rush.png`。细草茎成束、浅沟槽和纤维粗细变化取代散草，运行时加入克制的法线起伏与色调调整。完整提示词及来源在 `review/app/rush-generation.json`。木质棋子、柔和光泽棋盘和短促碎片落子音保留。
- 主页 / 开局配置 / 简洁对局页 / 按需打开的菜单与棋谱；放大棋盘、淡化榻榻米、降低木色饱和度，采用 2K 棋字贴图、更细棋线、4× MSAA 和各向异性过滤。
- 3D 拖动抬起、落点反馈、吃子入台、升变翻面；处理多指干扰、拖出棋盘、系统取消触控及窗口失焦。
- 0.3.9 落子音采用用户录音中选定的 `sample-02.wav`，保留原片段的起音与频谱，裁掉安静长尾并渐隐至 120 ms；来源保存在 `assets/audio/selected-snap-source.wav`，处理参数见 `review/app/audio-checks.json`。声音开关、音量、试听、落点提示、上一步标记、坐标和同机转向偏好可以保存。
- 全部棋种走法、阻挡、升变选择与强制升变、吃子还原、打入、二步、无路可走的打入限制、打步诘、王手、自陷王手、将死和无合法着手判负。
- 四次同一局面的千日手，以及连续王手一方判负；局面判定包含持驹和行棋方。
- 同机双人、基础离线 AI、悔棋、投了、手动翻转视角。
- 每手保存完整着手序列，重启自动恢复；临时文件写入、备份恢复、对载入着手逐一进行合法性校验。
- 棋谱逐手回放、点击跳转、返回当前对局。回放期间暂停电脑行棋；悔棋与新开局会丢弃过期 AI 结果。

**当前是可玩原型，并非完整产品。** AI 是自编的入门级、有时间上限的迭代加深搜索，使用子力与简单位置估值，尚未接入专业 USI 引擎或棋力评级。当前不含计时、入玉宣言、持将棋裁定、让子局、联网、多局档案、KIF/CSA 导入导出、引擎复盘评分或学习题库。千日手在本版以和棋结束，由用户重新开局。

自动存档位于 Godot `user://current-game.json`，桌面版使用用户应用数据下的 `ShogiStudio` 目录；Android 使用应用私有数据目录。新开局会替换当前自动存档，配置页会明确提示。开局的先后手和难度随棋谱保存，兼容旧版存档；偏好设置保存在 `user://preferences.cfg`。

## 验证与构建

```powershell
# 环境配置见 DEV_ENVIRONMENT.md；规则交叉验证额外使用 python-shogi
.venv\Scripts\python.exe -m pip install python-shogi==1.1.1
npm run test:app
npm run test:minimal
npm run build:android
npm run build:windows
```

测试包含初始局面 perft 30 / 900 / 25470、规则边界、存档损坏恢复、AI 合法性与独立 `python-shogi` 交叉验证。交互检查使用实际 Godot 渲染和输入事件，覆盖屏幕选点、动画、升变、打入、回放、翻转、后台 AI、满持驹和终局布局，截图为实际引擎画面。测试使用隔离文件，不覆盖正常对局存档。

报告：`review/app/rules-tests.json`、`oracle-tests.json`、`v04/ui-tests.json`、`audio-checks.json`。本机桌面已验证；触控测试为 Godot 输入事件模拟，安卓导出使用开发调试签名，手机触控、性能和系统适配仍需真机验收。

## 代码结构与后续

- `godot/minimal.tscn`、`godot/scripts/shogi_minimal.gd`：默认竖屏极简模式、纯文字绘制、点击和触控输入、后台 AI 与独立存档。
- `godot/scripts/shogi_rules.gd`：独立局面、合法着手生成。
- `godot/scripts/shogi_game.gd`：对局历史、终局、悔棋、存取。
- `godot/scripts/shogi_history_motion.gd`：重建实体身份与入台顺序，规划普通落子、悔棋、回放和分阶段吃子。
- `godot/scripts/shogi_hand_layout.gd`：持驹分组、姿态、点击范围和数量位置。
- `godot/scripts/shogi_home_stage.gd`：独立主页展示场景与模式切换。
- `godot/scripts/shogi_ai.gd`：在独立线程中读取局面副本的基础搜索。
- `godot/main.gd`：3D 棋盘、触控、动画与界面。
- `godot/scripts/shogi_interface.gd`：主页、配置页、极简对局控件与弹出菜单。
- `godot/scripts/shogi_preferences.gd`：偏好存取与数值校验。
- `scripts/build_wood_sound.py`：可复现处理用户选定录音，输出 `godot/assets/audio/wood-place.wav`。
- `godot/tests/`、`scripts/check_rules_oracle.py`：规则与交互验证。

下一步：安卓真机体验与性能验证 → 计时和剩余终局规则 → 专业 USI 引擎接入 → 棋谱档案与导入导出 → 引擎复盘、关键失误与学习题库。

规则参考：[日本将棋联盟对局规则](https://www.shogi.or.jp/match/taikyoku_rules/)。UI 与线程实现参考 [Godot 官方文档](https://docs.godotengine.org/en/stable/classes/class_thread.html)。

## 美术模型与原始审核工具

以提供的《世界游戏大全》将棋截图作为构图、颜色和桌游质感参考。模型与木纹、榻榻米纹理由脚本原创生成；未提取参考游戏的模型、贴图或音效。

## 查看

- 本地审核：`npm install`，然后 `npm run serve`，打开 http://127.0.0.1:8765。
- 默认镜头展示完整初始摆棋，鼠标拖动旋转，滚轮或双指缩放。
- “棋子细节”可选择九种棋子外观（包含王将与玉将），查看正面和底面的成棋文字。
- `review/01-scene.png`：整体；`02-rook-front.png`：飞车近景；`03-rook-back.png`：龙王背面；`04-scene-angle.png`：侧面造型。

## 模型

- `models/shogi-scene.glb`：棋盘、40 枚独立棋子、两座持驹台、榻榻米。
- `models/board.glb`：带倒角的棋盘和底脚。
- `models/komadai.glb`：持驹台桌面、立柱、底座。
- `models/piece-*.glb`：九种独立棋子外观，闭合实体、斜面、倒角及正反面贴图。
- `models/piece-study.glb`：正面及六种成棋背面排列。
- `models/manifest.json`：坐标、尺寸、资源来源说明。

格式为 glTF 2.0 二进制 GLB，所有材质纹理内嵌，可在支持 glTF 的 Blender、Godot 等工具中继续编辑。模型使用 +Y 朝上、-Z 为棋子尖端方向；一个单位约 40 mm。棋盘表面 Y=2.8（唯一尺寸源为 `godot/assets/scene-layout.json`），棋盘每格宽 0.98、深 1.08。引擎导入后如需要真实米制，统一缩放 0.04。

GLB 本身仅包含几何与 PBR 材质。网页审核仍为独立的美术查看工具；可玩 App 位于 `godot/`，使用单独配置的镜头与灯光。当前没有做 Android 真机性能验收。

## 字形与授权

字面使用 **LuffyKudo 的菱湖体将棋 SVG**，采用 [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)；[作者源项目](https://github.com/LuffyKudo/Shogi-Themes/tree/af44470b85b160fa01e23b2a63d8a91232cf34c3/Ryoko)。修改后的字面 SVG、遮罩和图集沿用此授权。源文件、固定提交与哈希见 `assets/calligraphy/ryoko/provenance.json`，完整署名说明见 `assets/calligraphy/README.md`。Yuji Syuku 继续用于棋盘坐标。

- 字体来源：https://github.com/google/fonts/tree/main/ofl/yujisyuku
- 上游：https://github.com/Kinutafontfactory/Yuji
- 授权：SIL Open Font License 1.1，完整文本位于 `assets/fonts/OFL.txt`。
- Three.js（审核预览）：MIT，见 `node_modules/three/LICENSE`。
- App 中文界面：Noto Sans SC，来源 [Google Fonts](https://github.com/google/fonts/tree/main/ofl/notosanssc)，SIL OFL 1.1；完整授权在 `godot/assets/fonts/OFL-NotoSansSC.txt`。

## 重建与验证

使用 Python 3 + NumPy + Pillow 运行 `scripts/build_models.py`，复制 `models/shogi-scene.glb` 至 `godot/assets/shogi-scene.glb` 后用 Godot 导入。网页美术工具另运行 `scripts/prepare_preview.py`。后者同时输出本地预览和当前任务内的可交互审核视图。

所有 13 个 GLB 已通过 Khronos glTF Validator，零错误、零警告。浏览器检查覆盖加载、镜头旋转、棋子选择、背面切换和窄屏布局；结果在 `review/validation.json`、`review/browser-checks.json` 和 `review/inline-checks.json`。

审核建议：先看棋盘木色、镜头倾斜程度、棋子宽厚比例、字形和持驹台的大小位置。当前对局画面采用初始局面，因此持驹台为空。

