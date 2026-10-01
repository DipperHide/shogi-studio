extends RefCounted
## Full record extent with only the visible columns instantiated.
var ui
var entries: Array = []
var offsets: Array[float] = []
var widths: Array[float] = []
var selected = -1
var first = -1
var last = -1
var extent = 0.0
var render_key = ""
var measured: Dictionary = {}

func configure(items: Array, selected_index: int, reveal: bool) -> void:
	entries = items; selected = selected_index
	offsets.clear(); widths.clear(); extent = 0.0
	var font = ui.app.text_font
	for entry in entries:
		offsets.append(extent)
		var width = 42.0
		for text_value in entry.labels:
			var text_key = str([ui.app.preferences.language, ui.app.preferences.piece_font, text_value])
			if not measured.has(text_key): measured[text_key] = font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18
			width = maxf(width, measured[text_key])
			if measured.size() > 4096: measured.erase(measured.keys()[0])
		widths.append(width)
		extent += width + 3
	ui.move_strip.custom_minimum_size.x = maxf(0, extent - 3)
	render_key = ""
	if reveal and selected >= 0:
		var left = offsets[selected]
		var right = left + widths[selected]
		var current: float = ui.move_scroll.scroll_horizontal
		if left < current: ui.move_scroll.set_deferred("scroll_horizontal", int(left))
		elif right > current + ui.move_scroll.size.x: ui.move_scroll.set_deferred("scroll_horizontal", int(right - ui.move_scroll.size.x))
	refresh()

func refresh() -> void:
	if entries.is_empty(): return
	var left: float = ui.move_scroll.scroll_horizontal - ui.move_scroll.size.x
	var right: float = ui.move_scroll.scroll_horizontal + ui.move_scroll.size.x * 2
	var begin = _index(left)
	var end = mini(entries.size(), _index(right) + 1)
	var key = str([begin, end, selected])
	if render_key == key: return
	render_key = key; first = begin; last = end - 1
	for child in ui.move_strip.get_children(): ui.move_strip.remove_child(child); child.queue_free()
	_spacer(offsets[begin] - 3 if begin > 0 else 0)
	for i in range(begin, end):
		var entry: Dictionary = entries[i]
		var column = VBoxContainer.new()
		column.custom_minimum_size.x = widths[i]
		column.add_theme_constant_override("separation", 2)
		ui.move_strip.add_child(column)
		for row in range(entry.ids.size()):
			var id: int = entry.ids[row]
			if id < 0:
				var blank = Control.new(); blank.custom_minimum_size.y = 28; column.add_child(blank); continue
			var item: Button
			if entry.study:
				item = ui.variation_ui.move_button(id, row == 0)
			else:
				item = ui.compact_button(entry.labels[row], func(): ui.show_history(id), 28)
				item.name = "HistoryMove_%d" % id
				item.add_theme_stylebox_override("normal", ui.Design.box(ui.app.palette().accent if i == selected else Color.TRANSPARENT, 4, 3))
			item.add_theme_font_size_override("font_size", 14)
			column.add_child(item)
	var remainder = extent - (offsets[end - 1] + widths[end - 1] + 3)
	_spacer(maxf(0, remainder - 3))

func _spacer(width: float) -> void:
	if width <= 0: return
	var node = Control.new(); node.custom_minimum_size.x = width; ui.move_strip.add_child(node)

func _index(x: float) -> int:
	var low = 0; var high = offsets.size() - 1
	while low < high:
		var middle = (low + high + 1) / 2
		if offsets[middle] <= x: low = middle
		else: high = middle - 1
	return low
