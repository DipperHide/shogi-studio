extends SceneTree

const Codec = preload("res://scripts/shogi_usi_codec.gd")
const EngineClient = preload("res://scripts/shogi_usi_engine.gd")
const Rules = preload("res://scripts/shogi_rules.gd")
var failures: Array[String] = []
var checks: int = 0
var client
var received: Dictionary = {}
var last_info: Dictionary = {}
var errors: Array[String] = []

func _initialize() -> void:
	create_timer(50).timeout.connect(func(): printerr("USI TEST TIMEOUT"); quit(1))
	call_deferred("run")

func check(value: bool, name: String) -> void:
	checks += 1
	if not value:
		failures.append(name)
		printerr("USI FAIL: ", name)

func until(predicate: Callable, seconds: float = 10.0) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return predicate.call()

func run() -> void:
	var position = Rules.new()
	check(Codec.sfen(position) == "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1", "standard initial SFEN")
	for i in range(81):
		check(Codec.parse_square(Codec.square_name(i)) == i, "USI square roundtrip %d" % i)
	for invalid in ["", "7z", "0a", "10a", "a7", "7a\n"]:
		check(Codec.parse_square(invalid) == -1, "invalid square rejected: %s" % invalid)
	var moves: Array = []
	seed(2431)
	for ply in range(90):
		var parsed = Codec.parse_sfen(Codec.sfen(position, ply + 1))
		check(parsed != null and parsed.key() == position.key(), "SFEN roundtrip ply %d" % ply)
		var legal = position.legal_moves()
		if legal.is_empty():
			break
		var move: Dictionary = legal[randi() % legal.size()]
		check(Codec.parse_move(Codec.move_name(move), position) == move, "USI move roundtrip ply %d" % ply)
		moves.append(move)
		position = position.after(move)
	for invalid in ["9/9/9/9/9/9/9/9/8 b - 1", "9/9/9/9/9/9/9/9/+9 b - 1", "9/9/9/9/9/9/9/9/9 b 99P 1", "9/9/9/9/9/9/9/9/9 b 0P 1"]:
		check(Codec.parse_sfen(invalid) == null, "invalid SFEN rejected")
	var info = Codec.parse_info("info depth 14 multipv 2 score cp -53 nodes 994 nps 8000 pv 7g7f 3c3d")
	check(info.depth == 14 and info.multipv == 2 and info.score == "-53" and info.pv == ["7g7f", "3c3d"], "MultiPV info parsing")
	check(Codec.parse_info("info string loading").is_empty(), "diagnostic text is not analysis")
	client = EngineClient.new()
	root.add_child(client)
	client.best_move.connect(func(id, move, special): received[id] = {"move": move, "special": special})
	client.analysis.connect(func(id, details): last_info[id] = details)
	client.failed.connect(func(message): errors.append(message); printerr("ENGINE ERROR: ", message))
	check(client.launch() == OK, "official engine process launches")
	check(await until(func(): return client.available() or client.phase == "error", 30.0) and client.available(), "USI handshake and NNUE model ready")
	if not client.available():
		finish()
		return
	check("YaneuraOu" in client.engine_name, "actual YaneuraOu identity")
	check(client.options.has("MultiPV") and client.options.has("FV_SCALE"), "actual engine capabilities discovered")
	position = Rules.new()
	for level in range(6):
		var id = 10 + level
		check(client.search(position, [], id, level), "request difficulty %d" % level)
		check(await until(func(): return received.has(id), 10.0), "difficulty %d completes" % level)
		check(received.has(id) and received[id].move in position.legal_moves(), "difficulty %d returns legal move" % level)
	check(client.search(position, [], 50, 5, true), "analysis starts")
	check(await until(func(): return client.variation_lines.size() == 3 or received.has(50)), "analysis produces output")
	check(client.variation_lines.size() == 3, "three actual candidate variations")
	client.cancel()
	check(await until(func(): return client.phase == "ready"), "stop drains response and restores ready")
	check(not received.has(50), "canceled result never emitted")
	check(client.search(position, [], 60, 5, true), "long analysis starts before superseding")
	var move = Codec.parse_move("7g7f", position)
	var next = position.after(move)
	check(client.search(next, [move], 61, 1), "next request supersedes old analysis")
	check(await until(func(): return received.has(61)) and received[61].move in next.legal_moves(), "replacement request uses exact history and side")
	check(not received.has(60), "obsolete response not applied")
	var started = Time.get_ticks_msec()
	check(client.search(next, [move], 62, 5, false, "startpos", 200), "strongest level accepts remaining-clock budget")
	check(await until(func(): return received.has(62), 1.5), "clock-limited search returns before normal strongest budget")
	check(received.has(62) and received[62].move in next.legal_moves(), "clock-limited move is legal")
	check(Time.get_ticks_msec() - started < 1200, "clock budget shortens actual engine thinking")
	check(errors.is_empty(), "no process or protocol errors")
	var pid: int = client.process.pid
	client.shutdown()
	check(not OS.is_process_running(pid), "engine child terminates on shutdown")
	finish()

func finish() -> void:
	var out = ProjectSettings.globalize_path("res://../review/app/complete")
	DirAccess.make_dir_recursive_absolute(out)
	var report = {"checks": checks, "failures": failures, "engine": client.engine_name if client != null else "", "errors": errors, "sample_analysis": last_info, "transcript": client.transcript if client != null else []}
	var file = FileAccess.open(out.path_join("usi-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("USI_TESTS: ", JSON.stringify({"checks": checks, "failures": failures, "errors": errors}))
	quit(0 if failures.is_empty() else 1)
