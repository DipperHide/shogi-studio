extends RefCounted
var app
var checks: int = 0
var failures: Array[String] = []
var output: String
var screenshots: Array[String] = []

func check(value: bool, name: String) -> void:
	checks += 1
	if not value: failures.append(name); printerr("UNIFIED FAIL: ", name)

func settle(seconds: float = 0.06) -> void:
	await app.get_tree().create_timer(seconds).timeout

func until(predicate: Callable, seconds: float = 12) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await app.get_tree().process_frame
	return predicate.call()

func capture(name: String) -> void:
	await settle()
	RenderingServer.force_draw(false)
	await app.get_tree().process_frame
	app.get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))
	screenshots.append(name)

func tap(point: Vector2) -> void:
	for pressed in [true, false]:
		var event = InputEventScreenTouch.new()
		event.index = 0
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await settle(0.025)

func click(source: String) -> void:
	for button in app.ui.root.find_children("*", "Button", true, false):
		if button.text == app.t(source) and button.is_visible_in_tree():
			var parent = button.get_parent()
			while parent != null:
				if parent is ScrollContainer: parent.ensure_control_visible(button)
				parent = parent.get_parent()
			await settle()
			for pressed in [true, false]:
				var event = InputEventMouseButton.new()
				event.position = button.get_global_rect().get_center()
				event.button_index = MOUSE_BUTTON_LEFT
				event.pressed = pressed
				Input.parse_input_event(event)
				Input.flush_buffered_events()
				await settle(0.025)
			return
	check(false, "button available: " + source)

func play(value: String) -> void:
	var move = app.Codec.parse_move(value, app.game.position)
	check(not move.is_empty(), "legal fixture move " + value)
	app._commit(move)
	await settle(0.25)

func resize(dimensions: Vector2i) -> void:
	app.get_window().content_scale_size = dimensions
	app.get_window().size = dimensions
	await settle(0.12)
	app._layout()

var command_path: String
var command_id: int = -1
var running: bool = true

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/cross-device")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--device-output="):
			output = ProjectSettings.globalize_path(argument.trim_prefix("--device-output="))
	DirAccess.make_dir_recursive_absolute(output)
	command_path = ProjectSettings.globalize_path("res://../.work/device-peer-command.json")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--peer-command="): command_path = argument.trim_prefix("--peer-command=")
	app.get_window().title = "将棋 · Windows ↔ Android 联机测试"
	app.set_preference("language", "zh")
	app.set_preference("color_mode", "light")
	await settle(0.3)
	while running:
		if FileAccess.file_exists(command_path):
			var command = JSON.parse_string(FileAccess.get_file_as_string(command_path))
			if command is Dictionary and command.get("id", -1) > command_id:
				command_id = int(command.id)
				await execute(command)
		write_state()
		await settle(0.15)
	app.get_tree().quit(0 if failures.is_empty() else 1)

func execute(command: Dictionary) -> void:
	app.active = true
	match command.get("action", ""):
		"host":
			app.ui.show_host()
			app.ui.page.find_child("端口", true, false).text = str(int(command.get("port", 19325)))
			await click("创建")
			check(app.session != null and app.session.is_host, "Windows creates a real TCP host")
		"join":
			app.ui.show_join()
			app.ui.page.find_child("对方地址", true, false).text = command.address
			app.ui.page.find_child("端口", true, false).text = str(int(command.port))
			app.ui.page.find_child("六位房间码", true, false).text = command.code
			await click("连接")
		"move":
			app.ui.close()
			await settle(0.3)
			var move = app.Codec.parse_move(command.move, app.game.position)
			check(not move.is_empty() and app._can_play(), "Windows input ready for " + command.move)
			if move.is_empty() or not app._can_play(): return
			if move.drop > 0:
				await tap(app.hand_slot(app.session.local_side, move.drop).get_center())
			else:
				await tap(app.square_rect(move.from).get_center())
			await tap(app.square_rect(move.to).get_center())
			if app.ui.page_name == "promotion": await click("升变" if move.promote else "不变")
			if app.ui.page_name == "confirm-move": await click("确认落子")
		"answer":
			app.ui.show_offer()
			await click("同意" if command.accept else "不同意")
		"request":
			check(app.session.request(command.offer), "Windows sends " + command.offer + " offer")
		"disconnect":
			app.session.link.disconnect_peer()
		"reconnect":
			check(app.session.reconnect() == OK, "Windows starts reconnect")
		"board":
			app.ui.close()
		"connection":
			app.ui.show_connection()
		"appearance":
			app.set_appearance(command.appearance)
		"capture":
			await capture(command.name)
		"leave":
			check(app._leave_network(), "Windows leaves test session")
		"finish":
			if app.session != null: app._leave_network()
			running = false
		_:
			check(false, "Unknown device-peer command")
	await settle(0.25)
	print("DEVICE_PEER_COMMAND: ", command_id, " ", command.get("action"))

func write_state() -> void:
	var session = app.session
	var state = {"platform": OS.get_name(), "version": ProjectSettings.get_setting("application/config/version"), "executable": OS.get_executable_path(), "command_id": command_id, "checks": checks,
		"failures": failures, "connected": session != null and session.connected_ready,
		"status": app.network_status, "page": app.ui.page_name, "game": app.game.to_data(),
		"position_key": app.game.position.key(), "result": app.game.result_code, "winner": app.game.winner}
	if session != null:
		state.merge({"is_host": session.is_host, "side": session.local_side, "port": session.port,
			"room": session.room_code, "match": session.match_id, "offer": session.offer,
			"address": session.address})
	var path = output.path_join("windows-state.json")
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(state, "  "))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
