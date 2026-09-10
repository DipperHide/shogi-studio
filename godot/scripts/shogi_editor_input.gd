extends Node
var editor
var dragging = false
var pointer_id = -2
var start = Vector2.ZERO
var current = Vector2.ZERO
var source_square = -1
var piece = 0
var source_control: Button
var preview: Control

func _input(event: InputEvent) -> void:
	if not editor.is_visible_in_tree(): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and pointer_id != -2:
		cancel(); get_viewport().set_input_as_handled(); return
	if event is InputEventMouseButton and event.device < 0: return
	var press = event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	var motion = event is InputEventScreenDrag or event is InputEventMouseMotion
	if not press and not motion: return
	var point: Vector2 = event.position
	if press and event.pressed and pointer_id == -2:
		if not editor.menu.page_scroll.get_global_rect().has_point(point): return
		source_square = editor.square_at(point)
		piece = editor.pos.board[source_square] if source_square >= 0 else 0
		source_control = editor.cells[source_square] if source_square >= 0 else null
		if source_square < 0:
			for value in editor.palette:
				if value != 0 and editor.palette[value].get_global_rect().has_point(point):
					piece = editor.brush if editor.Rules.base(editor.brush) == editor.Rules.base(value) and signi(editor.brush) == signi(value) else value
					source_control = editor.palette[value]
					break
		if source_control == null: return
		source_control.grab_focus()
		start = point; current = point; dragging = false
		pointer_id = event.index if event is InputEventScreenTouch else -1
		get_viewport().set_input_as_handled()
	elif pointer_id != -2:
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			if event.index != pointer_id: return
		elif pointer_id != -1: return
		current = point
		if motion:
			if piece != 0 and point.distance_to(start) > 7: dragging = true
			if dragging: update_preview()
			get_viewport().set_input_as_handled()
		elif press and not event.pressed:
			var target: int = editor.square_at(point)
			if not editor.menu.page_scroll.get_global_rect().has_point(point): target = -1
			if event is InputEventScreenTouch and event.canceled: target = -1
			if dragging:
				if target >= 0:
					if source_square >= 0: editor.pos.board[source_square] = 0
					editor.pos.board[target] = piece
					editor.edited()
			elif target == source_square and target >= 0: editor.paint(target)
			elif source_square < 0 and source_control.get_global_rect().has_point(point) and not (event is InputEventScreenTouch and event.canceled): editor.choose_brush(piece)
			cancel()
			get_viewport().set_input_as_handled()

func update_preview() -> void:
	if preview == null:
		preview = preload("res://scripts/shogi_editor_cell.gd").new()
		preview.editor = editor
		preview.piece = piece
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.focus_mode = Control.FOCUS_NONE
		editor.menu.root.add_child(preview)
	var edge: float = editor.board_rect.size.x / 9 * 1.2
	preview.size = Vector2.ONE * edge
	preview.position = current - preview.size / 2
	preview.queue_redraw()
	source_control.queue_redraw()

func cancel() -> void:
	if is_instance_valid(preview): preview.queue_free()
	preview = null
	pointer_id = -2
	dragging = false
	if is_instance_valid(source_control): source_control.queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED: cancel()

func _exit_tree() -> void:
	cancel()
