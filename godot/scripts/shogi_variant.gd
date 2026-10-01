extends RefCounted
const Standard = preload("res://scripts/shogi_game.gd")
const Chu = preload("res://scripts/chu_game.gd")
static func from_data(data: Variant):
	if not data is Dictionary: return null
	match data.get("variant","standard"):
		"standard": return Standard.from_data(data)
		"chu": return Chu.from_data(data)
	return null
static func is_chu(game) -> bool: return game is Chu
