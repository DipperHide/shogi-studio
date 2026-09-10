extends Button
const Bar = preload("res://scripts/shogi_evaluation_bar.gd")
var editor
var progress = 0.5
var origin = 0.5
var target = 0.5
var elapsed = 0.75
var state: Dictionary = {}
var view_key = ""

func setup(owner_editor) -> void:
	editor = owner_editor
	name = "EditorEvaluation"
	for style in ["normal", "hover", "pressed", "disabled", "focus"]: add_theme_stylebox_override(style, StyleBoxEmpty.new())
	pressed.connect(editor.toggle_evaluation)

func _process(delta: float) -> void:
	if editor == null: return
	var next = Bar.sample(editor.analysis.details, editor.pos.turn)
	if not next.available: next.text = "—"
	elif editor.analysis.details.get("score_type") == "mate": next.text = "#" if next.depth == 0 else ("−詰" if next.score < 0 else "詰") + str(absi(int(editor.analysis.details.score)))
	else: next.text = str(roundi(next.score / 100.0)) if absf(next.score) >= 1000 else "%.1f" % (next.score / 100.0)
	if next != state:
		state = next
		if target != state.fraction: origin = progress; target = state.fraction; elapsed = 0
		if not state.available or editor.menu.app.preferences.studio.animation <= 0: progress = target; elapsed = 0.75
	if elapsed < 0.75:
		elapsed = minf(0.75, elapsed + delta)
		progress = lerpf(origin, target, (1 - cos(PI * elapsed / 0.75)) / 2.0)
		queue_redraw()
	var next_key = str([state, editor.flipped, editor.analysis.enabled, size, editor.analysis.error])
	if next_key != view_key:
		view_key = next_key
		accessibility_name = "局面评分 " + state.text + ("，深度 %d" % state.depth if state.depth > 0 else "") + ("，点击暂停" if editor.analysis.enabled else "，已暂停，点击恢复")
		tooltip_text = accessibility_name + ("。" + editor.analysis.error if not editor.analysis.error.is_empty() else "")
		queue_redraw()

func _draw() -> void:
	if editor == null or state.is_empty(): return
	var alpha = 1.0 if editor.analysis.enabled else 0.35
	draw_rect(Rect2(Vector2.ZERO, size), Color(Bar.DARK, alpha))
	var white = Rect2(0, 0 if editor.flipped else size.y * (1 - progress), size.x, size.y * progress)
	draw_rect(white, Color(Bar.LIGHT, alpha))
	if editor.analysis.enabled:
		var font = editor.menu.Design.heading_font(editor.menu.app.text_font)
		var font_size = 8
		while font_size > 6 and font.get_string_size(state.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x: font_size -= 1
		var extent = font.get_string_size(state.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var advantage = state.score >= 0
		var bottom = advantage != editor.flipped
		var baseline = size.y - 2 - font.get_descent(font_size) if bottom else 2 + font.get_ascent(font_size)
		draw_string(font, Vector2((size.x - extent.x) / 2, baseline), state.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Bar.DARK if advantage else Bar.LIGHT)
	else:
		draw_texture_rect(editor.menu.reference_icon("ic_play_round"), Rect2(size / 2 - Vector2(8, 8), Vector2(16, 16)), false, editor.menu.app.palette().accent)
	if has_focus(): draw_rect(Rect2(Vector2.ZERO, size).grow(-1), editor.menu.app.palette().accent, false, 1)
