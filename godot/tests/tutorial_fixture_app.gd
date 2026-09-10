extends "res://scripts/shogi_app.gd"
## Exercise the real menu, active Game and input gate without loading user saves or an engine.
func _ready() -> void:
	testing = true
	auto_play = false
	preferences.language = "zh"
	i18n.language = "zh"
	text_font = FontVariation.new()
	_update_font()
	ui = Menu.new()
	add_child(ui)
	ui.initialize(self)
	set_process(false)

func _layout() -> void: pass
func _pause_search() -> void: pass
func _leave_review() -> void: pass
func _refresh() -> void: pass
func _cancel_motion() -> void: pass
func _notification(what: int) -> void: pass
