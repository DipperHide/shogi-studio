extends Control
## Shared application controller. Renderers never own or submit a game state.

const Design = preload("res://scripts/shogi_design.gd")
const Rules = preload("res://scripts/shogi_rules.gd")
const Game = preload("res://scripts/shogi_game.gd")
const AI = preload("res://scripts/shogi_ai.gd")
const USI = preload("res://scripts/shogi_usi_engine.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Menu = preload("res://scripts/shogi_chessis_menu.gd")
const MatchSession = preload("res://scripts/shogi_match_session.gd")
const NetworkStore = preload("res://scripts/shogi_network_store.gd")
const FONT = preload("res://assets/fonts/NotoSansSC.ttf")
const SAVE_PATH = "user://active-game.json"
const GLYPHS = ["", "歩", "香", "桂", "銀", "金", "角", "飛", "玉", "と", "成香", "成桂", "成銀", "", "馬", "龍"]
const INK = Color("202020")
const LINE = Color("777777")

var game = Game.new()
var testing: bool = false
var coach
var test_runner: RefCounted
var board_rect = Rect2()
var cell: float = 48.0
var checked_cells: Array[int] = []
var check_key: String = ""
var pending_move: Dictionary = {}
var pending_move_key: String = ""
var play_area = Rect2()
var wide_layout: bool = false
var top_player_rect = Rect2()
var bottom_player_rect = Rect2()
var legal: Array[Dictionary] = []
var selection: int = -1
var selected_drop: int = 0
var promotion_moves: Array[Dictionary] = []
var promotion_cells: Array[int] = []
var hand_rects: Dictionary = {1: {}, -1: {}}
var result_rect = Rect2()
var notice: String = ""
var pointer_id: int = -2
var pointer_start = Vector2.ZERO
var pointer_moved: bool = false
var keyboard_square: int = 58
var keyboard_visible: bool = false
var keyboard_hand: int = 0
var active: bool = true
var thread: Thread
var ai_engine: RefCounted
var revision: int = 0
var ai_revision: int = 0
var pending_ai: Dictionary = {}
var classic: bool = false
var text_font: FontVariation
var font_variations: Dictionary = {}
var ui
var usi
var engine_provider: String = "yaneuraou"
var engine_level: int = 2
var engine_request: int = 0
var engine_context: Dictionary = {}
var analysis_lines: Dictionary = {}
var replay_index: int = -1
var flipped: bool = false
var session
var network_status: String = ""
var last_clock_save: int = 0
const Preferences = preload("res://scripts/shogi_preferences.gd")
const Records = preload("res://scripts/shogi_records.gd")
const I18n = preload("res://scripts/shogi_i18n.gd")
const Motion = preload("res://scripts/shogi_history_motion.gd")
var preferences = Preferences.new()
var records = Records.new()
var i18n = I18n.new()
var board_view
var wood_view
var review_game
var review_path: String = ""
var save_path: String = SAVE_PATH
var save_failed: bool = false
var preferences_failed: bool = false
var dark: bool = true
var audio_player: AudioStreamPlayer
var transition: Array = []
var motion_progress: float = 1.0
var motion_tween
var visual_tokens: Array = []
var ai_started_at: int = 0
var ai_due_at: int = 0
var drag_source: int = -1
var drag_drop: int = 0
var pointer_current = Vector2.ZERO
var last_theme_poll: int = 0
var auto_play: bool = true
var network_view_key: String = ""
var network_store = NetworkStore.new()
var network_save_path: String = "user://network-game.json"
var first_board_frame_ms: int = -1
var engine_start_ms: int = -1

func _ready() -> void:
	# Android Back belongs to our page stack; SceneTree otherwise exits after notification.
	get_tree().quit_on_go_back = false
	var args = OS.get_cmdline_user_args()
	# Android launch activities intentionally reject external command-line extras.
	# A debug-only request in private app storage enables the same isolated probe.
	if OS.get_name() == "Android" and OS.has_feature("debug") and FileAccess.file_exists("user://package-probe.request"):
		DirAccess.remove_absolute("user://package-probe.request")
		args.append("--package-probe")
	# Legacy art fixtures remain available only to development tests.
	if Array(args).any(func(arg): return arg in ["--ui-test", "--art-review", "--smoke-test"]):
		set_process(false)
		set_process_input(false)
		get_tree().change_scene_to_file.call_deferred("res://main.tscn")
		return
	testing = Array(args).any(func(arg): return arg in ["--minimal-test", "--complete-test", "--network-ui-test", "--package-probe", "--unified-test", "--unified-peer"])
	if testing:
		preferences.language = "zh"
		auto_play = false
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 60
	else:
		preferences.load_from()
		var saved = records.migrate(save_path, ["user://minimal-game.json", "user://current-game.json"])
		if saved != null: game = saved
		if not records.error.is_empty(): notice = records.error; save_failed = true
	if "--classic" in args: preferences.appearance = "wood"
	i18n.language = preferences.language
	text_font = FontVariation.new()
	_update_font()
	dark = preferences.is_dark()
	RenderingServer.set_default_clear_color(palette().background)
	if OS.get_name() == "Android":
		_sync_mobile_scale()
		get_window().size_changed.connect(_sync_mobile_scale)
	if OS.has_feature("mobile"): DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
	get_window().title = "将棋"
	engine_level = game.engine_level
	engine_provider = game.engine_provider
	flipped = game.human_side == -1
	board_view = preload("res://scripts/shogi_board_view.gd").new()
	board_view.app = self
	board_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board_view)
	ui = Menu.new()
	add_child(ui)
	ui.initialize(self)
	coach = preload("res://scripts/shogi_coach.gd").new()
	add_child(coach)
	coach.initialize(self)
	audio_player = AudioStreamPlayer.new()
	audio_player.stream = preload("res://assets/audio/wood-place.wav")
	add_child(audio_player)
	focus_mode = Control.FOCUS_ALL
	resized.connect(_layout)
	set_appearance(preferences.appearance)
	_refresh()
	if "--package-probe" in args:
		test_runner = load("res://scripts/shogi_package_probe.gd").new()
		test_runner.run.call_deferred(self)
	elif "--unified-test" in args or "--unified-peer" in args:
		test_runner = load("res://tests/chessis30_test.gd" if "--chessis30" in args else "res://tests/chessis29_test.gd" if "--chessis29" in args else "res://tests/chessis28_test.gd" if "--chessis28" in args else "res://tests/chessis27_test.gd" if "--chessis27" in args else "res://tests/chessis26_test.gd" if "--chessis26" in args else "res://tests/chessis25_test.gd" if "--chessis25" in args else "res://tests/chessis24_test.gd" if "--chessis24" in args else "res://tests/chessis23_test.gd" if "--chessis23" in args else "res://tests/chessis22_test.gd" if "--chessis22" in args else "res://tests/chessis21_test.gd" if "--chessis21" in args else "res://tests/chessis20_test.gd" if "--chessis20" in args else "res://tests/chessis19_test.gd" if "--chessis19" in args else "res://tests/chessis18_test.gd" if "--chessis18" in args else "res://tests/chessis17_test.gd" if "--chessis17" in args else "res://tests/chessis16_test.gd" if "--chessis16" in args else "res://tests/chessis15_test.gd" if "--chessis15" in args else "res://tests/chessis14_test.gd" if "--chessis14" in args else "res://tests/chessis13_test.gd" if "--chessis13" in args else "res://tests/chessis12_test.gd" if "--chessis12" in args else "res://tests/chessis11_test.gd" if "--chessis11" in args else "res://tests/chessis_motion_test.gd" if "--motion-probe" in args else "res://tests/chessis10_test.gd" if "--chessis10" in args else "res://tests/chessis09_test.gd" if "--chessis09" in args else "res://tests/chessis_ui_test.gd" if "--chessis" in args else "res://tests/ui08_test.gd" if "--ui08" in args else "res://tests/ui07_test.gd" if "--ui07" in args else "res://tests/unified_peer_test.gd" if "--unified-peer" in args else "res://tests/unified_test.gd").new()
		test_runner.run.call_deferred(self)
	elif testing:
		test_runner = load("res://tests/network_ui_test.gd" if "--network-ui-test" in args else "res://tests/complete_ui_test.gd" if "--complete-test" in args else "res://tests/minimal_test.gd").new()
		test_runner.run.call_deferred(self)
	else:
		_restore_network()
		ui.show_home()
		_deferred_engine.call_deferred()

func _sync_mobile_scale() -> void:
	# Android densityDpi follows the user's display scaling, not the physical panel.
	# A portrait base viewport otherwise halves landscape touch targets on rotation.
	var density = maxf(1.0, DisplayServer.screen_get_dpi() / 160.0)
	var logical = Vector2i((Vector2(get_window().size) / density).round())
	if logical.x > 0 and logical.y > 0 and get_window().content_scale_size != logical:
		get_window().content_scale_size = logical

func _layout() -> void:
	if board_view == null: return
	var usable = safe_rect()
	if ui != null and ui.sheet:
		usable.size.y = maxf(260, usable.size.y - ui.sheet_height())
		usable.size.x = maxf(260, usable.size.x - ui.sheet_width())
	play_area = Design.board_area(usable)
	var edge = floorf(minf(play_area.size.x - 10, play_area.size.y - 184))
	edge = maxf(108, edge)
	wide_layout = size.x > size.y
	if wide_layout: edge = maxf(108, minf(usable.size.x - (230 if usable.size.x > 600 else 12), usable.size.y - 66))
	cell = edge / 9.0
	var y = play_area.position.y + 88 + maxf(0, (play_area.size.y - edge - 220) * 0.22)
	board_rect = Rect2(Vector2(usable.get_center().x - edge / 2, y).floor(), Vector2.ONE * edge)
	top_player_rect = Rect2(board_rect.position - Vector2(0, 88), Vector2(edge, 42))
	bottom_player_rect = Rect2(Vector2(board_rect.position.x, board_rect.end.y + 50), Vector2(edge, 42))
	if wide_layout:
		board_rect.position = Vector2(usable.position.x + 6, usable.position.y + 56 + (usable.size.y - 62 - edge) / 2)
		var panel_x = board_rect.end.x + 14
		var panel_width = maxf(0, usable.end.x - panel_x - 12)
		top_player_rect = Rect2(panel_x, usable.position.y + 58, panel_width, 42)
		bottom_player_rect = Rect2(panel_x, usable.position.y + 156, panel_width, 42)
	# Keep the board-first workbench's move ribbon and analysis controls visible.
	if ui != null and ui.has_method("receive_info"):
		var variation_margin = 30 if _study_active() else 0
		var side_eval = ui.evaluation_bar != null and ui.evaluation_bar.reserve(safe_rect())
		var gutter = 28 if side_eval else 0
		var credit = 16 if side_eval else 0
		if not wide_layout:
			edge = maxf(108, minf(usable.size.x - 14 - gutter, usable.size.y - 433 - variation_margin + credit))
			cell = edge / 9.0
			board_rect = Rect2(Vector2(usable.get_center().x - edge / 2 + gutter / 2.0, usable.position.y + 126 + variation_margin), Vector2.ONE * edge)
			top_player_rect = Rect2(board_rect.position - Vector2(0, 88), Vector2(edge, 42))
			bottom_player_rect = Rect2(Vector2(board_rect.position.x, board_rect.end.y + 50), Vector2(edge, 42))
		else:
			edge = maxf(108, minf(usable.size.x - 300 - gutter, usable.size.y - 150 - variation_margin + credit))
			cell = edge / 9.0
			board_rect = Rect2(Vector2(usable.position.x + 10 + gutter, usable.position.y + 40 + variation_margin), Vector2.ONE * edge)
			var panel_x = board_rect.end.x + 16
			var panel_width = maxf(160, usable.end.x - panel_x - 10)
			top_player_rect = Rect2(panel_x, usable.position.y + 40, panel_width, 42)
			bottom_player_rect = Rect2(panel_x, usable.position.y + 142, panel_width, 42)
	hand_rects = {1: {}, -1: {}}
	var position = _display_position()
	var key: String = position.key()
	if key != check_key:
		check_key = key
		checked_cells = Design.checked_squares(position)
	for side in [1, -1]:
		for kind in range(1, 8):
			if position.hands[side][kind] > 0: hand_rects[side][kind] = hand_slot(side, kind)
	result_rect = Rect2(usable.position.x + 12, usable.end.y - 116, usable.size.x - 24, 46)
	if wide_layout: result_rect = Rect2(bottom_player_rect.position.x, usable.end.y - 114, bottom_player_rect.size.x, 46)
	if wood_view != null: wood_view.layout_board()
	if ui != null: ui.layout()
	_redraw()

func square_rect(square: int) -> Rect2:
	if wood_view != null: return wood_view.square_rect(square)
	if flipped: square = 80 - square
	return Rect2(board_rect.position + Vector2(square % 9, square / 9) * cell, Vector2(cell, cell))

func _text(_value: String, _rect: Rect2, _font_size: int, _color: Color = INK, _inverted: bool = false) -> void:
	pass

func _draw() -> void:
	pass

func _result_text() -> String:
	return i18n.result(game)

func _refresh() -> void:
	legal.clear()
	var playing = _play_game()
	if playing.result.is_empty(): legal = playing.position.legal_moves()
	_layout()
	if wood_view != null: wood_view.sync()
	_redraw()

func _clear_selection() -> void:
	pending_move.clear()
	pending_move_key = ""
	selection = -1
	selected_drop = 0
	drag_source = -1
	drag_drop = 0
	pointer_moved = false
	promotion_moves.clear()
	promotion_cells.clear()
	_redraw()

func _can_play() -> bool:
	if _study_active(): return active and motion_progress >= 1.0 and not ui.is_open() and ui.study.current.result.is_empty()
	if _practice_active(): return active and motion_progress >= 1.0 and not ui.is_open() and ui.practice.can_answer()
	if game.engine_match: return false
	return active and motion_progress >= 1.0 and review_game == null and (ui == null or not ui.is_open()) and replay_index < 0 and game.result.is_empty() and (session.can_move() if session != null else (game.mode == "local" or game.position.turn == game.human_side))

func _square_at(point: Vector2) -> int:
	if wood_view != null: return wood_view.square_at(point)
	if not board_rect.has_point(point): return -1
	var local = (point - board_rect.position) / cell
	var square = int(local.y) * 9 + int(local.x)
	return 80 - square if flipped else square

func _tap(point: Vector2) -> void:
	if ui != null and ui.is_open():
		return
	var playing = _play_game()
	if _practice_active() and not ui.practice.can_answer(): return
	if not playing.result.is_empty():
		if result_rect.has_point(point):
			ui.show_result()
		return
	if not _can_play():
		return
	var square = _square_at(point)
	if not promotion_moves.is_empty():
		var choice = promotion_cells.find(square)
		if choice >= 0:
			_propose_move(promotion_moves[choice])
		else:
			_clear_selection()
		return
	for kind in hand_rects[playing.position.turn]:
		if hand_hit_rect(playing.position.turn, kind).has_point(point):
			selection = -1
			selected_drop = 0 if selected_drop == kind else kind
			_redraw()
			return
	if square < 0:
		_clear_selection()
		return
	var choices: Array[Dictionary] = []
	for move in legal:
		if move.to == square and ((selected_drop > 0 and move.drop == selected_drop) or (selection >= 0 and move.from == selection)):
			choices.append(move)
	if choices.size() == 1:
		_propose_move(choices[0])
	elif choices.size() > 1:
		choices.sort_custom(func(a, b): return a.promote and not b.promote)
		promotion_moves = choices
		var left = square - square % 9 + mini(square % 9, 7)
		promotion_cells.assign([left, left + 1])
		keyboard_square = left
		ui.show_promotion()
		_redraw()
	elif playing.position.board[square] * playing.position.turn > 0:
		selected_drop = 0
		selection = -1 if selection == square else square
		_redraw()

func _propose_move(move: Dictionary) -> void:
	if preferences.confirm_move:
		pending_move = move.duplicate()
		pending_move_key = _play_game().position.key()
		ui.show_move_confirmation()
	else:
		_commit(move)

func _confirm_pending_move() -> bool:
	var move = pending_move.duplicate()
	var valid = not move.is_empty() and pending_move_key == _play_game().position.key()
	ui.close()
	if not valid or not _can_play():
		_clear_selection()
		return false
	_commit(move)
	return true

func _commit(move: Dictionary) -> void:
	if _study_active(): ui.study.commit(move); return
	if _practice_active(): ui.practice.submit(move); return
	if session != null:
		if session.submit(move): _clear_selection()
		return
	var before = _view_tokens()
	var visual_start = {}
	if wood_view != null and pointer_moved and is_instance_valid(wood_view.dragged_node):
		for id in range(before.size()):
			if before[id].square == move.from and move.from >= 0: visual_start[id] = wood_view.dragged_node.position
	if not game.play(move): return
	if coach != null: coach.committed()
	revision += 1
	_clear_selection()
	_save()
	_refresh()
	_present_transition(before, true, visual_start)
	ai_due_at = 0

func _save() -> void:
	game.engine_level = engine_level
	game.engine_provider = engine_provider
	if session != null:
		_save_network()
		return
	if not testing:
		var game_failed = game.save_to(save_path) != OK
		save_failed = game_failed or preferences_failed
		notice = "未能保存本局" if game_failed else "保存设置失败，请重试" if preferences_failed else ""
	_redraw()

func _retry_save() -> void:
	if not testing: preferences_failed = preferences.save_to() != OK
	_save()

func _new_game() -> bool:
	if ui != null and ui.has_method("finish_study") and not ui.finish_study(false): return false
	if _practice_active(): ui.practice.stop(false)
	if coach != null: coach.clear()
	if not _leave_network(): return false
	_leave_review()
	_cancel_motion()
	_pause_search()
	revision += 1
	pending_ai.clear()
	game = Game.new()
	replay_index = -1
	flipped = false
	keyboard_hand = 0
	keyboard_square = 58
	_clear_selection()
	_save()
	_refresh()
	return true

func _input(event: InputEvent) -> void:
	if classic:
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if event.pressed and not event.echo: _back_requested()
		get_viewport().set_input_as_handled()
		return
	if ui != null and ui.is_open():
		return
	if ui != null and ui.has_method("consume_board_input") and ui.consume_board_input(event):
		get_viewport().set_input_as_handled()
		return
	# GUI menu buttons consume their own input without selecting board text.
	if ui != null and (event is InputEventMouseButton or event is InputEventScreenTouch) and ui.handles_point(event.position):
		return
	if event is InputEventKey:
		if event.pressed and not event.echo:
			_key(event)
		return
	# Native touches are handled once; ignore Godot's synthesized mouse copy.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		if event.pressed and pointer_id == -2:
			_pointer_down(event.index, event.position)
		elif not event.pressed and pointer_id == event.index:
			_pointer_up(event.position, event.canceled)
	elif event is InputEventScreenDrag and event.index == pointer_id:
		pointer_current = event.position
		pointer_moved = pointer_moved or event.position.distance_to(pointer_start) > 12.0
		_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and pointer_id == -2:
			_pointer_down(-1, event.position)
		elif not event.pressed and pointer_id == -1:
			_pointer_up(event.position, false)
	elif event is InputEventMouseMotion and pointer_id == -1:
		pointer_current = event.position
		pointer_moved = pointer_moved or event.position.distance_to(pointer_start) > 12.0
		_redraw()

func _pointer_down(id: int, point: Vector2) -> void:
	pointer_id = id
	pointer_start = point
	pointer_current = point
	pointer_moved = false
	keyboard_visible = false
	drag_source = -1
	drag_drop = 0
	if _can_play() and promotion_moves.is_empty():
		var playing = _play_game()
		var square = _square_at(point)
		if square >= 0 and playing.position.board[square] * playing.position.turn > 0: drag_source = square
		for kind in hand_rects[playing.position.turn]:
			if hand_hit_rect(playing.position.turn, kind).has_point(point): drag_drop = kind
	_redraw()

func _pointer_up(point: Vector2, canceled: bool) -> void:
	pointer_id = -2
	if not canceled and pointer_moved and preferences.studio.drag and _can_play() and (drag_source >= 0 or drag_drop > 0):
		selection = drag_source
		selected_drop = drag_drop
		var dest = _square_at(point)
		if dest >= 0: _tap(point)
		else: _clear_selection()
	elif not canceled and not pointer_moved:
		_tap(point)
	drag_source = -1
	drag_drop = 0
	_redraw()

func _key(event: InputEventKey) -> void:
	var playing = _play_game()
	if event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		keyboard_visible = true
		keyboard_hand = 0
		var displayed = 80 - keyboard_square if flipped else keyboard_square
		var x = displayed % 9
		var y = displayed / 9
		x = clampi(x + (1 if event.keycode == KEY_RIGHT else -1 if event.keycode == KEY_LEFT else 0), 0, 8)
		y = clampi(y + (1 if event.keycode == KEY_DOWN else -1 if event.keycode == KEY_UP else 0), 0, 8)
		keyboard_square = 80 - (y * 9 + x) if flipped else y * 9 + x
	elif event.keycode == KEY_TAB:
		keyboard_visible = true
		var kinds: Array = [0] + hand_rects[playing.position.turn].keys()
		keyboard_hand = kinds[(kinds.find(keyboard_hand) + 1) % kinds.size()]
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		if _practice_active() and not ui.practice.can_answer(): return
		keyboard_visible = true
		if not playing.result.is_empty():
			_restart_request()
		elif keyboard_hand != 0 and hand_rects[playing.position.turn].has(keyboard_hand):
			_tap(hand_hit_rect(playing.position.turn, keyboard_hand).get_center())
		else:
			_tap(square_rect(keyboard_square).get_center())
	else:
		return
	get_viewport().set_input_as_handled()
	_redraw()

func _ai_allowed() -> bool:
	if _study_active(): return false
	if _practice_active(): return false
	return session == null and review_game == null and active and motion_progress >= 1.0 and (ui == null or not ui.is_open()) and replay_index < 0 and game.result.is_empty() and game.mode == "ai" and (game.engine_match or game.position.turn != game.human_side)

func _process(_delta: float) -> void:
	if board_view == null: return
	if Time.get_ticks_msec() - last_theme_poll > 500:
		last_theme_poll = Time.get_ticks_msec()
		if dark != preferences.is_dark(): apply_preferences()
	if session == null:
		var pause_clock = not active or review_game != null or replay_index >= 0 or (ui != null and ui.is_open()) or not game.result.is_empty()
		game.clock.tick(pause_clock)
		if game.clock.expired_side != 0 and game.result.is_empty():
			game.update_result()
			_pause_search()
			revision += 1
			_save()
			_refresh()
	if game.clock.preset != 0:
		_redraw()
		if not game.clock.paused and Time.get_ticks_msec() - last_clock_save > 1000:
			last_clock_save = Time.get_ticks_msec()
			_save()
	if thread != null and thread.is_started() and not thread.is_alive():
		var response = thread.wait_to_finish()
		thread = null
		ai_engine = null
		if ai_revision == revision and response is Dictionary and response.has("move"):
			pending_ai = response.move
	if not pending_ai.is_empty() and _ai_allowed() and _ai_delay_done():
		var move = pending_ai
		pending_ai = {}
		_commit(move)
	if auto_play and thread == null and pending_ai.is_empty() and _ai_allowed():
		if engine_provider == "yaneuraou":
			if usi != null and usi.phase == "ready" and engine_context.is_empty():
				_request_engine("play", game.position, game.moves, false)
			return
		ai_revision = revision
		ai_started_at = Time.get_ticks_msec()
		thread = Thread.new()
		ai_engine = AI.new()
		var think_ms: int = [150, 300, 650, 1100, 1800, 3000][engine_level]
		if game.clock.preset != 0: think_ms = mini(think_ms, maxi(20, game.clock.remaining[game.position.turn] + game.clock.period_left - 150))
		if thread.start(ai_engine.choose.bind(game.position.copy(), think_ms, [1, 1, 2, 2, 3, 3][engine_level])) != OK:
			thread = null
			ai_engine = null
			if not legal.is_empty():
				_commit(legal[0])

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		active = false
		pointer_id = -2
		if is_node_ready():
			_clear_selection()
			_pause_search()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		active = true
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready():
		_back_requested()

func _back_requested() -> void:
	if ui == null: return
	if ui.is_open():
		ui.back()
	elif selection >= 0 or selected_drop != 0 or not promotion_moves.is_empty():
		_clear_selection()
	elif ui.has_method("receive_info") and (ui.drawing or replay_index >= 0):
		ui.back()
	else:
		_save()
		ui.show_home()

func _exit_tree() -> void:
	_cancel_motion()
	if usi != null:
		usi.shutdown()
	if thread != null and thread.is_started():
		thread.wait_to_finish()

func _display_position() -> ShogiRules:
	var viewed = _view_game()
	return viewed.positions[replay_index] if replay_index >= 0 and replay_index < viewed.positions.size() else viewed.position

func _practice_active() -> bool:
	return ui != null and ui.has_method("practice_active") and ui.practice_active()

func _play_game():
	if _study_active(): return ui.study.current
	return ui.practice.exercise if _practice_active() else game

func _study_active() -> bool:
	return ui != null and ui.has_method("study_active") and ui.study_active()

func _load_engine() -> void:
	if engine_start_ms < 0: engine_start_ms = Time.get_ticks_msec()
	_pause_search()
	if usi == null:
		usi = USI.new()
		add_child(usi)
		usi.best_move.connect(_engine_best)
		usi.analysis.connect(_engine_info)
		usi.failed.connect(func(message): notice = message; engine_context.clear(); _redraw(); if ui != null: ui.update_analysis(message))
		usi.ready_changed.connect(func(ready):
			if ready:
				notice = ""
				if ui != null and ui.has_method("receive_info"): ui.live_key = ""
				if ui != null and ui.page_name == "analysis":
					_request_analysis()
				_redraw()
		)
	usi.analysis_count = preferences.studio.analysis_lines
	usi.thread_count = preferences.studio.threads
	usi.hash_size = preferences.studio.hash
	usi.launch()

func _pause_search() -> void:
	pending_ai.clear()
	revision += 1
	engine_context.clear()
	if usi != null:
		usi.cancel()

func _request_engine(kind: String, position: ShogiRules, moves: Array, analyze: bool) -> void:
	usi.analysis_count = preferences.studio.analysis_lines
	engine_request += 1
	if kind == "play": ai_started_at = Time.get_ticks_msec()
	engine_context = {"id": engine_request, "kind": kind, "revision": revision, "key": position.key()}
	var limit_ms = 0
	if kind == "play" and game.clock.preset != 0:
		limit_ms = maxi(20, game.clock.remaining[game.position.turn] + game.clock.period_left - 150)
	if not usi.search(position, moves, engine_request, engine_level, analyze, _view_game().initial_command(), limit_ms):
		engine_context.clear()

func _request_analysis() -> void:
	if usi == null:
		_load_engine()
	if not usi.available():
		ui.update_analysis(usi.last_error if usi.phase == "error" else "引擎准备中…")
		return
	analysis_lines.clear()
	var moves: Array = _view_game().moves.slice(0, replay_index) if replay_index >= 0 else _view_game().moves
	_request_engine("analysis", _display_position(), moves, true)
	ui.update_analysis("正在分析…")

func _engine_info(id: int, details: Dictionary) -> void:
	if engine_context.get("id", -1) != id or engine_context.get("kind") != "analysis":
		return
	if engine_context.revision != revision or _display_position().key() != engine_context.key:
		return
	if ui.has_method("receive_info"): ui.receive_info(details)
	var position = _display_position().copy()
	var names: Array[String] = []
	for value in details.get("pv", []).slice(0, 5):
		var move = Codec.parse_move(value, position)
		if move.is_empty():
			break
		names.append(position.notation(move))
		position = position.after(move)
	var score = str(details.get("score", "?"))
	if details.get("score_type") == "mate":
		score = t("将死") + " " + score
	else:
		score = t("评分") + " " + score
	analysis_lines[details.multipv] = "%d. %s  %s" % [details.multipv, score, " ".join(names)]
	var lines: Array[String] = [t("评分以当前行棋方为准")]
	for i in range(1, preferences.studio.analysis_lines + 1):
		if analysis_lines.has(i):
			lines.append(analysis_lines[i])
	ui.update_analysis("\n".join(lines))

func _engine_best(id: int, move: Dictionary, special: String) -> void:
	if engine_context.get("id", -1) != id:
		return
	var context = engine_context
	engine_context = {}
	if context.revision != revision:
		return
	if context.kind == "play" and _ai_allowed() and game.position.key() == context.key:
		if not move.is_empty():
			pending_ai = move
			ai_revision = revision
		elif special == "resign":
			game.resign(game.position.turn)
			_save()
			_refresh()
		elif special == "win" and game.declare_win(game.position.turn):
			_save()
			_refresh()
		else:
			notice = "引擎已停止，请打开菜单检查局面"
			_redraw()

func _start_match(mode: String, side: int, level: int, provider: String, clock_preset: int = 0) -> void:
	if not _new_game(): return
	game.mode = mode
	game.human_side = side
	game.clock.configure(clock_preset)
	engine_level = level
	engine_provider = provider
	flipped = side == -1
	_save()
	_refresh()
	if provider == "yaneuraou" and (usi == null or usi.phase in ["closed", "error"]):
		_load_engine()

func _save_settings() -> void:
	_pause_search()
	_save()

func _undo_move() -> void:
	if _study_active(): ui.study.undo(); return
	if _practice_active(): ui.practice.retry(); return
	if coach != null: coach.clear()
	var before = _view_tokens()
	_leave_review()
	if session != null:
		session.request("undo")
		return
	_pause_search()
	revision += 1
	pending_ai.clear()
	game.undo()
	replay_index = -1
	_clear_selection()
	_save()
	_refresh()
	_present_transition(before)

func _resign_game() -> void:
	if session != null:
		session.resign()
		return
	_pause_search()
	revision += 1
	game.resign(game.human_side if game.mode == "ai" else game.position.turn)
	_clear_selection()
	_save()
	_refresh()

func _declare_win() -> bool:
	if session != null:
		return session.declare_win()
	var side = game.human_side if game.mode == "ai" else game.position.turn
	if not game.declare_win(side):
		return false
	_pause_search()
	revision += 1
	_clear_selection()
	_save()
	_refresh()
	return true

func _archive_game() -> bool:
	if testing: return true
	var path = records.archive(game)
	if path.is_empty(): notice = records.error; save_failed = true; _redraw()
	return not path.is_empty()

func _list_archives() -> Array:
	return records.list_all()

func _load_archive(path: String) -> bool:
	if session != null: return false
	if ui != null and ui.has_method("finish_study") and not ui.finish_study(false): return false
	var saved = records.read(path)
	if saved == null: notice = records.error; return false
	_pause_search()
	review_game = saved
	review_path = path
	replay_index = saved.moves.size()
	_clear_selection()
	_refresh()
	if saved.variation_tree != null and ui.has_method("start_variation_analysis"):
		ui.start_variation_analysis(saved, -1, path)
	return true

func _restart_request() -> void:
	if session != null:
		session.request("rematch")
	elif _archive_game():
		_start_match(game.mode, game.human_side, engine_level, engine_provider, game.clock.preset)

func _prepare_network() -> bool:
	if ui != null and ui.has_method("finish_study") and not ui.finish_study(false): return false
	if not _archive_game(): return false
	if not _leave_network(): return false
	_leave_review()
	_pause_search()
	revision += 1
	pending_ai.clear()
	replay_index = -1
	session = MatchSession.new()
	add_child(session)
	session.changed.connect(_network_changed)
	session.status_changed.connect(_network_status)
	session.rejected.connect(_network_status)
	session.offer_received.connect(func(_action, _local): ui.show_offer.call_deferred())
	return true

func _network_changed() -> void:
	var before = visual_tokens.duplicate(true)
	if session == null:
		return
	var next_key = str([session.match_id, session.game.position.key(), session.game.result, session.local_side, session.connected_ready])
	if next_key == network_view_key:
		game = session.game
		_redraw()
		ui.update_connection()
		if ui.page_name == "offer" and session.offer.is_empty(): ui.show_connection.call_deferred()
		return
	network_view_key = next_key
	_pause_search()
	revision += 1
	game = session.game
	flipped = session.local_side == -1
	if replay_index >= 0:
		replay_index = mini(replay_index, game.moves.size())
	_clear_selection()
	notice = ("轮到你" if session.can_move() else "等待对手") if session.connected_ready else "联机未连接"
	_refresh()
	_save_network()
	ui.update_connection()
	_present_transition(before)
	if ui.page_name == "offer" and session.offer.is_empty():
		ui.show_connection.call_deferred()

func _network_status(message: String) -> void:
	network_status = message
	ui.update_connection()

func _host_network(listen_port: int, side: int, clock_preset: int = 0) -> Error:
	if not _prepare_network(): return ERR_CANT_CREATE
	var error = session.host_tcp(listen_port, side, "", "*", clock_preset)
	_network_changed()
	return error

func _join_network(address: String, port: int, code: String) -> Error:
	if not _prepare_network(): return ERR_CANT_CREATE
	var error = session.join_tcp(address, port, code)
	_network_changed()
	return error

func _connect_bluetooth(host: bool, address: String = "", side: int = 1, clock_preset: int = 0) -> Error:
	if not _prepare_network(): return ERR_CANT_CREATE
	var error = session.host_bluetooth(side, clock_preset) if host else session.join_bluetooth(address)
	_network_changed()
	return error

func _leave_network() -> bool:
	if session == null:
		return true
	if not testing and not network_store.clear(network_save_path):
		notice = network_store.error
		save_failed = true
		return false
	network_view_key = ""
	var previous = session
	session = null
	previous.link.stop()
	remove_child(previous)
	previous.queue_free()
	network_status = ""
	return true

func _save_network() -> void:
	if testing or session == null:
		return
	if not network_store.write(network_save_path, session):
		_network_status(network_store.error)

func _restore_network() -> void:
	var snapshot = network_store.read(network_save_path)
	if snapshot.is_empty():
		if not network_store.error.is_empty(): notice = network_store.error
		return
	var data: Dictionary = snapshot.meta
	if not _prepare_network(): return
	session.game = snapshot.game
	session.game.clock_authority = data.is_host
	session.is_host = data.is_host
	session.local_side = int(data.side)
	session.room_code = data.room
	session.match_id = data.match
	session.resume_token = data.token
	session.transport = data.transport
	session.address = data.address
	session.port = int(data.port)
	_network_changed()
	_network_status("已恢复联机棋局，点击重新连接继续")

func t(source: String, values: Array = []) -> String:
	return i18n.text(source, values)

func palette() -> Dictionary:
	var p = Design.palette(dark)
	if dark:
		p.merge({"background": Color("181818"), "surface": Color("202020"), "ink": Color("f5f5f5"), "muted": Color("aeaeae"), "line": Color("383838"), "accent": Color("4285f4"), "soft": Color("292929"), "selected": Color("b7c271"), "board": Color("ddbc8b"), "board_line": Color("715436"), "piece": Color("f5dca8"), "piece_ink": Color("261d14")}, true)
	else:
		p.merge({"background": Color("eeeeee"), "surface": Color("ffffff"), "ink": Color("2b2828"), "muted": Color("757575"), "accent": Color("58a6ff"), "soft": Color("e4e4e4"), "board": Color("ddbc8b"), "board_line": Color("715436")}, true)
	var colors = {"classic": "ddbc8b", "walnut": "b38a64", "green": "b3c39a", "blue": "afc9de", "slate": "b9babe", "custom": str(preferences.studio.get("custom_color", "ddbc8b"))}
	p.board = Color(colors.get(preferences.studio.board_theme, "ddbc8b"))
	return p

func _update_font() -> void:
	var base: Font = load("res://assets/fonts/NotoSansJP.ttf") if preferences.language == "ja" else FONT
	if text_font != null and text_font.base_font == base: return
	var key = "ja" if preferences.language == "ja" else "zh"
	if font_variations.has(key):
		text_font = font_variations[key]
		return
	# Existing labels may still hold shaped text from the previous font. Replacing
	# the variation lets those references live until the new theme is applied.
	var next = FontVariation.new()
	next.base_font = base
	# Course text stays Chinese even when navigation is Japanese. Keep Japanese
	# glyph forms first, with complete Chinese coverage for the lesson body.
	if preferences.language == "ja": next.fallbacks = [FONT]
	next.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 400.0}
	# Retain both immutable variants while deferred text shaping can still use
	# their RIDs during a theme/language switch. This cache is bounded to two.
	font_variations[key] = next
	text_font = next

func apply_preferences() -> void:
	dark = preferences.is_dark()
	i18n.language = preferences.language
	TranslationServer.set_locale("zh_CN" if preferences.language == "zh" else preferences.language)
	_update_font()
	RenderingServer.set_default_clear_color(palette().background)
	if ui != null: ui.apply_theme()
	if wood_view != null: wood_view.apply_lighting()
	_refresh()

func set_preference(key: String, value: Variant) -> void:
	preferences.set(key, value)
	if key == "color_mode" and Engine.has_singleton("ShogiPlatform"):
		var platform = Engine.get_singleton("ShogiPlatform")
		if platform.has_method("setColorMode"): platform.setColorMode(value)
	if not testing: preferences_failed = preferences.save_to() != OK
	if preferences_failed:
		notice = "保存设置失败，请重试"
		save_failed = true
	if key == "appearance": set_appearance(value)
	apply_preferences()

func set_appearance(value: String) -> void:
	preferences.appearance = value
	# Visual changes never stop the session or engine and never reset its clock.
	if value == "wood" and wood_view == null:
		wood_view = load("res://scripts/shogi_wood_view.gd").new()
		wood_view.app = self
		add_child(wood_view)
	elif value != "wood" and wood_view != null:
		var old = wood_view
		wood_view = null
		remove_child(old)
		old.queue_free()
	_refresh()

func _redraw() -> void:
	if board_view != null: board_view.queue_redraw()
	if wood_view != null:
		wood_view.update_selection()
		wood_view.update_drag()

func safe_rect() -> Rect2:
	var rect = Rect2(Vector2.ZERO, size)
	if OS.has_feature("mobile"):
		var safe = Rect2(DisplayServer.get_display_safe_area())
		var screen_size = Vector2(DisplayServer.screen_get_size())
		if safe.has_area() and screen_size.x > 0 and screen_size.y > 0:
			rect = Rect2(safe.position * size / screen_size, safe.size * size / screen_size)
	return rect

func hand_slot(side: int, kind: int) -> Rect2:
	var slot = [7, 6, 5, 4, 3, 2, 1].find(kind)
	var bottom = (side == 1) != flipped
	if wide_layout:
		var player = bottom_player_rect if bottom else top_player_rect
		return Rect2(player.position.x + slot * player.size.x / 7, player.end.y + 4, player.size.x / 7, 42)
	var width = board_rect.size.x / 7.0
	var x = board_rect.position.x + (6 - slot if bottom else slot) * width
	var y = board_rect.end.y + 4 if bottom else board_rect.position.y - 46
	return Rect2(x, y, width, 42)

func hand_hit_rect(side: int, kind: int) -> Rect2:
	return hand_slot(side, kind)

func _view_game():
	return review_game if review_game != null else game

func _view_tokens() -> Array:
	var viewed = _view_game()
	return Motion.state(viewed.positions[0], viewed.moves, viewed.moves.size() if replay_index < 0 else replay_index)

func _leave_review() -> void:
	review_game = null
	review_path = ""
	replay_index = -1

func _set_replay(ply: int) -> void:
	if _study_active(): ui.study.seek(ply); return
	var before = _view_tokens()
	_pause_search()
	replay_index = clampi(ply, 0, _view_game().moves.size())
	_refresh()
	_present_transition(before, false)

func _continue_review() -> bool:
	if session != null or review_game == null or not _archive_game(): return false
	var data = review_game.to_data().duplicate(true)
	if replay_index >= 0 and replay_index < review_game.moves.size():
		Game.truncate_data(data, replay_index)
		for key in ["resigned", "resigned_side", "agreed_draw", "declared_side", "clock"]: data.erase(key)
	var next = Game.from_data(data)
	if next == null: return false
	if not testing and next.save_to(save_path) != OK:
		notice = "保存棋谱失败"
		save_failed = true
		_redraw()
		return false
	_pause_search()
	game = next
	engine_provider = game.engine_provider
	engine_level = game.engine_level
	flipped = game.human_side == -1
	_leave_review()
	_save()
	_refresh()
	return true

func _cancel_motion() -> void:
	if is_instance_valid(motion_tween): motion_tween.kill()
	motion_progress = 1.0
	transition.clear()

func _present_transition(before: Array, sound: bool = true, visual_start: Dictionary = {}) -> void:
	# A replay tap may interrupt a capture, promotion or drop. Rebase every
	# physical piece on the pose on screen, before killing the previous tween.
	var rendered = {}
	if motion_progress < 1.0 and before == visual_tokens:
		for track in transition:
			var pose = {"visual_rect": board_view.motion_rect(track), "visual_value": board_view.motion_value(track)}
			if wood_view != null and wood_view.animated_nodes.has(track.id):
				pose["visual_pose"] = wood_view.motion_pose(track.id)
			rendered[track.id] = pose
	_cancel_motion()
	var after = _view_tokens()
	visual_tokens = after.duplicate(true)
	if before.size() != after.size() or (before == after and rendered.is_empty()): return
	transition = Motion.tracks(before, after)
	for track in transition:
		if rendered.has(track.id): track.merge(rendered[track.id])
		if visual_start.has(track.id): track["visual_start"] = visual_start[track.id]
	motion_progress = 0.0
	# Install the start pose in the same input event that commits the move.
	# A layout refresh must never expose the final position before this pose.
	if wood_view != null: wood_view.animate_tracks(transition, 0.0)
	_redraw()
	motion_tween = preload("res://scripts/shogi_rendered_tween.gd").new()
	add_child(motion_tween)
	motion_tween.begin(self, preferences.studio.animation,
		func(value): motion_progress = value; _redraw(); if wood_view != null: wood_view.animate_tracks(transition, value),
		func():
			transition.clear()
			if sound: _play_sound()
			if game.mode == "local" and session == null and preferences.auto_flip and replay_index < 0:
				flipped = game.position.turn == -1
				_layout()
			if wood_view != null: wood_view.sync()
			_redraw()
	)

func _play_sound(preview: bool = false) -> void:
	if audio_player != null and (preferences.sound or preview):
		audio_player.volume_db = linear_to_db(maxf(0.0001, preferences.volume))
		audio_player.play()

func _ai_delay_done() -> bool:
	var delay = [300, 800, 1500][preferences.move_pace]
	if game.clock.preset != 0:
		var available: int = game.clock.remaining[game.position.turn] + game.clock.period_left
		if available < 2000: return true
	return Time.get_ticks_msec() - ai_started_at >= delay

func _deferred_engine() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if session == null: _load_engine()
