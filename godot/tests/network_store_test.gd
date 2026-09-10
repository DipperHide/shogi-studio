extends SceneTree
const Store = preload("res://scripts/shogi_network_store.gd")
const Session = preload("res://scripts/shogi_match_session.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
var checks = 0
var failures: Array[String] = []
var path: String

func check(value: bool, name: String) -> void:
	checks += 1
	if not value: failures.append(name); printerr("NETWORK STORE FAIL: ", name)

func raw(data: Variant) -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

func _initialize() -> void:
	var directory = ProjectSettings.globalize_path("res://../review/app/complete/network-store")
	DirAccess.make_dir_recursive_absolute(directory)
	path = directory.path_join("isolated-" + str(Time.get_ticks_usec()) + ".json")
	var store = Store.new()
	var session = Session.new()
	session.is_host = true
	session.room_code = "724613"
	session.match_id = "test-match"
	session.resume_token = "test-resume"
	session.game.mode = "local"
	session.game.clock.configure(1)
	check(store.write(path, session), "initial snapshot saved")
	session.game.play(Codec.parse_move("7g7f", session.game.position))
	check(store.write(path, session), "replacement saved with backup")
	var restored = store.read(path)
	check(not restored.is_empty() and restored.game.moves.size() == 1, "latest legal history restored")
	check(restored.meta.token == session.resume_token and restored.meta.match == session.match_id, "credentials restored atomically with history")
	check(restored.game.clock_authority and restored.game.clock.paused, "restored host clock waits for connection")
	var valid: Dictionary = restored.meta.duplicate(true)
	session.is_host = false
	session.local_side = -1
	check(store.write(path, session), "guest snapshot saved")
	check(not store.read(path).game.clock_authority, "guest cannot become clock authority on restore")
	# The previous valid host copy must survive corrupt-primary recovery and rewrite.
	raw({"broken": true})
	restored = store.read(path)
	check(store.recovered and restored.meta.is_host and restored.game.moves.size() == 1, "corrupt primary recovers previous valid snapshot")
	check(store.write(path, session), "write succeeds after recovery")
	raw({"broken": true})
	restored = store.read(path)
	check(store.recovered and not restored.is_empty() and restored.meta.is_host, "recovery rewrite preserves valid backup")
	check(store.clear(path), "clear removes all snapshot generations")
	check(store.read(path).is_empty() and store.error.is_empty(), "explicit exit cannot resurrect backup")
	for patch in [{"side": 0}, {"side": "1"}, {"port": 1024.5}, {"port": 65536}, {"is_host": 1}, {"transport": "unknown"}, {"token": 42}, {"version": 2}]:
		var malformed = valid.duplicate(true)
		malformed.merge(patch, true)
		raw(malformed)
		check(store.read(path).is_empty() and not store.error.is_empty(), "reject malformed metadata " + str(patch))
	var invalid = valid.duplicate(true)
	invalid.game.moves[0].to = 0
	raw(invalid)
	check(store.read(path).is_empty(), "reject illegal history before reconnect")
	check(not store.write(directory.path_join("missing-parent/snapshot.json"), session) and not store.error.is_empty(), "write error is reported")
	store.clear(path)
	session.free()
	var report = {"checks": checks, "failures": failures}
	var output = FileAccess.open(directory.get_base_dir().path_join("network-store-tests.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print("NETWORK_STORE_TESTS: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
