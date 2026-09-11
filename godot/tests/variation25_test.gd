extends SceneTree
const Game = preload("res://scripts/shogi_game.gd")
const Variations = preload("res://scripts/shogi_variation_tree.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Records = preload("res://scripts/shogi_records.gd")
var checks = 0
var failures: Array = []
var output = "res://../review/app/chessis25"

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func add(tree, parent: int, text: String) -> int:
	var id: int = tree.append(parent, Codec.parse_move(text, tree.nodes[parent].position))
	check(id > 0, "legal branch move " + text)
	return id

func data_game(tree, source):
	var data: Dictionary = source.to_data().duplicate(true)
	data.moves = tree.main.map(func(id): return tree.nodes[id].move)
	data.erase("clock")
	data.comments = {}
	data.annotations = {}
	var ids = [0] + tree.main
	for ply in range(ids.size()):
		if not tree.nodes[ids[ply]].comment.is_empty(): data.comments[str(ply)] = tree.nodes[ids[ply]].comment
		if not tree.nodes[ids[ply]].annotations.is_empty(): data.annotations[str(ply)] = tree.nodes[ids[ply]].annotations
	data.variations = tree.to_data()
	return Game.from_data(data)

func _initialize() -> void:
	if "--chessis26-regression" in OS.get_cmdline_user_args(): output = "res://../review/app/chessis26"
	if "--chessis27-regression" in OS.get_cmdline_user_args(): output = "res://../review/app/chessis27"
	if "--chessis28-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis28")
	output = ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(output)
	var source = Game.new()
	source.mode = "local"
	for text in ["7g7f", "3c3d", "8h2b+", "3a2b", "B*4e"]:
		check(source.play(Codec.parse_move(text, source.position)), "legal source " + text)
	source.comments = {"0": "初始说明", "3": "升变并交换角"}
	source.annotations = {"3": [[64, 10]]}
	var tree = Variations.from_game(source)
	check(tree != null and tree.main.size() == 5 and tree.nodes.size() == 6, "source becomes one main path")
	var main_before: Array = tree.main.duplicate()
	var alternative = add(tree, tree.main[0], "8c8d")
	var nested_a = add(tree, alternative, "2g2f")
	var nested_b = add(tree, alternative, "6g6f")
	var following = add(tree, nested_b, "8d8e")
	var following2 = add(tree, following, "7f7e")
	tree.nodes[nested_b].comment = "先让银将有路可走 [url=invalid]文本[/url]"
	tree.nodes[nested_b].annotations = [[0, 80]]
	check(tree.main == main_before, "adding nested alternatives preserves the main line")
	check(tree.path(following2) == [main_before[0], alternative, nested_b, following, following2], "nested path contains the exact ancestors")
	var size: int = tree.nodes.size()
	check(add(tree, alternative, "2g2f") == nested_a and tree.nodes.size() == size, "reusing an existing continuation does not duplicate it")
	check(tree.append(alternative, {"from": 0, "to": 80, "drop": 0, "promote": false}) < 0 and tree.nodes.size() == size, "illegal insertion is atomic")
	tree.cursor = nested_b
	var serialized: Dictionary = tree.to_data()
	var restored = Variations.from_data(JSON.parse_string(JSON.stringify(serialized)), source.positions[0], source.moves)
	check(restored != null and restored.to_data() == serialized, "nested tree, comments, drawings and cursor round-trip")
	var stored = data_game(tree, source)
	check(stored != null and stored.to_data().variations == serialized, "game JSON preserves the complete tree")
	check(tree.promote(nested_b) and tree.main == tree.path(following2), "promotion selects the nested continuation through its leaf")
	check(tree.nodes.has(main_before.back()) and tree.nodes[nested_a].parent == alternative, "promotion retains old main and sibling variation")
	var promoted = data_game(tree, source)
	check(promoted != null and promoted.comments.get("3") == tree.nodes[nested_b].comment and promoted.annotations.get("3") == [[0, 80]], "promoted comments and drawings follow their moves")
	check(promoted != null and Game.from_data(promoted.to_data()) != null, "promoted tree remains a legal saved game")
	var removed_parent: int = tree.nodes[alternative].parent
	check(tree.remove(alternative), "remove a whole nested variation")
	check(not tree.nodes.has(nested_a) and not tree.nodes.has(nested_b) and not tree.nodes.has(following2) and tree.cursor == removed_parent, "subtree removal clears descendants and returns the cursor to its parent")
	check(tree.main == [main_before[0]] and tree.nodes.has(main_before.back()), "removing a selected main branch preserves unrelated alternatives")
	tree = Variations.from_data(serialized, source.positions[0])
	check(tree != null and tree.to_data() == serialized, "undo restores the exact removed tree")
	var continued = Game.from_data(stored.to_data())
	check(continued.play(Codec.parse_move("8c8d", continued.position)), "live main line can continue with an attached tree")
	check(Game.from_data(continued.to_data()) != null and continued.variation_tree.main.size() == 6, "continued main line synchronizes with its tree")
	continued.undo()
	check(continued.moves.size() == 5 and continued.variation_tree.main.size() == 5 and Game.from_data(continued.to_data()) != null, "undo shortens the main line and preserves tree validity")
	var truncated: Dictionary = stored.to_data().duplicate(true)
	Game.truncate_data(truncated, 2)
	truncated.erase("clock")
	check(Game.from_data(truncated) != null and truncated.variations.main.size() == 2, "continue-from-position preserves future moves as alternatives")
	for change in [
		func(d): d.nodes[1].parent = 1,
		func(d): d.nodes[0].children.append(d.nodes[0].children[0]),
		func(d): d.nodes[0].children.clear(),
		func(d): d.nodes[1].move.to = 80,
		func(d): d.nodes[1].move.drop = 1.5,
		func(d): d.nodes[1].annotations = [[-1, 80]],
		func(d): d.nodes[1].comment = 42,
		func(d): d.main.reverse(),
		func(d): d.cursor = 999999,
		func(d): d.nodes[1].children.append(0),
		func(d): d.nodes[0].move = {"from": 1}
	]:
		var invalid: Dictionary = serialized.duplicate(true)
		change.call(invalid)
		check(Variations.from_data(invalid, source.positions[0], source.moves) == null, "reject malformed tree " + str(checks))
	var records = Records.new()
	records.root = output.path_join("records")
	var saved: String = records.archive(stored, "带嵌套变化的棋谱")
	check(not saved.is_empty() and records.read(saved).to_data().variations == serialized, "archive stores and reloads all nested variations")
	var bytes_before = FileAccess.get_file_as_bytes(saved)
	stored.comments["0"] = "界".repeat(Game.MAX_SAVE_BYTES / 2)
	check(not records.write(saved, stored, "过大的棋谱") and FileAccess.get_file_as_bytes(saved) == bytes_before, "oversized save preserves the existing readable record")
	var repeating = Game.new()
	repeating.set_initial("4k4/9/9/9/9/9/9/9/4K4 b - 1")
	var repeat_tree = Variations.from_game(repeating)
	var id = 0
	for _round in range(3):
		for move in ["5i4i", "5a4a", "4i5i", "4a5a"]: id = add(repeat_tree, id, move)
	check(repeat_tree.nodes[id].terminal and repeat_tree.append(id, Codec.parse_move("5i4i", repeat_tree.nodes[id].position)) < 0, "a variation stops at fourfold repetition")
	var transpositions = Variations.from_game(Game.new())
	var leaves: Array = []
	for sequence in [["7g7f", "3c3d", "2g2f", "8c8d"], ["2g2f", "8c8d", "7g7f", "3c3d"]]:
		var end = 0
		for move in sequence: end = add(transpositions, end, move)
		leaves.append(end)
	check(leaves[0] != leaves[1] and transpositions.nodes[leaves[0]].key == transpositions.nodes[leaves[1]].key, "transposed positions retain distinct move histories")
	transpositions.nodes[leaves[0]].comment = "此线路独有的注释"
	check(transpositions.nodes[leaves[1]].comment.is_empty(), "transposed positions do not share comments")
	var excessive = {"version": 1, "nodes": [], "main": []}
	excessive.nodes.resize(Variations.MAX_NODES + 1)
	check(Variations.from_data(excessive, source.positions[0]) == null, "oversized node collections are rejected before replay")
	FileAccess.open(output.path_join("variation-core.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	print("VARIATION25: ", checks, " checks; ", failures)
	quit(0 if failures.is_empty() else 1)
