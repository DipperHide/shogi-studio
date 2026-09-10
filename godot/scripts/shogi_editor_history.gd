extends RefCounted
## Each loaded setup keeps its own 50-step undo/redo history, as in C4773q.
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const LIMIT = 50
var entries: Array[String] = []
var histories: Array = []
var index = -1

static func normalized(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if not values is Array: return result
	for value in values.slice(maxi(0, values.size() - LIMIT)):
		if not value is String or value.length() > 512: continue
		var position = Codec.parse_sfen(value)
		if position != null: result.append(Codec.sfen(position))
	return result

func begin(source: String, saved: Variant = []) -> void:
	entries = normalized(saved)
	if entries.is_empty() or entries.back() != source: entries.append(source)
	while entries.size() > LIMIT: entries.pop_front()
	histories.clear()
	for entry in entries: histories.append({"undo": [entry], "redo": []})
	index = entries.size() - 1

func current() -> String:
	return histories[index].undo.back()

func push(sfen: String) -> bool:
	if sfen == current(): return false
	var history: Dictionary = histories[index]
	history.undo.append(sfen)
	history.redo.clear()
	while history.undo.size() > LIMIT: history.undo.pop_front()
	return true

func can_undo() -> bool:
	return index >= 0 and histories[index].undo.size() > 1

func can_redo() -> bool:
	return index >= 0 and not histories[index].redo.is_empty()

func undo() -> bool:
	if not can_undo(): return false
	histories[index].redo.append(histories[index].undo.pop_back())
	return true

func redo() -> bool:
	if not can_redo(): return false
	histories[index].undo.append(histories[index].redo.pop_back())
	return true

func seek(next: int) -> bool:
	if next < 0 or next >= entries.size() or next == index: return false
	index = next
	return true

func remember(sfen: String) -> Array[String]:
	if entries.is_empty() or entries.back() != sfen or histories.back().undo.back() != sfen:
		entries.append(sfen)
		histories.append({"undo": [sfen], "redo": []})
		while entries.size() > LIMIT: entries.pop_front(); histories.pop_front()
	index = entries.size() - 1
	return entries.duplicate()
