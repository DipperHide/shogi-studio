extends SceneTree
## Empty-window control for separating frame stalls from shogi app logic.
var frames = []
var pre = 0
var previous = 0
var began = 0

func _initialize() -> void:
	root.size = Vector2i(393, 852)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	RenderingServer.frame_pre_draw.connect(before_draw)
	RenderingServer.frame_post_draw.connect(after_draw)
	began = Time.get_ticks_usec()
	previous = began

func before_draw() -> void:
	pre = Time.get_ticks_usec()

func after_draw() -> void:
	var now = Time.get_ticks_usec()
	frames.append({"ms": (now - began) / 1000.0, "gap_ms": (now - previous) / 1000.0, "render_ms": (now - pre) / 1000.0})
	previous = now
	if now - began > 10000000:
		RenderingServer.frame_pre_draw.disconnect(before_draw)
		RenderingServer.frame_post_draw.disconnect(after_draw)
		var output = "res://../review/app/chessis24/empty-window.json"
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--output24="): output = argument.trim_prefix("--output24=")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
		FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(frames, "  "))
		print("EMPTY24 frames=", frames.size(), " max_gap_ms=", frames.slice(5).map(func(frame): return frame.gap_ms).max())
		quit.call_deferred()
