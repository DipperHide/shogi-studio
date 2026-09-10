extends "res://tests/unified_test.gd"
var frames: Array = []

func snapshot(phase: String) -> void:
	var wood = app.wood_view
	var poses = {}
	for id in wood.animated_nodes:
		var node: Node3D = wood.animated_nodes[id]
		var shadow = node.get_node("PieceContact")
		poses[str(id)] = {"position": str(node.position), "transform": str(node.transform), "node": node.get_instance_id(), "shadow": str(shadow.global_position), "shadow_current": shadow.previous == node.global_transform}
	frames.append({"phase": phase, "progress": app.motion_progress, "static_visible": wood.piece_layer.visible, "animated": poses, "camera": str(wood.camera.transform)})
	# Let SceneTree flush new mesh instances and visibility to the renderer.
	await app.get_tree().process_frame
	await RenderingServer.frame_post_draw
	app.get_viewport().get_texture().get_image().save_png(output.path_join(phase + ".png"))

func run(instance) -> void:
	app = instance
	var baseline = "--baseline" in OS.get_cmdline_user_args()
	output = ProjectSettings.globalize_path("res://../review/app/chessis09/motion-" + ("before" if baseline else "after"))
	if "--chessis13-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis13/motion")
	if "--chessis16-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis16/motion")
	if "--chessis20-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis20/chessis_motion_test")
	DirAccess.make_dir_recursive_absolute(output)
	app._start_match("local", 1, 2, "basic")
	app.preferences.studio.animation = 0.4
	await resize(Vector2i(393, 852))
	app.set_appearance("wood")
	await settle(0.15)
	var index = 0
	for move in ["7g7f", "3c3d", "8h2b+", "3a2b", "B*4e"]:
		await snapshot("%d-rest" % index)
		app._commit(app.Codec.parse_move(move, app.game.position))
		app.motion_tween.pause()
		await snapshot("%d-commit" % index)
		check(not app.wood_view.piece_layer.visible and not app.wood_view.animated_nodes.is_empty(), move + " initial pose is installed synchronously")
		var previous_nodes = {}
		var stationary = {}
		for track in app.transition:
			if track.before == track.after and track.before.square >= 0 and app.wood_view.animated_nodes.has(track.id): stationary[track.id] = app.wood_view.animated_nodes[track.id].transform
		var camera: Transform3D = app.wood_view.camera.transform
		for p in [0.0, 0.25, 0.5, 0.75, 1.0]:
			app.motion_progress = p
			app.wood_view.animate_tracks(app.transition, p)
			await snapshot("%d-frame-%02d" % [index, int(p * 100)])
			for id in app.wood_view.animated_nodes:
				var node: Node3D = app.wood_view.animated_nodes[id]
				check(node.get_node("PieceContact").previous == node.global_transform, move + " shadow follows same frame " + str(p))
				previous_nodes[id] = node.get_instance_id()
				if stationary.has(id): check(node.transform.is_equal_approx(stationary[id]), move + " stationary piece stays fixed " + str(id))
			if p == 0.5:
				app._refresh()
				check(not app.wood_view.piece_layer.visible, move + " refresh preserves transition")
				for id in previous_nodes:
					check(app.wood_view.animated_nodes.has(id) and app.wood_view.animated_nodes[id].get_instance_id() == previous_nodes[id], move + " refresh preserves physical node " + str(id))
			check(camera == app.wood_view.camera.transform, move + " camera stable")
		app._cancel_motion()
		app.wood_view.sync()
		await settle(0.05)
		await snapshot("%d-landed" % index)
		index += 1
	app.game = app.Game.new()
	app.game.mode = "local"
	app._refresh()
	var from: Vector2 = app.square_rect(56).get_center()
	var to: Vector2 = app.square_rect(47).get_center()
	# Hidden test windows can lose focus when another build process starts.
	app.active = true
	app._pointer_down(0, from)
	app.pointer_moved = true
	app.pointer_current = to
	app._redraw()
	var release: Vector3 = app.wood_view.dragged_node.position
	app._pointer_up(to, false)
	app.motion_tween.pause()
	var moved = app.transition.filter(func(t): return t.before.square == 56)[0]
	check(app.wood_view.animated_nodes[moved.id].position.is_equal_approx(release), "drag release continues from pointer, without jumping back")
	await snapshot("drag-release")
	app.wood_view.animate_tracks(app.transition, 0.5)
	check(app.wood_view.animated_nodes[moved.id].position.y <= release.y, "drag settles without a second hop")
	await snapshot("drag-settle")
	app._cancel_motion()
	var file = FileAccess.open(output.path_join("telemetry.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "frames": frames}, "  "))
	print("MOTION PROBE: ", checks, " checks, ", failures.size(), " failures")
	app.get_tree().quit(0 if baseline or failures.is_empty() else 1)
