extends RefCounted
var checks=0
var failures:Array=[]
var app
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func frames(count: int=3) -> void:
	for i in range(count): await app.get_tree().process_frame
func run(owner) -> void:
	app=owner
	if OS.get_name()!="Android": app.get_window().content_scale_size=app.get_window().size
	if "--chu-light" in OS.get_cmdline_user_args(): app.preferences.color_mode="light"; app.dark=false
	app.open_chu(); await frames()
	var screen=app.chu_screen
	check(screen!=null,"Chu entry")
	check(not app.coach.enabled and not app.live.enabled and not app.ui.report.running,"analysis tasks disabled")
	check(app.usi==null or app.usi.phase in ["stopped","idle","failed"],"engine stopped")
	screen.close_modal(); await frames()
	check(screen.board.board_rect.size.x>100,"board visible")
	check(app.safe_rect().encloses(screen.controls_scroll.get_global_rect()),"controls scroll area fits safe bounds")
	for square in [0,11,132,143]: check(screen.board.square_at(screen.board.center(square))==square,"corner hit "+str(square))
	var move=screen.game.position.legal_moves()[0]
	screen.choose(move.from); screen.choose(move.path[0]); screen._confirm(); await frames()
	check(screen.game.moves.size()==1,"ordinary move interaction")
	screen.show_history(0); check(screen.display_position().key()==screen.game.positions[0].key(),"reverse replay")
	screen.replay=-1
	var p=screen.Game.Rules.new(false); p.board[143]=screen.C.KING; p.board[0]=-screen.C.KING; p.board[78]=screen.C.LION; p.board[66]=-screen.C.GOLD; p.board[54]=-screen.C.SILVER; p.board[20]=-screen.C.ROOK
	screen.game=screen.Game.new(); screen.game.set_initial(p); screen._refresh(true)
	screen.choose(78); screen.choose(66)
	check(screen.game.moves.is_empty() and screen.path==[66],"first leg stays preview")
	screen.choose(54); check(screen.game.moves.is_empty() and screen.path==[66,54],"second leg stays preview")
	screen._confirm(); check(screen.game.moves.size()==1 and screen.game.position.board[66]==0 and screen.game.position.board[54]==screen.C.LION,"double capture one turn")
	screen.game.undo(); screen.clear_pending(); screen.choose(78); screen.choose(66)
	screen.board.cancel_input(); check(screen.path.is_empty() and screen.game.moves.is_empty(),"cancel input discards preview")
	screen.choose(78); screen.choose(66); screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(screen.path.is_empty() and screen.game.moves.is_empty(),"background discards preview")
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	screen.board.zoom=3; screen.board.pan=Vector2(100,100); screen.board.queue_redraw(); await frames()
	check(screen.board.zoom==3,"3x zoom")
	screen.board.reset_view(); check(screen.board.zoom==1 and screen.board.pan==Vector2.ZERO,"reset fit")
	var touch=InputEventScreenTouch.new(); touch.index=0; touch.pressed=true; touch.position=screen.board.size/2-Vector2(40,0); screen.board._gui_input(touch)
	touch=InputEventScreenTouch.new(); touch.index=1; touch.pressed=true; touch.position=screen.board.size/2+Vector2(40,0); screen.board._gui_input(touch)
	var drag=InputEventScreenDrag.new(); drag.index=1; drag.position=screen.board.size/2+Vector2(160,0); drag.relative=Vector2(120,0); screen.board._gui_input(drag)
	check(screen.board.zoom>2 and screen.path.is_empty(),"two-finger pinch cancels selection")
	touch=InputEventScreenTouch.new(); touch.index=1; touch.pressed=false; touch.canceled=true; screen.board._gui_input(touch)
	check(screen.board.touches.is_empty(),"touch cancel clears both contacts")
	screen.board.reset_view()
	screen.flipped=true; await frames(); check(screen.board.square_at(screen.board.center(0))==0,"flipped hit")
	screen.flipped=false
	var entries=[]
	for i in range(4000): entries.append({"labels":[str(i)+" 中将棋长棋谱"],"ids":[i],"study":false})
	screen.ribbon.configure(entries,3999,true); await frames(5); screen.ribbon.refresh()
	check(screen.move_strip.get_child_count()<60,"virtual history bounded")
	check(screen.move_scroll.get_h_scroll_bar().max_value>4000,"history full scroll extent")
	screen.move_scroll.scroll_horizontal=0; await frames(); screen.ribbon.refresh(); check(screen.ribbon.first==0,"history scroll to beginning")
	screen.ribbon_signature=""; screen._refresh(true)
	screen.start_editor(); screen.close_modal(); screen.edit_piece=screen.C.PAWN; screen.choose(75)
	check(screen.edit_position.board[75]==screen.C.PAWN,"position editor")
	screen.editing=false; screen.close_modal(); screen.game=screen.Game.new(); screen._refresh(true); await frames()
	screen.imported=true; screen.replay=0; screen.continue_replay()
	check(not screen.imported and screen.replay==-1,"continue imported record becomes separately saved active game")
	screen._attach_session(); screen.session.is_host=true; screen.session.local_side=1
	screen.session.offer={"action":"undo","side":-1,"id":"test-offer"}; screen.session.offer_received.emit("undo",false)
	check(screen.pending_offer_dialog,"remote request shown")
	screen.close_modal(); check(screen.session.offer.is_empty(),"closing request dialog rejects and unlocks game")
	screen._stop_session(); screen.clear_pending(); screen._refresh(true)
	# Native record_imported is connected to the derived menu's callback.
	var previous_records: String = app.records.root
	app.records.root = "user://chu-probe-records"
	var replacement = screen.Game.new()
	replacement.play(replacement.position.legal_moves()[0])
	app.ui._import_text(JSON.stringify(replacement.to_data()))
	check(screen.game.state_key() == replacement.state_key() and screen.replay == 1, "native JSON callback reaches active Chu board")
	app.ui._import_text("invalid chu record")
	check(screen.game.state_key() == replacement.state_key(), "invalid native Chu import preserves board")
	app.records.root = previous_records
	screen.close_modal(); screen.game=screen.Game.new(); screen.replay=-1; screen._refresh(true)
	var report={"platform":OS.get_name(),"viewport":[app.size.x,app.size.y],"board":[screen.board.board_rect.size.x,screen.board.board_rect.size.y]}
	if OS.get_name()!="Android":
		await RenderingServer.frame_post_draw
		app.get_viewport().get_texture().get_image().save_png("user://chu-probe.png")
	app.close_chu(); await frames(); check(app.chu_screen==null,"return standard")
	report.checks=checks; report.failures=failures
	var output=FileAccess.open("user://chu-probe.json",FileAccess.WRITE); output.store_string(JSON.stringify(report,"\t")); output.close()
	print("CHU_PROBE_RESULT "+JSON.stringify(report))
	app.get_tree().quit(0 if failures.is_empty() else 1)
