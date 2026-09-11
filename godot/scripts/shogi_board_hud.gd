extends RefCounted
## Shared geometry for player identities and clocks, including narrow panels.
static func player_layout(area: Rect2) -> Dictionary:
	var inset = 6.0
	if area.size.x < 210:
		return {"compact": true, "avatar": Rect2(),
			"name": Rect2(area.position + Vector2(inset, 1), Vector2(maxf(0, area.size.x - inset * 2), 18)),
			"clock": Rect2(Vector2(area.end.x - minf(94, area.size.x - inset * 2) - inset, area.position.y + 22), Vector2(minf(94, area.size.x - inset * 2), 18))}
	var avatar = Rect2(area.position + Vector2(4, 5), Vector2(30, 30))
	var clock = Rect2(Vector2(area.end.x - 89, area.position.y + 5), Vector2(84, 30))
	return {"compact": false, "avatar": avatar,
		"name": Rect2(area.position + Vector2(42, 0), Vector2(maxf(0, clock.position.x - area.position.x - 50), 40)), "clock": clock}

static func colors(palette: Dictionary, warm: bool, dark: bool) -> Dictionary:
	if not warm:
		return {"tray": palette.soft, "edge": palette.line, "muted": palette.muted,
			"player": palette.surface, "avatar": palette.soft, "clock": palette.soft,
			"clock_ink": palette.muted, "ink": palette.ink}
	return {"tray": Color("d9bd8d") if dark else Color("ecddbd"), "edge": Color("ab8654") if dark else Color("c8aa76"),
		"muted": Color("715737"), "player": Color(0.57, 0.40, 0.22, 0.14) if dark else Color(0.74, 0.58, 0.34, 0.08),
		"avatar": Color("96764e") if dark else Color("e3cc9e"), "clock": Color("ead3a9"),
		"clock_ink": Color("60472c"), "ink": palette.ink}
