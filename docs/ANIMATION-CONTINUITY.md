# 0.24 回放动画衔接

在吃子或升变动画尚未结束时改变回放位置，旧实现会从上一动画的目标位置创建新动画。直接回放和失误练习会跳动；主界面的旧队列会等待动画结束后才处理最后一次选择。

现在所有回放入口立即接受选定手数，并以每枚实体棋子当前的显示姿态为起点。2D 保留矩形和当前棋面，3D 保留位置、缩放、朝向以及升变翻面的角度和高度。中途被吃的棋子继续保留模型；随后打入的持驹可以创建此前不存在的模型。动画结束后统一恢复静态棋盘。

同一个合法五手棋谱覆盖普通移动、角交换、升变和打入。测试暂停真实 Tween 并推进 0.18 秒，通过实际回放入口连续定位 2、3、4、5、0、5、5、3、2 手，逐枚比较切换前后的绘制矩形、模型和棋面变换；分别运行 2D／3D 与先后手方向。输入夹具是之前真实 YaneuraOu 报告的保存结果，绝非临时编造的胜率或线路。测试不依靠不稳定的墙钟等待来碰巧采样动画中间状态。

## 帧时间仍有未解决问题

另一个诊断记录实际 `frame_post_draw` 的时间间隔。Windows 测试机（RTX 3050 Ti、驱动 577.03）出现约 450 毫秒的间歇停顿；先前只检查“出现过一个中间帧”的测试不足以证明全程流畅。移除棋盘和全部业务代码的空窗口也复现了停顿，且大部分时间落在 `frame_pre_draw` 与 `frame_post_draw` 之间。OpenGL、ANGLE／D3D11 和 Vulkan 的空窗口对照均有此现象。现有证据尚不能区分 Godot、显示驱动、桌面合成或其他运行环境原因。

因此本次修复针对中途切换的姿态跳变，**没有解决本机周期性绘制停顿，也没有通过改短动画或跳帧来宣称流畅**。计时记录单独标出是否满足 50 毫秒帧间隔目标，不与功能断言合并为“全部性能通过”。Android 未连接真机，不能从 Windows 数据推断手机表现。没有为此关闭无障碍支持或更换应用渲染后端。

复现空窗口诊断：

```powershell
godot --path godot --script res://tests/render_loop24_probe.gd
godot --path godot --rendering-driver opengl3_angle --script res://tests/render_loop24_probe.gd -- --output24=res://../review/app/chessis24/empty-angle.json
godot --path godot --rendering-method mobile --rendering-driver vulkan --script res://tests/render_loop24_probe.gd -- --output24=res://../review/app/chessis24/empty-vulkan.json
```

其中 `godot` 为本机 Godot 4.7.2 控制台程序路径。渲染后端选项见 [Godot 官方项目设置](https://docs.godotengine.org/en/4.5/classes/class_projectsettings.html#class-projectsettings-property-rendering-gl-compatibility-driver-windows)。本次功能测试入口是 `scripts/test_chessis24.ps1`；GitHub CI 增加了虚拟显示上的确定性姿态回归，发布前仍需另行确认远程 CI 的实际结果。

## 0.28 补充

[动画计时](ANIMATION-CLOCK.md)进一步保证先画出起点，再推进剩余移动。绘制停顿会延长实际播放时间，仍不等于消除渲染停顿；原有中断姿态测试继续保留。
