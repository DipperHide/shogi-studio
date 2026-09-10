extends "res://tests/chessis13_test.gd"
const Insight=preload("res://scripts/shogi_accuracy_insight.gd")

func tap_ribbon(kind: String, side: int) -> void:
	app.ui.show_report()
	await settle()
	for hit in app.ui.report_phases.targets:
		if hit.side==side and hit.get("kind","phase")==kind:
			app.ui.page_scroll.ensure_control_visible(hit.button)
			await settle()
			await tap(hit.button.get_global_rect().get_center())
			return
	check(false,"ribbon target exists "+kind)

func drag_chart(chart, from: Vector2, to: Vector2) -> void:
	var pressed=InputEventScreenTouch.new()
	pressed.index=0; pressed.position=from; pressed.pressed=true
	Input.parse_input_event(pressed); Input.flush_buffered_events()
	await settle(0.02)
	var previous=from
	for i in range(1,7):
		var point=from.lerp(to,i/6.0)
		var event=InputEventScreenDrag.new()
		event.index=0; event.position=point; event.relative=point-previous
		Input.parse_input_event(event); Input.flush_buffered_events()
		previous=point
		await settle(0.02)
	var released=InputEventScreenTouch.new()
	released.index=0; released.position=to; released.pressed=false
	Input.parse_input_event(released); Input.flush_buffered_events()
	await settle()

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event=InputEventKey.new()
		event.keycode=code; event.pressed=pressed
		Input.parse_input_event(event); Input.flush_buffered_events()
		await settle(0.02)

func run(instance) -> void:
	app=instance
	output=ProjectSettings.globalize_path("res://../review/app/chessis17/ui")
	if "--chessis21-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis21/chessis17_test")
	if "--chessis18-regression" in OS.get_cmdline_user_args(): output=ProjectSettings.globalize_path("res://../review/app/chessis18/accuracy-ui")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root=output.path_join("records")
	app.ui.tutorial.progress_path=output.path_join("learning-test.json")
	app.get_tree().create_timer(190).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local",1,2,"basic")
	app.ui.close()
	app.set_appearance("anime2d")
	await play("9g9f")
	live=app.game
	saved_live=live.to_data().duplicate(true)
	report=app.ui.report
	practice=app.ui.practice
	var historic=preload("res://scripts/shogi_historic_games.gd").new()
	var source=historic.game_for(historic.entries()[0])
	report.start(source,false,{"quick_mode":"depth","quick_depth":3},{"threads":2,"hash":32})
	check(await until(func():return report.rows.size()>=12 or not report.running,20),"historical report produces partial real evidence")
	report.cancel()
	var prefix=report.samples.duplicate(true)
	app.ui.show_accuracy_insight(1)
	await capture("partial-accuracy")
	check(app.ui.report_accuracy_view.model.points.all(func(p):return p.ply<=report.rows.size()),"partial chart never shows future or placeholder points")
	app.ui.back()
	report.resume()
	check(await until(func():return not report.running,100),"actual 140-ply engine analysis and verification complete")
	check(report.error.is_empty() and report.samples.size()==source.positions.size(),"all insight points have actual before and after positions")
	check(report.samples.slice(0,prefix.size())==prefix,"report resume preserves exact measured prefix")
	var saved_report=report.game.to_data().duplicate(true)
	var models={"sente":Insight.build(report,1),"gote":Insight.build(report,-1)}
	FileAccess.open(output.path_join("actual-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"source":saved_report,"samples":report.samples,"rows":report.rows,"insights":models},"  "))
	for mode in ["dark","light"]:
		app.set_preference("color_mode",mode)
		for side in [1,-1]:
			for dimensions in [Vector2i(360,760),Vector2i(393,852),Vector2i(852,393),Vector2i(1100,800)]:
				await resize(dimensions)
				app.ui.show_accuracy_insight(side)
				await settle()
				var view=app.ui.report_accuracy_view
				check(app.safe_rect().encloses(app.ui.page.get_global_rect()) and app.ui.page.size.x<=440.1,"reference accuracy dialog fits device and 440px cap")
				check(view.model.points.size()==report.summary(side).evaluated,"chart includes exactly scored moves for selected player")
				check(view.find_child("AccuracyInsightValue",true,false).text==app.ui.accuracy_text(report.summary(side)),"hero matches main report accuracy")
				check(view.chart.size.y==144 and view.chart.size.x>=44+13*view.model.points.size(),"long chart preserves original spacing and height")
				check(view.selection.get_child_count()==0,"opening accuracy chart does not invent a selected card")
				await capture("accuracy-"+mode+"-"+str(side)+"-%dx%d"%[dimensions.x,dimensions.y])
	await resize(Vector2i(393,852))
	app.set_preference("color_mode","dark")
	app.ui.report_selected_ply=14
	await tap_ribbon("accuracy",-1)
	check(app.ui.page_name=="report-accuracy" and app.ui.report_accuracy_view.model.side==-1,"actual gote accuracy chip opens accuracy insight")
	var view=app.ui.report_accuracy_view
	app.ui.page_scroll.ensure_control_visible(view.chart_scroll)
	await settle()
	await tap(view.chart.global_position+view.chart.point_for(0))
	var point=view.model.points[0]
	check(view.chart.active_ply==point.ply and view.selection.get_child_count()==1,"chart touch selects the original shogi ply")
	check(view.find_child("AccuracyMoveScore",true,false).text=="本手准确率："+Insight.accuracy_label(point),"selected score uses same actual per-move data")
	check(view.find_child("AccuracyMoveEngine",true,false).text==Insight.engine_label(point),"selected evaluation uses correct adjacent positions")
	await capture("selected-accuracy-move")
	var selected=view.chart.active_ply
	app.ui.page_scroll.ensure_control_visible(view.chart_scroll)
	await settle()
	var rect=view.chart_scroll.get_global_rect()
	await drag_chart(view.chart,rect.position+Vector2(rect.size.x-20,60),rect.position+Vector2(40,60))
	check(view.chart_scroll.scroll_horizontal>0,"actual touch drag scrolls long accuracy chart")
	check(view.chart.active_ply==selected,"dragging does not select an unrelated point")
	view.chart.grab_focus()
	await key(KEY_END)
	check(view.chart.active_ply==view.model.points.back().ply and view.chart_scroll.scroll_horizontal>0,"keyboard End selects and reveals final actual move")
	await capture("scrolled-accuracy")
	point=view.model.points.back()
	await press("OpenAccuracyMoveBoard")
	check(app.ui.page==null and app.review_game==report.game and app.replay_index==point.ply,"selected insight card opens exact report board position")
	check(app.ui.report_board_active and app.ui.live_key==report.game.positions[point.ply].key(),"insight handoff uses saved analysis for same board root")
	await capture("accuracy-to-board")
	await tap_ribbon("phase",1)
	check(app.ui.page_name=="report-phase" and app.ui.page.size.x<=440.1,"phase bar keeps separate bounded phase dialog")
	await capture("bounded-phase-detail")
	app.ui.back()
	check(app.ui.report_selected_ply==point.ply and app.ui.page_name=="report","return from phase preserves report selection")
	app.ui.set_extra("report_cpl",true)
	await tap_ribbon("acpl",1)
	check(app.ui.page_name=="report-metric-info","ACPL has independent explanatory target")
	await capture("acpl-info")
	app.ui.back()
	app.ui.page_scroll.ensure_control_visible(app.ui.report_phases)
	await capture("separate-summary-chips")
	app.ui.close()
	preserve("all accuracy and phase actions")
	check(report.game.to_data()==saved_report,"accuracy navigation leaves analyzed historical game unchanged")
	# Actual short opening contains only book moves, so no scored points exist.
	var short_game=app.Game.new()
	short_game.play(app.Codec.parse_move("7g7f",short_game.position))
	report.start(short_game,false,{"quick_mode":"depth","quick_depth":3})
	check(await until(func():return not report.running,10),"real opening-only report completes")
	app.ui.show_accuracy_insight(1)
	check(app.ui.report_accuracy_view.model.points.is_empty() and app.ui.page.find_child("AccuracyChartEmpty",true,false)!=null,"opening-only game shows honest empty chart")
	check(app.ui.page.find_child("AccuracyInsightValue",true,false).text=="—","unscored player is not shown as perfect")
	await capture("empty-accuracy")
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"screenshots":screenshots},"  "))
	print("CHESSIS 17 UI: ",checks," checks; ",failures)
	app.get_tree().quit(0 if failures.is_empty() else 1)
