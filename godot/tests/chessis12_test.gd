extends "res://tests/unified_test.gd"

func capture(name: String) -> void:
	await settle(0.08)
	await RenderingServer.frame_post_draw
	app.get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))
	screenshots.append(name)

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis12/ui")
	if "--chessis21-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis21/chessis12_test")
	if "--chessis13-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis13/report-ui")
	if "--chessis14-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis14/report-ui")
	if "--chessis15-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis15/report-ui")
	if "--chessis16-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis16/report-ui")
	if "--chessis17-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis17/report-ui")
	if "--chessis18-regression" in OS.get_cmdline_user_args(): output=ProjectSettings.globalize_path("res://../review/app/chessis18/report-ui")
	if "--chessis19-regression" in OS.get_cmdline_user_args(): output=ProjectSettings.globalize_path("res://../review/app/chessis19/report-ui")
	if "--chessis20-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis20/chessis12_test")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.get_tree().create_timer(160).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local", 1, 2, "basic")
	app.ui.close()
	await resize(Vector2i(393, 852))
	var live = app.game
	var original_key: String = live.position.key()
	var historic = preload("res://scripts/shogi_historic_games.gd").new()
	var source = historic.game_for(historic.entries()[0])
	var report = app.ui.report
	report.start(source, false, {"quick_mode": "depth", "quick_depth": 3}, {"threads": 2, "hash": 32})
	check(await until(func(): return report.samples.size() >= 8 or not report.running, 15), "historic report starts with real engine samples")
	report.cancel()
	var prefix: Array = report.samples.duplicate(true)
	app.ui.show_report()
	await capture("partial-report")
	check(report.can_resume() and not report.summary(1).counts.is_empty(), "partial report retains actual counts and can resume")
	check(report.summary(1).count + report.summary(-1).count == report.rows.size(), "partial summary counts only analyzed moves")
	app.ui.show_phase_accuracy(1)
	await capture("partial-phase-detail")
	check(app.ui.page.find_child("Phase3", true, false) == null, "unanalyzed endgame omitted until this player has analyzed hands")
	app.ui.back()
	check(app.ui.page_name == "report", "phase detail back returns to report")
	report.resume()
	check(await until(func(): return not report.running, 100), "full 140-ply historical report finishes")
	check(report.error.is_empty() and report.samples.size() == source.positions.size(), "every historical position has real score")
	check(report.samples.slice(0, prefix.size()) == prefix, "resume retains exact completed engine samples")
	check(report.rows.all(func(row): return row.has("metrics")), "every evaluated move contains accuracy inputs")
	check(report.rows.all(func(row): return row.category == "定式" if row.metrics.book else (row.category in ["最佳", "妙手", "锐利"]) == (row.best == app.Codec.move_name(report.game.moves[row.ply - 1]))), "book moves separated and every best-family category matches principal variation identity")
	var reached_endgame = false
	for row in report.rows:
		if reached_endgame: check(row.classification.endgame, "classification endgame remains active at ply " + str(row.ply))
		reached_endgame = row.classification.endgame
	for row in report.rows:
		if row.category not in ["妙手", "锐利"]: continue
		var proof: Dictionary = row.classification.verification
		check(proof.accepted and proof.candidates.size() == 2 and proof.candidates[0].depth == proof.candidates[1].depth, "historical rare category has complete same-depth engine evidence")
	check(report.phases().size() == 3, "real full game has opening, middlegame and endgame")
	for side in [1, -1]:
		var stats: Dictionary = report.summary(side)
		var count = 0
		for segment in report.phases(): count += report.phase_summary(side, segment).count
		check(count == stats.count, "phase counts reconcile with overall side " + str(side))
		check(stats.has_accuracy and is_finite(stats.accuracy) and stats.accuracy >= 0 and stats.accuracy <= 100, "actual accuracy finite and bounded for side " + str(side))
	app.ui.show_report()
	for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393), Vector2i(1100, 800)]:
		await resize(dimensions)
		var ribbon = app.ui.report_phases
		app.ui.page_scroll.ensure_control_visible(ribbon)
		await capture("report-%dx%d" % [dimensions.x, dimensions.y])
		check(app.safe_rect().encloses(app.ui.page.get_global_rect()), "full report fits " + str(dimensions))
		check(ribbon.size.x <= app.ui.page.size.x and app.ui.report_chart.size.x == ribbon.size.x, "phase rows and chart share width " + str(dimensions))
		check(ribbon.hits.size() == 10, "both players have three phase targets plus accuracy and rating targets " + str(dimensions))
		for hit in ribbon.hits: check(Rect2(Vector2.ZERO, ribbon.size).encloses(hit.rect), "phase touch region fits at " + str(dimensions))
	await resize(Vector2i(393, 852))
	app.ui.select_report_move(14)
	app.ui.page_scroll.ensure_control_visible(app.ui.report_phases)
	await settle()
	var hit: Dictionary = app.ui.report_phases.hits[0]
	await tap(app.ui.report_phases.global_position + hit.rect.get_center())
	check(app.ui.page_name == "report-phase", "actual phase bar touch opens details")
	await capture("phase-detail-sente")
	check(app.ui.page.find_child("PhaseAccuracyView", true, false) != null, "phase touch opens compact read-only cards")
	app.ui.back()
	check(app.ui.page_name == "report" and app.ui.report_selected_ply == 14, "return retains selected report move")
	await settle()
	app.ui.page_scroll.ensure_control_visible(app.ui.report_phases)
	await settle()
	var last: Dictionary = app.ui.report_phases.hits.filter(func(item): return item.side == -1 and item.kind == "accuracy")[0]
	check(app.ui.page_scroll.get_global_rect().has_point(app.ui.report_phases.global_position + last.rect.get_center()), "accuracy target is visibly scrolled into viewport before tapping")
	await tap(app.ui.report_phases.global_position + last.rect.get_center())
	check(app.ui.page_name == "report-accuracy", "other player's accuracy chip opens dedicated per-move insight")
	await capture("accuracy-detail-gote")
	app.ui.back()
	app.ui.show_phase_accuracy(-1)
	await capture("phase-detail-gote")
	app.ui.back()
	check(app.ui.page_name == "report" and app.ui.report_selected_ply == 14, "read-only phase popup preserves original selection")
	check(app.game == live and app.game.position.key() == original_key, "phase exploration preserves live game")
	app.ui.report_selected_ply = -1
	app.ui.set_extra("report_cpl", true)
	app.ui.show_report()
	check(app.ui.report_phases.show_cpl, "optional ACPL reaches phase summary")
	app.ui.page_scroll.ensure_control_visible(app.ui.report_phases)
	await capture("report-acpl")
	for mode in ["light", "dark"]:
		var title = app.ui.page.find_children("*", "Label", true, false)[0]
		var color: Color = title.get_theme_color("font_color")
		app.set_preference("color_mode", mode)
		check(title.get_theme_color("font_color") == color, "wood report text contrast survives theme change " + mode)
		await capture("report-" + mode)
	app.ui.show_phase_accuracy(-1, 3)
	for dimensions in [Vector2i(360, 760), Vector2i(852, 393)]:
		await resize(dimensions)
		check(app.safe_rect().encloses(app.ui.page.get_global_rect()), "phase details fit " + str(dimensions))
		await capture("phase-%dx%d" % [dimensions.x, dimensions.y])
	FileAccess.open(output.path_join("actual-report.json"), FileAccess.WRITE).store_string(JSON.stringify({"source": source.metadata, "samples": report.samples, "rows": report.rows, "sente": report.summary(1), "gote": report.summary(-1), "phases": report.phases()}, "  "))
	FileAccess.open(output.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "screenshots": screenshots}, "  "))
	print("CHESSIS 12 UI: ", checks, " checks; ", failures)
	app.get_tree().quit(0 if failures.is_empty() else 1)
