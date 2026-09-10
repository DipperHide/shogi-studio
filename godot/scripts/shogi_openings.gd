extends RefCounted
## Short, legally validated example lines, not statistics from master games.
const LINES = [
	{"name": "角道开放", "group": "基础", "description": "先开放角行斜线，观察对方如何应对。", "moves": "7g7f 3c3d"},
	{"name": "飞车先步", "group": "居飞车", "description": "推进飞车前方的步，为交换飞先步作准备。", "moves": "2g2f 8c8d 2f2e 8d8e"},
	{"name": "相挂初形", "group": "居飞车", "description": "双方推进飞先步，再用金保护角头。", "moves": "2g2f 8c8d 2f2e 8d8e 6i7h 4a3b"},
	{"name": "四间飞车", "group": "振飞车", "description": "闭合角道，飞车转到六筋；接着安排玉的安全。", "moves": "7g7f 3c3d 6g6f 8c8d 2h6h"},
	{"name": "三间飞车", "group": "振飞车", "description": "飞车转到七筋，围绕角道与七筋组织进攻。", "moves": "7g7f 3c3d 6g6f 8c8d 2h7h"},
	{"name": "中飞车", "group": "振飞车", "description": "先推中步，再把飞车转到五筋。", "moves": "5g5f 3c3d 2h5h"},
	{"name": "向飞车", "group": "振飞车", "description": "角行离开八筋后，将飞车转到八筋对抗。", "moves": "7g7f 3c3d 6g6f 8c8d 8h7g 8d8e 2h8h"},
	{"name": "矢仓准备", "group": "围玉", "description": "银将上七七、金上七八，建立矢仓骨架。", "moves": "7g7f 8c8d 7i6h 3c3d 6h7g 7a6b 6i7h"},
	{"name": "美浓围准备", "group": "围玉", "description": "振飞后，玉向右移动，银将上三八保护玉。", "moves": "7g7f 3c3d 6g6f 8c8d 2h6h 6a5b 5i4h 5a4b 4h3h 4b3b 3h2h 7c7d 3i3h"}
]

static func game_for(line: Dictionary):
	var codec = preload("res://scripts/shogi_exchange.gd").new()
	return codec.parse("position startpos moves " + line.moves)
