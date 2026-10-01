extends Node
var ui
var mode = 0
var background: Panel
var handle: Button
var expand: Button
var origin = Vector2.ZERO
var initial_top = 0.0
var pointer = -99
var dragging = false
var drag_top = 0.0
var compact = Rect2()

func initialize(menu) -> void:
	ui = menu
	background = Panel.new()
	background.name = "AnalysisBackground"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.root.add_child(background)
	ui.root.move_child(background, ui.live_panel.get_index())
	var header = HBoxContainer.new()
	header.name = "AnalysisHandle"
	ui.live_panel.add_child(header); ui.live_panel.move_child(header, 0)
	handle = ui.compact_button("⋯  分析", func(): set_mode((mode + 1) % 3), 24)
	handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	handle.tooltip_text = "向上拖动扩大分析区"
	header.add_child(handle)
	expand = ui.compact_button("展开", func(): set_mode(2 if mode != 2 else 0), 24)
	expand.name = "ExpandAnalysis"
	header.add_child(expand)

func set_mode(value: int) -> void:
	mode = clampi(value, 0, 2)
	dragging = false; pointer = -99
	ui.app._cancel_pointer()
	ui.layout()

func fit(rect: Rect2) -> void:
	compact = rect
	var safe: Rect2 = ui.app.safe_rect()
	var ceiling = ui.move_scroll.get_global_rect().end.y + 4
	var bottom = ui.toolbar.position.y - 6
	var top = rect.position.y
	if mode == 1: top = maxf(ceiling, bottom - safe.size.y * 0.6)
	elif mode == 2: top = ceiling
	if dragging: top = clampf(drag_top, ceiling, compact.position.y)
	# Landscape keeps the board visible to the left of the workbench.
	ui.live_panel.position.y = top
	ui.live_panel.size.y = maxf(40, bottom - top)
	background.position = ui.live_panel.position - Vector2(3, 2)
	background.size = ui.live_panel.size + Vector2(6, 4)
	background.visible = ui.live_panel.is_visible_in_tree() and not ui.practice_active()
	background.add_theme_stylebox_override("panel", ui.Design.box(ui.app.palette().surface, 7, 0))
	expand.text = ui.app.t("收起" if mode > 0 else "展开")

func _process(_delta: float) -> void:
	if background != null: background.visible = ui.live_panel.is_visible_in_tree() and not ui.practice_active()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		pointer = -99; dragging = false

func _input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION: return
	var touch = event is InputEventScreenTouch
	var mouse = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	if touch or mouse:
		var id: int = event.index if touch else -1
		if event.pressed:
			if handle.is_visible_in_tree() and handle.get_global_rect().has_point(event.position):
				pointer = id; origin = event.position; initial_top = ui.live_panel.position.y
		elif id == pointer:
			pointer = -99
			if dragging:
				var safe: Rect2 = ui.app.safe_rect()
				var targets = [compact.position.y, maxf(ui.move_scroll.get_global_rect().end.y + 4, ui.toolbar.position.y - 6 - safe.size.y * 0.6), ui.move_scroll.get_global_rect().end.y + 4]
				var closest = 0
				for i in range(1, 3):
					if absf(targets[i] - drag_top) < absf(targets[closest] - drag_top): closest = i
				handle.set_pressed_no_signal(false)
				handle.notification(Control.NOTIFICATION_SCROLL_BEGIN)
				set_mode(closest)
				get_viewport().set_input_as_handled()
		return
	if (event is InputEventScreenDrag and event.index == pointer) or (event is InputEventMouseMotion and pointer == -1):
		if event.position.distance_to(origin) < 10 and not dragging: return
		dragging = true
		drag_top = initial_top + event.position.y - origin.y
		handle.set_pressed_no_signal(false)
		handle.notification(Control.NOTIFICATION_SCROLL_BEGIN)
		ui.layout()
		get_viewport().set_input_as_handled()
