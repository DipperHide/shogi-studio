extends SceneTree
const Application = preload("res://scripts/shogi_app.gd")
const Session = preload("res://scripts/shogi_match_session.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
class Harness extends Application:
	func _ready() -> void:
		set_process(false)
		set_process_input(false)
class QuietUI extends RefCounted:
	var page_name = ""
	var sheet = false
	func update_connection(): pass
	func show_offer(): pass
	func show_connection(): pass

var checks = 0
var failures: Array[String] = []
var directory: String
var snapshot_path: String
var app
var guest

func check(value: bool, name: String) -> void:
	checks += 1
	if not value: failures.append(name); printerr("NETWORK RESTORE FAIL: ", name)

func until(predicate: Callable, seconds: float = 4) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	return predicate.call()

func make_app():
	var instance = Harness.new()
	instance.ui = QuietUI.new()
	instance.network_save_path = snapshot_path
	instance.save_path = directory.path_join("local.json")
	instance.records.root = directory.path_join("records")
	root.add_child(instance)
	return instance

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	directory = ProjectSettings.globalize_path("res://../review/app/complete/network-restore")
	DirAccess.make_dir_recursive_absolute(directory)
	snapshot_path = directory.path_join("snapshot-" + str(Time.get_ticks_usec()) + ".json")
	app = make_app()
	check(app._host_network(29539, 1, 1) == OK, "application creates persisted host")
	guest = Session.new()
	root.add_child(guest)
	check(guest.join_tcp("127.0.0.1", 29539, app.session.room_code) == OK, "guest starts connection")
	check(await until(func(): return app.session.connected_ready and guest.connected_ready), "initial handshake")
	check(app.session.reconnect() == OK and guest.reconnect() == OK, "reconnect on an active match is harmless")
	check(app.session.connected_ready and guest.connected_ready, "reconnect button cannot revoke an already completed handshake")
	check(app.session.submit(Codec.parse_move("7g7f", app.game.position)), "host plays first move")
	check(await until(func(): return guest.game.moves.size() == 1), "guest acknowledges initial move")
	check(guest.submit(Codec.parse_move("3c3d", guest.game.position)), "guest plays reply")
	check(await until(func(): return app.game.moves.size() == 2 and guest.game.moves.size() == 2), "reply persisted by application")
	var key: String = app.game.position.key()
	var token: String = guest.resume_token
	var match_id: String = guest.match_id
	app._save_network()
	app.free() # Simulate process shutdown: do not intentionally leave/delete the match.
	check(await until(func(): return not guest.connected_ready), "guest observes host shutdown")
	app = make_app()
	app._restore_network()
	check(app.session != null and app.game.position.key() == key, "application restart restores exact game")
	check(not app.session.connected_ready and app.game.clock.paused, "restored clock waits for peer")
	check(app.session.resume_token == token and app.session.match_id == match_id, "restart preserves the opponent identity")
	check(app.session.reconnect() == OK and guest.reconnect() == OK, "both reconnect using saved identity")
	check(await until(func(): return app.session.connected_ready and guest.connected_ready), "restored sessions finish handshake")
	check(app.game.position.key() == guest.game.position.key() and guest.resume_token == token, "resumed history and credentials agree")
	check(app.session.submit(Codec.parse_move("2g2f", app.game.position)), "game remains playable after restart")
	check(await until(func(): return guest.game.moves.size() == 3), "resumed move delivered exactly once")
	app._save_network()
	app.free()
	await until(func(): return not guest.connected_ready)
	var f = FileAccess.open(snapshot_path, FileAccess.WRITE)
	f.store_string("{interrupted")
	f.close()
	app = make_app()
	app._restore_network()
	check(app.session != null and app.game.moves.size() >= 2, "application recovers corrupt primary from legal backup")
	check(app._leave_network(), "intentional exit clears reconnect state")
	check(not FileAccess.file_exists(snapshot_path) and not FileAccess.file_exists(snapshot_path + ".bak"), "exit removes primary and backup")
	app._restore_network()
	check(app.session == null, "relaunch after exit cannot resurrect match")
	app.free()
	guest.free()
	var report = {"checks": checks, "failures": failures, "transport": "loopback TCP", "restart_recovery": true}
	var out = FileAccess.open(directory.get_base_dir().path_join("network-restore-tests.json"), FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "  "))
	out.close()
	print("NETWORK_RESTORE_TESTS: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
