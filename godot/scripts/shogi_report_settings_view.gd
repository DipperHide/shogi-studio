extends VBoxContainer
var menu
var modes: Dictionary = {}
var values: Dictionary = {}
var warnings: Dictionary = {}
var smart: CheckButton

func build(owner_menu) -> void:
	menu = owner_menu
	add_theme_constant_override("separation", 12)
	for prefix in ["quick", "deep"]:
		var key: String = prefix
		var card = menu.card_column(self)
		style_card(card)
		var header = HBoxContainer.new()
		card.add_child(header)
		var icon = TextureRect.new()
		icon.texture = menu.reference_icon("ic_quick_report" if key == "quick" else "ic_deep_report")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(20, 20)
		icon.modulate = menu.app.palette().ink
		header.add_child(icon)
		var titles = VBoxContainer.new()
		titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		titles.add_theme_constant_override("separation", 1)
		header.add_child(titles)
		titles.add_child(menu.label("快速报告" if key == "quick" else "深度报告", 15))
		var caption = menu.label("快速发现明显失误" if key == "quick" else "分析更细致，也检查细小失误", 12)
		caption.add_theme_color_override("font_color", menu.app.palette().muted)
		titles.add_child(caption)
		var track = HBoxContainer.new()
		track.add_theme_constant_override("separation", 3)
		card.add_child(track)
		modes[key] = []
		for mode in ["time", "depth"]:
			var mode_key: String = mode
			var item = menu.compact_button("时间" if mode == "time" else "深度", func(): menu.set_report_option(key + "_mode", mode_key); refresh(), 40)
			item.name = key.capitalize() + mode.capitalize()
			track.add_child(item)
			modes[key].append(item)
		var value = menu.button("", func(): menu.show_report_value(key))
		value.name = key.capitalize() + "Value"
		value.alignment = HORIZONTAL_ALIGNMENT_LEFT
		value.custom_minimum_size.y = 44
		value.add_theme_stylebox_override("normal", menu.Design.box(Color.TRANSPARENT, 8, 5))
		value.add_theme_font_size_override("font_size", 14)
		card.add_child(value)
		values[key] = value
		var warning = menu.label("", 12)
		warning.add_theme_color_override("font_color", Color("e9b55a"))
		card.add_child(warning)
		warnings[key] = warning
		if key == "deep":
			var line_names: Array[String] = ["1", "2", "3", "4", "5"]
			var lines = menu.choice(card, "候选线路", line_names, menu.app.preferences.report.deep_lines - 1, true)
			lines.name = "DeepLines"
			lines.item_selected.connect(func(index): menu.set_report_option("deep_lines", index + 1))
			var note = menu.label("仅用于深度报告。更多线路会展示备选走法，也会延长分析时间。", 12)
			note.add_theme_color_override("font_color", menu.app.palette().muted)
			card.add_child(note)
	var card = menu.card_column(self)
	style_card(card)
	smart = CheckButton.new()
	smart.name = "SmartAnalysis"
	smart.text = "智能分析"
	smart.custom_minimum_size.y = 38
	smart.add_theme_font_size_override("font_size", 15)
	smart.button_pressed = menu.app.preferences.report.smart
	smart.toggled.connect(func(value): menu.set_report_option("smart", value); refresh())
	card.add_child(smart)
	var caption = menu.label("根据局面调整分析量。复杂局面充分搜索，简单局面更快完成。", 12)
	caption.add_theme_color_override("font_color", menu.app.palette().muted)
	card.add_child(caption)
	refresh()

func style_card(card: VBoxContainer) -> void:
	var dark: bool = menu.app.preferences.is_dark()
	var style = menu.Design.box(Color(1, 1, 1, 20.0 / 255) if dark else Color.WHITE, 14, 14)
	style.border_color = Color(1, 1, 1, 38.0 / 255) if dark else Color(0, 0, 0, 20.0 / 255)
	style.set_border_width_all(1)
	card.get_parent().add_theme_stylebox_override("panel", style)

func refresh() -> void:
	var settings: Dictionary = menu.app.preferences.report
	for prefix in ["quick", "deep"]:
		var is_time: bool = settings[prefix + "_mode"] == "time"
		for i in range(2):
			var selected: bool = i == (0 if is_time else 1)
			modes[prefix][i].add_theme_stylebox_override("normal", menu.Design.box(menu.app.palette().accent if selected else menu.app.palette().soft, 8, 4))
			modes[prefix][i].add_theme_color_override("font_color", Color.WHITE if selected else menu.app.palette().muted)
		var heading = ("最大分析" if settings.smart else "每步分析") + ("时间" if is_time else "深度")
		var amount: float = settings[prefix + ("_time" if is_time else "_depth")]
		values[prefix].text = heading + "    " + ("%.1f 秒" % amount if is_time else str(int(amount))) + "   ›"
		warnings[prefix].text = "较长时间会明显延长整局分析。" if is_time else "较高深度会明显延长整局分析。"
		warnings[prefix].visible = amount >= (5 if is_time else 25)
