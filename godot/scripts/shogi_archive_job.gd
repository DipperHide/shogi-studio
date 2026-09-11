extends "res://scripts/shogi_import_job.gd"
const Records = preload("res://scripts/shogi_records.gd")
const Model = preload("res://scripts/shogi_archive_model.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
var lock = Mutex.new()
var stopped = false

func cancel() -> void:
	lock.lock(); stopped = true; lock.unlock()

func cancelled() -> bool:
	lock.lock(); var value = stopped; lock.unlock(); return value

func begin_index(directory: String, filters: Dictionary) -> Error:
	var chosen = filters.duplicate(true)
	worker = Thread.new()
	var error = worker.start(func():
		var store = Records.new(); store.root = directory
		var entries = store.list_all(cancelled)
		var selected = Model.select(entries,chosen)
		var error_text = ""
		if not chosen.sfen.is_empty():
			var target = Codec.parse_sfen(chosen.sfen)
			if target == null or not Records.Game.position_error(target).is_empty(): return {"entries":entries,"rows":[],"error":"SFEN 局面无效，请检查棋子和行棋方。"}
			var matching = []
			var key = target.key()
			for entry in selected:
				if cancelled(): return {"entries":[],"rows":[],"error":"cancelled"}
				var game = store.read(entry.path)
				if game != null and game.positions.any(func(pos): return pos.key()==key): matching.append(entry)
			selected = matching
		return {"entries":entries,"rows":selected,"error":error_text}
	)
	if error != OK: worker = null
	return error
