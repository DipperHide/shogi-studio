extends "res://tests/unified_test.gd"
## Desktop-side driver for a real installed Android peer. Excluded from exports.
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
			if not app.promotion_moves.is_empty():
				for index in range(app.promotion_moves.size()):
					if app.promotion_moves[index].promote == move.promote:
						await tap(app.square_rect(app.promotion_cells[index]).get_center())
						break
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
	var state = {"platform": OS.get_name(), "command_id": command_id, "checks": checks,
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
