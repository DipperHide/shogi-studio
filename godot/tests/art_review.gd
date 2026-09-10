extends RefCounted
var app
var output = "res://../review/app/v044/"

func capture(name: String) -> void:
	await app.get_tree().create_timer(0.4).timeout
	for i in range(4):
		await app.get_tree().process_frame
	RenderingServer.force_draw(false)
	await app.get_tree().process_frame
	app.get_viewport().get_texture().get_image().save_png(output+name+".png")

func run(instance) -> void:
	app = instance
	app.get_tree().create_timer(25).timeout.connect(func(): app.get_tree().quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await capture("art-home")
	app.ui._choose_home(2)
	await capture("art-home-local")
	app._start_game("local")
	await capture("art-board")
	# The user's latest reference position makes visual comparison meaningful.
	var reference = app.Rules.new(false)
	reference.board.assign([-2,-3,-4,-5,-8,0,0,-3,-2, 0,-7,0,0,0,0,-5,0,0,
		-1,0,-1,-1,-1,-1,-4,-1,-1, 0,0,0,0,0,0,-1,0,0,
		0,-1,0,0,0,0,0,1,0, 0,0,1,0,0,0,0,0,0,
		1,1,4,1,1,1,1,0,1, 0,0,0,0,0,4,0,7,0,
		2,3,0,5,8,5,0,3,2])
	reference.hands[1][6] = 1
	reference.hands[-1][6] = 1
	app.game.position = reference
	app.game.positions = [reference.copy()]
	app._refresh()
	await capture("art-reference-position")
	app._start_game("local")
	await app.get_tree().create_timer(0.5).timeout
	app.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	app.camera.position = Vector3(10,11,15)
	app.camera.look_at(Vector3(0,1.5,0))
	app.camera.fov = 48
	await capture("art-structure")
	app._update_camera()
	var p = app.Rules.new(false)
	p.board[80] = 8
	p.board[0] = -8
	for side in [-1,1]:
		p.hands[side] = [0,9,2,2,2,2,1,1]
	app.game.position = p
	app.game.positions = [p.copy()]
	app._refresh()
	await capture("art-hands")
	p.hands[1][1] = 18
	p.hands[-1][1] = 0
	app.game.positions = [p.copy()]
	app._refresh()
	await capture("art-hands-18")
	p = app.Rules.new(false)
	var values = [8,-8,7,15,6,14,5,4,12,3,11,2,10,1,9]
	for i in range(values.size()):
		p.board[20+(i/5)*18+i%5] = values[i]
	app.game.position = p
	app.game.positions = [p.copy()]
	app._refresh()
	app.camera.position = Vector3(0,13,7)
	app.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	app.camera.look_at(Vector3(0,app.Scene.BOARD_Y,0))
	app.camera.fov = 43
	await capture("art-faces")
	p = app.Rules.new(false)
	p.board[38] = 8
	p.board[40] = 7
	p.board[42] = 4
	app.game.position = p
	app.game.positions = [p.copy()]
	app._refresh()
	app.camera.position = Vector3(0.8,5.9,4.6)
	app.camera.look_at(Vector3(0,app.Scene.BOARD_Y+0.10,0))
	app.camera.fov = 46
	await capture("art-piece-closeup")
	print("SHOGI_ART_REVIEW_OK")
	app.get_tree().quit()
