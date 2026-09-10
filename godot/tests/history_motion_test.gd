extends SceneTree
const Motion = preload("res://scripts/shogi_history_motion.gd")
const Rules = preload("res://scripts/shogi_rules.gd")
const Hand = preload("res://scripts/shogi_hand_layout.gd")
const Scene = preload("res://scripts/shogi_scene_layout.gd")
const Game = preload("res://scripts/shogi_game.gd")
var checks = 0

func _initialize() -> void:
	create_timer(5).timeout.connect(func(): printerr("History motion test timeout"); quit(1))
	var game = Game.new()
	game.mode = "local"
	game.position = Rules.new(false)
	game.position.board[80] = 8
	game.position.board[4] = -8
	game.position.board[20] = 7
	game.position.board[11] = -12
	game.position.hands[1][4] = 2
	game.positions = [game.position.copy()]
	for values in [[20,11,0,true],[4,5,0,false],[-1,40,4,false],[5,6,0,false],[40,31,0,false],[6,7,0,false],[11,20,0,false]]:
		assert(game.play({"from":values[0],"to":values[1],"drop":values[2],"promote":values[3]}))
	for source in range(game.positions.size()):
		for target in range(game.positions.size()):
			var tracks = Motion.plan(game.positions[0],game.moves,source,target)
			assert(tracks.size() == 6,"All physical identities conserved, even duplicate held kinds")
			for endpoint in ["before","after"]:
				var position = Rules.new(false)
				var expected = game.positions[source if endpoint == "before" else target]
				position.turn = expected.turn
				for track in tracks:
					var token = track[endpoint]
					if token.square >= 0:
						assert(position.board[token.square] == 0)
						position.board[token.square] = token.value
					else:
						position.hands[1 if token.value > 0 else -1][absi(token.value)] += 1
				assert(position.key() == expected.key(),"Animation endpoints must exactly match legal snapshots")
				checks += 1
	var backwards = Motion.plan(game.positions[0],game.moves,1,0)
	assert(backwards.any(func(t): return t.before.square == -1 and t.before.value == 4 and t.after.square == 11 and t.after.value == -12),"Undo restores captured piece owner and promoted face")
	assert(backwards.any(func(t): return t.before.value == 15 and t.after.value == 7),"Undo turns promoted mover back over")
	checks += 2
	var widths = [0.0,.68,.71,.74,.78,.80,.82,.84]
	var depths = [0.0,.84,.88,.90,.92,.94,.96,.98]
	for side in [-1,1]:
		for kind in range(1,8):
			for count in [1,2,3,4,18]:
				var initial = Rules.new(false)
				initial.hands[side][kind] = count
				var tokens = Motion.state(initial,[],0)
				var layout = Hand.layout(tokens)
				var group = layout.groups[side*kind]
				assert(layout.poses.size() == count and group.ids.size() == count)
				for id in group.ids:
					var pose = layout.poses[id]
					assert(pose == layout.poses[group.top],"Quantity shares one landing slot, never stacked or fanned")
					assert(is_equal_approx(pose.position.y,Scene.TRAY_Y),"Quantity cannot change the stand's landing height")
					for x in [-widths[kind]/2,widths[kind]/2]:
						for z in [-depths[kind]/2,depths[kind]/2]:
							var corner = pose.position + Basis(Vector3.UP,pose.rotation)*Vector3(x,0,z)*pose.scale
							assert(group.bounds.grow(.001).has_point(Vector2(corner.x,corner.z)),"Rotated piece stays within its own group")
							var tray = Scene.tray_center(side)
							assert(absf(corner.x-tray.x) < Scene.data.tray_width/2 and absf(corner.z-tray.z) < Scene.data.tray_depth/2,"Full-size held pieces stay inside the existing tray")
				checks += 1
	var capture_stages = Motion.stages(game.positions[0],game.moves,0,1)
	assert(capture_stages.size() == 2)
	assert(capture_stages[0].any(func(t): return t.before.square == 11 and t.after.square < 0),"Victim moves before attacker")
	assert(capture_stages[1].any(func(t): return t.before.square == 20 and t.after.square == 11),"Attacker lands only after destination clears")
	var drop = Motion.plan(game.positions[0],game.moves,2,3)
	var hand = Hand.layout(Motion.state(game.positions[0],game.moves,2))
	assert(drop.any(func(t): return t.id == hand.groups[4].top and t.after.square == 40),"Drop always takes the visible top physical piece")
	var ordered = Hand.layout([{ "square":-1,"value":4,"hand_order":1},{"square":-1,"value":4,"hand_order":2}])
	assert(ordered.groups[4].top == 1,"Most recent capture goes on top instead of beneath an existing stack")
	checks += 5
	var successive = Game.new()
	successive.mode = "local"
	successive.position = Rules.new(false)
	for item in [[4,-8],[11,-4],[20,7],[29,-4],[80,8]]:
		successive.position.board[item[0]] = item[1]
	successive.positions = [successive.position.copy()]
	for values in [[20,11,0,false],[4,5,0,false],[11,29,0,false],[5,6,0,false],[-1,40,4,false]]:
		assert(successive.play({"from":values[0],"to":values[1],"drop":values[2],"promote":values[3]}))
	var second_capture = Motion.state(successive.positions[0],successive.moves,4)
	assert(Hand.layout(second_capture).groups[4].top == 3,"Later higher-id capture is placed above earlier captured silver")
	var latest_drop = Motion.plan(successive.positions[0],successive.moves,4,5)
	assert(latest_drop[3].after.square == 40 and latest_drop[1].after.square == -1,"Drop consumes most recent captured physical piece")
	var restored_drop = Motion.plan(successive.positions[0],successive.moves,5,4)
	assert(restored_drop[3].end == Hand.layout(second_capture).poses[3].position,"Undo restores that same piece to its exact top position")
	checks += 8
	var file = FileAccess.open("res://../review/app/history-motion-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":[]},"  "))
	print("SHOGI_HISTORY_MOTION_TESTS: %d checks passed" % checks)
	quit()
