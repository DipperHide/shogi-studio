extends "res://tests/chessis13_test.gd"
const Model = preload("res://scripts/shogi_report_chart_model.gd")
var evidence = []

func send_key(code: Key) -> void:
	for down in [true, false]:
		var event = InputEventKey.new()
		event.keycode = code; event.pressed = down
		Input.parse_input_event(event); Input.flush_buffered_events()
		await settle(0.025)

func show_chart() -> void:
	app.ui.show_report()
	app.ui.select_report_move(14)
	await settle(0.1)
	app.ui.page_scroll.ensure_control_visible(app.ui.report_chart)
	await settle(0.9)

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis22/ui")
	if "--chessis23-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis23/chessis22_test")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.save_path = output.path_join("active-test.json")
	app.ui.tutorial.progress_path = output.path_join("learning-test.json")
	app.get_tree().create_timer(180).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local", 1, 2, "basic")
	app.ui.close()
	var original = app.game
	var original_key = original.position.key()
	await resize(Vector2i(393, 852))
	report = app.ui.report
	var historic = preload("res://scripts/shogi_historic_games.gd").new()
	var source = historic.game_for(historic.entries()[0])
	report.start(source, false, {"quick_mode": "depth", "quick_depth": 3}, {"threads": 2, "hash": 32})
	check(await until(func(): return not report.running, 100), "actual engine completes historical report")
	check(report.error.is_empty() and report.rows.size() == 140 and report.samples.size() == 141, "chart uses full actual analysis")
	FileAccess.open(output.path_join("engine-report.json"), FileAccess.WRITE).store_string(JSON.stringify({"source": source.to_data(), "rows": report.rows, "samples": report.samples}, "  "))
	app.ui.show_report()
	await settle(0.1)
	check(app.ui.report_chart.reveal > 0 and app.ui.report_chart.reveal < 1, "chart reveals progressively after opening")
	await capture("chart-revealing")
	await settle(0.9)
	check(app.ui.report_chart.reveal == 1, "chart reveal completes within configured interval")
	for mode in ["dark", "light"]:
		app.set_preference("color_mode", mode)
		for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393), Vector2i(1100, 800)]:
			await resize(dimensions)
			await show_chart()
			var chart = app.ui.report_chart
			check(chart.size.y == 168, "reference chart height retained")
			check(chart.markers.size() == report.rows.filter(func(row): return row.category in Model.MARKED).size(), "all and only reference categories have chart icons")
			check(chart.visible_markers().size() == chart.markers.size(), "completed reveal shows every analyzed marker")
			check(chart.focus_mode == Control.FOCUS_ALL and not chart.accessibility_name.is_empty(), "chart supports focus and an accessible description")
			var plot = Model.plot_rect(chart.size)
			for marker in chart.markers:
				var row = report.rows[marker.ply - 1]
				check(marker.side == row.side and marker.category == row.category, "marker retains actual mover and classification")
				check(is_equal_approx(marker.center.x, chart.point_for(marker.ply).x), "marker has the actual ply x coordinate")
				check(plot.encloses(Rect2(marker.center - Vector2(0, 6), Vector2(0, 12))), "marker fits plot after resize")
				check(chart.textures[marker.icon] is Texture2D, "actual classification texture is loaded")
			var groups = app.ui.report_phases.find_child("PhaseSideGroups", true, false)
			var labels = app.ui.report_phases.find_child("PhaseLabelsInset", true, false).get_child(0)
			check(absf(groups.global_position.x - (chart.global_position.x + plot.position.x)) < 1, "phase groups align with the chart plot left edge")
			check(absf(labels.global_position.x - groups.global_position.x) < 1 and absf(labels.size.x - groups.size.x) < 1, "phase titles and bars use the same chart insets")
			check(app.ui.report_phases.find_children("PhaseLabelDivider", "ColorRect", true, false).size() == report.phases().size() - 1, "phase labels have reference boundary separators")
			for i in range(1, report.phases().size()):
				var expected = Model.point(report.phases()[i].start - 0.5, 0, plot, 140).x + chart.global_position.x
				check(absf(labels.get_child(i).global_position.x - expected) <= 2, "phase title boundary matches dashed graph boundary")
			evidence.append({"window": str(dimensions), "theme": mode, "plot": str(plot), "markers": chart.markers.size()})
			await capture("chart-%s-%dx%d" % [mode, dimensions.x, dimensions.y])
			var pixels = app.get_viewport().get_texture().get_image()
			for item in [[3, chart.SENTE_BACKGROUND], [165, chart.GOTE_BACKGROUND]]:
				var location: Vector2 = chart.global_position + Vector2(plot.position.x + plot.size.x * 0.75, item[0])
				var color = pixels.get_pixel(roundi(location.x), roundi(location.y))
				check(absf(color.r - item[1].r) < 0.02 and absf(color.g - item[1].g) < 0.02 and absf(color.b - item[1].b) < 0.02, "rendered target zones fill original vertical inset too")
	await resize(Vector2i(393, 852))
	await show_chart()
	var chart = app.ui.report_chart
	var isolated = chart.markers.filter(func(marker): return chart.markers.all(func(other): return other.ply == marker.ply or marker.center.distance_to(other.center) > 25))
	check(not isolated.is_empty(), "real historical report has isolated marker for expanded hit-target test")
	if not isolated.is_empty():
		var marker = isolated[0]
		var hit = marker.center + Vector2(9, 0)
		var plain_ply = roundi((hit.x - 8) / (chart.size.x - 16) * 140)
		check(plain_ply != marker.ply, "test differentiates icon selection from nearest curve ply")
		await tap(chart.global_position + hit)
		check(app.ui.report_selected_ply == marker.ply and chart.active == marker.ply, "touch near actual icon selects its original move")
		await capture("marker-selected")
	chart.grab_focus()
	await send_key(KEY_END)
	check(app.ui.report_selected_ply == 140, "keyboard End selects last analyzed move")
	await send_key(KEY_LEFT)
	check(app.ui.report_selected_ply == 139, "keyboard Left selects previous analyzed move")
	await send_key(KEY_RIGHT)
	check(app.ui.report_selected_ply == 140, "keyboard Right selects next analyzed move")
	await send_key(KEY_HOME)
	check(app.ui.report_selected_ply == -1, "keyboard Home clears selected move at initial position")
	await send_key(KEY_RIGHT)
	check(app.ui.report_selected_ply == 1, "keyboard advances from initial position")
	app.ui.select_report_move(20)
	await settle()
	app.ui.page_scroll.ensure_control_visible(chart)
	await settle()
	var from = chart.global_position + chart.point_for(20)
	var to = chart.global_position + chart.point_for(60)
	var down = InputEventScreenTouch.new()
	down.index = 0; down.pressed = true; down.position = from
	Input.parse_input_event(down); Input.flush_buffered_events()
	await settle()
	for i in range(1, 7):
		var drag = InputEventScreenDrag.new()
		drag.index = 0; drag.position = from.lerp(to, i / 6.0); drag.relative = (to - from) / 6
		Input.parse_input_event(drag); Input.flush_buffered_events()
		await settle(0.025)
	down.pressed = false; down.position = to
	Input.parse_input_event(down); Input.flush_buffered_events()
	await settle()
	check(app.ui.report_selected_ply == 60, "drag scrubs to the intended analyzed ply")
	check(app.game == original and app.game.position.key() == original_key, "chart exploration leaves live game intact")
	var all_samples = report.samples
	var all_rows = report.rows
	report.samples = report.samples.slice(0, 31)
	report.rows = report.rows.slice(0, 30)
	app.ui.show_report()
	await settle(0.9)
	chart = app.ui.report_chart
	check(chart.markers.all(func(marker): return marker.ply <= 30), "partial report never shows future classification icons")
	chart.choose(140)
	check(app.ui.report_selected_ply == 30, "unavailable future curve selection clamps to analyzed prefix")
	app.ui.page_scroll.ensure_control_visible(chart)
	await capture("partial-chart")
	report.samples = all_samples; report.rows = all_rows
	FileAccess.open(output.path_join("geometry.json"), FileAccess.WRITE).store_string(JSON.stringify(evidence, "  "))
	await finish()
