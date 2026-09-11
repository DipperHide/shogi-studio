extends "res://tests/chessis23_test.gd"

func weighted_glyphs(font: Font, weight: float, text: String) -> void:
	var ts = TextServerManager.get_primary_interface()
	var line = TextLine.new()
	line.add_string(text, font, 24, "ja")
	var glyphs = ts.shaped_text_get_glyphs(line.get_rid())
	check(not glyphs.is_empty(), "mixed Japanese and Chinese text shapes")
	for glyph in glyphs:
		if text.substr(glyph.start, 1) == " ": continue
		check(glyph.index != 0 and ts.font_get_variation_coordinates(glyph.font_rid).get(ts.name_to_tag("wght"), 100.0) == weight, "glyph " + text.substr(glyph.start, 1) + " uses weight " + str(weight))

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/fonts-hints")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records-" + str(Time.get_ticks_usec()))
	app.save_path = output.path_join("active.json")
	app.ui.tutorial.progress_path = output.path_join("learning.json")
	app.get_tree().create_timer(180).timeout.connect(func(): app.get_tree().quit(2))
	await resize(Vector2i(360, 800))
	app.set_preference("language", "ja")
	for text in ["局面编辑 棋譜を検討 推奨手順", "从入门到实战 学習する メニュー"]:
		weighted_glyphs(app.text_font, 400.0, text)
		weighted_glyphs(app.Design.heading_font(app.text_font), 600.0, text)
	app.ui.show_drawer()
	check(app.t("局面编辑") == "局面編集" and app.t("关于") == "このアプリについて", "drawer uses Japanese editor and about labels")
	await capture("japanese-menu")
	for language in ["zh", "ja", "en", "ja"]:
		app.set_preference("language", language)
		await settle(0.1)
		check(TranslationServer.get_locale().begins_with(language), "text locale follows selected language")
		for label in app.ui.page.find_children("*", "Label", true, false):
			if label.has_theme_font_override("font"):
				check(label.get_theme_font("font").base_font == app.text_font.base_font, "existing heading follows language switch")
	app.ui.tutorial.show_catalog()
	await capture("japanese-tutorial-catalog")
	check(not app.ui.tutorial.books.is_empty(), "tutorial courses load")
	app.ui.tutorial.show_book(app.ui.tutorial.books[0])
	await capture("japanese-tutorial-chapters")
	app._start_match("local", 1, 2, "basic"); app.ui.close()
	var original = app.RecordChanges.game_signature(app.game)
	app.ui.toolbar.get_child(2).name = "SearchHint"
	await press("BestLine")
	check(app.ui.live_enabled and await until(func(): return app.ui.live_details.has(1), 20), "first best-line tap starts real analysis")
	var request = app.engine_context.get("id", -1)
	var info = app.ui.live_details.get(1, {}).duplicate(true)
	await capture("best-line-visible")
	await press("BestLine")
	check(not app.ui.live_enabled and app.ui.arrows.is_empty() and app.ui.pv_rows.is_empty() and app.ui.live_details.is_empty(), "second best-line tap clears hints and candidate rows")
	check(app.engine_context.is_empty(), "closing best line cancels its engine request")
	app._engine_info(request, info)
	await settle(0.3)
	check(app.ui.pv_rows.is_empty() and app.ui.arrows.is_empty(), "late engine response cannot restore hidden hints")
	await capture("best-line-hidden")
	await press("SearchHint")
	check(app.ui.live_enabled and await until(func(): return app.ui.live_details.has(1), 15), "search button can open hints after best line closes")
	await press("BestLine")
	check(not app.ui.live_enabled and app.ui.pv_rows.is_empty(), "best line closes hints opened by search")
	await press("BestLine")
	check(await until(func(): return app.ui.live_details.has(1), 15), "best line reopens hints")
	await press("SearchHint")
	check(not app.ui.live_enabled and app.ui.pv_rows.is_empty(), "search closes hints opened by best line")
	await press("BestLine")
	check(await until(func(): return app.ui.live_details.has(1), 15), "best line can start a candidate preview")
	if app.ui.pv_rows.has(1):
		app.ui.pv_rows[1].play_button.name = "PreviewBestLine"
		await press("PreviewBestLine")
		check(not app.ui.pv_context.is_empty(), "candidate preview opens")
		await press("BestLine")
		check(app.ui.pv_context.is_empty() and not app.ui.live_enabled and app.ui.pv_rows.is_empty(), "best-line toggle closes preview and hints together")
	check(app.RecordChanges.game_signature(app.game) == original and app.records.list_all().is_empty(), "hint toggles leave game and archive unchanged")
	app._pause_search()
	await finish()
