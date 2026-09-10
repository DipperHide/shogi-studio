extends SceneTree
const Library = preload("res://scripts/shogi_historic_games.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")

func _initialize() -> void:
	var library = Library.new()
	var evidence = []
	var failures = []
	var total = 0
	for entry in Library.entries():
		var game = library.game_for(entry)
		if game == null:
			failures.append({"id": entry.id, "error": library.error})
			continue
		if game.moves.size() != int(entry.plies) or game.result.is_empty():
			failures.append({"id": entry.id, "error": "Ply count or terminal mismatch"})
		if not game.comments.is_empty(): failures.append({"id": entry.id, "error": "Unexpected editorial content"})
		total += game.moves.size()
		evidence.append({"id": entry.id, "plies": game.moves.size(), "result": game.result_code, "winner": game.winner, "final_sfen": Codec.sfen(game.position), "source": entry.source, "sha256": entry.sha256})
		print("VERIFIED ", entry.id, " ", game.moves.size())
	var path = ProjectSettings.globalize_path("res://../review/app/chessis20" if "--chessis20-regression" in OS.get_cmdline_user_args() else "res://../review/app/chessis09")
	DirAccess.make_dir_recursive_absolute(path)
	FileAccess.open(path.path_join("historic-validation.json"), FileAccess.WRITE).store_string(JSON.stringify({"games": evidence.size(), "plies": total, "failures": failures, "evidence": evidence}, "  "))
	print("HISTORIC: ", evidence.size(), " games, ", total, " plies, failures: ", failures)
	quit(0 if failures.is_empty() and evidence.size() >= 190 else 1)
