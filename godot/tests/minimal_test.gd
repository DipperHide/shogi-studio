extends RefCounted

const Rules = preload("res://scripts/shogi_rules.gd")
const Game = preload("res://scripts/shogi_game.gd")
var app
var checks: int = 0
var failures: Array[String] = []
var output: String
var screenshots: int = 0

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures.append(title)
		printerr("MINIMAL FAIL: ", title)

func settle() -> void:
	for i in range(4):
		await app.get_tree().process_frame
	while app.motion_progress < 1.0: await app.get_tree().process_frame

func capture(filename: String) -> void:
	await settle()
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw(false)
		await app.get_tree().process_frame
		app.get_viewport().get_texture().get_image().save_png(output + "/" + filename + ".png")
		screenshots += 1

func physical(point: Vector2) -> Vector2:
	return point * Vector2(app.get_window().size) / app.get_viewport().get_visible_rect().size

func touch(point: Vector2, pressed: bool, id: int = 0, canceled: bool = false) -> void:
	var event = InputEventScreenTouch.new()
	event.position = physical(point)
	event.pressed = pressed
	event.index = id
	event.canceled = canceled
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await settle()

func tap_point(point: Vector2) -> void:
	await touch(point, true)
	await touch(point, false)

func tap(square: int) -> void:
	await tap_point(app.square_rect(square).get_center())

func fixture(position = null) -> void:
	app._new_game()
	app.game.mode = "local"
	app.active = true
	if position != null:
		app.game.position = position
		app.game.positions = [position.copy()]
	app._refresh()

func empty() -> ShogiRules:
	var position = Rules.new(false)
	position.board[80] = 8
	position.board[0] = -8
	return position

func run(instance) -> void:
	app = instance
	app.get_tree().create_timer(120).timeout.connect(func(): printerr("MINIMAL TEST TIMEOUT"); app.get_tree().quit(1))
	output = ProjectSettings.globalize_path("res://../review/app/minimal")
	DirAccess.make_dir_recursive_absolute(output)
	await settle()
	check(app.game.mode == "ai" and app.game.human_side == 1, "launch directly into human-first offline game")
	check(app.find_children("*", "Node3D").is_empty(), "minimal scene loads no 3D geometry")
	check(app.audio_player != null, "minimal shares configurable placement audio")
	check(app.hand_rects[1].is_empty() and app.hand_rects[-1].is_empty(), "no hand UI before captures")
	check(app.legal.size() == 30, "initial legal moves shared with full rules")
	check(app.board_rect.size.x == app.board_rect.size.y, "9 by 9 board is square")
	for square in range(81):
		check(app._square_at(app.square_rect(square).get_center()) == square, "cell hit test %d" % square)
	await capture("01-board")
	fixture()
	await tap(58)
	check(app.selection == 58, "native touch selects text exactly once with mouse emulation enabled")
	await capture("02-selected")
	await tap(40)
	check(app.game.moves.is_empty() and app.selection == 58, "illegal two-square pawn move rejected")
	await tap(49)
	check(app.game.moves.size() == 1 and app.game.position.board[49] == 1 and app.game.position.turn == -1, "second tap commits legal move")
	await tap(22)
	await tap(31)
	check(app.game.moves.size() == 2, "same-device second side can move with rotated text")

	fixture()
	await touch(app.square_rect(58).get_center(), true)
	await touch(app.square_rect(57).get_center(), true, 1)
	await touch(app.square_rect(57).get_center(), false, 1)
	check(app.selection == -1, "secondary finger does not select")
	await touch(app.square_rect(58).get_center(), false, 0, true)
	check(app.selection == -1 and app.pointer_id == -2, "canceled touch never selects")
	await touch(app.square_rect(58).get_center(), true)
	await touch(app.square_rect(49).get_center(), false)
	check(app.selection == -1, "release on another square does not count as tap")
	await tap(58)
	await tap(58)
	check(app.selection == -1, "tap selected text again to cancel")

	var p = empty()
	p.board[20] = 7
	p.board[11] = -12
	fixture(p)
	await tap(20)
	await tap(11)
	check(app.promotion_moves.size() == 2 and app.game.moves.is_empty(), "optional promotion waits for a choice")
	await capture("03-promotion")
	await tap(app.promotion_cells[0])
	check(app.game.position.board[11] == 15 and app.game.position.hands[1][4] == 1, "promotion plus capture demotes captured piece into text hand")
	check(app.hand_rects[1].has(4), "captured piece has a tappable text area")
	await capture("04-captured-hand")

	p = empty()
	p.board[20] = 1
	fixture(p)
	await tap(20)
	await tap(11)
	await tap(app.promotion_cells[1])
	check(app.game.position.board[11] == 1, "optional non-promotion preserved")
	fixture(p)
	await tap(20)
	await tap(11)
	await tap_point(Vector2(1, 1))
	check(app.promotion_moves.is_empty() and app.game.moves.is_empty(), "tap outside promotion cancels without moving")
	p.board[20] = 0
	p.board[11] = 1
	fixture(p)
	await tap(11)
	await tap(2)
	check(app.game.position.board[2] == 9 and app.promotion_moves.is_empty(), "last-rank promotion is automatic")

	p = empty()
	p.hands[1][1] = 2
	p.hands[1][4] = 1
	p.board[58] = 1
	fixture(p)
	await tap_point(app.hand_rects[1][1].get_center())
	await tap(40)
	check(app.game.moves.is_empty() and app.selected_drop == 1, "nifu drop rejected by shared rules")
	await tap(41)
	check(app.game.position.board[41] == 1 and app.game.position.hands[1][1] == 1, "text hand tap then empty square drops a pawn")

	p = empty()
	for side in [1, -1]:
		for kind in range(1, 8):
			p.hands[side][kind] = 18 if kind == 1 else 2
	fixture(p)
	for dimensions in [Vector2i(320, 480), Vector2i(360, 640), Vector2i(390, 844), Vector2i(768, 1024), Vector2i(844, 390)]:
		app.get_window().content_scale_size = dimensions
		app.get_window().size = dimensions
		await settle()
		app._layout()
		var viewport = Rect2(Vector2.ZERO, app.size)
		check(viewport.encloses(app.board_rect), "board fits %s" % dimensions)
		check(viewport.encloses(app.result_rect), "result fits %s" % dimensions)
		for side in [1, -1]:
			for rect in app.hand_rects[side].values():
				check(viewport.encloses(rect), "full hands fit %s side %d" % [dimensions, side])
		if dimensions.x == 390:
			await capture("05-portrait-full-hands")
	app.get_window().content_scale_size = Vector2i(480, 800)
	app.get_window().size = Vector2i(480, 800)
	await settle()

	fixture()
	app.game.mode = "ai"
	await tap(58)
	await tap(49)
	await tap(22)
	check(app.selection == -1 and app.game.moves.size() == 1, "human cannot move AI's pieces during thinking")
	app.ai_revision = app.revision
	app.thread = Thread.new()
	app.ai_engine = app.AI.new()
	app.thread.start(app.ai_engine.choose.bind(app.game.position.copy(), 120, 1))
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var deadline = Time.get_ticks_msec() + 4000
	while app.thread != null and Time.get_ticks_msec() < deadline:
		await app.get_tree().process_frame
	check(app.pending_ai.is_empty() and app.game.moves.size() == 1, "canceled AI completion cannot apply in background")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	app.engine_provider = "basic"
	app.auto_play = true
	deadline = Time.get_ticks_msec() + 4000
	while app.game.moves.size() < 2 and Time.get_ticks_msec() < deadline: await app.get_tree().process_frame
	app.auto_play = false
	await settle()
	check(app.game.moves.size() == 2 and app.game.position.turn == 1, "AI resumes with a legal reply on focus return")
	check(Game.from_data(app.game.to_data()) != null, "minimal game save replays legally")
	app.ai_revision = app.revision
	app.thread = Thread.new()
	app.ai_engine = app.AI.new()
	app.thread.start(app.ai_engine.choose.bind(app.game.position.copy(), 120, 1))
	app._new_game()
	deadline = Time.get_ticks_msec() + 4000
	while app.thread != null and Time.get_ticks_msec() < deadline:
		await app.get_tree().process_frame
	check(app.game.moves.is_empty() and app.pending_ai.is_empty(), "new game rejects obsolete AI response")

	fixture()
	var key = InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	app._key(key)
	check(app.selection == 58, "keyboard can select starting pawn")
	key.keycode = KEY_UP
	app._key(key)
	key.keycode = KEY_ENTER
	app._key(key)
	check(app.game.moves.size() == 1, "keyboard can move selected pawn")
	app.game.resign()
	app._refresh()
	await capture("06-result")
	await tap_point(app.result_rect.get_center())
	check(app.game.result.is_empty() and app.game.moves.is_empty(), "result text starts a fresh game")
	var report = {"checks": checks, "failures": failures, "screenshots": screenshots, "ok": failures.is_empty()}
	var file = FileAccess.open(output + "/ui-tests.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("MINIMAL_TESTS: ", JSON.stringify(report))
	app.get_tree().quit(0 if failures.is_empty() else 1)
