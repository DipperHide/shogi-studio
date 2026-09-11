extends RefCounted
## Compare saved content, excluding navigation and ticking clocks.
static func tree_content(tree) -> Dictionary:
	var data: Dictionary = tree.to_data()
	data.erase("cursor")
	return data

static func study_signature(tree, metadata: Dictionary) -> String:
	return JSON.stringify([tree_content(tree), metadata]).sha256_text()

static func game_signature(game) -> String:
	var data: Dictionary = game.to_data().duplicate(true)
	for field in ["clock", "mode", "human_side", "difficulty", "engine_provider", "engine_level", "engine_match"]: data.erase(field)
	if data.get("variations") is Dictionary: data.variations.erase("cursor")
	return JSON.stringify(data).sha256_text()

static func has_content(game) -> bool:
	return not game.moves.is_empty() or not game.comments.is_empty() or not game.annotations.is_empty() or not game.metadata.is_empty() or not game.initial_sfen.is_empty() or game.resigned or game.agreed_draw or game.declared_side != 0
