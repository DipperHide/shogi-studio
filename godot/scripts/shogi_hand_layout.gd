extends RefCounted
const Scene = preload("res://scripts/shogi_scene_layout.gd")
const SCALE = 1.0
const COLUMN_PITCH = 1.04
const ROW_PITCH = 1.10
const ORDER = [7,6,5,4,3,2,1]

static func center(side: int, kind: int) -> Vector3:
	var slot = ORDER.find(kind)
	var column = slot%3 if kind != 1 else 1
	return Scene.tray_center(side)+Vector3(side*(column-1)*COLUMN_PITCH,0,side*(slot/3-1)*ROW_PITCH)

static func layout(tokens: Array) -> Dictionary:
	var poses: Dictionary = {}
	var groups: Dictionary = {}
	for side in [-1,1]:
		for kind in ORDER:
			var ids: Array[int] = []
			for id in range(tokens.size()):
				if tokens[id].square < 0 and tokens[id].value == side*kind:
					ids.append(id)
			ids.sort_custom(func(a,b): return tokens[a].get("hand_order",0) > tokens[b].get("hand_order",0) if tokens[a].get("hand_order",0) != tokens[b].get("hand_order",0) else a < b)
			if ids.is_empty():
				continue
			var origin = center(side,kind)
			# Keep every logical identity for saves/undo, but render only `top`.
			# All members share the group's landing point; quantity replaces piles.
			for id in ids:
				poses[id] = {"position":origin,"rotation":PI if side<0 else 0.0,"scale":SCALE}
			groups[side*kind] = {"side":side,"kind":kind,"ids":ids,"top":ids[0],"center":origin,"bounds":Rect2(Vector2(origin.x-COLUMN_PITCH/2,origin.z-ROW_PITCH/2),Vector2(COLUMN_PITCH,ROW_PITCH)),"count_position":origin+Vector3(side*0.43,Scene.HEIGHTS[kind]*SCALE+0.10,side*0.36)}

	return {"poses":poses,"groups":groups}
