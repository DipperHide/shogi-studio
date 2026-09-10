extends "res://tests/chessis13_test.gd"
const Quality = preload("res://scripts/shogi_report_quality.gd")
var evidence = []

func press(name: String) -> void:
	await settle(0.1)
	var control = app.ui.root.find_child(name, true, false)
	check(control != null and control.is_visible_in_tree() and not control.disabled, "available visible control " + name)
	if control == null: return
	var parent = control.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(control)
		parent = parent.get_parent()
	await RenderingServer.frame_post_draw
	await app.get_tree().process_frame
	# Dispatch after the scrolled layout has been painted, then paint the press
	# before release, matching separate hardware input frames.
	for down in [true, false]:
		var event = InputEventScreenTouch.new()
		event.index = 0; event.pressed = down
		event.position = control.get_global_rect().get_center()
		Input.parse_input_event(event); Input.flush_buffered_events()
		await RenderingServer.frame_post_draw
		await app.get_tree().process_frame

func key(code: Key) -> void:
	for down in [true, false]:
		var event = InputEventKey.new()
		event.keycode = code; event.pressed = down
		Input.parse_input_event(event); Input.flush_buffered_events()
		await settle(0.025)

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis23/ui")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.save_path = output.path_join("active-test.json")
	app.ui.tutorial.progress_path = output.path_join("learning-test.json")
	app.get_tree().create_timer(180).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local", 1, 2, "basic")
	app.ui.close()
	live = app.game; saved_live = live.to_data().duplicate(true)
	practice = app.ui.practice
	report = app.ui.report
	var historic = preload("res://scripts/shogi_historic_games.gd").new()
	var source = historic.game_for(historic.entries()[0])
	report.start(source, false, {"quick_mode": "depth", "quick_depth": 3}, {"threads": 2, "hash": 32})
	check(await until(func(): return not report.running, 100), "actual engine finishes historical analysis")
	check(report.error.is_empty() and report.rows.size() == 140, "statistics use all 140 actual analyzed moves")
	FileAccess.open(output.path_join("engine-report.json"), FileAccess.WRITE).store_string(JSON.stringify({"source": source.to_data(), "rows": report.rows, "samples": report.samples}, "  "))
	for mode in ["dark", "light"]:
		app.set_preference("color_mode", mode)
		for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393), Vector2i(1100, 800)]:
			await resize(dimensions)
			app.ui.report_moves_expanded = false
			app.ui.show_report()
			await settle(0.1)
			var stats = app.ui.report_statistics
			check(not stats.pies[0].visible and not stats.insight.visible and stats.expand.visible, "report starts with collapsed statistics")
			for category in report.CATEGORIES:
				check(stats.cells[category][0].visible == Quality.row_visible(category, false, [report.summary(1).counts, report.summary(-1).counts]), "collapsed reference row visibility " + category)
			await press("ExpandReportMoves")
			await settle(0.12)
			check(stats.pies[0].reveal > 0 and stats.pies[0].reveal < 1, "expanding starts actual pie reveal")
			await settle(0.9)
			check(not stats.expand.visible and stats.cells.values().all(func(row): return row.all(func(cell): return cell.visible)), "one-way expansion shows every category")
			app.ui.page_scroll.ensure_control_visible(stats.pies[0])
			await settle(0.1)
			for side_index in range(2):
				var side: int = 1 if side_index == 0 else -1
				var pie = stats.pies[side_index]
				var counts: Dictionary = report.summary(side).counts
				check(pie.counts == counts, "pie uses actual side counts")
				check(pie.reveal == 1 and pie.ranges.size() <= 3, "reveal completes with at most three groups")
				check(pie.size.y == 200 and absf(pie.size.x - stats.cells["定式"][side_index * 2].size.x) < 1, "pie aligned under matching table player column")
				check(absf(pie.global_position.x - stats.cells["定式"][side_index * 2].global_position.x) < 1, "pie and raw count column share x coordinate")
				var geo = pie.geometry()
				check(pie.hit_group(geo.center) == -1, "white hole ignores taps")
				var pixels = app.get_viewport().get_texture().get_image()
				var at: Vector2 = pie.global_position + geo.center
				check(pixels.get_pixel(roundi(at.x), roundi(at.y)).r > 0.96 and pixels.get_pixel(roundi(at.x), roundi(at.y)).g > 0.96, "rendered pie hole is white in both themes")
				check(pie.accessibility_name.contains("加权"), "assistive description identifies weighted percentage")
			check(app.safe_rect().encloses(app.ui.page.get_global_rect()), "statistics fit safe area")
			evidence.append({"window": str(dimensions), "theme": mode, "pie_width": stats.pies[0].size.x, "sente": Quality.weights(report.summary(1).counts), "gote": Quality.weights(report.summary(-1).counts)})
			await capture("statistics-%s-%dx%d" % [mode, dimensions.x, dimensions.y])
	await resize(Vector2i(393, 852))
	app.set_preference("color_mode", "dark")
	app.ui.show_report()
	await settle(0.1)
	var stats = app.ui.report_statistics
	var pie = stats.pies[0]
	check(pie.visible, "last expansion remains available for interaction tests")
	if not pie.visible: await finish(); return
	app.ui.page_scroll.ensure_control_visible(pie)
	await settle(0.9)
	var saved_counts: Dictionary = pie.counts
	pie.counts = {}; pie.queue_redraw()
	await settle(0.1)
	check(pie.ranges.is_empty(), "empty report draws no false category")
	pie.counts = {"最佳": 12}; pie.finish_reveal()
	await settle(0.1)
	check(pie.ranges.size() == 1 and pie.ranges[0].group == 2, "single category draws one complete ring")
	var fixture_pixel: Vector2 = pie.global_position + pie.geometry().center + Vector2(pie.geometry().radius * 0.85, 0)
	var fixture_color = app.get_viewport().get_texture().get_image().get_pixel(roundi(fixture_pixel.x), roundi(fixture_pixel.y))
	check(fixture_color.g > 0.95 and fixture_color.r < 0.05, "single full ring is actually rendered green")
	pie.counts = saved_counts; pie.queue_redraw()
	await settle(0.1)
	for segment in pie.ranges.duplicate(true):
		var geo = pie.geometry()
		var at: Vector2 = pie.global_position + geo.center + Vector2.from_angle(segment.start + segment.sweep / 2) * geo.radius * 0.8
		await tap(at)
		check(pie.active == segment.group and stats.insight.visible, "real touch opens selected quality insight")
		check(stats.insight_percent.text == "%.1f%%" % Quality.percentage(Quality.weights(pie.counts), segment.group), "insight displays exact weighted percentage with one decimal")
		check(app.ui.page_name == "report" and app.review_game == null, "pie explanation keeps report open")
		await settle(0.2)
		check(app.ui.page_scroll.get_global_rect().encloses(stats.insight.get_global_rect()), "selected explanation automatically scrolls into view")
		app.ui.page_scroll.ensure_control_visible(pie)
		await settle(0.2)
	await capture("quality-selected")
	pie.grab_focus()
	await key(KEY_HOME)
	check(pie.active == pie.ranges.front().group, "keyboard Home selects first available quality")
	await key(KEY_END)
	check(pie.active == pie.ranges.back().group, "keyboard End selects final available quality")
	await settle(0.2)
	var rotation_before: float = pie.rotation_angle
	var previous_selection: int = pie.active
	var geo = pie.geometry()
	var segment = pie.ranges[0]
	var angle: float = segment.start + segment.sweep / 2
	var down = InputEventScreenTouch.new()
	down.index = 0; down.pressed = true; down.position = pie.global_position + geo.center + Vector2.from_angle(angle) * geo.radius * 0.8
	Input.parse_input_event(down); Input.flush_buffered_events()
	for step in range(1, 7):
		var drag = InputEventScreenDrag.new()
		drag.index = 0
		drag.position = pie.global_position + geo.center + Vector2.from_angle(angle + step * 0.16) * geo.radius * 0.8
		Input.parse_input_event(drag); Input.flush_buffered_events()
		if step < 6: await settle(0.025)
	down.pressed = false
	down.position = pie.global_position + geo.center + Vector2.from_angle(angle + 0.96) * geo.radius * 0.8
	Input.parse_input_event(down); Input.flush_buffered_events()
	var released_speed = absf(pie.velocity)
	await settle(0.04)
	check(absf(pie.rotation_angle - rotation_before) > 0.3, "actual touch drag rotates pie")
	check(pie.active == previous_selection and pie.pointer == -2, "drag does not trigger another slice and releases pointer")
	await settle(0.1)
	check(released_speed > 0 and absf(pie.velocity) < released_speed, "release inertia decelerates from a measured nonzero velocity")
	FileAccess.open(output.path_join("rotation.json"), FileAccess.WRITE).store_string(JSON.stringify({"released_speed": released_speed, "after_speed": absf(pie.velocity), "angle_before": rotation_before, "angle_after": pie.rotation_angle}, "  "))
	pie.velocity = 0
	var category: String = report.rows.filter(func(row): return report.rows.filter(func(other): return other.category == row.category).size() > 1)[0].category
	var first: int = Quality.next_ply(report.rows, category, 0, -1)
	await press("ClassificationRow_" + category)
	await settle(0.35)
	check(app.ui.page == null and app.review_game == report.game and app.replay_index == first, "table category returns board at original classified move")
	preserve("category navigation")
	var next: int = Quality.next_ply(report.rows, category, 0, first)
	await press("InlineCategory_" + category)
	await settle(0.35)
	check(app.replay_index == next, "board category control advances to next occurrence")
	var counter = app.ui.report_inline.find_child("InlineCategory_" + category, true, false)
	check(counter.size.y <= counter.get_parent().get_parent().size.y, "two-line board category control is not vertically clipped")
	preserve("repeat category navigation")
	app.ui.show_report()
	await settle(0.1)
	check(app.ui.report_statistics.pies[0].visible, "same report retains expanded statistics")
	app.ui.report.game = app.Game.from_data(source.to_data())
	app.ui.show_report()
	check(not app.ui.report_statistics.pies[0].visible, "different report resets collapsed statistics")
	FileAccess.open(output.path_join("geometry.json"), FileAccess.WRITE).store_string(JSON.stringify(evidence, "  "))
	await finish()
