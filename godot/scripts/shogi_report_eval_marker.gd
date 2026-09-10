extends Control
## Compact before/after marker from the reference story cards; linear display scale.
var sample: Dictionary = {}

func _init() -> void:
	custom_minimum_size = Vector2(7, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var value: float = preload("res://scripts/shogi_move_classification.gd").score(sample, 1)
	var share: float = (1.0 if value > 0 else 0.0) if sample.get("mate", false) else clampf((value + 500) / 1000, 0.08, 0.92)
	draw_style_box(preload("res://scripts/shogi_design.gd").box(Color("242323"), 2, 0), Rect2(Vector2.ZERO, size))
	var height = size.y * share
	draw_rect(Rect2(0, size.y - height, size.x, height), Color("f8f1e6"))
	draw_rect(Rect2(Vector2.ZERO, size), Color("70665a"), false, 1)
