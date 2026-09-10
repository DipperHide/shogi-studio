extends Node
## A private, cancellable 500 ms search after 250 ms without edits.
signal changed
const Bridge = preload("res://scripts/shogi_usi_engine.gd")
const Game = preload("res://scripts/shogi_game.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
var engine
var enabled = true
var position
var key = ""
var generation = 0
var due = -1
var details: Dictionary = {}
var error = ""
var searching = false
var threads = 1
var hash_size = 64
var launches = 0
var retries = 0
var requests: Array = []

func update(next, running: bool) -> void:
	var next_key: String = Codec.sfen(next) if next != null else ""
	if next_key == key and running == enabled: return
	generation += 1
	key = next_key
	position = next.copy() if next != null else null
	enabled = running
	details.clear()
	error = ""
	retries = 0
	searching = false
	due = -1
	if not enabled:
		stop_engine()
	else:
		if is_instance_valid(engine): engine.cancel()
		if position != null and Game.position_error(position).is_empty(): due = Time.get_ticks_msec() + 250
	changed.emit()

func stop_engine() -> void:
	if is_instance_valid(engine):
		engine.shutdown()
		engine.queue_free()
	engine = null

func _launch() -> void:
	engine = Bridge.new()
	engine.thread_count = threads
	engine.hash_size = hash_size
	engine.analysis_count = 1
	engine.pv_interval = 0
	add_child(engine)
	var active_engine = engine
	engine.analysis.connect(receive)
	engine.best_move.connect(func(id, _move, _special):
		if id == generation and enabled: searching = false; changed.emit()
	)
	engine.failed.connect(func(message):
		if engine != active_engine: return
		failed(message)
	)
	launches += 1
	engine.launch()

func failed(message: String) -> void:
	generation += 1
	searching = false
	details.clear()
	due = -1
	stop_engine()
	if enabled and position != null and Game.position_error(position).is_empty() and retries < 2:
		retries += 1
		error = ""
		due = Time.get_ticks_msec() + 500
	else: error = message
	changed.emit()

func receive(id: int, value: Dictionary) -> void:
	if id != generation or not enabled or position == null or not Game.position_error(position).is_empty(): return
	if not value.has("score") or not value.get("bound", "").is_empty(): return
	details = value.duplicate(true)
	changed.emit()

func _process(_delta: float) -> void:
	if not enabled or due < 0 or Time.get_ticks_msec() < due: return
	if not is_instance_valid(engine): _launch()
	if not is_instance_valid(engine) or not error.is_empty() or not engine.available(): return
	due = -1
	if position.legal_moves().is_empty():
		details = {"score": -1, "score_type": "mate", "depth": 0, "pv": []}
		changed.emit()
		return
	searching = true
	requests.append({"generation": generation, "sfen": key, "milliseconds": 500})
	while requests.size() > 50: requests.pop_front()
	engine.search(position, [], generation, 5, true, key, 500, {"milliseconds": 500})
	changed.emit()

func _exit_tree() -> void:
	generation += 1
	enabled = false
	due = -1
	stop_engine()
