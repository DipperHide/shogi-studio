extends SceneTree
const Preferences = preload("res://scripts/shogi_preferences.gd")
const Rules = preload("res://scripts/shogi_rules.gd")
const Design = preload("res://scripts/shogi_design.gd")
var checks = 0
var failures: Array = []
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures.append(title)

func _initialize() -> void:
	var path = "user://ui07-preferences-test.cfg"
	var config = ConfigFile.new()
	config.set_value("preferences", "appearance", "minimal")
	config.set_value("preferences", "language", "ja")
	config.set_value("preferences", "volume", 0.25)
	config.save(path)
	var p = Preferences.new()
	p.load_from(path)
	check(p.appearance == "anime2d" and p.piece_font == "mincho", "legacy flat migrates to clear wood")
	check(p.language == "ja" and p.volume == 0.25 and not p.confirm_move, "unrelated preferences retained")
	p.appearance = "minimal"
	p.confirm_move = true
	p.save_to(path)
	var reload = Preferences.new()
	reload.load_from(path)
	check(reload.appearance == "minimal" and reload.confirm_move, "explicit classic and confirm preference survive reload")
	config.set_value("preferences", "appearance", "wood")
	config.save(path)
	reload.load_from(path)
	check(reload.appearance == "wood", "existing 3D preference retained")
	DirAccess.remove_absolute(path)
	var position = Rules.new(false)
	position.board[76] = 8
	position.board[4] = -8
	position.board[49] = -7
	var checked = position.copy()
	check(Design.checked_squares(position) == [76], "king warning computed")
	position.board[67] = 5
	check(Design.checked_squares(position).is_empty(), "blocking check clears warning")
	check(Design.checked_squares(checked) == [76], "history position retains its own warning")
	position.board[67] = 0
	position.board[4] = 0
	position.board[3] = -8
	position.board[30] = 7
	check(Design.checked_squares(position) == [76, 3], "both king warnings in editable tutorial fixture")
	position.board[76] = 0
	position.board[3] = 0
	check(Design.checked_squares(position).is_empty(), "kingless tutorial fixture is not highlighted")
	var report = {"checks": checks, "failures": failures}
	var file = FileAccess.open("res://../review/app/ui07/state-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("UI07_STATE: ", report)
	quit(0 if failures.is_empty() else 1)
