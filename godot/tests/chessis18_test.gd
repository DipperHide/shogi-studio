extends "res://tests/chessis13_test.gd"
const PhaseView=preload("res://scripts/shogi_phase_accuracy_view.gd")

func phase_view(): return app.ui.page.find_child("PhaseAccuracyView",true,false)

func verify_cards(side: int) -> void:
	var view=phase_view()
	var model=view.model
	check(model.phases.size()==view.find_child("PhaseCards",true,false).get_child_count(),"each analyzed player phase has one card")
	var count=0
	for entry in model.phases:
		var card=view.find_child("Phase"+str(entry.type),true,false)
		count+=entry.stats.count
		var expected={}
		var segment=report.phases().filter(func(p):return p.type==entry.type)[0]
		for row in report.rows:
			if row.side==side and row.ply>=segment.start and row.ply<=segment.end and row.category in PhaseView.BAD:
				expected[row.category]=int(expected.get(row.category,0))+1
		check(entry.errors.size()==expected.size(),"phase exposes only positive actual error categories")
		check(card.find_child("PhaseTitle"+str(entry.type),true,false).text=="%s（%d 手）"%[entry.name,entry.stats.count],"phase title uses this player's actual hands")
		var chips=card.find_child("PhaseErrors"+str(entry.type),true,false)
		if entry.stats.has_accuracy:
			if expected.is_empty():
				check(chips.get_child_count()==1 and chips.get_child(0).name=="PhaseErrorClean","scored clean phase has one green check state")
			else:
				var names=[]
				for category in PhaseView.BAD:
					if expected.has(category): names.append("PhaseError"+category)
				check(chips.get_children().map(func(c):return str(c.name))==names,"error chips follow missed win, blunder, mistake, inaccuracy order")
				for error in entry.errors: check(error.count==expected[error.category],"error pill retains actual count")
		else: check(chips==null,"unscored phase has no invented clean or error summary")
		var score=card.find_child("PhaseScore"+str(entry.type),true,false)
		check(score.size.y<35 and score.get_theme_stylebox("normal").content_margin_left==10,"score is a compact filled pill")
		check(card.find_children("*","BaseButton",true,false).is_empty(),"reference phase card is read-only")
	check(count==report.summary(side).count,"visible cards reconcile with player analyzed hand total")

func analyze(source) -> void:
	report.start(source,false,{"quick_mode":"depth","quick_depth":3},{"threads":2,"hash":32})
	check(await until(func():return not report.running,15),"real short analysis completes")
	check(report.error.is_empty() and report.rows.size()==source.moves.size(),"short phase state has real complete engine evidence")

func run(instance) -> void:
	app=instance
	output=ProjectSettings.globalize_path("res://../review/app/chessis18/ui")
	if "--chessis21-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis21/chessis18_test")
	if "--chessis19-regression" in OS.get_cmdline_user_args(): output=ProjectSettings.globalize_path("res://../review/app/chessis19/phase-ui")
	if "--chessis20-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis20/chessis18_test")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root=output.path_join("records")
	app.ui.tutorial.progress_path=output.path_join("learning-test.json")
	app.get_tree().create_timer(190).timeout.connect(func():app.get_tree().quit(2))
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
	check(await until(func():return report.rows.size()>=8 or not report.running,20),"historic analysis supplies real partial evidence")
	report.cancel()
	var prefix=report.samples.duplicate(true)
	await resize(Vector2i(393,852))
	app.ui.show_phase_accuracy(1)
	await capture("partial-phase")
	check(phase_view().model.phases.size()==1 and app.ui.page.find_child("Phase3",true,false)==null,"future middle and endgame are omitted from partial phase popup")
	check(phase_view().model.phases[0].stats.count==report.summary(1).count,"partial phase includes only already analyzed player hands")
	app.ui.back()
	report.resume()
	check(await until(func():return not report.running,100),"full historical report finishes")
	check(report.error.is_empty() and report.samples.size()==141,"all 140 historical hands have actual before and after evaluations")
	check(report.samples.slice(0,prefix.size())==prefix,"resume keeps all earlier measured samples")
	var saved_report=report.game.to_data().duplicate(true)
	var models={"sente":PhaseView.snapshot(report,1),"gote":PhaseView.snapshot(report,-1)}
	FileAccess.open(output.path_join("actual-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"source":saved_report,"samples":report.samples,"rows":report.rows,"segments":report.phases(),"phases":models},"  "))
	for mode in ["dark","light"]:
		app.set_preference("color_mode",mode)
		for side in [1,-1]:
			for dimensions in [Vector2i(360,760),Vector2i(393,852),Vector2i(852,393),Vector2i(1100,800)]:
				await resize(dimensions)
				app.ui.show_phase_accuracy(side)
				await settle()
				check(app.safe_rect().encloses(app.ui.page.get_global_rect()) and app.ui.page.size.x<=440.1,"compact phase dialog fits safe screen and reference width cap")
				var view=phase_view()
				check(view.model.phases.size()==3,"complete historical game displays all three player phases")
				check(view.find_child("PhasePlayerName",true,false).get_line_count()==1,"actual player name remains one line")
				if dimensions.y>dimensions.x:
					check(app.ui.page.size.y<460 and app.ui.page_scroll.get_global_rect().encloses(view.get_global_rect()),"all compact phase cards fit without portrait scrolling")
				verify_cards(side)
				await capture("phase-"+mode+"-"+str(side)+"-%dx%d"%[dimensions.x,dimensions.y])
	await resize(Vector2i(393,852))
	app.set_preference("color_mode","dark")
	app.ui.report_selected_ply=14
	app.ui.show_report()
	app.ui.page_scroll.ensure_control_visible(app.ui.report_phases)
	await settle()
	var target=app.ui.report_phases.hits.filter(func(h):return h.side==-1 and h.get("kind","phase")=="phase")[0]
	await tap(app.ui.report_phases.global_position+target.rect.get_center())
	check(app.ui.page_name=="report-phase" and phase_view().model.side==-1,"actual gote phase ribbon touch opens the gote dialog")
	await capture("phase-from-ribbon")
	app.ui.back()
	check(app.ui.page_name=="report" and app.ui.report_selected_ply==14,"closing read-only phase popup preserves selected report ply")
	app.ui.open_report_position(14)
	await until(func():return app.motion_progress>=1)
	app.ui.show_history(15)
	await settle(0.06)
	check(app.motion_progress>0 and app.motion_progress<1,"report replay still moves through intermediate animation frames")
	await settle(0.5)
	check(app.replay_index==15 and app._display_position().key()==report.game.positions[15].key(),"report board lands on exact next analyzed position")
	preserve("phase exploration and replay")
	check(report.game.to_data()==saved_report,"phase exploration preserves historical source")
	# Real opening-only report: actual book label, no perfect numeric score.
	var short_game=app.Game.new()
	short_game.play(app.Codec.parse_move("7g7f",short_game.position))
	await analyze(short_game)
	app.ui.show_phase_accuracy(1)
	await capture("book-phase")
	check(phase_view().model.phases.size()==1 and phase_view().find_child("PhaseScore1",true,false).text=="定式","genuine book-only phase displays book pill")
	check(phase_view().find_child("PhaseOverallScore",true,false).text=="—" and phase_view().find_child("PhaseErrors1",true,false)==null,"book-only overall has no invented score or no-mistakes claim")
	app.ui.show_phase_accuracy(-1)
	await capture("empty-player")
	check(phase_view().model.phases.is_empty() and phase_view().find_child("PhaseEmpty",true,false)!=null,"player with no analyzed hands receives explicit empty state")
	# King on 1i can only escape to 1h; bishop checks and rook seals 2h/2i.
	var forced=app.Game.new()
	check(forced.set_initial("k6r1/9/9/9/9/9/6b2/9/8K b - 1"),"forced legal fixture loads")
	check(forced.position.legal_moves().size()==1,"forced fixture has exactly one legal move")
	forced.play(app.Codec.parse_move("1i1h",forced.position))
	await analyze(forced)
	app.ui.show_phase_accuracy(1)
	await capture("forced-phase")
	var phase=phase_view().model.phases[0]
	check(phase.stats.forced==1 and not phase.stats.has_accuracy,"actual forced move contributes no scored weight")
	check(phase_view().find_child("PhaseScore"+str(phase.type),true,false).text=="—","forced-only phase is not mislabeled as book or perfect")
	check(phase_view().find_child("PhaseErrors"+str(phase.type),true,false)==null,"forced-only phase does not falsely claim no mistakes")
	FileAccess.open(output.path_join("forced-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"source":forced.to_data(),"samples":report.samples,"rows":report.rows,"phase":phase},"  "))
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"screenshots":screenshots},"  "))
	print("CHESSIS 18 UI: ",checks," checks; ",failures)
	app.get_tree().quit(0 if failures.is_empty() else 1)
