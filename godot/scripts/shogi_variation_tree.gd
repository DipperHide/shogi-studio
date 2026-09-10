extends RefCounted
## A legal move tree. The main line is an explicit path, so undo can retain
## the old continuation without silently making it part of the main line.
const Rules = preload("res://scripts/shogi_rules.gd")
const MAX_NODES = 4096
const MAX_PLY = 2000
var nodes: Dictionary = {}
var main: Array = []
var cursor: int = 0
var next_id: int = 1
var error: String = ""

func initialize(initial: ShogiRules) -> void:
	nodes = {0: {"parent": -1, "children": [], "move": {}, "position": initial.copy(), "key": initial.key(), "depth": 0, "comment": "", "annotations": [], "terminal": false}}
	main.clear()
	cursor = 0
	next_id = 1

static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value) and value >= minimum and value <= maximum

static func move_value(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not raw.get("promote") is bool: return {}
	if not integer(raw.get("from"), -1, 80) or not integer(raw.get("to"), 0, 80) or not integer(raw.get("drop"), 0, 7): return {}
	return {"from": int(raw.from), "to": int(raw.to), "drop": int(raw.drop), "promote": raw.promote}

static func valid_marks(value: Variant) -> bool:
	if not value is Array or value.size() > 64: return false
	for mark in value:
		if not mark is Array or mark.size() != 2: return false
		for square in mark:
			if not integer(square, 0, 80): return false
	return true

static func canonical_marks(value: Array) -> Array:
	return value.map(func(mark): return [int(mark[0]), int(mark[1])])

func path(id: int) -> Array:
	if not nodes.has(id): return []
	var result: Array = []
	while id > 0:
		result.push_front(id)
		id = nodes[id].parent
	return result

func append(parent: int, raw: Dictionary) -> int:
	error = ""
	var move = move_value(raw)
	if not nodes.has(parent) or move.is_empty(): return -1
	for child in nodes[parent].children:
		if nodes[child].move == move: return child
	if nodes.size() >= MAX_NODES or nodes[parent].depth >= MAX_PLY:
		error = "这份棋谱的变化数量已达到上限。"
		return -1
	if nodes[parent].terminal or not nodes[parent].position.is_legal_move(move):
		error = "这一步不合法，或所在变化已经终局。"
		return -1
	var pos: ShogiRules = nodes[parent].position.after(move)
	var key = pos.key()
	var occurrences = 1
	var ancestor = parent
	while ancestor >= 0:
		if nodes[ancestor].key == key: occurrences += 1
		ancestor = nodes[ancestor].parent
	var id = next_id
	next_id += 1
	nodes[id] = {"parent": parent, "children": [], "move": move, "position": pos, "key": key, "depth": nodes[parent].depth + 1,
		"comment": "", "annotations": [], "terminal": occurrences >= 4 or pos.legal_moves(false, true).is_empty()}
	nodes[parent].children.append(id)
	return id

func append_main(move: Dictionary) -> int:
	var id = append(main.back() if not main.is_empty() else 0, move)
	if id >= 0:
		main.append(id)
		cursor = id
	return id

func main_notes(comments: Dictionary, annotations: Dictionary) -> void:
	var ids = [0] + main
	for ply in range(ids.size()):
		nodes[ids[ply]].comment = str(comments.get(str(ply), ""))
		nodes[ids[ply]].annotations = canonical_marks(annotations.get(str(ply), []))

func main_next(id: int) -> int:
	var index = -1 if id == 0 else main.find(id)
	if id != 0 and index < 0: return -1
	return main[index + 1] if index + 1 < main.size() else -1

func line_through(id: int) -> Array:
	var result = path(id)
	if not nodes.has(id): return result
	while not nodes[id].children.is_empty():
		var next = main_next(id)
		# The main line may intentionally end before a retained continuation.
		if (id == 0 or id in main) and next < 0: break
		id = next if next >= 0 else nodes[id].children[0]
		result.append(id)
	return result

func promote(id: int) -> bool:
	if id <= 0 or not nodes.has(id): return false
	var line = path(id)
	var end = id
	while not nodes[end].children.is_empty():
		end = nodes[end].children[0]
		line.append(end)
	main = line
	cursor = id
	return true

func remove(id: int) -> bool:
	if id <= 0 or not nodes.has(id): return false
	var parent: int = nodes[id].parent
	var removed: Array = [id]
	var index = 0
	while index < removed.size():
		removed.append_array(nodes[removed[index]].children)
		index += 1
	nodes[parent].children.erase(id)
	if id in main: main = main.slice(0, main.find(id))
	if cursor in removed: cursor = parent
	for item in removed: nodes.erase(item)
	return true

func to_data() -> Dictionary:
	var order: Array = []
	var pending: Array = [0]
	while not pending.is_empty():
		var id: int = pending.pop_back()
		order.append(id)
		var children: Array = nodes[id].children.duplicate()
		children.reverse()
		pending.append_array(children)
	var indices: Dictionary = {}
	for i in range(order.size()): indices[order[i]] = i
	var serialized: Array = []
	for id in order:
		var node: Dictionary = nodes[id]
		serialized.append({"parent": indices[node.parent] if id > 0 else -1, "children": node.children.map(func(child): return indices[child]),
			"move": node.move.duplicate(), "comment": node.comment, "annotations": node.annotations.duplicate(true)})
	return {"version": 1, "nodes": serialized, "main": main.map(func(id): return indices[id]), "cursor": indices.get(cursor, 0)}

static func from_data(data: Variant, initial: ShogiRules, expected_main: Variant = null):
	if not data is Dictionary or data.get("version") != 1 or not data.get("nodes") is Array or not data.get("main") is Array: return null
	if data.nodes.is_empty() or data.nodes.size() > MAX_NODES or data.main.size() > MAX_PLY: return null
	var tree = load("res://scripts/shogi_variation_tree.gd").new()
	tree.initialize(initial)
	for id in range(data.nodes.size()):
		var raw = data.nodes[id]
		if not raw is Dictionary or not raw.get("children") is Array or not raw.get("comment", "") is String or raw.get("comment", "").length() > 20000 or not valid_marks(raw.get("annotations", [])): return null
		if id == 0:
			if raw.get("parent") != -1 or raw.get("move", {}) != {}: return null
		else:
			if not integer(raw.get("parent"), 0, id - 1): return null
			var move = move_value(raw.get("move"))
			if move.is_empty() or tree.append(int(raw.parent), move) != id: return null
		tree.nodes[id].comment = raw.get("comment", "")
		tree.nodes[id].annotations = canonical_marks(raw.get("annotations", []))
	for id in range(data.nodes.size()):
		var children: Array = []
		for child in data.nodes[id].children:
			if not integer(child, id + 1, data.nodes.size() - 1) or int(child) in children or tree.nodes[int(child)].parent != id: return null
			children.append(int(child))
		if children.size() != tree.nodes[id].children.size(): return null
		tree.nodes[id].children = children
	var previous = 0
	for value in data.main:
		if not integer(value, 1, data.nodes.size() - 1) or tree.nodes[int(value)].parent != previous: return null
		previous = int(value)
		tree.main.append(previous)
	if expected_main != null:
		if not expected_main is Array or tree.main.size() != expected_main.size(): return null
		for i in range(tree.main.size()):
			if tree.nodes[tree.main[i]].move != expected_main[i]: return null
	if not integer(data.get("cursor", 0), 0, data.nodes.size() - 1): return null
	tree.cursor = int(data.get("cursor", 0))
	return tree

static func from_game(game):
	if game.variation_tree != null: return from_data(game.variation_tree.to_data(), game.positions[0], game.moves)
	var tree = load("res://scripts/shogi_variation_tree.gd").new()
	tree.initialize(game.positions[0])
	for move in game.moves:
		if tree.append_main(move) < 0: return null
	tree.main_notes(game.comments, game.annotations)
	return tree
