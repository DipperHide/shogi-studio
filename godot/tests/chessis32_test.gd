extends "res://tests/chessis23_test.gd"
const Hint = preload("res://scripts/shogi_move_hint.gd")
const SFEN = "k8/9/4P4/9/9/9/9/9/8K b - 1"

func candidates(first: String = "5c5b+") -> void:
	app._pause_search(); app.ui.clear_pv_rows(); app.ui.live_details.clear()
	app.ui.live_enabled = true; app.ui.live_key = app._display_position().key()
	app.ui.receive_info({"multipv":1,"score":100,"pv":[first,"9a9b"]})
	app.ui.receive_info({"multipv":2,"score":50,"pv":["5c5b","9a9b"]})

func run(instance) -> void:
	app = instance; output = ProjectSettings.globalize_path("res://../review/app/chessis32/ui")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records"); app.save_path = output.path_join("active.json")
	app.ui.tutorial.progress_path = output.path_join("learning.json")
	app.get_tree().create_timer(180).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local",1,2,"basic"); app.ui.close()
	live = app.game; saved_live = live.to_data().duplicate(true); practice = app.ui.practice; report = app.ui.report
	var source = app.Game.new(); check(source.set_initial(SFEN), "promotion analysis fixture is legal")
	source.mode = "local"; app.review_game = source; app.replay_index = 0; app._refresh()
	for style in ["minimal","wood"]:
		app.set_appearance(style)
		for flip in [false,true]:
			app.flipped = flip; app.set_preference("color_mode","light" if flip else "dark")
			for dimensions in [Vector2i(360,760),Vector2i(393,852),Vector2i(852,393),Vector2i(1100,800)]:
				await resize(dimensions); candidates(); await settle(0.12); await RenderingServer.frame_post_draw
				var badges = app.board_view.hint_badges
				check(badges.size()==2, "both promotion alternatives appear on painted " + style)
				check(badges[0].text=="1 成" and badges[1].text=="2 不成", "painted badges preserve promotion and candidate number")
				check(not badges[0].rect.intersects(badges[1].rect) and badges.all(func(b): return app.board_rect.encloses(b.rect)), "same destination badges do not overlap or leave board")
				for index in [1,2]:
					var row = app.ui.pv_rows[index]
					check(row.hint_label.is_visible_in_tree() and row.get_global_rect().encloses(row.hint_label.get_global_rect()), "visible pinned promotion label inside candidate row")
					check(row.scroll.size.x >= 30 and row.get_global_rect().encloses(row.eye_button.get_global_rect()), "candidate text remains scrollable and controls accessible")
				check(app.ui.pv_rows[2].move_label.text.contains("歩不成"), "line explicitly includes declined promotion")
				await capture("hint-%s-%s-%d" % [style,"flipped" if flip else "normal",dimensions.x])
	await resize(Vector2i(360,760)); app.set_appearance("minimal")
	for language in ["en","ja"]:
		app.set_preference("language",language); candidates(); await settle(); await RenderingServer.frame_post_draw
		check(app.ui.pv_rows[1].hint_label.text=="1 "+app.t("升变") and app.ui.pv_rows[2].hint_label.text=="2 "+app.t("不升变"), "translated pinned promotion choice")
		for row in app.ui.pv_rows.values(): check(row.scroll.size.x >= 30 and row.get_global_rect().end.x <= app.safe_rect().end.x, "translated hints fit narrow layout")
		app.ui.analysis_scroll.ensure_control_visible(app.ui.pv_rows[2]); await settle()
		check(app.ui.analysis_scroll.get_global_rect().encloses(app.ui.pv_rows[2].hint_label.get_global_rect()), "translated second candidate can be fully scrolled into view")
		await capture("hint-"+language)
	app.set_preference("language","zh"); candidates(); await settle()
	app.ui.pv_rows[1].eye_button.name = "HideFirstHint"; await press("HideFirstHint"); await settle(); await RenderingServer.frame_post_draw
	check(app.board_view.hint_badges.size()==1 and app.board_view.hint_badges[0].line==2 and app.board_view.hint_badges[0].color==Hint.color(2), "hiding first arrow keeps second number and color")
	app.ui.toggle_live(); await settle(); await RenderingServer.frame_post_draw
	check(app.board_view.hint_badges.is_empty(), "pausing analysis removes promotion overlays")
	candidates("1i1h"); await settle(); await RenderingServer.frame_post_draw
	check(not app.ui.pv_rows[1].hint_label.visible and app.board_view.hint_badges.size()==1, "ordinary first move clears stale promotion marker")
	app.ui.receive_info({"multipv":1,"pv":["1i1h","9a9b","5c5b"]})
	check(app.ui.pv_rows[1].move_label.text.contains("歩不成") and not app.ui.pv_rows[1].hint_label.visible, "later declined promotion is identified without mislabeling first move")
	candidates(); app.ui.pv_rows[1].play_button.name = "PlayPromotionHint"; await press("PlayPromotionHint")
	app.ui.autoplay_on = false; app.ui.show_history(1)
	check(await until(func(): return app.motion_progress==1,4), "promotion preview finishes moving")
	check(app._display_position().board[app.Codec.parse_square("5b")]==9, "preview executes promoted pawn rather than unpromoted alternative")
	app.ui.stop_pv(false); app.ui.live_enabled=false; app._pause_search()
	preserve("promotion hints and preview")
	for promote in [true,false]:
		await fixture(SFEN,"1i1h","5c5b+" if promote else "5c5b")
		await press("PracticeHint"); await settle(); await RenderingServer.frame_post_draw
		check(app.board_view.hint_badges.is_empty(), "partial hint does not reveal full promotion answer")
		await press("PracticeHint"); await settle(); await RenderingServer.frame_post_draw
		check(practice.message.contains("升变" if promote else "不升变"), "full practice hint names promotion choice")
		check(app.board_view.hint_badges.size()==1 and app.board_view.hint_badges[0].choice==("升变" if promote else "不升变"), "practice arrow and text agree")
		await capture("practice-promote" if promote else "practice-keep")
		practice.stop(false)
	await finish()
