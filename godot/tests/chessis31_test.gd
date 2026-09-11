extends "res://tests/chessis23_test.gd"
const Historic = preload("res://scripts/shogi_historic_games.gd")
var archive
var motions = {}
var loaded_count = 0

class DelayedSync extends "res://scripts/shogi_tournament_sync.gd":
	signal replied(response: Dictionary)
	var requests = []
	func _request(url: String, _limit: int) -> Dictionary:
		requests.append(url)
		return await replied

func sheet_ready() -> void:
	check(await until(func(): return archive.reveal >= 1, 4), "filter sheet finishes visible slide")
	await settle()

func list_ready() -> void:
	var ready = await until(func(): return app.ui.page_name == "tournament-archive", 4)
	check(ready, "filter closes back to archive")
	if not ready:
		var trace = {"page":app.ui.page_name,"closing":archive.closing,"reveal":archive.reveal,"size":str(app.size),"window":str(app.get_window().size),"mode":app.get_window().mode}
		if is_instance_valid(archive.sheet_motion):
			trace.merge({"active":archive.sheet_motion.active,"visible":archive.sheet_motion.visible(),"suspended":archive.sheet_motion.suspended,"clock":str([archive.sheet_motion.clock.presented,archive.sheet_motion.clock.consumed,archive.sheet_motion.clock.last_tick]),"tween_valid":archive.sheet_motion.native.is_valid()})
		print("SHEET FAILURE: ", JSON.stringify(trace))
		FileAccess.open(output.path_join("sheet-failure.json"),FileAccess.WRITE).store_string(JSON.stringify(trace,"  "))
		await capture("sheet-failure")
		await finish()
	await settle()

func type_query(value: String) -> void:
	archive.filter_search.grab_focus()
	for character in value:
		var event = InputEventKey.new(); event.pressed = true; event.unicode = character.unicode_at(0)
		Input.parse_input_event(event); Input.flush_buffered_events()
	await settle()

func run(instance) -> void:
	app = instance; output = ProjectSettings.globalize_path("res://../review/app/chessis31/ui")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records"); app.save_path = output.path_join("active.json"); app.ui.tutorial.progress_path = output.path_join("learning.json")
	app.get_tree().create_timer(240).timeout.connect(func(): app.get_tree().quit(2))
	await resize(Vector2i(393,852))
	app._start_match("local",1,2,"basic"); app.ui.close(); await play("7g7f")
	live = app.game; saved_live = live.to_data().duplicate(true); practice = app.ui.practice
	app.ui.show_historic_games(); archive = app.ui.tournament_view
	check(app.ui.historic_recent and archive.rows.size() == 26, "recent official catalog opens from drawer entry")
	check(app.ui.page_name == "tournament-archive" and app.ui.page.find_child("HistoricSearch",true,false) == null, "archive uses separate filter instead of inline form")
	await press("OfflineTournaments")
	check(archive.rows.size() == 195, "all offline games remain available")
	if "--sheet-stress" in OS.get_cmdline_user_args():
		await resize(Vector2i(1100,800))
		for iteration in range(24):
			app.set_preference("color_mode","dark" if iteration%2==0 else "light")
			await press("HistoricFilter"); await sheet_ready()
			var observed = [0]
			app.ui.page.find_child("HistoricFilterClose",true,false).pressed.connect(func(): observed[0]+=1)
			await press("HistoricFilterClose")
			print("SHEET TAP ",iteration," signal=",observed[0]," closing=",archive.closing," reveal=",archive.reveal)
			await list_ready()
		await finish(); return
	for mode in ["dark","light"]:
		app.set_preference("color_mode",mode)
		for dimensions in [Vector2i(360,760),Vector2i(393,852),Vector2i(852,393),Vector2i(1100,800)]:
			await resize(dimensions); await settle()
			check(app.ui.page.get_global_rect() == app.safe_rect(), "full archive fills safe area " + mode + str(dimensions))
			var header = app.ui.page.get_child(0).get_child(0)
			var heading = header.find_child("HistoricTitle",true,false)
			check(header.size.y == 44 and heading.size.x >= 80 and heading.get_line_count() == 1, "archive title remains one line beside compact filter and close")
			var row = app.ui.page.find_child("HistoricGame_" + archive.rows[0].id,true,false)
			check(row.size.x <= app.safe_rect().size.x and row.get_theme_stylebox("panel").content_margin_left == 0, "compact row stays within width")
			var title = row.find_children("*","Label",true,false)[0]
			check(title.get_theme_color("font_color") == Color("f8f1e6") and title.get_theme_font_size("font_size") == 16, "wood list keeps readable 16px title in both themes")
			await capture("archive-%s-%d" % [mode,dimensions.x])
			await press("HistoricFilter"); await sheet_ready()
			check(app.safe_rect().encloses(app.ui.page.get_global_rect()) and absf(app.ui.page.get_global_rect().end.y-app.safe_rect().end.y)<1, "filter anchors at bottom within safe area")
			check(app.ui.page.find_child("HistoricFilterApply",true,false).get_global_rect().end.y <= app.safe_rect().end.y, "filter apply stays visible without scrolling")
			check(app.ui.page.find_child("HistoricFilterApply",true,false).text == "显示结果" and app.ui.page.find_child("HistoricFilterReset",true,false).text == "重置筛选", "filter footer retains text beside its icons")
			check(app.ui.page.find_child("HistoricEvents",true,false).get_children().size() == 5, "event checkboxes derive from offline catalog")
			var icon = app.ui.page.find_child("HistoricEvent_棋圣战",true,false).get_theme_icon("unchecked").get_image()
			check(icon.get_size()==Vector2i(18,18) and icon.get_pixel(1,9).get_luminance()>0.1, "unchecked event outline stays visible on both themes")
			await capture("archive-filter-%s-%d" % [mode,dimensions.x])
			await press("HistoricFilterClose"); await list_ready()
	if "--sheet-only" in OS.get_cmdline_user_args(): await finish(); return
	await resize(Vector2i(393,852)); app.set_preference("color_mode","dark")
	await press("HistoricMore")
	check(archive.state().limit == 40 and app.ui.historic_list.find_children("HistoricGame_*","PanelContainer",false,false).size() == 40, "load more appends another twenty games")
	app.ui.page_scroll.scroll_vertical = 320; await settle()
	var position = app.ui.page_scroll.scroll_vertical
	await press("HistoricFilter"); await sheet_ready(); await type_query("不存在")
	await press("HistoricFilterClose"); await list_ready()
	check(archive.rows.size() == 195 and archive.state().query.is_empty() and app.ui.page_scroll.scroll_vertical == position, "cancel discards draft and restores list position")
	await press("HistoricFilter"); await sheet_ready()
	await press("HistoricEvent_棋圣战"); await press("HistoricEvent_王位战"); await press("HistoricFilterApply"); await list_ready()
	var expected = Historic.search("","棋圣战").size()+Historic.search("","王位战").size()
	check(archive.rows.size() == expected and archive.state().events.size() == 2 and archive.state().limit == 20, "applied event choices combine with OR and restart result window")
	await press("HistoricFilter"); await sheet_ready(); await type_query("不存在")
	await press("HistoricFilterApply"); await list_ready()
	check(archive.rows.is_empty() and app.ui.historic_count.text.begins_with("0"), "no matches shows a real empty state")
	await capture("archive-no-matches")
	await press("HistoricFilter"); await sheet_ready(); await press("HistoricFilterReset"); await list_ready()
	check(archive.rows.size() == 195 and archive.state().events.is_empty() and archive.state().query.is_empty(), "Reset clears and applies filters like reference")
	# The complete row loads a private replay through the asynchronous validator.
	var first = archive.rows[0]
	await press("HistoricLoad_" + first.id)
	check(await until(func(): return not archive.local_busy,15), "offline validation completes")
	check(app.ui.page == null and app.review_game.moves.size() == first.plies and not app.review_game.result.is_empty(), "native row click loads complete historic record")
	preserve("historic full row")
	app.ui.show_history(10)
	var frames = []; var deadline = Time.get_ticks_msec()+4000
	while Time.get_ticks_msec()<deadline:
		await RenderingServer.frame_post_draw; frames.append(app.motion_progress)
		if app.motion_progress>=1: break
	motions.replay = frames
	check(frames[0]==0 and frames[-1]==1 and frames.any(func(value): return value>0 and value<1), "historic replay shows complete intermediate animation")
	check(app.ui.continue_button.visible, "loaded tournament offers continuation from selected move")
	var keep = app.review_game
	app.ui.show_historic_games(); await settle()
	check(archive.selected_id == first.id, "returning archive remembers selected game")
	archive.open_entry(first)
	check(archive.local_busy, "offline load begins in private worker")
	app.ui.show_openings("")
	check(await until(func(): return not archive.local_busy,15), "dismissed offline validation finishes")
	check(app.ui.page_name=="openings" and app.review_game==keep, "dismissed offline result cannot replace later page or replay")
	app.ui.show_historic_games()
	# A delayed official response may populate cache, but cannot steal a new page.
	var mock = DelayedSync.new(); app.ui.add_child(mock); mock.initialize(output.path_join("cache-"+str(Time.get_ticks_usec())),false)
	var entry = first.duplicate(true); entry.erase("kif")
	var normalized = mock.Download.normalize(first.kif.to_utf8_buffer()); entry.moves_sha256 = normalized.moves_sha256
	mock.index = {"schema":1,"updated_utc":"2026-09-11","games":[entry]}
	mock.changed.connect(archive.refresh); mock.game_resolved.connect(archive.resolved)
	mock.game_resolved.connect(func(_request,_id,_game): loaded_count+=1)
	app.ui.tournaments = mock
	await press("LatestTournaments"); await press("HistoricLoad_"+entry.id)
	check(mock.downloading and mock.download_id==entry.id and archive.pending!=0, "row exposes actual request and downloading state")
	var status = app.ui.page.find_child("HistoricState_"+entry.id,true,false)
	check(status.busy and status.is_processing() and not status.cached, "only requested row draws active progress")
	await capture("archive-downloading")
	app.ui.back(); app.ui.show_historic_games()
	mock.replied.emit({"ok":true,"body":first.kif.to_utf8_buffer()})
	check(await until(func(): return not mock.downloading,15), "closed flow download and validation finish")
	check(app.ui.page_name=="tournament-archive" and app.review_game==keep, "late reply cannot steal reopened archive or replace prior replay")
	check(loaded_count==1 and not mock.cache_data(entry).is_empty(), "completed closed download remains cached")
	status = app.ui.page.find_child("HistoricState_"+entry.id,true,false)
	check(status.cached and not status.busy, "cache marker follows validated move payload")
	var requests = mock.requests.size()
	await press("HistoricLoad_"+entry.id)
	check(await until(func(): return not mock.downloading,15), "cached record still receives full legality validation")
	check(app.ui.page==null and mock.requests.size()==requests and app.review_game.moves.size()==entry.plies, "cached row opens offline without another HTTP request")
	app.ui.show_historic_games()
	mock._save(entry.id+".json",{"kif":"corrupt"}); archive.refresh()
	status = app.ui.page.find_child("HistoricState_"+entry.id,true,false)
	check(not status.cached, "corrupted local data loses cache marker")
	await press("HistoricLoad_"+entry.id); mock.replied.emit({"ok":false,"body":PackedByteArray()})
	check(await until(func(): return not mock.downloading,8), "failed download releases pending state")
	check(app.ui.page_name=="tournament-archive" and not app.ui.page.find_child("HistoricLoad_"+entry.id,true,false).disabled, "failed download allows native retry")
	await capture("archive-download-error")
	await press("OfflineTournaments")
	check(archive.rows.size()==195, "offline library survives recent network failure")
	if "--tournament-ui-network" in OS.get_cmdline_user_args():
		var real = preload("res://scripts/shogi_tournament_sync.gd").new()
		app.ui.add_child(real); real.initialize(output.path_join("official-"+str(Time.get_ticks_usec())),false)
		real.changed.connect(archive.refresh); real.game_resolved.connect(archive.resolved); app.ui.tournaments = real
		await press("LatestTournaments")
		var latest = archive.rows[0]
		await press("HistoricLoad_"+latest.id)
		check(await until(func(): return not real.downloading,35), "real official KIF download and worker finish")
		check(app.ui.page==null and app.review_game.moves.size()==latest.plies and app.review_game.metadata["来源"]==latest.source, "real latest tournament opens with full moves and official attribution")
		check(not real.cache_data(latest).is_empty(), "real latest game has matching cached payload")
		await capture("latest-official-board")
		FileAccess.open(output.path_join("official-download.json"),FileAccess.WRITE).store_string(JSON.stringify({"id":latest.id,"source":latest.source,"plies":latest.plies,"moves_sha256":latest.moves_sha256,"cached":not real.cache_data(latest).is_empty()},"  "))
	app.ui.back(); preserve("all archive operations")
	FileAccess.open(output.path_join("motion-frames.json"),FileAccess.WRITE).store_string(JSON.stringify(motions))
	await finish()
