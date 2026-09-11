extends SceneTree
const Data = preload("res://scripts/shogi_openings.gd")
const Motion = preload("res://scripts/shogi_history_motion.gd")
var failures = []
var checks = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL: ", label)

func _init() -> void:
	var catalog = Data.catalog()
	check(catalog.size() == 9, "catalog makes no unsupported expansion claim")
	check(Data.search("", 0).size() == 7 and Data.search("", 1).size() == 2, "opening and castle categories")
	check(Data.search("", -1, -1).size() == 3 and Data.search("", -1, 1).size() == 9, "both-side examples match either side")
	check(Data.search("", 1, -1).is_empty(), "no unsupported gote castle example")
	for query in ["三间", "三間飛車", "third file", "　THIRD  ROOK　"]:
		check(Data.search(query).size() == 1 and Data.search(query)[0].id == 4, "normalized multilingual search " + query)
	check(Data.search("no-match").is_empty(), "search empty state")
	check(Data.search("三間", 1).is_empty(), "query respects category")
	check(Data.side_name(0) == "双方" and Data.side_name(-1) == "后手", "side labels describe repertoire owner")
	for entry in catalog:
		var game = Data.game_for(entry)
		check(game != null, "legal example " + entry.name)
		if game == null: continue
		check(game.moves.size() == entry.moves.split(" ", false).size(), "all source plies retained " + entry.name)
		check(not Data.notation(entry).is_empty(), "localized notation " + entry.name)
		for ply in [0, game.moves.size()]:
			var tokens = Motion.state(game.positions[0], game.moves, ply)
			check(tokens.size() == 40, "physical identity " + entry.name + " " + str(ply))
			var board = []
			board.resize(81); board.fill(0)
			for token in tokens:
				if token.square >= 0: board[token.square] = token.value
			check(board == Array(game.positions[ply].board), "preview agrees with legally replayed position " + entry.name)
	catalog[0].name = "changed"; catalog[0].moves = "7g7e"
	check(Data.catalog()[0].name == "角道开放", "catalog mutation cannot corrupt source")
	check(Data.game_for(catalog[0]) == null, "invalid preview is rejected")
	for invalid in [{}, {"moves": 12}, {"moves": ""}, {"moves": "7g7f ".repeat(900)}]:
		check(Data.game_for(invalid) == null, "malformed line is rejected")
	var output = ProjectSettings.globalize_path("res://../review/app/chessis29")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("openings-core.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	print("OPENINGS29: ", checks, " checks, failures: ", failures)
	quit(0 if failures.is_empty() else 1)
