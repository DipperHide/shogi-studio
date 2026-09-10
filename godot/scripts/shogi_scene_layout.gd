extends RefCounted
## Shared physical dimensions used by the asset builder and runtime.
static var data: Dictionary = preload("res://assets/scene-layout.json").data
static var BOARD_Y: float = data.board_top + data.piece_clearance
static var TRAY_Y: float = data.tray_top + data.piece_clearance
static var CELL_X: float = data.cell_width
static var CELL_Z: float = data.cell_depth
const HEIGHTS = [0.0,0.16,0.17,0.18,0.19,0.2,0.21,0.215,0.23]

static func square_position(square: int) -> Vector3:
	return Vector3((square%9-4)*CELL_X,BOARD_Y,(square/9-4)*CELL_Z)

static func tray_center(side: int) -> Vector3:
	return Vector3(side*data.tray_x,TRAY_Y,side*data.tray_z)
