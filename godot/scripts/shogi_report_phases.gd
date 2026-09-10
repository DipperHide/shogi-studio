extends VBoxContainer
## phase_ribbon.xml / C4570h: proportional phase bars and wrapping side summaries.
signal selected(side: int, phase: int)
signal accuracy_selected(side: int)
signal acpl_selected(side: int)
signal rating_selected(side: int)
const Metrics = preload("res://scripts/shogi_report_metrics.gd")
const Design = preload("res://scripts/shogi_design.gd")
const INK = Color("f8f1e6")
const SECONDARY = Color("d9cab4")
var report
var ui
var show_cpl: bool = false
var signature = ""
var targets: Array = []
var hits: Array:
	get:
		var result = []
		for target in targets:
			if is_instance_valid(target.button) and target.button.is_visible_in_tree():
				var hit: Dictionary = target.duplicate()
				hit.erase("button")
				hit.rect = Rect2(target.button.global_position - global_position, target.button.size)
				result.append(hit)
		return result

class SidePiece extends Control:
	var side: int = 1
	func _ready() -> void:
		custom_minimum_size = Vector2(22, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var shape = PackedVector2Array([Vector2(11, 1), Vector2(18, 5), Vector2(21, 21), Vector2(1, 21), Vector2(4, 5)])
		draw_colored_polygon(shape, Color("f8f1e6") if side == 1 else Color("191716"))
		shape.append(shape[0])
		draw_polyline(shape, Color("d9cab4"), 1, true)
		draw_string(preload("res://assets/fonts/YujiSyuku-Regular.ttf"), Vector2(4, 17), "歩", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("191716") if side == 1 else Color("f8f1e6"))

static func accuracy_caption(stats: Dictionary) -> String:
	if not stats.has_accuracy: return "—"
	var value = roundf(float(stats.accuracy) * 10) / 10
	if stats.accuracy < 100 and value >= 100: value = 99.9
	return ("%d%%" % roundi(value)) if value == roundf(value) else ("%.1f%%" % value)

static func phase_caption(stats: Dictionary) -> String:
	if stats.has_accuracy: return "%d%%" % roundi(stats.accuracy)
	return "定式" if stats.count > 0 and stats.book == stats.count else "—"

static func player_caption(value: String, side: int) -> String:
	var text = value.replace("🏆", "").replace("🤖", "").replace("💻", "").strip_edges()
	text = RegEx.create_from_string("\\s*\\(\\d{2,5}\\)\\s*$").sub(text, "").strip_edges()
	return ("先手" if side == 1 else "后手") if text.is_empty() else text

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	refresh()

func gap(parent: Control, height: int) -> void:
	var space = Control.new()
	space.custom_minimum_size.y = height
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(space)

func margins(parent: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var box = MarginContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	for entry in [["left", left], ["top", top], ["right", right], ["bottom", bottom]]: box.add_theme_constant_override("margin_" + entry[0], entry[1])
	parent.add_child(box)
	return box

func texture(key: String, pixels: int, tint: Color = Color.WHITE) -> TextureRect:
	var icon = TextureRect.new()
	icon.texture = ui.reference_icon(key)
	icon.custom_minimum_size = Vector2(pixels, pixels)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = tint
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func register(button: Button, side: int, phase: int, kind: String) -> void:
	button.set_meta("phase_ribbon_control", true)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	var focus = Design.box(Color.TRANSPARENT, 5, 0)
	focus.border_color = Color("58a6ff")
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	targets.append({"button": button, "side": side, "phase": phase, "kind": kind})
	button.pressed.connect(func():
		match kind:
			"accuracy": accuracy_selected.emit(side)
			"acpl": acpl_selected.emit(side)
			"rating": rating_selected.emit(side)
			_: selected.emit(side, phase)
	)

func refresh() -> void:
	if report == null or report.game == null or ui == null: return
	var sides = []
	var phases: Array = report.phases()
	for side in [1, -1]:
		var summary: Dictionary = report.summary(side)
		if summary.count == 0: continue
		var stats = []
		for phase in phases: stats.append(report.phase_summary(side, phase))
		sides.append({"side": side, "name": player_caption(report.player_name(side), side), "winner": report.game.winner == side, "summary": summary, "stats": stats})
	var next = JSON.stringify([phases, sides, show_cpl])
	if next == signature: return
	signature = next
	targets.clear()
	for child in get_children(): remove_child(child); child.queue_free()
	visible = not sides.is_empty()
	if not visible: return
	gap(self, 6)
	var divider = ColorRect.new()
	divider.name = "PhaseTopDivider"
	divider.color = Color("f8f1e633")
	divider.custom_minimum_size.y = 1
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)
	gap(self, 5)
	var labels_panel = PanelContainer.new()
	labels_panel.name = "PhaseLabelStrip"
	labels_panel.add_theme_stylebox_override("panel", Design.box(Color("00000010"), 0, 0))
	labels_panel.custom_minimum_size.y = 22
	add_child(labels_panel)
	var labels = HBoxContainer.new()
	labels.add_theme_constant_override("separation", 0)
	var labels_inset = margins(labels_panel, 8, 0, 8, 0)
	labels_inset.name = "PhaseLabelsInset"
	labels_inset.add_child(labels)
	var total: int = report.game.moves.size()
	for segment in phases:
		var caption = ui.label(segment.name, 11)
		caption.add_theme_font_override("font", Design.heading_font(ui.app.text_font))
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		caption.clip_text = true
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var span = Metrics.span(segment, total)
		caption.size_flags_stretch_ratio = maxf(0.5, span.y - span.x)
		caption.add_theme_color_override("font_color", INK)
		labels.add_child(caption)
		if segment != phases[0]:
			var boundary = ColorRect.new()
			boundary.name = "PhaseLabelDivider"
			boundary.color = Color("f8f1e699")
			boundary.mouse_filter = Control.MOUSE_FILTER_IGNORE
			caption.add_child(boundary)
			boundary.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
			boundary.offset_right = 1
	var inset = margins(self, 8, 2, 8, 6)
	var groups = VBoxContainer.new()
	groups.name = "PhaseSideGroups"
	groups.add_theme_constant_override("separation", 20)
	inset.add_child(groups)
	for side in sides: add_side(groups, side, phases, total)

func add_side(parent: Control, data: Dictionary, phases: Array, total: int) -> void:
	var side: int = data.side
	var group = PanelContainer.new()
	group.name = "PhaseSideSente" if side == 1 else "PhaseSideGote"
	var background = Design.box(Color("18202866"), 8, 0)
	background.border_color = Color("58a6ff77")
	background.set_border_width_all(1)
	background.content_margin_bottom = 6
	group.add_theme_stylebox_override("panel", background)
	parent.add_child(group)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	group.add_child(column)
	var bars = HBoxContainer.new()
	bars.name = "PhaseSegments"
	bars.add_theme_constant_override("separation", 4)
	bars.custom_minimum_size.y = 34
	column.add_child(bars)
	for i in range(phases.size()):
		var segment: Dictionary = phases[i]
		var stats: Dictionary = data.stats[i]
		var span = Metrics.span(segment, total)
		if stats.count == 0:
			var empty = Control.new()
			empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			empty.size_flags_stretch_ratio = maxf(0.5, span.y - span.x)
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bars.add_child(empty)
			continue
		var button = Button.new()
		button.name = "PhaseScore%d" % segment.type
		button.text = phase_caption(stats)
		button.clip_text = true
		button.custom_minimum_size.y = 34
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_stretch_ratio = maxf(0.5, span.y - span.x)
		button.add_theme_font_size_override("font_size", 12 if stats.has_accuracy else 10)
		button.add_theme_color_override("font_color", INK)
		var color = Metrics.accuracy_color(stats.accuracy) if stats.has_accuracy else Color("8d6e63")
		button.add_theme_stylebox_override("normal", Design.box(Color(color, 92.0/255), 5, 0))
		button.add_theme_stylebox_override("hover", Design.box(Color(color, 0.55), 5, 0))
		button.add_theme_stylebox_override("pressed", Design.box(Color(color, 0.65), 5, 0))
		button.tooltip_text = ("先手" if side == 1 else "后手") + " · " + segment.name + " · " + button.text
		button.accessibility_name = button.tooltip_text
		register(button, side, segment.type, "phase")
		bars.add_child(button)
	gap(column, 6)
	var player_inset = margins(column, 10, 0, 10, 0)
	var player = HBoxContainer.new()
	player.name = "PhasePlayer"
	player.custom_minimum_size.y = 24
	player.add_theme_constant_override("separation", 0)
	player_inset.add_child(player)
	var pawn = SidePiece.new()
	pawn.side = side
	pawn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	player.add_child(pawn)
	if data.winner:
		var winner_inset = margins(player, 5, 0, 0, 0)
		winner_inset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var winner = texture("ic_trophy_neutral", 16)
		winner.name = "PhaseWinner"
		winner_inset.add_child(winner)
	var name_inset = margins(player, 6, 0, 0, 0)
	name_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label = ui.label(data.name, 12)
	name_label.name = "PhasePlayerName"
	name_label.max_lines_visible = 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_constant_override("line_spacing", 1)
	name_label.add_theme_color_override("font_color", INK)
	if data.winner: name_label.add_theme_font_override("font", Design.heading_font(ui.app.text_font))
	name_label.tooltip_text = data.name
	name_label.accessibility_name = ("先手" if side == 1 else "后手") + " · " + data.name + (" · 胜者" if data.winner else "")
	name_inset.add_child(name_label)
	gap(column, 3)
	var summary_panel = PanelContainer.new()
	summary_panel.name = "PhaseSummary"
	summary_panel.custom_minimum_size.y = 30
	summary_panel.add_theme_stylebox_override("panel", Design.box(Color("1d252d66"), 6, 0))
	column.add_child(summary_panel)
	var inner = margins(summary_panel, 8, 3, 8, 3)
	var flow = HFlowContainer.new()
	flow.name = "PhaseSummaryFlow"
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 0)
	flow.add_theme_constant_override("v_separation", 0)
	inner.add_child(flow)
	var fill = Metrics.accuracy_color(data.summary.accuracy) if data.summary.has_accuracy else Color("8d6e63")
	metric_chip(flow, side, "accuracy", "准确率", accuracy_caption(data.summary), Color(fill, 102.0/255), 14, "ic_accurate_neutral")
	if show_cpl: metric_chip(flow, side, "acpl", "ACPL", str(roundi(data.summary.average_loss)) if data.summary.has_accuracy else "—", Color("2d343b33"), 12)
	# The reference keeps this chip visible even when no estimate is available.
	# Shogi does not yet have a calibrated rating model; never manufacture Elo.
	metric_chip(flow, side, "rating", "估计等级分", "—", Color("2d343b33"), 12, "ic_rating_trend_neutral")

func metric_chip(parent: Control, side: int, kind: String, prefix: String, value: String, fill: Color, font_size: int, icon: String = "") -> void:
	var outer = margins(parent, 3, 2, 3, 2)
	var button = Button.new()
	button.name = "PhaseMetric" + kind.capitalize()
	button.custom_minimum_size.y = 26
	button.add_theme_stylebox_override("normal", Design.box(fill, 6, 0))
	button.add_theme_stylebox_override("hover", Design.box(fill.lightened(0.16), 6, 0))
	button.add_theme_stylebox_override("pressed", Design.box(fill.lightened(0.25), 6, 0))
	button.accessibility_name = ("先手" if side == 1 else "后手") + " · " + prefix + ": " + value
	button.tooltip_text = button.accessibility_name
	outer.add_child(button)
	var content = HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 0)
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 8; content.offset_right = -8
	content.offset_top = 4; content.offset_bottom = -4
	if not icon.is_empty():
		content.add_child(texture(icon, 24, SECONDARY))
		var spacer = Control.new()
		spacer.custom_minimum_size.x = 3
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(spacer)
	for part in [[prefix + ": ", false], [value, true]]:
		var label = ui.label(part[0], font_size)
		label.name = "MetricValue" if part[1] else "MetricLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_color", INK if part[1] else SECONDARY)
		if part[1]: label.add_theme_font_override("font", Design.heading_font(ui.app.text_font))
		content.add_child(label)
	button.custom_minimum_size = content.get_combined_minimum_size() + Vector2(16, 8)
	button.custom_minimum_size.y = maxf(26, button.custom_minimum_size.y)
	register(button, side, 0, kind)
