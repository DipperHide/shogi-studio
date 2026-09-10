# 将棋品牌素材

0.8.0 默认入口使用新制作的 `studio-icon.svg` 王将图标，路径由代码绘制，`scripts/build_studio_icon.gd` 生成 PNG 与 Windows ICO。页面木纹由渲染代码绘制。没有把参考 Chessis APK 的图标、棋子、角色或木纹位图打入安装包。以下 0.7 素材记录为历史说明，旧资源保留供原有美术场景使用，不再作为 0.8 的主页和玩家头像。

## 0.7 品牌素材历史

2026-09-07 角色纠正。使用内置 image_gen，直接以用户提供的五张雏鹤爱参考图生成新版同人头像与首页插画。参考图的 SHA-256 与验收见 review/app/ui07/character-correction/。生成图并非官方原画或合作标志。

纠正前提示词误写为深蓝长发、红棕眼睛和粉色领结，与雏鹤爱角色设计不符；该版已替换，不再使用。

新版锁定特征：栗棕发、蓝／青蓝眼睛、平刘海、低双马尾、红白发结与黄色细绳、白色蓝边帽、蓝色连衣裙、白衬衫与黄色领结。所有角色入口共享这两张素材。

## 首页完整提示词

```text
Use case: illustration. Asset: landscape homepage illustration for an existing shogi app.
Create a NEW composition featuring exactly Ai Hinatsuru (雏鹤あい / 雏鹤爱) from The Ryuo's Work Is Never Done!, using the five attached user reference images as the authority for character identity. All five are CHARACTER DESIGN references, not layout templates. References 2 and 5 define her face, hair color and eye color; reference 3 defines her costume and low twin-tail hairstyle; references 1 and 4 define the white blue-trimmed beret and cheerful personality.
Identity fidelity is critical: warm chestnut-brown hair, straight short bangs, rounded youthful face, enormous turquoise-blue eyes with the violet/blue shading shown in the screenshots, long LOW twin tails tied below the ears with small red/pink and white ties, thin yellow ribbon loops near her shoulders. White beret with blue trim. Blue sleeveless pinafore dress, white collared blouse with softly ruffled long sleeves, narrow yellow ribbon necktie. Preserve her original childlike anime proportions and exact recognizable facial design. This is a wholesome shogi illustration. Do not make an older teenager. Do not substitute navy/black loose hair, reddish eyes, a pink neck bow, a school blazer or another anime girl.
Clean Japanese 2D anime cel shading and precise linework close to the supplied character references, restrained highlights. Warm friendly smile, looking toward the viewer, holding one small wooden pentagonal shogi piece near her chest.
Composition: 1536x1024 landscape (3:2), waist-up character on the RIGHT half, complete white hat and face comfortably inside the frame; face around x=1120,y=340. Keep all important facial features within the upper 650 pixels for responsive banner cropping. Left 48% is quiet pale ivory/cream negative space, with only very subtle warm watercolor texture. Subtle pale sky blue at upper right, sparse delicate cherry blossom petals near the upper right edge. No other people, no text, no title, no letters, no watermark, no UI, no collage, no border. The image will sit behind dark blue UI text on the left.
```

## 图标完整提示词

```text
Use case: illustration. Asset: square app icon for the shogi app 将棋.
Draw Ai Hinatsuru (雏鹤爱 / 雛鶴あい) from The Ryuo's Work Is Never Done!, faithfully matching the user-provided character references.
Input roles: image 1 is the newly corrected homepage artwork to keep the same character and cel-shading; images 2, 3, and 4 are authoritative character references for facial features, exact costume, hairstyle and eye color.
Square 1024x1024, one cheerful close-up portrait. Warm chestnut-brown hair with straight bangs and long LOW twin tails tied below the ears; small red/pink and white hair ties, thin yellow loops visible near shoulders. Very large blue/turquoise eyes with violet shading and round youthful face, matching the original anime. White beret with a blue edge, white collared ruffled blouse, blue pinafore dress and a narrow yellow neck ribbon. Keep the original young anime character design, not an older teen. Hold one large pale wooden pentagonal shogi piece marked with the clearly drawn black character 歩 near lower-left shoulder, not covering the face.
Composition for an app launcher: head and white hat entirely in frame with about 8% space above the hat; face centered around x=530,y=510; eyes, nose, mouth, and piece all contained in the central 66% circle so they survive an Android round mask. At small size both bright blue eyes and brown twin-tail silhouette should be easy to recognize. Blue dress and yellow necktie may extend into bottom edge. Pure soft sky blue background (#96cdf4) across the entire square, clean simple silhouette, no rounded border drawn into the artwork. Crisp Japanese anime cel coloring matching the reference screenshots. No app name, no additional text beyond 歩, no logos, no watermark, no second person. Absolutely no navy or black hair, red or brown eyes, pink neck bow, or school blazer.
```

ai-home.png / ai-icon.png 保存生成原图；Godot 纹理导入分别限宽 1024 / 256，带 mipmaps。ai-adaptive.png 用于 Android 启动器安全区；shogi.ico 包含 16、24、32、48、64、128、256 像素版本。归一化使用 Godot Image 缩放，ICO 仅封装对应 PNG，不修改图像内容。
