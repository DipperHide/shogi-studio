extends RefCounted
## Stored IDs are stable; presentation order is independent of save data.
const DEFAULT = 7
const ORDER = [6, 7, 8, 9, 0, 1, 2, 3, 4, 5]
const ORIGINAL = [
	{"name": "初学", "nodes": 80, "depth": 1, "milliseconds": 250, "basic_ms": 150, "basic_depth": 1},
	{"name": "入门", "nodes": 400, "depth": 2, "milliseconds": 400, "basic_ms": 300, "basic_depth": 1},
	{"name": "普通", "nodes": 2500, "depth": 4, "milliseconds": 700, "basic_ms": 650, "basic_depth": 2},
	{"name": "进阶", "nodes": 20000, "depth": 8, "milliseconds": 1200, "basic_ms": 1100, "basic_depth": 2},
	{"name": "高手", "nodes": 180000, "depth": 18, "milliseconds": 2500, "basic_ms": 1800, "basic_depth": 3},
	{"name": "最强", "nodes": 2000000, "depth": 40, "milliseconds": 5000, "basic_ms": 3000, "basic_depth": 3},
]
const PROFILES = ORIGINAL + [
	{"name": "随手", "random": 1.0, "basic_ms": 0, "basic_depth": 0},
	{"name": "启蒙", "random": 0.6, "basic_ms": 100, "basic_depth": 1},
	{"name": "新手", "random": 0.35, "basic_ms": 150, "basic_depth": 1},
	{"name": "基础练习", "random": 0.15, "basic_ms": 250, "basic_depth": 2},
]

static func names() -> Array[String]:
	var result: Array[String] = []
	for id in ORDER: result.append(PROFILES[id].name)
	return result

static func weak(id: int) -> bool:
	return id >= 6 and id <= 9

static func valid(id: int) -> bool:
	return id >= 0 and id < PROFILES.size()
