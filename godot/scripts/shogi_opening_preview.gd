extends BoxContainer
const Motion = preload("res://scripts/shogi_history_motion.gd")
var view
var game
var entry: Dictionary
var ply = 0
var board
var moves: RichTextLabel
var play_button: Button
var previous: Button
var next: Button
var playing = false
var elapsed = 0.0
var labels: Array = []
var details: VBoxContainer
var board_column: VBoxContainer
var controls: HBoxContainer
var footer: HBoxContainer

func build(owner_view, source: Dictionary, parsed) -> void:
	view = owner_view; entry = source.duplicate(true); game = parsed
	if not entry.get("record",false): game.metadata["棋战"] = entry.name
	ply = 0 if entry.get("record",false) else game.moves.size()
	name = "OpeningPreview"
	vertical = true
	add_theme_constant_override("separation", 8)
	details = VBoxContainer.new(); details.add_theme_constant_override("separation", 4)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(details)
	board_column = VBoxContainer.new(); board_column.add_theme_constant_override("separation", 4)
	board_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(board_column)
	var info = view.text(entry.description, 13)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(info)
	moves = RichTextLabel.new()
	moves.name = "OpeningMoves"
	moves.bbcode_enabled = true; moves.fit_content = true; moves.scroll_active = false
	if entry.get("record",false): moves.fit_content = false; moves.scroll_active = true; moves.custom_minimum_size.y = 62
	moves.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	moves.add_theme_font_size_override("normal_font_size", 13)
	moves.add_theme_color_override("default_color", Color("f8f1e6"))
	details.add_child(moves)
	for i in range(game.moves.size()): labels.append("%d. %s" % [i + 1, preload("res://scripts/shogi_move_hint.gd").notation(game.positions[i],game.moves[i]) if entry.get("record",false) else game.labels[i]])
	moves.meta_clicked.connect(func(value): seek(int(str(value))))
	var summary: String = entry.summary if entry.get("record",false) else view.Data.side_name(int(entry.get("side", 0))) + " · " + str(entry.get("group", "")) + " · 教学示例，无对局胜率数据"
	var metadata = view.text(summary, 12)
	metadata.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(metadata)
	board = preload("res://scripts/shogi_opening_board.gd").new()
	board.name = "OpeningMiniBoard"
	board.app = view.ui.app; board.preview = self
	board_column.add_child(board)
	board.tokens = Motion.state(game.positions[0], game.moves, ply)
	controls = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	board_column.add_child(controls)
	controls.add_child(view.action("翻转", board.flip_board, "OpeningFlip", "ic_flip_board"))
	previous = view.action("上一手", Callable(), "OpeningPrevious", "ic_nav_previous")
	controls.add_child(previous)
	bind_navigation(previous, -1)
	play_button = view.action("播放", toggle_play, "OpeningPlay", "ic_nav_play")
	controls.add_child(play_button)
	next = view.action("下一手", Callable(), "OpeningNext", "ic_nav_next")
	controls.add_child(next)
	bind_navigation(next, 1)
	update_controls()
	resized.connect(layout_preview)

func layout_preview() -> void:
	if not is_instance_valid(footer): return
	var safe: Rect2 = view.ui.app.safe_rect()
	var wide = safe.size.x > safe.size.y
	vertical = not wide
	var controls_parent = details if wide else board_column
	if controls.get_parent() != controls_parent: controls.reparent(controls_parent)
	var footer_parent = details if wide else view.ui.page.get_child(0)
	if footer.get_parent() != footer_parent: footer.reparent(footer_parent)
	board._layout()

func bind_navigation(control: Button, direction: int) -> void:
	var held = {"start": -1, "point": Vector2.ZERO, "consumed": false}
	var timer = Timer.new()
	timer.one_shot = true; timer.wait_time = 0.45
	control.add_child(timer)
	timer.timeout.connect(func():
		if held.start < 0 or not control.is_visible_in_tree(): return
		held.consumed = true
		seek(0 if direction < 0 else game.moves.size())
	)
	control.pressed.connect(func():
		if not held.consumed: seek(ply + direction)
		held.consumed = false
	)
	control.gui_input.connect(func(event):
		if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION):
			if event.pressed:
				held.start = Time.get_ticks_msec(); held.point = event.position; held.consumed = false
				timer.start()
			else: held.start = -1; timer.stop()
		elif event is InputEventScreenDrag or event is InputEventMouseMotion:
			if event.position.distance_to(held.point) > 12: held.start = -1; timer.stop()
	)
	control.tooltip_text += " · 长按跳到" + ("起局" if direction < 0 else "末手")

func seek(target: int, autoplay: bool = false) -> void:
	if not autoplay: playing = false
	elapsed = 0
	ply = clampi(target, 0, game.moves.size())
	board.animate_to(Motion.state(game.positions[0], game.moves, ply))
	update_controls()

func update_controls() -> void:
	previous.disabled = ply == 0
	next.disabled = ply == game.moves.size()
	view.ui.set_reference_icon(play_button, "ic_nav_pause" if playing else "ic_nav_play")
	play_button.tooltip_text = "暂停播放" if playing else "逐手播放"
	play_button.accessibility_name = play_button.tooltip_text
	var shown = []
	var start = maxi(0,ply-8) if entry.get("record",false) else 0
	var end = mini(labels.size(),start+16) if entry.get("record",false) else labels.size()
	for i in range(start,end):
		var label: String = labels[i]
		if i == ply - 1: label = "[color=#ffdd57]" + label + "[/color]"
		shown.append("[url=%d]%s[/url]" % [i + 1, label])
	moves.text = "[center]" + "  ".join(shown) + "[/center]"
	board.accessibility_name = "%s · 第 %d / %d 手" % [entry.name, ply, game.moves.size()]

func toggle_play() -> void:
	playing = not playing; elapsed = 0
	if playing and ply == game.moves.size(): seek(0, true)
	update_controls()

func _process(delta: float) -> void:
	if not playing or board == null or not is_visible_in_tree() or not get_window().visible or get_window().mode == Window.MODE_MINIMIZED: return
	if board.motion < 1: elapsed = 0; return
	if ply == game.moves.size(): playing = false; update_controls(); return
	elapsed += minf(delta, 0.1)
	if elapsed >= 0.7: seek(ply + 1, true)

func stop() -> void:
	playing = false
	if is_instance_valid(board) and is_instance_valid(board.motion_tween): board.motion_tween.kill()

func _exit_tree() -> void:
	stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		playing = false; elapsed = 0
		if is_instance_valid(play_button): update_controls()
