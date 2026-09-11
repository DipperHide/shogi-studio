extends "res://scripts/shogi_import_job.gd"
const Historic = preload("res://scripts/shogi_historic_games.gd")

static func validate(entry: Dictionary, normalized: Dictionary):
	if normalized.get("plies", 0) != entry.plies: return null
	if entry.has("moves_sha256") and entry.moves_sha256 != normalized.get("moves_sha256", ""): return null
	var combined = entry.duplicate(true)
	combined.kif = normalized.get("kif", "")
	var game = Historic.new().game_for(combined)
	if game == null or game.moves.size() != int(entry.plies) or game.result.is_empty(): return null
	return game

func begin_record(entry: Dictionary, normalized: Dictionary) -> Error:
	var metadata = entry.duplicate(true)
	var record = normalized.duplicate(true)
	worker = Thread.new()
	var error = worker.start(func(): return {"game": validate(metadata, record)})
	if error != OK: worker = null
	return error
