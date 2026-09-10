extends "res://tests/chessis13_test.gd"
const Ribbon = preload("res://scripts/shogi_report_phases.gd")
var geometry = []

func target(side: int, kind: String) -> Button:
	for item in app.ui.report_phases.targets:
		if item.side == side and item.kind == kind: return item.button
	return null

func touch_target(side: int, kind: String) -> void:
	await settle(0.15)
	var button = target(side, kind)
	check(button != null, "native " + kind + " control exists")
	if button == null: return
	app.ui.page_scroll.ensure_control_visible(button)
	await settle()
	check(app.ui.page_scroll.get_global_rect().encloses(button.get_global_rect()), "native " + kind + " button is in the visible scroll area")
	await tap(button.get_global_rect().get_center())

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis21/ui")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.save_path = output.path_join("active-test.json")
	app.ui.tutorial.progress_path = output.path_join("learning-test.json")
	app.get_tree().create_timer(175).timeout.connect(func(): check(false, "test deadline"); finish())
	app._start_match("local", 1, 2, "basic")
	app.ui.close()
	await resize(Vector2i(393, 852))
	report = app.ui.report
	var historic = preload("res://scripts/shogi_historic_games.gd").new()
	var source = historic.game_for(historic.entries()[0])
	report.start(source, false, {"quick_mode": "depth", "quick_depth": 3}, {"threads": 2, "hash": 32})
	check(await until(func(): return not report.running, 100), "real 140-ply report completes")
	check(report.error.is_empty() and report.samples.size() == 141, "ribbon uses real full-game analysis")
	FileAccess.open(output.path_join("engine-report.json"), FileAccess.WRITE).store_string(JSON.stringify({"source": report.game.to_data(), "rows": report.rows, "samples": report.samples}, "  "))
	for pair in [[0.0, "0%"], [90.0, "90%"], [90.25, "90.3%"], [99.96, "99.9%"], [100.0, "100%"]]:
		check(Ribbon.accuracy_caption({"has_accuracy": true, "accuracy": pair[0]}) == pair[1], "reference overall percentage format " + str(pair))
	check(Ribbon.phase_caption({"has_accuracy": true, "accuracy": 90.5}) == "91%", "phase bar rounds separately from overall precision")
	check(Ribbon.phase_caption({"has_accuracy": false, "count": 2, "book": 2}) == "定式", "actual book-only phase label")
	check(Ribbon.phase_caption({"has_accuracy": false, "count": 2, "book": 0}) == "—", "forced-only phase does not pretend to be book")
	check(Ribbon.player_caption("🏆 🤖 Computer (1800)", 1) == "Computer", "decorative winner and rating removed from player name")
	check(Ribbon.player_caption("藤井聡太王位", 1) == "藤井聡太王位", "actual shogi titles remain intact")
	check(Ribbon.player_caption("  ", -1) == "后手", "blank player falls back to side name")
	for mode in ["dark", "light"]:
		app.set_preference("color_mode", mode)
		for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393), Vector2i(1100, 800)]:
			await resize(dimensions)
			app.preferences.studio.report_cpl = true
			app.ui.show_report()
			await settle()
			var ribbon = app.ui.report_phases
			app.ui.page_scroll.ensure_control_visible(ribbon)
			await settle()
			check(ribbon.hits.size() == 12, "phase, accuracy, ACPL and rating controls for both players")
			check(ribbon.find_child("PhaseLabelStrip", true, false).size.y == 22, "reference label strip height")
			check(ribbon.find_child("PhaseTopDivider", true, false).size.y == 1, "reference divider height")
			var groups = ribbon.find_child("PhaseSideGroups", true, false)
			check(groups.get_theme_constant("separation") == 20, "reference side group spacing")
			var side_index = 0
			for group in groups.get_children():
				var side = 1 if side_index == 0 else -1
				var bars = group.find_child("PhaseSegments", true, false)
				check(bars.size.y == 34 and bars.get_theme_constant("separation") == 4, "reference 34-high bars and shared gaps")
				var style = group.get_theme_stylebox("panel")
				check(style.bg_color == Color("18202866") and style.border_color == Color("58a6ff77") and style.corner_radius_top_left == 8, "reference translucent outlined side group")
				var player = group.find_child("PhasePlayerName", true, false)
				check(player.text == report.player_name(side) and player.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT, "player name is left aligned and separate from side icon")
				var trophies = group.find_children("PhaseWinner", "TextureRect", true, false)
				check(trophies.size() == (1 if source.winner == side else 0), "trophy only belongs to actual winner")
				if not trophies.is_empty(): check(trophies[0].size == Vector2(16, 16), "winner icon is 16 by 16")
				var flow = group.find_child("PhaseSummaryFlow", true, false)
				var lines = {}
				for wrapper in flow.get_children():
					lines[roundi(wrapper.position.y)] = true
					check(flow.get_global_rect().grow(1).encloses(wrapper.get_global_rect()), "metric chip remains inside flow width")
					var button = wrapper.get_child(0)
					check(button.custom_minimum_size.y >= 26 and not button.accessibility_name.is_empty() and button.focus_mode == Control.FOCUS_ALL, "native chips expose keyboard and accessibility targets")
				if dimensions.x <= 393: check(lines.size() == 2, "narrow summaries wrap without shrinking text")
				if dimensions.x == 1100: check(lines.size() == 1, "wide summaries remain on one row")
				geometry.append({"window": str(dimensions), "theme": mode, "side": side, "group_size": str(group.size), "summary_lines": lines.size(), "ribbon_height": ribbon.size.y})
				side_index += 1
			for hit in ribbon.hits: check(Rect2(Vector2.ZERO, ribbon.size).grow(1).encloses(hit.rect), "native hit region remains inside resized ribbon")
			await capture("ribbon-%s-%dx%d" % [mode, dimensions.x, dimensions.y])
	await resize(Vector2i(393, 852))
	app.ui.show_report()
	app.ui.select_report_move(14)
	await touch_target(1, "phase")
	check(app.ui.page_name == "report-phase", "native phase button opens side detail")
	app.ui.back()
	await touch_target(-1, "accuracy")
	check(app.ui.page_name == "report-accuracy", "native accuracy chip opens per-move insight")
	app.ui.back()
	await touch_target(1, "acpl")
	check(app.ui.page_name == "report-metric-info", "native ACPL chip opens loss explanation")
	app.ui.back()
	await settle(0.15)
	var rating = target(-1, "rating")
	app.ui.page_scroll.ensure_control_visible(rating)
	await settle()
	rating.grab_focus()
	for down in [true, false]:
		var action = InputEventAction.new()
		action.action = "ui_accept"; action.pressed = down
		Input.parse_input_event(action); Input.flush_buffered_events()
		await settle()
	check(app.ui.page_name == "report-metric-info", "rating chip supports keyboard activation")
	var return_button = app.ui.page.find_children("*", "Button", true, false).filter(func(b): return b.text == "返回分析报告")[0]
	check(return_button.get_theme_color("font_color") == Color("f8f1e6"), "rating explanation keeps readable return text in light mode")
	await capture("rating-unavailable")
	app.ui.back()
	await settle(0.15)
	check(app.ui.report_selected_ply == 14, "all detail round trips preserve selected move")
	var old_metadata = report.game.metadata.duplicate(true)
	report.game.metadata["先手"] = "非常长的棋手名称用于验证第二行与截断非常长的棋手名称用于验证第二行与截断 (1800)"
	app.ui.report_phases.refresh()
	await settle()
	var player = app.ui.report_phases.find_child("PhasePlayerName", true, false)
	check(player.max_lines_visible == 2 and player.get_line_count() >= 2 and not player.text.contains("1800"), "long name wraps to two visible lines without duplicating rating")
	app.ui.page_scroll.ensure_control_visible(app.ui.report_phases)
	await capture("long-player-name")
	report.game.metadata = old_metadata
	var original_rows = report.rows
	var original_samples = report.samples
	report.rows = report.rows.slice(0, 1)
	report.samples = report.samples.slice(0, 2)
	app.ui.report_phases.refresh()
	await settle()
	check(app.ui.report_phases.find_child("PhaseSideSente", true, false) != null and app.ui.report_phases.find_child("PhaseSideGote", true, false) == null, "side with no analyzed moves is not fabricated")
	check(app.ui.report_phases.hits.filter(func(hit): return hit.kind == "phase").size() == 1, "unobserved phases have no clickable score")
	await capture("partial-ribbon")
	report.rows = original_rows; report.samples = original_samples
	FileAccess.open(output.path_join("geometry.json"), FileAccess.WRITE).store_string(JSON.stringify(geometry, "  "))
	await finish()
