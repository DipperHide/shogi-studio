extends SceneTree
const Quality = preload("res://scripts/shogi_report_quality.gd")
const Pie = preload("res://scripts/shogi_report_pie.gd")
var checks = 0
var failures = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr(message)

func _initialize() -> void:
	check(Quality.weights({}) == [0, 0, 0], "empty report is not divided by zero")
	var counts = {"定式": 1, "妙手": 2, "锐利": 3, "最佳": 4, "优秀": 5, "好棋": 6, "不精确": 7, "失误": 8, "漏着": 9, "错失胜机": 10}
	check(Quality.weights(counts) == [19, 12, 21], "all ten categories map to original three weighted groups")
	check(is_equal_approx(Quality.percentage([19, 12, 21], 1), 1200.0 / 52), "pie denominator uses weights rather than raw move count")
	for pair in [[0, 0], [1, 1], [2, 1], [3, 2], [4, 2], [5, 3]]:
		check(Quality.weights({"不精确": pair[0]}) == [0, pair[1], 0], "half-weight rounding boundary " + str(pair))
	for side_counts in [[{}, {}], [{"错失胜机": 1}, {}], [{}, {"错失胜机": 1}]]:
		for category in counts:
			check(Quality.row_visible(category, true, side_counts), "expanded includes " + category)
			check(Quality.row_visible(category, false, side_counts) == (category in Quality.COLLAPSED or (category == "错失胜机" and side_counts != [{}, {}])), "collapsed visibility " + category)
	var rows = [{"ply": 2, "side": -1, "category": "失误"}, {"ply": 5, "side": 1, "category": "失误"}, {"ply": 6, "side": -1, "category": "漏着"}, {"ply": 9, "side": 1, "category": "失误"}]
	check(Quality.next_ply(rows, "失误", 0, -1) == 2, "both players starts at first classified move")
	check(Quality.next_ply(rows, "失误", 0, 2) == 5, "next category occurrence")
	check(Quality.next_ply(rows, "失误", 0, 9) == 2, "end wraps to first occurrence")
	check(Quality.next_ply(rows, "失误", 1, 2) == 5, "side filter uses original mover")
	check(Quality.next_ply(rows, "失误", -1, 9) == 2, "side filter wraps")
	check(Quality.next_ply(rows, "妙手", 0, 0) == -1, "missing category does not fabricate a move")
	for dimensions in [Vector2(82, 200), Vector2(120, 200), Vector2(220, 200), Vector2(400, 200)]:
		var pie = Pie.new()
		pie.size = dimensions
		pie.counts = {"漏着": 1, "失误": 1, "最佳": 2}
		var geo = pie.geometry()
		check(geo.center == Vector2(dimensions.x / 2, 102.5), "pie reference inset center")
		check(Rect2(Vector2.ZERO, dimensions).encloses(Rect2(geo.center - Vector2.ONE * (geo.radius + 5), Vector2.ONE * (geo.radius + 5) * 2)), "selected radius remains inside cell")
		for angle in [-PI / 2, 0.0, 1.1, 7.0]:
			pie.rotation_angle = angle
			for entry in [[PI / 4, 0], [PI * 0.75, 1], [PI * 1.5, 2]]:
				var direction = Vector2.from_angle(angle + entry[0])
				check(pie.hit_group(geo.center + direction * geo.radius * 0.8) == entry[1], "rotated slice hit retains group")
				check(pie.hit_group(geo.center + direction * geo.radius * 0.3) == -1, "hole is not a slice")
				check(pie.hit_group(geo.center + direction * (geo.radius + 6)) == -1, "outside is not a slice")
		pie.active = 0
		check(pie.hit_group(geo.center + Vector2.from_angle(pie.rotation_angle + PI / 4) * (geo.radius + 4)) == 0, "expanded selected edge remains interactive")
		pie.counts = {}
		check(pie.hit_group(geo.center + Vector2(geo.radius * 0.8, 0)) == -1, "empty ring is not interactive")
		pie.free()
	var output = ProjectSettings.globalize_path("res://../review/app/chessis23")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("quality-core.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	print("QUALITY 23: ", checks, " checks; ", failures)
	quit(0 if failures.is_empty() else 1)
