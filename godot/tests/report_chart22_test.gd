extends SceneTree
const Model = preload("res://scripts/shogi_report_chart_model.gd")
var checks = 0
var failures = []
var cases = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("CHART FAIL: ", message)

func serial(entry: Dictionary) -> Dictionary:
	var result = entry.duplicate()
	for key in result:
		if result[key] is Vector2: result[key] = [result[key].x, result[key].y]
	return result

func _initialize() -> void:
	var plot = Model.plot_rect(Vector2(360, 168))
	check(plot == Rect2(8, 10, 344, 148), "plot uses original 8/10 offsets")
	check(Model.point(0, -99999, plot, 140) == Vector2(8, 158), "negative mate remains in plot")
	check(Model.point(140, 99999, plot, 140) == Vector2(352, 10), "positive mate remains in plot")
	check(Model.point(70, 0, plot, 140) == Vector2(180, 84), "zero at shared midpoint")
	check(Model.point(140, 1000 * Model.Metrics.CP_SCALE, plot, 140).y == 10, "existing shogi score conversion retained")
	var source = [{"ply": 1, "side": 1, "point": Vector2(20, 80)}, {"ply": 3, "side": 1, "point": Vector2(33, 80)}, {"ply": 5, "side": 1, "point": Vector2(47, 80)}, {"ply": 6, "side": -1, "point": Vector2(47, 80)}]
	var markers = Model.arrange(source, plot)
	check(markers.map(func(m): return m.level) == [0, 1, 0, 0], "less than 14 stacks, exact 14 resets, sides independent")
	check(markers.map(func(m): return m.center.y) == [19.0, 33.0, 19.0, 149.0], "upper and lower marker rows match reference")
	check(Model.marker_at(Vector2(20, 19), markers) == 1, "marker center selects original ply")
	check(Model.marker_at(Vector2(8, 19), markers) == -1, "exact 12px hit boundary is excluded")
	check(Model.marker_at(Vector2(8.01, 19), markers) == 1, "inside 12px hit boundary is included")
	check(Model.marker_at(Vector2(200, 80), markers) == -1, "blank chart area is not an icon")
	var tied = [{"ply": 2, "center": Vector2(10, 10)}, {"ply": 3, "center": Vector2(20, 10)}]
	check(Model.marker_at(Vector2(15, 10), tied) == 2, "equal-distance hits preserve first reference marker")
	var rows = []
	var samples = [{"score": 0}]
	for i in range(Model.Classification.NAMES.size()):
		rows.append({"ply": i + 1, "side": 1 if i % 2 == 0 else -1, "category": Model.Classification.NAMES[i]})
		samples.append({"score": (i - 5) * 300})
	markers = Model.markers(rows, samples, Vector2(360, 168), rows.size())
	check(markers.map(func(m): return m.category) == Model.MARKED, "exact five reference classifications appear")
	check(Model.markers(rows, samples.slice(0, 4), Vector2(360, 168), rows.size()).size() == 1, "partial report includes only analyzed classified moves")
	check(Model.markers([], [], Vector2(100, 168), 0).is_empty(), "empty analysis has no invented marker")
	var random = RandomNumberGenerator.new()
	random.seed = 22092026
	for height in [90, 168, 300]:
		for width in [120, 360, 1100]:
			for mirror in [1, -1]:
				plot = Model.plot_rect(Vector2(width, height))
				var entries = []
				for i in range(60):
					entries.append({"ply": i + 1, "side": (1 if random.randf() < 0.5 else -1) * mirror, "point": Vector2(plot.position.x + i * plot.size.x / 59, random.randf_range(plot.position.y - 50, plot.end.y + 50))})
				var actual = Model.arrange(entries, plot)
				for entry in actual:
					check(plot.encloses(Rect2(entry.center - Vector2(0, 6), Vector2(0, 12))), "dense marker remains within vertical bounds")
					check(entry.connector == ((entry.line_end.y - entry.line_start.y) * entry.side > 0), "connector stops at icon edge facing the curve")
				cases.append({"plot": [plot.position.x, plot.position.y, plot.size.x, plot.size.y], "entries": entries.map(serial), "actual": actual.map(serial)})
	var output = ProjectSettings.globalize_path("res://../review/app/chessis22")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("chart-core.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "cases": cases}, "  "))
	print("CHART 22: ", checks, " checks; ", failures)
	quit(0 if failures.is_empty() else 1)
