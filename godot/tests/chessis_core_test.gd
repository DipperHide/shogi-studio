extends SceneTree
const Game = preload("res://scripts/shogi_game.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Exchange = preload("res://scripts/shogi_exchange.gd")
var failures: Array[String] = []
var checks = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL: ", message)

func _init() -> void:
	var codec = Exchange.new()
	var game = codec.parse("position startpos moves 7g7f 3c3d 8h2b+ 3a2b B*4e")
	check(game != null, "capture promotion and drop fixture")
	if game == null: quit(1); return
	game.comments["2"] = "角道开放\n考察下一步"
	game.metadata["先手"] = "测试者"
	game.annotations["1"] = [[56, 47]]
	for format in ["JSON", "KIF", "CSA", "USI"]:
		var text = Exchange.export_game(game, format)
		var restored = codec.parse(text)
		check(restored != null, "parse " + format + " " + codec.error)
		if restored == null: continue
		check(restored.position.key() == game.position.key(), "position roundtrip " + format)
		check(restored.moves == game.moves, "moves roundtrip " + format)
		if format in ["JSON", "KIF", "CSA"]: check(str(restored.comments.get("2", "")).strip_edges() == game.comments["2"], "comments " + format)
	var custom = Game.new()
	check(custom.set_initial(Codec.sfen(game.position)), "custom initial")
	custom.mode = "local"
	check(custom.play(custom.position.legal_moves()[0]), "move from custom position")
	for format in ["JSON", "KIF", "CSA", "USI"]:
		var restored = codec.parse(Exchange.export_game(custom, format))
		check(restored != null and restored.position.key() == custom.position.key(), "custom start roundtrip " + format + " " + codec.error)
	check(codec.parse("position startpos moves 7g7e") == null, "illegal move rejected")
	check(codec.parse("9/9/9/9/9/9/9/9/9 b - 1") == null, "missing kings rejected")
	var invalid = Game.Rules.new()
	invalid.board[45] = 1
	check(not Game.position_error(invalid).is_empty(), "nifu rejected")
	invalid = Game.Rules.new()
	invalid.hands[1][7] = 1
	check(not Game.position_error(invalid).is_empty(), "too many pieces rejected")
	for line in preload("res://scripts/shogi_openings.gd").LINES:
		check(preload("res://scripts/shogi_openings.gd").game_for(line) != null, "opening " + line.name)
	var legacy = Game.new().to_data()
	for key in ["initial_sfen", "metadata", "comments", "annotations", "engine_match"]: legacy.erase(key)
	check(Game.from_data(legacy) != null, "legacy save compatible")
	game.engine_match = true
	check(Game.from_data(game.to_data()).engine_match, "engine match persistence")
	print("CHESSIS CORE: ", checks, " checks, failures: ", failures)
	quit(0 if failures.is_empty() else 1)
