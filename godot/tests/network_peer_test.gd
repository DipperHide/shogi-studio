extends SceneTree
## Two independently launched processes use the same public match API as the UI.
const Session = preload("res://scripts/shogi_match_session.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
var session
var host: bool
var checks: int = 0
var failures: Array[String] = []
var notices: Array[String] = []
var rejected: int = 0
var finished: bool = false

func _initialize() -> void:
	host = "host" in OS.get_cmdline_user_args()
	create_timer(45).timeout.connect(func(): check(false, "peer timeout"); finish())
	call_deferred("run")

func check(value: bool, name: String) -> void:
	checks += 1
	if not value:
		failures.append(name)
		printerr("NETWORK FAIL: ", name)

func until(predicate: Callable, seconds: float = 8.0) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return predicate.call()

func move(value: String) -> bool:
	return session.submit(Codec.parse_move(value, session.game.position))

func run() -> void:
	session = Session.new()
	root.add_child(session)
	session.status_changed.connect(func(message): notices.append(message))
	session.rejected.connect(func(_message): rejected += 1)
	if host:
		check(session.host_tcp(19321, 1, "654321", "127.0.0.1") == OK, "host listens")
		session.offer_received.connect(func(_action, local):
			if not local:
				check(session.answer(true), "host accepts peer request")
		)
		check(await until(func(): return session.connected_ready), "host authenticated peer")
		check(move("7g7f"), "host first move")
		check(await until(func(): return session.game.moves.size() == 2), "host receives guest move")
		check(move("2g2f"), "host third move")
		check(await until(func(): return not session.connected_ready), "host detects disconnect")
		check(not session.can_move(), "host cannot play disconnected")
		check(await until(func(): return session.connected_ready), "host accepts authenticated resume")
		check(await until(func(): return session.game.agreed_draw), "host reaches agreed draw")
		check(await until(func(): return session.game.moves.is_empty() and session.local_side == -1), "rematch swaps host seat")
		check(await until(func(): return session.game.moves.size() == 1), "host receives rematch first move")
		check(session.resign(), "host resigns on own turn")
		await create_timer(0.8).timeout
		finish()
		return
	check(session.join_tcp("127.0.0.1", 19321, "654321") == OK, "guest connection begins")
	check(await until(func(): return session.connected_ready and session.game.moves.size() == 1), "guest authenticated and receives move")
	check(session.local_side == -1, "guest seat assigned")
	var old_key = session._key()
	check(move("3c3d"), "guest sends legal move")
	check(session.pending_move and session._key() == old_key, "guest waits for authority before changing board")
	check(not move("4c4d"), "second unacknowledged move blocked")
	check(await until(func(): return session.game.moves.size() == 3), "guest receives ack and host reply")
	var saved_key = session._key()
	var saved_token = session.resume_token
	session.link.disconnect_peer()
	check(not session.can_move(), "guest cannot play disconnected")
	await create_timer(0.3).timeout
	check(session.reconnect() == OK, "guest reconnects")
	check(await until(func(): return session.connected_ready), "guest resume handshake")
	check(session._key() == saved_key and session.resume_token == saved_token, "resume restores exact board and identity")
	check(move("8c8d"), "guest moves after reconnect")
	check(await until(func(): return session.game.moves.size() == 4), "resumed move acknowledged")
	# Inject protocol-level bad moves rather than testing only local validation.
	check(session.link.send({"v": 1, "type": "move", "match": session.match_id, "ply": 4, "before": session._key(), "move": "4c4d"}), "send out-of-turn packet")
	check(await until(func(): return rejected == 1), "authority rejects out-of-turn packet")
	check(session.game.moves.size() == 4, "rejected move preserves history")
	check(session.request("undo"), "guest requests undo")
	check(await until(func(): return session.game.moves.size() == 3 and session.offer.is_empty()), "agreed undo synchronized")
	check(session.link.send({"v": 1, "type": "move", "match": session.match_id, "ply": 3, "before": session._key(), "move": "1a9i"}), "send illegal geometry")
	check(await until(func(): return rejected == 2), "authority rejects illegal geometry")
	check(session.game.moves.size() == 3, "illegal move does not alter board")
	check(move("8c8d"), "move after undo")
	check(await until(func(): return session.game.moves.size() == 4), "move after undo acknowledged")
	check(session.request("draw"), "guest requests draw")
	check(await until(func(): return session.game.agreed_draw), "draw agreed and synchronized")
	check(not session.can_move(), "no moves after draw")
	check(session.game.from_data(session.game.to_data()).agreed_draw, "agreed draw survives save/load")
	check(session.request("rematch"), "guest requests rematch")
	check(await until(func(): return session.game.moves.is_empty() and session.local_side == 1), "rematch swaps guest seat and resets game")
	check(move("7g7f"), "guest plays first in rematch")
	check(await until(func(): return session.game.resigned), "remote resignation synchronized")
	check(session.game.resigned_side == -1 and "先手获胜" in session.game.result, "correct winner after seat swap")
	finish()

func finish() -> void:
	if finished:
		return
	finished = true
	var report = {"checks": checks, "failures": failures, "notices": notices, "key": session._key() if session != null else "", "result": session.game.result if session != null else "", "transport": "TCP IPv4 loopback, independent processes", "internet_tested": false, "bluetooth_tested": false}
	var path = ProjectSettings.globalize_path("res://../review/app/complete/network-" + ("host" if host else "guest") + ".json")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	if session != null:
		session.link.stop()
	print("NETWORK ", "host" if host else "guest", ": ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
