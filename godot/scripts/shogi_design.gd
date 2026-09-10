extends RefCounted
## Shared visual tokens and position-derived warnings. No game mutation.
static func palette(dark: bool) -> Dictionary:
	var p = {"background": Color("f7f6f2"), "surface": Color("ffffff"), "ink": Color("24344b"), "muted": Color("66758a"), "line": Color("dce2e8"), "accent": Color("3e658d"), "selected": Color("c4dce8"), "last": Color("e4ecd2"), "soft": Color("eaf0f6"), "pink": Color("f2dfe5"), "board": Color("e9c994"), "board_line": Color("987b53"), "piece": Color("fff0ce"), "piece_ink": Color("322c26"), "danger": Color("bc3547"), "danger_fill": Color("ed9393")}
	if dark:
		p.merge({"background": Color("141e2d"), "surface": Color("202e41"), "ink": Color("edf1f7"), "muted": Color("a8b7cb"), "line": Color("38485e"), "accent": Color("9cbfe4"), "selected": Color("425e74"), "last": Color("3e5146"), "soft": Color("28394f"), "pink": Color("574154"), "board": Color("a18a64"), "board_line": Color("524634"), "piece": Color("dcc6a1"), "danger": Color("ff919c"), "danger_fill": Color("b85059")}, true)
	return p

static func box(color: Color, radius: int = 16, margin: int = 16) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style

static var heading_fonts: Dictionary = {}
static func heading_font(base: FontVariation) -> FontVariation:
	var key = base.get_instance_id()
	if not heading_fonts.has(key):
		var font = base.duplicate()
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
		heading_fonts[key] = font
	return heading_fonts[key]

static func checked_squares(position) -> Array[int]:
	var result: Array[int] = []
	for side in [1, -1]:
		var square: int = position.board.find(side * 8)
		if square >= 0 and position.in_check(side): result.append(square)
	return result

static func board_area(safe: Rect2) -> Rect2:
	var area = safe
	area.position.y += 52
	area.size.y -= 116
	return area

static var icons: Dictionary = {}
static func toggle_icon(checked: bool, disabled: bool, p: Dictionary) -> Texture2D:
	var color: Color = p.accent if checked else p.muted
	var key = "toggle" + str([checked, disabled, color])
	if icons.has(key): return icons[key]
	var image = Image.new()
	image.load_svg_from_string("<svg xmlns='http://www.w3.org/2000/svg' width='42' height='26' viewBox='0 0 42 26'><g opacity='%s'><rect x='1' y='2' width='40' height='22' rx='11' fill='#%s'/><circle cx='%d' cy='13' r='8' fill='white'/></g></svg>" % ["0.4" if disabled else "1", color.to_html(false), 29 if checked else 13])
	icons[key] = ImageTexture.create_from_image(image)
	return icons[key]

static func icon(name: String, color: Color) -> Texture2D:
	var key = name + color.to_html()
	if icons.has(key): return icons[key]
	var paths = {
		"home": "<path d='M3 10 12 3l9 7v10H15v-7H9v7H3Z'/>",
		"learn": "<path d='M12 6Q7 2 2 5v15q5-3 10 0 5-3 10 0V5q-5-3-10 1v14'/>",
		"history": "<rect x='5' y='3' width='14' height='18' rx='2'/><path d='M9 8h6m-6 4h6m-6 4h4'/>",
		"settings": "<path d='M4 7h16M4 17h16'/><circle cx='9' cy='7' r='3'/><circle cx='16' cy='17' r='3'/>",
		"undo": "<path d='m8 4-5 5 5 5M3 9h11a6 6 0 0 1 0 12'/>",
		"more": "<circle cx='4' cy='12' r='1'/><circle cx='12' cy='12' r='1'/><circle cx='20' cy='12' r='1'/>",
		"play": "<path d='m8 4 13 8L8 20Z'/>",
		"people": "<circle cx='8' cy='7' r='3'/><path d='M2 21v-3a6 6 0 0 1 12 0v3m3-18a3 3 0 0 1 0 6m1 5a5 5 0 0 1 4 5v2'/>",
		"bluetooth": "<path d='M12 2v20l7-6-14-9m0 10L19 8Z'/>",
		"network": "<rect x='8' y='2' width='8' height='6' rx='1'/><path d='M12 8v5M4 17v-4h16v4'/><rect x='1' y='17' width='6' height='5' rx='1'/><rect x='17' y='17' width='6' height='5' rx='1'/>"
	}
	var image = Image.new()
	image.load_svg_from_string("<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24'><g fill='none' stroke='#%s' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round'>%s</g></svg>" % [color.to_html(false), paths.get(name, paths.more)])
	icons[key] = ImageTexture.create_from_image(image)
	return icons[key]
