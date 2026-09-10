extends "res://tests/chessis13_test.gd"

func preview_phase_fixture(historic_source,kind: String) -> void:
	# Real legal moves with explicitly synthetic scores for deterministic narrative QA.
	# These screenshots are labeled fixtures and are never exported as engine evidence.
	app.ui.close()
	var source=app.Game.from_data(historic_source.to_data())
	source.moves=source.moves.slice(0,42)
	source.positions=source.positions.slice(0,43)
	source.labels=source.labels.slice(0,42)
	source.position=source.positions.back().copy()
	source.result="分支测试结果" if kind!="phase_neutral" else ""
	source.result_code="resign" if kind!="phase_neutral" else ""
	source.winner=0 if kind in ["phase_neutral","phase_draw_plain"] else 1
	source.metadata={"先手":"分支测试数据","后手":"非引擎测量"}
	report.game=source
	report.samples=[]; report.rows=[]
	for i in range(43):
		var score=0
		if kind in ["phase_win_all_slips","dominant_win_slips"] and i>= (2 if kind=="dominant_win_slips" else 42): score=201
		report.samples.append({"score":score*report.Metrics.CP_SCALE,"mate":false,"pv":[],"candidates":[],"depth":0})
	for i in range(42):
		var side=int(source.positions[i].turn)
		var category="最佳" if side==1 else "不精确"
		if kind=="phase_draw_plain" and i==41: category="失误"
		var metrics={"accuracy":100 if side==1 else 50,"cpl":0 if side==1 else 15,"wpl":0 if side==1 else 10,"before_chance":50,"after_chance":50,"book":false,"weight":1}
		report.rows.append({"ply":i+1,"side":side,"category":category,"label":source.labels[i],"metrics":metrics,"best":"","loss":0,"score":report.samples[i+1].score})
	report.index=43
	report.phase_cache_size=-1
	var story=report.story()
	check(story.summary_kind==kind and story.moments.is_empty(),"full report selects no-moment phase branch "+kind)
	for dimensions in [Vector2i(360,760),Vector2i(852,393)]:
		await resize(dimensions)
		app.ui.show_report()
		var warning=app.ui.label("分支测试数据 · 以下评分不是引擎测量",13)
		app.ui.report_story.content.add_child(warning)
		await capture("fixture-"+kind+"-%dx%d"%[dimensions.x,dimensions.y])
		check(app.ui.report_story.find_child("StoryMoments",true,false)==null,"no-moment summary never creates empty key-moment controls")
		check(app.ui.page.get_global_rect().end.x>=app.ui.report_story.get_global_rect().end.x,"long phase summary fits screen width")

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis19/ui")
	if "--chessis22-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis22/chessis19_test")
	if "--chessis21-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis21/chessis19_test")
	if "--chessis16-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis16/story-ui")
	if "--chessis20-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis20/chessis19_test")
	if "--chessis17-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis17/story-ui")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.ui.tutorial.progress_path = output.path_join("learning-test.json")
	app.get_tree().create_timer(180).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local",1,2,"basic")
	app.ui.close()
	await play("7g7f")
	live = app.game
	saved_live = live.to_data().duplicate(true)
	report = app.ui.report
	practice = app.ui.practice
	var historic = preload("res://scripts/shogi_historic_games.gd").new()
	var source = historic.game_for(historic.entries()[0])
	report.start(source,false,{"quick_mode":"depth","quick_depth":3},{"threads":2,"hash":32})
	check(await until(func(): return report.rows.size() >= 18 or not report.running,20),"historical engine report begins")
	report.cancel()
	await resize(Vector2i(393,852))
	app.ui.show_report()
	check(not report.story().complete and not report.story().closed,"partial actual report does not narrate final outcome")
	check(app.ui.report_story.model.analyzed_plies == report.rows.size(),"partial summary reflects current analyzed prefix")
	await capture("partial-story")
	var prefix = report.samples.duplicate(true)
	report.resume()
	check(await until(func(): return report.rows.size() >= prefix.size() + 4 or not report.running,20),"open report continues receiving actual engine positions")
	check(app.ui.report_story.model.analyzed_plies == report.rows.size() and not app.ui.report_story.model.closed,"visible summary updates live without borrowing the future result")
	check(await until(func(): return not report.running,105),"complete actual historical report finishes")
	check(report.error.is_empty() and report.samples.size() == source.positions.size(),"every historical position has actual engine output")
	check(report.samples.slice(0,prefix.size()) == prefix,"resuming narrative preserves previous real scores")
	app.ui.show_report()
	var model = report.story()
	check(model.complete and model.closed and model.winner == source.winner,"summary uses actual completed historical result")
	check(model.moments.size() > 1 and model.moments.size() <= 10,"real game has expandable bounded turning points")
	for moment in model.moments:
		check(moment.before == report.samples[moment.ply-1] and moment.after == report.samples[moment.ply],"moment retains exact engine before/after evidence")
	FileAccess.open(output.path_join("actual-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"source":report.game.to_data(),"samples":report.samples,"rows":report.rows,"story":model},"  "))
	for mode in ["dark","light"]:
		app.set_preference("color_mode",mode)
		for dimensions in [Vector2i(360,760),Vector2i(393,852),Vector2i(852,393),Vector2i(1100,800)]:
			await resize(dimensions)
			app.ui.show_report()
			await settle()
			check(app.ui.report_story.find_child("StoryMoments",true,false).get_child_count() == 1,"reference default shows one moment")
			var summary = app.ui.report_story.find_child("GameStorySummary",true,false)
			check(summary.get_global_rect().end.x <= app.ui.page.get_global_rect().end.x,"narrative stays inside report width")
			check(app.ui.report_story.find_children("StoryMoveTitle","Label",true,false).all(func(item): return item.get_line_count()==1),"moment move title never wraps vertically")
			check(app.ui.report_story.find_children("StoryMoveScore*","Label",true,false).size()==2,"before and after scores are visible")
			check(app.ui.report_story.find_child("StoryMoveSide",true,false).size==Vector2(12,12),"reference player side marker keeps 12px square size")
			check(app.ui.report_story.find_child("StoryMoveReason",true,false).get_parent().get_theme_constant("margin_left")==24,"moment explanation uses original inset")
			check(app.ui.report_story.find_child("ToggleStoryMoments",true,false).size_flags_horizontal==Control.SIZE_SHRINK_CENTER,"expand action centers below cards")
			check(app.ui.report_story.find_child("ToggleStoryMoments",true,false).get_theme_color("font_color")==Color("58a6ff") and app.ui.report_story.find_child("ToggleStoryMoments",true,false).get_theme_stylebox("normal") is StyleBoxEmpty,"reference expand action retains blue text without idle button fill")
			check(app.ui.report_story.find_child("StoryMomentsHelp",true,false).get_theme_color("font_color")==Color("d9cab4"),"reference key-moment caption retains secondary text color")
			await capture("story-"+mode+"-%dx%d" % [dimensions.x,dimensions.y])
	await resize(Vector2i(393,852))
	app.set_preference("color_mode","dark")
	app.ui.show_report()
	await press("ToggleStoryMoments")
	check(app.ui.report_story.find_child("StoryMoments",true,false).get_child_count()==model.moments.size(),"expand reveals every selected turning point")
	await capture("expanded-moments")
	var target: int = model.moments[-1].ply
	await press("StoryMoment%d" % target)
	check(app.ui.report_selected_ply==target and app.ui.report_chart.active==target,"actual card touch selects matching graph move")
	await capture("selected-moment")
	await press("StoryMomentsHelp")
	check(app.ui.page_name=="report-story-info" and app.safe_rect().encloses(app.ui.page.get_global_rect()),"key moments explanation opens in bounded dialog")
	await capture("key-moments-help")
	app.ui.back()
	check(app.ui.report_selected_ply==target and app.ui.report_story_expanded,"help returns to prior selection and expansion")
	await press("ToggleStoryMoments")
	check(app.ui.report_story.find_child("StoryMoments",true,false).get_child_count()==1,"collapse restores one-moment view")
	preserve("all story actions")
	for kind in ["phase_neutral","phase_win_all_slips","phase_draw_plain","dominant_win_slips"]:
		await preview_phase_fixture(source,kind)
	preserve("all phase story fixtures")
	app.ui.close()
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"screenshots":screenshots},"  "))
	print("CHESSIS 19 UI: ",checks," checks; ",failures)
	app.get_tree().quit(0 if failures.is_empty() else 1)
