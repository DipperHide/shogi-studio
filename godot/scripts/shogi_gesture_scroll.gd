extends "res://scripts/shogi_page_scroll.gd"
## Axis-aware drags for nested candidate rows, on touch and desktop.
signal user_scrolled
var dragging = false
var pointer = -99
var origin = Vector2.ZERO
var previous = Vector2.ZERO
var axis = -1
var gesture_generation = 0

func _input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION: return
	var touch = event is InputEventScreenTouch
	var mouse = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	if touch or mouse:
		var id: int = event.index if touch else -1
		if event.pressed:
			pointer = id if is_visible_in_tree() and get_global_rect().has_point(event.position) else -99
			origin = event.position; previous = origin; dragging = false; axis = -1
		elif id == pointer:
			pointer = -99
			if dragging:
				_cancel_buttons(self)
				get_viewport().set_input_as_handled()
				dragging = false
		return
	var moving = (event is InputEventScreenDrag and event.index == pointer) or (event is InputEventMouseMotion and pointer == -1)
	if not moving or not is_visible_in_tree(): return
	var delta: Vector2 = event.position - origin
	if axis < 0:
		if delta.length() < 10: return
		axis = 0 if absf(delta.x) > absf(delta.y) else 1
	if not _can_scroll(axis) or _nested_owner(self, axis): return
	if not dragging:
		dragging = true
		gesture_generation += 1
		_cancel_buttons(self)
	var distance: Vector2 = event.position - previous
	previous = event.position
	if axis == 0: scroll_horizontal -= roundi(distance.x)
	else: scroll_vertical -= roundi(distance.y)
	user_scrolled.emit()
	get_viewport().set_input_as_handled()

func _can_scroll(direction: int) -> bool:
	if (horizontal_scroll_mode if direction == 0 else vertical_scroll_mode) == SCROLL_MODE_DISABLED: return false
	var bar = get_h_scroll_bar() if direction == 0 else get_v_scroll_bar()
	return bar.max_value > bar.page + 1

func _nested_owner(node: Node, direction: int) -> bool:
	for child in node.get_children():
		if child.has_method("_can_scroll") and child.is_visible_in_tree() and child.get_global_rect().has_point(origin) and child._can_scroll(direction): return true
		if _nested_owner(child, direction): return true
	return false

func _cancel_buttons(node: Node) -> void:
	if node is BaseButton: node.set_pressed_no_signal(false)
	if node is Control: node.notification(Control.NOTIFICATION_SCROLL_BEGIN)
	for child in node.get_children(): _cancel_buttons(child)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		pointer = -99; dragging = false; gesture_generation += 1
