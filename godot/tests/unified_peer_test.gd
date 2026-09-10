extends "res://tests/unified_test.gd"
## Two real app processes, each with its own renderer, language and clock display.
var host: bool
var finished: bool = false

func run(instance) -> void:
	if "--device-peer" in OS.get_cmdline_user_args():
		var device_runner = load("res://tests/device_peer_test.gd").new()
		await device_runner.run(instance)
		return
	app = instance
	host = "host" in OS.get_cmdline_user_args()
	output = ProjectSettings.globalize_path("res://../review/app/unified")
	app.get_tree().create_timer(45).timeout.connect(func(): check(false, "peer deadline"); finish())
	app.set_preference("language", "ja" if host else "en")
	app.set_preference("color_mode", "dark" if host else "light")
	app.set_appearance("minimal" if host else "wood")
	check(app._prepare_network(), "prepare shared session")
	if host:
		check(app.session.host_tcp(19325, 1, "654321", "127.0.0.1", 1) == OK, "direct host listens")
	else:
		check(app.session.join_tcp("127.0.0.1", 19325, "654321") == OK, "direct guest joins")
	app._network_changed()
	check(await until(func(): return app.session.connected_ready), "authenticated connection")
	check(app.game.clock.preset == 1, "clock preset synchronized")
	for ply in range(5):
		check(await until(func(): return app.game.moves.size() >= ply), "both peers reach ply " + str(ply))
		if (ply % 2 == 0) != host: continue
		await settle(0.3)
		app.active = true
		var value = ["7g7f", "3c3d", "8h2b+", "3a2b", "B*5e"][ply]
		var move = app.Codec.parse_move(value, app.game.position)
		check(not move.is_empty(), "legal synchronized move " + value)
		app.selection = move.from
		app.selected_drop = move.drop
		var clock_before = app.game.clock.remaining[app.session.local_side]
		await settle(0.65)
		check(app.selection == move.from and app.selected_drop == move.drop, "periodic clock update preserves selection")
		var connection = app.session
		app.set_appearance("wood" if app.preferences.appearance == "minimal" else "minimal")
		check(app.session == connection and app.session.connected_ready, "skin switch preserves connection")
		check(app.game.clock.remaining[app.session.local_side] <= clock_before, "skin switch never resets clock")
		check(app.selection == move.from and app.selected_drop == move.drop, "skin switch preserves input")
		app._commit(move)
		app.set_appearance("wood" if app.preferences.appearance == "minimal" else "minimal")
		check(await until(func(): return app.game.moves.size() == ply + 1), "pending move commits once after switch")
	check(await until(func(): return app.game.moves.size() == 5), "capture promotion and drop synchronized")
	await settle(0.4)
	check(app.game.position.hands[-1][6] == 1, "captured bishop preserved")
	check(app.preferences.language == ("ja" if host else "en"), "interface language stays local")
	await capture("peer-" + ("host-ja" if host else "guest-en"))
	if not host: check(app.session.resign(), "guest resignation")
	check(await until(func(): return app.game.result_code == "resign"), "stable reason received")
	check(app.game.winner == 1, "winner independent of UI language")
	check(app.i18n.result(app.game) == ("先手の勝ち · 投了" if host else "Sente wins · Resignation"), "localized final result")
	await settle(0.7)
	finish()

func finish() -> void:
	if finished: return
	finished = true
	var report = {"checks": checks, "failures": failures, "key": app.game.position.key(), "moves": app.game.moves.size(), "result_code": app.game.result_code, "winner": app.game.winner, "language": app.preferences.language, "clock": app.game.clock.to_data()}
	var role = "host" if host else "guest"
	var file = FileAccess.open(output.path_join("peer-" + role + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("UNIFIED_PEER_", role.to_upper(), ": ", checks, " checks, ", failures.size(), " failures")
	app._leave_network()
	app.set_appearance("minimal")
	await settle(0.2)
	app.get_tree().quit(0 if failures.is_empty() else 1)
