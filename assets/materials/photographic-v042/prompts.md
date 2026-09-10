# 木作 0.4.2 图像生成记录

用户授权：使用提供的实物照片，通过生成或裁剪图片模拟真实材质。
工具：内置 image_gen.imagegen。两张独立素材均已目视检查；无文字、网格、棋子、背景轮廓或明显烘焙高光。原始输出保留在 Codex generated_images，工作副本在本目录。

## kaya-long-grain.png

参考：`C:/Temp/codex-clipboard-f1b81812-fbbe-4cbb-ac39-000a0afa12e1.png`、`C:/Temp/codex-clipboard-6672e558-6797-456f-881f-17e92ab20893.png`。

Create a game-ready photorealistic WOOD MATERIAL TEXTURE, using the attached actual Japanese shogi board and wooden pieces as material reference. Output one large square image filled edge-to-edge with a clean unmarked quarter-sawn Japanese kaya / fine boxwood wood surface, photographed perfectly straight down under very soft neutral diffuse light. Absolutely NO grid, NO writing, NO chess pieces, NO borders, NO furniture silhouette, NO perspective, NO shadows or specular hotspots baked into the texture. Natural pale warm honey wood, as on the real pieces in reference 2 and the board in reference 1; restrained golden wheat color, NOT orange, NOT sepia, NOT gray. Fine long grain running vertically, naturally varying fiber spacing, subtle wavy grain sweeping in a few places, extremely fine darker latewood lines, gentle variations between individual growth zones. Continuous real wood optical detail and delicate satin polish with microscopic pores, not rough planks, not strong repeating barcode stripes, no knots, no scratches, no distressed finish. It should look like a high-resolution scan of real exquisitely finished solid kaya wood. Even overall illumination and exposure across the whole image so it can be used as a PBR base color. No text. Material-production asset, NOT a mockup or app screenshot.

原始输出：`C:/Users/jinda/.codex/generated_images/01a07512-4a7e-7fe1-9bf0-143e2bb84917/exec-82cbf172-4220-4cae-a657-f39d2478f516.png`。

## kaya-end-grain.png

参考：`C:/Temp/codex-clipboard-f1b81812-fbbe-4cbb-ac39-000a0afa12e1.png`。

Produce a high resolution photorealistic wood material scan of the FRONT CUT FACE of the real Japanese kaya shogi board in this reference. The entire square image must be ONLY unmarked smooth wood, no board silhouette, no legs, no grid, no background, no border, no text. Flat orthographic scan under even diffuse neutral light, no baked illumination gradient and no specular highlights. Fine continuous naturally curving growth rings: the center of the tree is OUTSIDE the frame well ABOVE the top edge, giving broad nested U-shaped arcs sweeping gently across the lower and central wood face, as in the reference front surface. Very fine narrow fibers, delicate irregular latewood spacing, pale natural honey wheat boxwood/kaya color, NOT dark orange or brown. Exquisitely planed satin-smooth wood, absolutely no saw marks, roughness, cracks or knots. A usable real wood end-grain PBR base color texture with subtle photographic fiber detail. No obvious regular sinusoidal lines. Fill the whole square with wood.

原始输出：`C:/Users/jinda/.codex/generated_images/01a07512-4a7e-7fe1-9bf0-143e2bb84917/exec-5df7c040-0467-425e-8c35-374bdd68aada.png`。

## 接入方式与限制

`scripts/photo_wood.py` 将两张原图按部件校正均值色、裁剪、缩放，保留自然纹理。盘面降低纤维反差；棋子逐字面裁取不同区域。格线及授权书法由代码合成，保持清晰。棋盤端面用年轮图，纵面用长纹图；这些不同切面的纹理不保证解剖学上的连续对应。不是摄影测量资产，也没有宣称已达到照片级保真。

运行时使用柔和主光、独立漆字遮罩、低强度宽反光和轻量接触阴影。照片参考用于生成，没有将用户照片直接捆绑进安装包。既有草席和 sample-02 保留。
