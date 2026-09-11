extends "res://tests/chessis23_test.gd"
const Data = preload("res://scripts/shogi_openings.gd")
var opening
var preview
var original_review
var original_data: Dictionary
var frames = []

func preserve_opening(label: String) -> void:
	preserve(label)
	check(app.review_game == original_review and app.replay_index == 2 and app.review_path == "original-record", label + " preserves original replay object, path and cursor")
	check(original_review.to_data() == original_data, label + " preserves original annotations and metadata")

func shown_motion(target: int, label: String) -> void:
	preview.seek(target)
	var values = []
	var deadline = Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		values.append(preview.board.motion)
		if preview.board.motion == 1: break
	check(values.size() > 2 and values[0] == 0 and values[-1] == 1, label + " draws the start, middle and end")
	check(values.any(func(value): return value > 0 and value < 1), label + " has real intermediate frames")
	frames.append({"scenario": label, "values": values})

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis29/ui")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records"); app.save_path = output.path_join("active-test.json")
	app.ui.tutorial.progress_path = output.path_join("learning-test.json")
	app.get_tree().create_timer(180).timeout.connect(func(): app.get_tree().quit(2))
	# Input events are window pixels: equalize native and logical sizes first.
	await resize(Vector2i(393, 852))
	app._start_match("local", 1, 2, "basic"); app.ui.close()
	await play("7g7f"); await play("3c3d")
	practice = app.ui.practice
	live = app.game; saved_live = live.to_data().duplicate(true)
	original_review = Data.game_for(Data.catalog()[8])
	original_review.metadata["先手"] = "保留棋手"; original_review.comments["2"] = "保留注释"
	original_data = original_review.to_data().duplicate(true)
	app.review_game = original_review; app.replay_index = 2; app.review_path = "original-record"; app._refresh()
	app.ui.show_openings(""); opening = app.ui.opening_view
	check(opening.visible_entries.size() == 7, "initial list has seven opening examples")
	await press("OpeningSide-1")
	check(opening.visible_entries.size() == 3, "native side filter contains both-side examples")
	await press("OpeningTab1")
	check(opening.visible_entries.is_empty(), "native castle plus gote filter has honest empty state")
	await press("OpeningSide0")
	check(opening.visible_entries.size() == 2, "castle tab contains two actual lines")
	await press("OpeningTab0")
	opening.search_field.grab_focus()
	for character in "三間飛車":
		var event = InputEventKey.new(); event.pressed = true; event.unicode = character.unicode_at(0)
		Input.parse_input_event(event); Input.flush_buffered_events()
		await app.get_tree().process_frame
	await settle()
	check(opening.visible_entries.size() == 1 and opening.visible_entries[0].id == 4, "search updates on editing without recreating focused field")
	await press("OpeningEntry4"); preview = opening.preview
	check(app.ui.page_name == "opening-info" and preview.ply == 5, "entry opens its own mini board at final position like reference")
	preserve_opening("opening preview")
	await press("OpeningPrevious")
	check(preview.ply == 4, "native previous move selects exactly one earlier position")
	check(await until(func(): return preview.board.motion == 1, 4), "previous animation finishes naturally")
	await shown_motion(0, "start-jump")
	await shown_motion(3, "multi-ply-forward")
	var before_flip = preview.board.square_rect(0)
	await press("OpeningFlip")
	check(preview.board.flipped and preview.board.square_rect(80) == before_flip, "native flip reverses coordinates")
	for mode in ["dark", "light"]:
		app.set_preference("color_mode", mode)
		for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393), Vector2i(1100, 800)]:
			await resize(dimensions); await settle()
			check(preview.board.board_rect.size.x == preview.board.board_rect.size.y, "square preview " + str(dimensions))
			check(preview.board.board_rect.end.x <= preview.board.size.x and preview.board.board_rect.position.x >= 0, "board fits its width " + str(dimensions))
			var footer = app.ui.page.find_child("OpeningFooter", true, false)
			check(app.safe_rect().encloses(footer.get_global_rect()), "load button remains visible " + str(dimensions))
			if dimensions.x < dimensions.y: check(not footer.get_global_rect().intersects(app.ui.page_scroll.get_global_rect()), "portrait load footer outside scroll")
			else: check(app.ui.page_scroll.get_global_rect().encloses(preview.board.get_global_rect()), "landscape shows the entire mini board without scrolling")
			check(preview.details.get_child(0).get_theme_color("font_color").get_luminance() > 0.8, "readable wood text in " + mode)
			await press("OpeningFlip")
			check(preview.board.flipped == false, "native flip works in each layout")
			await press("OpeningFlip")
			check(preview.board.flipped, "native flip restores orientation in each layout")
			await capture("opening-preview-%s-%d" % [mode, dimensions.x])
	await resize(Vector2i(393, 852)); app.set_preference("color_mode", "dark")
	app.ui.page_scroll.scroll_vertical = 0
	await press("OpeningClose")
	check(opening.query == "三間飛車" and opening.visible_entries.size() == 1, "close detail restores exact filtered list")
	check(not is_instance_valid(preview), "closing frees mini board and animation owner")
	preserve_opening("closing detail")
	await press("OpeningClear")
	for mode in ["dark", "light"]:
		app.set_preference("color_mode", mode)
		for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393), Vector2i(1100, 800)]:
			await resize(dimensions); await settle()
			check(app.safe_rect().encloses(app.ui.page.get_global_rect()), "list fits safe area " + str(dimensions))
			check(app.safe_rect().encloses(opening.search_field.get_global_rect()), "search stays visible " + str(dimensions))
			for item in opening.list.get_children():
				check(item.size.x <= opening.list.size.x and item.get_child(0).get_combined_minimum_size().y + 20 <= item.size.y + 1, "wrapped list item fits " + str(item.name))
			await capture("opening-list-%s-%d" % [mode, dimensions.x])
	await resize(Vector2i(393, 852)); app.set_preference("color_mode", "dark")
	await press("OpeningEntry6")
	var list_scroll: int = opening.scroll
	check(list_scroll > 0, "opening a lower row saves list scroll")
	await press("OpeningClose")
	await settle()
	check(app.ui.page_scroll.scroll_vertical == list_scroll, "return restores the scrolled list")
	await press("OpeningEntry0"); preview = opening.preview
	await press("OpeningPlay")
	check(preview.playing and preview.ply == 0, "play restarts final example from its beginning")
	check(await until(func(): return preview.ply > 0, 4), "autoplay advances after visible hold")
	await press("OpeningPlay")
	check(not preview.playing, "pause stops scheduling moves")
	var paused_ply: int = preview.ply
	await settle(1.0)
	check(preview.ply == paused_ply, "paused cursor stays stable")
	await press("OpeningPlay")
	check(await until(func(): return not preview.playing and preview.ply == 2 and preview.board.motion == 1, 6), "autoplay finishes after the final animation")
	var next_button = preview.next
	preview.seek(0); await until(func(): return preview.board.motion == 1, 4)
	await settle()
	app.ui.page_scroll.ensure_control_visible(next_button); await settle()
	var hold = InputEventScreenTouch.new(); hold.index = 0; hold.pressed = true; hold.position = next_button.get_global_rect().get_center()
	Input.parse_input_event(hold); Input.flush_buffered_events()
	await settle(0.6)
	check(preview.ply == 2, "native long press jumps to last move")
	hold = InputEventScreenTouch.new(); hold.index = 0; hold.pressed = false; hold.position = next_button.get_global_rect().get_center()
	Input.parse_input_event(hold); Input.flush_buffered_events(); await settle()
	check(preview.ply == 2, "long press release does not add a second navigation action")
	preview.seek(0)
	await RenderingServer.frame_post_draw
	var before = []
	for i in range(preview.board.tokens.size()): before.append(preview.board.visual_rect(i))
	preview.seek(2)
	for i in range(before.size()): check(before[i] == preview.board.visual_rect(i), "rapid seek starts from rendered piece " + str(i))
	app.preferences.studio.animation = 0
	preview.seek(1)
	check(preview.board.motion == 1, "animation-off preference is honored")
	app.preferences.studio.animation = 0.25
	await press("OpeningLoad")
	check(app.ui.page == null and app.replay_index == 1 and app.review_game.moves.size() == 2 and app.review_path == "", "explicit load keeps full line at selected move")
	preserve("load opening")
	check(app.ui.continue_button.visible, "loaded opening offers continue-from-here")
	app.ui.show_openings("")
	await press("OpeningEntry1"); preview = opening.preview
	preview.toggle_play()
	app.ui.back(); app.ui.back(); await settle(1)
	check(not is_instance_valid(preview) and app.ui.page == null and app.replay_index == 1, "dismiss while playing frees callbacks and keeps main-board cursor")
	# A pending hold belongs to its page, and must disappear on dismissal.
	app.ui.show_openings(""); opening.show_info(Data.catalog()[8]); preview = opening.preview
	app.ui.page_scroll.ensure_control_visible(preview.previous); await settle()
	hold = InputEventScreenTouch.new(); hold.index = 0; hold.pressed = true; hold.position = preview.previous.get_global_rect().get_center()
	Input.parse_input_event(hold); Input.flush_buffered_events()
	app.ui.back(); await settle(0.7)
	hold = InputEventScreenTouch.new(); hold.index = 0; hold.pressed = false
	Input.parse_input_event(hold); Input.flush_buffered_events()
	check(not is_instance_valid(preview), "closing during a pending long press frees its owned timer")
	# Same mini board can safely replay captures, promotion and drops.
	opening.show_info({"name": "合法动画测试夹具", "description": "测试", "group": "测试", "side": 0, "moves": "7g7f 3c3d 8h2b+ 3a2b B*4e"})
	preview = opening.preview
	await shown_motion(2, "capture-promotion-reverse")
	await shown_motion(3, "capture-promotion-forward")
	await shown_motion(4, "promoted-piece-captured")
	await shown_motion(5, "hand-drop")
	check(preview.board.tokens.size() == 40 and preview.game.positions[5].hands[-1][6] == 1, "capture and drop retain all physical pieces and opponent hand")
	await capture("opening-capture-fixture")
	app.ui.back(); app.ui.back()
	FileAccess.open(output.path_join("motion-frames.json"), FileAccess.WRITE).store_string(JSON.stringify(frames, "  "))
	await finish()
