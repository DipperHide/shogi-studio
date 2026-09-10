extends RefCounted

const Rules = preload("res://scripts/shogi_rules.gd")
const Game = preload("res://scripts/shogi_game.gd")
const Preferences = preload("res://scripts/shogi_preferences.gd")
var failures: Array[String] = []
var checks: int = 0
var app
var output: String
var screenshots: int = 0

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures.append(title)
		printerr("UI FAIL: ",title)

func settle(seconds: float = 0.12) -> void:
	await app.get_tree().create_timer(seconds).timeout
	for frame in range(4):
		await app.get_tree().process_frame
	RenderingServer.force_draw(false)
	await app.get_tree().process_frame

func await_motion() -> void:
	var deadline = Time.get_ticks_msec()+3000
	while app.busy and Time.get_ticks_msec() < deadline:
		await app.get_tree().process_frame
	assert(not app.busy,"Piece animation must finish")
	await settle(0.02)

func capture(filename: String) -> void:
	await settle()
	RenderingServer.force_draw(false)
	app.get_viewport().get_texture().get_image().save_png(output+"/"+filename+".png")
	screenshots += 1

func point(square: int) -> Vector2:
	return app.camera.unproject_position(app._square_position(square))

func physical(p: Vector2) -> Vector2:
	return p * Vector2(app.get_window().size) / app.get_viewport().get_visible_rect().size

func mouse(p: Vector2, pressed: bool) -> void:
	if pressed:
		# Move the pointer first, as a physical click does. This updates GUI hover
		# and the window's pointer position after resize before dispatching a press.
		var move = InputEventMouseMotion.new()
		move.position = physical(p)
		Input.parse_input_event(move)
		Input.flush_buffered_events()
		await app.get_tree().process_frame
	var event = InputEventMouseButton.new()
	event.position = physical(p)
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await app.get_tree().process_frame
	await app.get_tree().process_frame

func motion(p: Vector2) -> void:
	var event = InputEventMouseMotion.new()
	event.position = physical(p)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await app.get_tree().process_frame

func click(square: int) -> void:
	await mouse(point(square),true)
	await mouse(point(square),false)

func click_button(text: String) -> void:
	await settle(0.06)
	var parent = app.ui.modal if app.ui.modal != null else app.ui.page
	for node in parent.find_children("*","Button",true,false):
		if node.text == text:
			await mouse(node.get_global_rect().get_center(),true)
			await mouse(node.get_global_rect().get_center(),false)
			await settle()
			return
	check(false,"button exists: "+text)

func touch(p: Vector2, pressed: bool, id: int = 0, canceled: bool = false) -> void:
	var event = InputEventScreenTouch.new()
	event.position = physical(p)
	event.index = id
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await app.get_tree().process_frame

func touch_motion(p: Vector2, id: int = 0) -> void:
	var event = InputEventScreenDrag.new()
	event.position = physical(p)
	event.index = id
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await app.get_tree().process_frame

func assert_fits(root_node: Control, title: String) -> void:
	var viewport = app.get_viewport().get_visible_rect()
	for child in root_node.find_children("*","Button",true,false):
		if child.is_visible_in_tree():
			check(viewport.encloses(child.get_global_rect()),title+": "+child.text)

func history_fixture() -> void:
	app._start_game("local")
	await settle(0.4)
	app.game.position = Rules.new(false)
	app.game.position.board[80] = 8
	app.game.position.board[4] = -8
	app.game.position.board[20] = 7
	app.game.position.board[11] = -12
	app.game.position.hands[1][4] = 1
	app.game.positions = [app.game.position.copy()]
	for values in [[20,11,0,true],[4,5,0,false],[-1,40,4,false]]:
		check(app.game.play({"from":values[0],"to":values[1],"drop":values[2],"promote":values[3]}),"history fixture legal move")
	app._refresh()

func check_counted_hands() -> void:
	app._start_game("local")
	await settle(0.4)
	for quantity in [1,2,3,4,18]:
		app.game.position = Rules.new(false)
		app.game.position.board[80] = 8
		app.game.position.board[0] = -8
		app.game.position.hands[1][1] = quantity
		app.game.positions = [app.game.position.copy()]
		app._refresh()
		check(app.hand_models.get_child_count() == 1,"quantity %d uses one visible held pawn" % quantity)
		check(app.hand_counts.get_child_count() == (0 if quantity == 1 else 1),"quantity %d has exactly one number when repeated" % quantity)
		if quantity > 1:
			check(app.hand_counts.get_child(0).text == str(quantity),"number shows full quantity %d" % quantity)
		check(app.hand_models.get_child(0).position == app.Hand.center(1,1),"quantity does not raise or spread the pawn")
		check(app.hand_models.get_child(0).scale.is_equal_approx(Vector3.ONE),"held pawn keeps its full board size at quantity %d" % quantity)
	var held = app.hand_models.get_child(0)
	var token_id = held.get_meta("token_id")
	var held_point = app.camera.unproject_position(held.position+Vector3(0,.08,0))
	await mouse(held_point,true)
	await motion(point(40))
	check(app.dragging and held.visible and held.position == held.get_meta("rest"),"drag keeps one remaining representative on stand")
	check(app.hand_counts.get_child(0).text == "17","drag removes exactly one from the displayed count")
	check(app.drag_node.get_meta("token_id") == token_id,"drag uses the selected stable identity")
	await capture("18-counted-hand-drag")
	app._cancel_pointer()
	app._clear_selection()
	check(app.hand_counts.get_child(0).text == "18" and app.hand_models.get_child_count() == 1,"cancel restores count without duplicate models")
	await mouse(held_point,true)
	await mouse(held_point,false)
	await click(40)
	await await_motion()
	check(app.game.position.hands[1][1] == 17 and app.hand_models.get_child_count() == 1,"click drop reduces inventory but keeps a single display object")
	check(app.hand_counts.get_child(0).text == "17" and app._display_tokens()[token_id].square == 40,"click drops the same identity and correct count")
	app._undo()
	await await_motion()
	check(app.game.position.hands[1][1] == 18 and app.hand_counts.get_child(0).text == "18","undo restores 18 in one counted group")
	check(app.hand_models.get_child_count() == 1,"undo leaves no coincident held models")

func check_history_animation() -> void:
	await history_fixture()
	app._undo()
	check(app.busy and app.history_position.board[40] == 4 and app.game.position.board[40] == 0,"undo retains source visual position while logical move is removed")
	app._set_replay(0)
	check(app.replay_index == -1 and not app._can_interact(),"animation rejects replay and board input until landing")
	await app.get_tree().create_timer(0.15).timeout
	check(app.history_layer.get_children().any(func(n): return n.get_meta("history_from") == 40 and n.position.y > app.Scene.BOARD_Y+0.2),"undo drop lifts physical piece toward stand")
	await capture("16-undo-lift")
	await await_motion()
	check(app.history_layer == null and app.piece_layer.visible and app.game.position.hands[1][4] == 2,"undo drop lands in hand and restores normal rendering")
	check(app.hand_models.get_child_count() == 1 and app.hand_counts.get_child(0).text == "2","undo into existing kind consolidates into one model plus count")
	app._undo()
	await await_motion()
	app._undo()
	check(app.history_steps.size() == 1 and app.history_steps[0].tracks.any(func(t): return t.before.square == -1 and t.after.square == 11),"undo capture takes the victim back from the stand")
	await await_motion()
	check(app.game.position.board[11] == -12 and app.game.position.board[20] == 7,"undo capture restores ownership and both promoted faces")
	await history_fixture()
	app._set_replay(0)
	check(app.busy and app.history_layer != null,"jumping through record animates physical identities")
	await capture("17-replay-rearrange")
	await await_motion()
	check(app.replay_index == 0 and app._display_position().key() == app.game.positions[0].key(),"record jump lands exactly on requested position")
	app._set_replay(1)
	await await_motion()
	check(app._display_position().board[11] == 15 and app._display_position().hands[1][4] == 2,"forward replay capture promotes and transfers victim to hand")
	check(app.hand_models.get_child_count() == 1 and app.hand_counts.get_child(0).text == "2","replayed capture into existing kind leaves no overlap")
	app._set_replay(2)
	await await_motion()
	app._set_replay(3)
	await await_motion()
	check(app._display_position().board[40] == 4,"forward replay drop lands on board")
	app._set_replay(0)
	await await_motion()
	app._toggle_replay()
	check(app.busy,"leaving old replay position animates return to live game")
	await await_motion()
	check(app.replay_index == -1 and app._display_position().key() == app.game.position.key(),"return to live game preserves moves and current state")
	app.game.mode = "ai"
	app.game.human_side = -1
	app._undo()
	check(app.busy and app.history_steps.size() == 1 and app.game.moves.size() == 1,"AI undo schedules two reverse moves in order")
	await await_motion()
	check(app.history_position == null and not app.busy,"two-ply undo releases animation state")

func run(instance) -> void:
	app = instance
	app.get_tree().create_timer(110).timeout.connect(func(): printerr("UI TEST TIMEOUT"); app.get_tree().quit(1))
	print("SHOGI_UI_TESTS_STARTED")
	output = ProjectSettings.globalize_path("res://../review/app/v044")
	DirAccess.make_dir_recursive_absolute(output)
	await settle(0.4)
	check(app.screen == "home" and app.ui.page != null,"launch opens homepage")
	check(not app.ui.hud.visible and not app._can_interact(),"home blocks board play")
	check(not app.board_stage.visible and app.ui.home_stage.viewport.find_world_3d() != app.get_world_3d(),"homepage renders an independent world while gameplay geometry is hidden")
	check(app.ui.home_stage.preview.find_world_3d() == app.ui.home_stage.viewport.find_world_3d(),"homepage preview shares only its showroom world")
	var gallery_point = Vector2(app.get_viewport().get_visible_rect().size.x*5.0/6.0,500)
	await mouse(gallery_point,true)
	await mouse(gallery_point,false)
	check(app.ui.home_selected == 2 and app.ui.page_name == "home","first object tap selects local mode without entering")
	await mouse(gallery_point,true)
	await mouse(gallery_point,false)
	check(app.ui.page_name == "setup" and app.ui.setup_mode == "local","second object tap opens selected mode")
	app.ui.show_home()
	await settle()
	await touch(Vector2(850,500),true)
	await touch_motion(Vector2(650,500))
	await touch(Vector2(650,500),false)
	check(app.ui.home_selected == 2 and app.ui.page_name == "home","native swipe changes homepage selection")
	app.ui.show_home()
	await settle()
	await capture("01-home")
	assert_fits(app.ui.page,"home")
	await click_button("人机对弈")
	check(app.ui.page_name == "setup","home opens configuration")
	await click_button("后手")
	await click_button("入门")
	check(app.ui.setup_side == -1 and app.ui.setup_difficulty == 0,"configuration choices apply")
	await capture("02-setup")
	await click_button("开始对局")
	await settle(0.4)
	check(app.game.human_side == -1 and app.game.difficulty == 0 and app.flipped,"configured game and viewpoint")
	check(app.ui.page == null and app.ui.hud.visible and app.ui.home_stage == null,"game removes home page and stops showroom rendering")
	app.ui.show_home()
	check(app.ui.home_continue != null,"homepage offers continue")
	await settle()
	await click_button("继续对局")
	await settle(0.4)
	check(app.game.human_side == -1,"continue preserves seat choice")
	app._start_game("local")
	await settle(0.4)
	check(app.pieces.size() == 40,"board renders 40 pieces")
	check(app.audio_player.stream.format == AudioStreamWAV.FORMAT_16_BITS,"placement recording imports as uncompressed PCM")
	check(absf(app.audio_player.stream.get_length()-0.095)<0.001,"placement has the shortened 95 ms decay")
	check(app.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,"tabletop camera keeps parallel grid lines")
	var near_width = point(80).distance_to(point(72))
	var far_width = point(8).distance_to(point(0))
	check(absf(near_width-far_width)<0.1,"far and near ranks keep the same readable size")
	check(absf(app.Scene.data.tray_x-app.Scene.data.tray_width/2-app.Scene.data.board_width/2)<0.001,"square stands meet the board edge")
	check(absf(app.Scene.data.tray_width/app.Scene.data.tray_depth-1.0)<0.04,"stands retain the reference square proportions")
	var resting_shadow = app.pieces[56].get_child(1)
	var resting_softness = resting_shadow.material.get_shader_parameter("softness")
	check(absf(resting_shadow.global_position.y-app.Scene.data.board_top-0.006)<0.001,"piece contact stays on the actual board surface")
	var ink_material = app.pieces[76].get_child(0).mesh.surface_get_material(0)
	check(ink_material is ShaderMaterial and ink_material.get_shader_parameter("has_ink") == true,"piece face has a separate lacquer ink mask")
	check(ink_material.get_shader_parameter("ink_texture").get_size() == Vector2(4096,4096),"piece calligraphy has a full resolution 4K mask")
	check(ink_material.shader.resource_path.ends_with("polished_boxwood.gdshader"),"pieces use their own wood and lacquer finish")
	check(not app.coordinate_layer.visible and not app.ui.replay_bar.visible,"board hides coordinates and record by default")
	check(app.ui.hud.find_children("*","Button",true,false).filter(func(b): return b.is_visible_in_tree()).size() == 1,"only menu control visible during play")
	await capture("03-clean-board")
	await mouse(point(56),true)
	await motion(point(47))
	check(app.dragging and app.game.moves.is_empty(),"mouse drag lifts without mutating position")
	check(app.drag_node.position.y > app.Scene.BOARD_Y+0.4,"dragged piece lifted above board")
	check(app.drag_node.get_child(1).material.get_shader_parameter("softness")>resting_softness*1.5,"lifted piece shadow softens with physical height")
	await capture("04-dragging")
	await mouse(point(47),false)
	await settle(0.5)
	await await_motion()
	check(app.game.moves.size() == 1 and app.game.position.board[47] == 1,"mouse release commits legal move")
	await click(24)
	check(app.selection == 24,"tap selects piece")
	await click(33)
	await settle(0.5)
	await await_motion()
	check(app.game.moves.size() == 2,"tap to move retained")
	var before = app.game.position.key()
	await mouse(point(55),true)
	await motion(point(37))
	await mouse(point(37),false)
	await settle()
	check(app.game.position.key() == before and app.pieces[55].position == app._square_position(55),"illegal drag returns to original square")
	await mouse(point(55),true)
	await motion(Vector2(20,20))
	await mouse(Vector2(20,20),false)
	check(app.pointer_id == -2 and app.game.position.key() == before,"release outside board or over UI cancels")
	await touch(point(55),true,0)
	await touch(point(54),true,1)
	await touch_motion(point(45),1)
	check(app.pointer_id == 0 and not app.dragging,"second finger ignored")
	await touch_motion(point(46),0)
	check(app.dragging,"native touch drag supported")
	await touch(point(46),false,0,true)
	check(app.pointer_id == -2 and app.game.position.key() == before,"OS touch cancellation returns piece")
	await touch(point(55),true,0)
	await touch_motion(point(46),0)
	await touch(point(46),false,0)
	await settle(0.5)
	await await_motion()
	check(app.game.moves.size() == 3 and app.game.position.board[46] == 1,"touch release moves once without duplicate mouse event")
	app._flip()
	await settle(0.4)
	await mouse(point(23),true)
	await motion(point(32))
	await mouse(point(32),false)
	await settle(0.5)
	await await_motion()
	check(app.game.position.board[32] == -1,"drag works after viewpoint flip")
	app.ui.show_pause()
	await capture("05-pause")
	assert_fits(app.ui.modal,"pause")
	await click_button("棋谱回放")
	await click_button("从头回放")
	check(app.busy and app.history_layer != null,"replay starts physical piece animation")
	await await_motion()
	check(app.replay_index == 0 and app._display_position().key() == Rules.new().key(),"menu opens replay at initial position")
	await mouse(point(56),true)
	await motion(point(47))
	await mouse(point(47),false)
	check(app.game.moves.size() == 4 and not app.dragging,"replay rejects dragging")
	await capture("06-replay")
	app._toggle_replay()
	await await_motion()
	app._undo()
	await await_motion()
	check(app.game.moves.size() == 3,"undo still works")
	app.ui.show_settings(true)
	await capture("07-settings")
	assert_fits(app.ui.modal,"settings")
	app._preference("coordinates",true)
	check(app.coordinate_layer.visible,"coordinate preference applies")
	app._preference("hints",false)
	app._preference("volume",0.35)
	var settings_path = "user://test-interface-preferences.cfg"
	check(app.preferences.save_to(settings_path) == OK,"preferences save")
	var restored = Preferences.new()
	restored.load_from(settings_path)
	check(restored.coordinates and not restored.hints and is_equal_approx(restored.volume,0.35),"preferences persist")
	DirAccess.remove_absolute(settings_path)
	app._preference("coordinates",false)
	app._preference("hints",true)
	app.ui.close_modal()
	# Compose a promotion/capture/drop position.
	app._start_game("local")
	await settle(0.4)
	app.game.position = Rules.new(false)
	app.game.position.board[80] = 8
	app.game.position.board[4] = -8
	app.game.position.board[20] = 7
	app.game.position.board[11] = -4
	app.game.positions = [app.game.position.copy()]
	app._refresh()
	await mouse(point(20),true)
	await motion(point(11))
	await mouse(point(11),false)
	check(app.ui.modal != null and app.game.moves.is_empty(),"promotion drag defers commit for choice")
	await capture("08-promotion")
	await click_button("成")
	await settle(0.5)
	await await_motion()
	check(app.game.position.board[11] == 15 and app.game.position.hands[1][4] == 1,"promotion capture commits correctly")
	await click(4)
	await click(5)
	await settle(0.5)
	await await_motion()
	var held = app.hand_models.get_child(0)
	var hand_point = app.camera.unproject_position(held.position)
	await mouse(hand_point,true)
	await mouse(hand_point,false)
	check(app.selected_drop == 4 and not app.dragging,"mouse tap keeps captured piece selected")
	# Four input frames can be shorter than the 100 ms lift on a fast renderer.
	if app.selection_tween != null and app.selection_tween.is_running():
		await app.selection_tween.finished
	check(held.position.y > app.Scene.TRAY_Y+0.05,"selected captured piece visibly lifted")
	await capture("15-hand-selected")
	await click(40)
	await settle(0.5)
	await await_motion()
	check(app.game.position.board[40] == 4 and app.game.position.hands[1][4] == 0,"mouse tap destination drops captured piece once")
	app._undo()
	await await_motion()
	app._flip()
	await settle(0.4)
	held = app.hand_models.get_child(0)
	hand_point = app.camera.unproject_position(held.position)
	await mouse(hand_point,true)
	await mouse(hand_point,false)
	await click(40)
	await settle(0.5)
	await await_motion()
	check(app.game.position.board[40] == 4 and app.game.position.hands[1][4] == 0,"captured piece tap works with flipped board")
	app._undo()
	await await_motion()
	app._flip()
	await settle(0.4)
	await settle()
	held = app.hand_models.get_child(0)
	hand_point = app.camera.unproject_position(held.position)
	await touch(hand_point,true)
	await touch(hand_point,false)
	check(app.selected_drop == 4 and not app.dragging,"touch tap keeps captured piece selected")
	await touch(point(5),true)
	await touch(point(5),false)
	check(app.game.position.hands[1][4] == 1 and app.game.position.board[5] == -8,"tap cannot drop onto occupied square")
	await touch(hand_point,true)
	await touch(hand_point,false)
	await touch(hand_point,true)
	await touch(hand_point,false)
	check(app.selected_drop == 0,"second tap on captured piece cancels selection")
	app._preference("hints",false)
	await touch(hand_point,true)
	await touch(hand_point,false)
	await touch(point(40),true)
	await touch(point(40),false)
	await settle(0.5)
	await await_motion()
	check(app.game.position.board[40] == 4 and app.game.position.hands[1][4] == 0,"touch tap drops once with hints disabled")
	app._undo()
	await await_motion()
	app._preference("hints",true)
	await settle()
	held = app.hand_models.get_child(0)
	await mouse(app.camera.unproject_position(held.position),true)
	await motion(point(40))
	check(app.dragging and app.selected_drop == 4,"held piece can be dragged from stand")
	await capture("09-hand-drag")
	await mouse(point(40),false)
	await settle(0.5)
	await await_motion()
	check(app.game.position.board[40] == 4 and app.game.position.hands[1][4] == 0,"drag drop consumes held piece once")
	# Focus loss must never leave a captured input pointer.
	await mouse(point(5),true)
	await motion(point(6))
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.pointer_id == -2 and not app.dragging,"focus loss cancels drag")
	app._clear_selection()
	app.get_window().size = Vector2i(960,540)
	await settle(0.4)
	await capture("10-small-board")
	await mouse(point(5),true)
	await motion(point(6))
	await mouse(point(6),false)
	await settle(0.5)
	await await_motion()
	check(app.game.position.board[6] == -8,"drag at scaled window resolution")
	app.get_window().size = Vector2i(1600,720)
	await settle(0.4)
	app._start_game("local")
	await settle(0.4)
	await capture("11-wide-board")
	app.ui.show_home()
	await capture("12-wide-home")
	app.get_window().size = Vector2i(1280,720)
	await settle(0.4)
	# AI is paused on home, and can play the opening when the human chooses gote.
	app._start_game("ai",-1,0)
	await settle(0.4)
	app.ui.show_home()
	app.testing = false
	await settle(0.5)
	await await_motion()
	check(app.game.moves.is_empty(),"AI does not play on homepage")
	app._resume_game()
	await settle(1.3)
	app.testing = true
	check(app.game.moves.size() == 1 and app.game.position.turn == -1,"AI plays sente opening for human gote")
	app._start_game("ai",1,1)
	await settle(0.4)
	app.testing = false
	await click(56)
	await click(47)
	await settle(0.4)
	app.testing = true
	app._undo()
	await await_motion()
	await settle(1.1)
	check(app.game.moves.is_empty(),"AI result invalidated by undo")
	await check_history_animation()
	app._start_game("local")
	await settle(0.4)
	for square in range(81):
		app.game.position.board[square] = 0
	app.game.position.board[80] = 8
	app.game.position.board[0] = -8
	for side in [1,-1]:
		app.game.position.hands[side] = [0,9,2,2,2,2,1,1]
	app.game.positions = [app.game.position.copy()]
	app._refresh()
	await capture("13-full-hands")
	check(app.hand_models.get_child_count() == 14,"38 held pieces use exactly one model for each of 14 groups")
	check(app.hand_counts.get_child_count() == 10,"each repeated kind has one count, single pieces have none")
	for side in [-1,1]:
		app.game.position.turn = side
		app.game.positions = [app.game.position.copy()]
		app._refresh()
		for held_piece in app.hand_models.get_children():
			if held_piece.get_meta("side") != side:
				continue
			var hit = app._hand_at(app.camera.unproject_position(held_piece.position+Vector3(0,.08,0)))
			check(hit != null and hit.get_meta("hand") == held_piece.get_meta("hand"),"any piece in a full stand hits its own kind")
			if hit != null:
				check(hit.get_meta("token_id") == app.hand_layout.groups[side*int(held_piece.get_meta("hand"))].top,"group hit always picks top stable identity")
	await check_counted_hands()
	app.game.result = "先手判负 · 连续王手千日手"
	app._refresh()
	app.ui.show_result()
	await capture("14-result")
	assert_fits(app.ui.modal,"result")
	check(not app._can_interact(),"finished game blocks board")
	var report = {"checks":checks,"failures":failures,"captures":screenshots}
	var file = FileAccess.open(output+"/ui-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("SHOGI_UI_TESTS: "+JSON.stringify(report))
	app.get_tree().quit(0 if failures.is_empty() else 1)
