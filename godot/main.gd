extends Node3D

const Rules = preload("res://scripts/shogi_rules.gd")
const Game = preload("res://scripts/shogi_game.gd")
const AI = preload("res://scripts/shogi_ai.gd")
const Preferences = preload("res://scripts/shogi_preferences.gd")
const Interface = preload("res://scripts/shogi_interface.gd")
const HistoryMotion = preload("res://scripts/shogi_history_motion.gd")
const Scene = preload("res://scripts/shogi_scene_layout.gd")
const Hand = preload("res://scripts/shogi_hand_layout.gd")
const SAVE_PATH = "user://current-game.json"
const PIECE_KEYS = ["","pawn","lance","knight","silver","gold","bishop","rook","jewel"]
const HEIGHTS = [0.0,0.16,0.17,0.18,0.19,0.2,0.21,0.215,0.23]

var game = Game.new()
var preferences = Preferences.new()
var has_game: bool = false
var screen: String = "home"
var ui
var camera: Camera3D
var camera_tween: Tween
var meshes: Dictionary = {}
var pieces: Dictionary = {}
var board_stage = Node3D.new()
var piece_layer = Node3D.new()
var markers = Node3D.new()
var hand_models = Node3D.new()
var hand_counts = Node3D.new()
var hand_layout: Dictionary = {}
var hand_by_id: Dictionary = {}
var selection_tween: Tween
var history_counts = Node3D.new()
var coordinate_layer = Node3D.new()
var selection: int = -1
var selected_drop: int = 0
var legal: Array[Dictionary] = []
var replay_index: int = -1
var flipped: bool = false
var busy: bool = false
var thread: Thread
var ai_engine: RefCounted
var ai_revision: int = 0
var revision: int = 0
var active_tween: Tween
var audio_player: AudioStreamPlayer
var testing: bool = false
var test_runner: RefCounted
var pointer_id: int = -2
var pointer_start = Vector2.ZERO
var pointer_eligible: bool = false
var pointer_same_selection: bool = false
var dragging: bool = false
var drag_node: Node3D
var drag_hand_source: Node3D
var drag_hover: int = -1
var last_save_error: Error = OK
var count_font: FontVariation
var history_position: ShogiRules
var history_layer: Node3D
var history_steps: Array = []
var history_finished: Callable

func _ready() -> void:
	# The classic scene keeps its landscape layout when launched explicitly.
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().min_size = Vector2i(960, 540)
	if not OS.has_feature("mobile"):
		get_window().size = Vector2i(1280, 720)
	testing = "--art-review" in OS.get_cmdline_user_args() or "--smoke-test" in OS.get_cmdline_user_args() or "--ui-test" in OS.get_cmdline_user_args()
	if not testing:
		preferences.load_from()
		var saved = Game.load_from(SAVE_PATH)
		if saved != null:
			game = saved
			has_game = true
	_build_world()
	ui = Interface.new()
	add_child(ui)
	ui.initialize(self)
	audio_player = AudioStreamPlayer.new()
	audio_player.stream = preload("res://assets/audio/wood-place.wav")
	add_child(audio_player)
	get_viewport().size_changed.connect(_resize)
	ui.show_home()
	if "--smoke-test" in OS.get_cmdline_user_args():
		print("SHOGI_SMOKE_OK: homepage, board, preferences and wood sound ready")
		get_tree().quit()
	elif "--art-review" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/art_review.gd").new()
		test_runner.run.call_deferred(self)
	elif "--ui-test" in OS.get_cmdline_user_args():
		test_runner = load("res://tests/ui_test.gd").new()
		test_runner.run.call_deferred(self)

func _build_world() -> void:
	count_font = FontVariation.new()
	count_font.base_font = preload("res://assets/fonts/NotoSansSC.ttf")
	count_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):520.0}
	var model = preload("res://assets/shogi-scene.glb").instantiate()
	add_child(board_stage)
	board_stage.add_child(model)
	for child in model.get_children():
		if child is MeshInstance3D:
			_retone(child)
		if str(child.name).begins_with("Tatami environment"):
			child.scale = Vector3(4,1,4)
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if str(child.name).begins_with("Tatami cloth seam"):
			child.visible = false
		if str(child.name).begins_with("sente_") or str(child.name).begins_with("gote_"):
			if child is MeshInstance3D:
				meshes[str(child.name).split("_")[1]] = child.mesh
			child.queue_free()
	for node in [piece_layer,markers,hand_models,hand_counts,history_counts,coordinate_layer]:
		board_stage.add_child(node)
	var world = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("e9dfc7")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fffdf6")
	environment.ambient_light_energy = 0.52
	var sky = Sky.new()
	var daylight = ShaderMaterial.new()
	daylight.shader = preload("res://assets/materials/daylight_reflection.gdshader")
	sky.sky_material = daylight
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = environment
	add_child(world)
	var sun = DirectionalLight3D.new()
	sun.light_color = Color("fff9ef")
	sun.light_energy = 1.10
	sun.rotation_degrees = Vector3(-64,-68,0)
	# Stable, soft projected contact shadows avoid GLES self-shadow stripes.
	sun.shadow_enabled = false
	sun.shadow_bias = 0.045
	sun.shadow_normal_bias = 0.15
	sun.shadow_blur = 3.0
	sun.shadow_opacity = 0.68
	sun.directional_shadow_max_distance = 50
	add_child(sun)
	_ground_shadow(Vector3(0.75,0.012,0.23),Vector2(Scene.data.board_width,Scene.data.board_depth),0.85,0.31)
	for side in [-1,1]:
		var center = Scene.tray_center(side)
		_ground_shadow(Vector3(center.x+0.64,0.014,center.z+0.25),Vector2(Scene.data.tray_width,Scene.data.tray_depth),0.62,0.25)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 100
	add_child(camera)
	var ranks = ["一","二","三","四","五","六","七","八","九"]
	for index in range(9):
		for axis in range(2):
			var coordinate = Label3D.new()
			coordinate.text = str(9-index) if axis == 0 else ranks[index]
			coordinate.font = preload("res://assets/fonts/YujiSyuku-Regular.ttf")
			coordinate.font_size = 48
			coordinate.pixel_size = 0.0055
			coordinate.outline_size = 0
			coordinate.modulate = Color("765d3f")
			coordinate.rotation.x = -PI/2
			coordinate.position = Vector3((index-4)*Scene.CELL_X,Scene.BOARD_Y+0.008,-5.05) if axis == 0 else Vector3(4.6,Scene.BOARD_Y+0.008,(index-4)*Scene.CELL_Z)
			coordinate_layer.add_child(coordinate)

func _retone(node: MeshInstance3D) -> void:
	node.mesh = node.mesh.duplicate()
	for surface in range(node.mesh.get_surface_count()):
		var source = node.mesh.surface_get_material(surface)
		if not source is StandardMaterial3D:
			continue
		if source.albedo_texture == null:
			var edge = source.duplicate()
			edge.albedo_color = Color("aa8658")
			edge.roughness = 0.48
			edge.metallic_specular = 0.5
			edge.clearcoat_enabled = true
			edge.clearcoat = 0.12
			edge.clearcoat_roughness = 0.24
			node.mesh.surface_set_material(surface,edge)
			continue
		var material = ShaderMaterial.new()
		if "Boxwood" in source.resource_name:
			material.shader = preload("res://assets/materials/polished_boxwood.gdshader")
			material.set_shader_parameter("wood_texture",source.albedo_texture)
			if "calligraphy" in source.resource_name:
				material.set_shader_parameter("ink_texture",preload("res://assets/materials/piece-ink.png"))
				material.set_shader_parameter("has_ink",true)
			node.mesh.surface_set_material(surface,material)
			continue
		material.shader = preload("res://assets/materials/quiet_wood.gdshader")
		material.set_shader_parameter("wood_texture",source.albedo_texture)
		material.set_shader_parameter("saturation",1.0)
		material.set_shader_parameter("lightness",1.0)
		if "calligraphy" in source.resource_name:
			material.set_shader_parameter("ink_texture",preload("res://assets/materials/piece-ink.png"))
			material.set_shader_parameter("has_ink",true)
		if str(node.name).begins_with("Tatami environment"):
			material = ShaderMaterial.new()
			material.shader = preload("res://assets/materials/sunlit_tatami.gdshader")
			material.set_shader_parameter("rush_texture",preload("res://assets/materials/igusa-rush.png"))
		elif "Komadai" in str(node.name):
			material.set_shader_parameter("surface_roughness",0.36)
			material.set_shader_parameter("finish_coat",0.20)
		elif str(node.name).begins_with("sente_") or str(node.name).begins_with("gote_"):
			material.set_shader_parameter("surface_roughness",0.35)
			material.set_shader_parameter("finish_coat",0.18)
		node.mesh.surface_set_material(surface,material)

func _resize() -> void:
	_cancel_pointer()
	_update_camera()

func _update_camera(animate: bool = false) -> void:
	if camera_tween != null:
		camera_tween.kill()
	var size = get_viewport().get_visible_rect().size
	# Parallel edges preserve board readability. A slight tabletop angle lets
	# the wooden rim, beveled pieces and space beneath the stands remain visible.
	var target = Vector3(0,Scene.BOARD_Y,0)
	var position_target = target + Vector3(0,30,6.4 if not flipped else -6.4)
	var height = maxf(13.45,18.8*size.y/maxf(1,size.x))
	var destination = Transform3D(Basis.IDENTITY,position_target).looking_at(target,Vector3(0,0,1 if flipped else -1))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	if animate:
		camera_tween = create_tween().set_parallel(true)
		camera_tween.tween_property(camera,"transform",destination,0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		camera_tween.tween_property(camera,"size",height,0.35)
	else:
		camera.transform = destination
		camera.size = height

func _display_position() -> ShogiRules:
	if history_position != null:
		return history_position
	return game.position if replay_index < 0 else game.positions[replay_index]

func _refresh() -> void:
	board_stage.visible = screen == "game"
	_cancel_pointer()
	selection = -1
	selected_drop = 0
	legal.clear()
	if game.result.is_empty():
		legal = game.position.legal_moves()
	_rebuild_pieces()
	_refresh_hands()
	_refresh_markers()
	coordinate_layer.visible = preferences.coordinates and screen == "game"
	if ui != null:
		ui.refresh()

func _rebuild_pieces() -> void:
	_clear_children(piece_layer)
	pieces.clear()
	var p = _display_position()
	for square in range(81):
		if p.board[square] != 0:
			var node = _piece(p.board[square])
			node.position = _square_position(square)
			piece_layer.add_child(node)
			pieces[square] = node

func _ground_shadow(origin: Vector3, dimensions: Vector2, softness: float, opacity: float) -> void:
	var shadow = MeshInstance3D.new()
	shadow.name = "GroundContact"
	var plane = PlaneMesh.new()
	plane.size = dimensions+Vector2.ONE*softness*5.0
	shadow.mesh = plane
	shadow.position = origin
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material = ShaderMaterial.new()
	material.shader = preload("res://assets/materials/contact_shadow.gdshader")
	material.set_shader_parameter("footprint",dimensions)
	material.set_shader_parameter("quad_size",plane.size)
	material.set_shader_parameter("pentagon",false)
	material.set_shader_parameter("softness",softness)
	material.set_shader_parameter("opacity",opacity)
	shadow.material_override = material
	board_stage.add_child(shadow)

func _piece(value: int, shadow_surface: float = -1.0) -> Node3D:
	var node = Node3D.new()
	var mesh = MeshInstance3D.new()
	var kind = Rules.base(value)
	mesh.mesh = meshes["king" if kind == 8 and value < 0 else PIECE_KEYS[kind]]
	if absi(value) > 8:
		mesh.rotation.z = PI
		mesh.position.y = HEIGHTS[kind]
	node.add_child(mesh)
	node.rotation.y = PI if value < 0 else 0.0
	var shadow = preload("res://scripts/shogi_contact_shadow.gd").new()
	var widths = [0,.68,.71,.74,.78,.8,.82,.84,.88]
	var depths = [0,.84,.88,.90,.92,.94,.96,.98,1.01]
	shadow.setup(node,Vector2(widths[kind],depths[kind]),shadow_surface)
	node.add_child(shadow)
	return node

func _square_position(square: int) -> Vector3:
	return Scene.square_position(square)

func _display_tokens() -> Array[Dictionary]:
	var ply = game.moves.size() if replay_index < 0 else replay_index
	return HistoryMotion.state(game.positions[0],game.moves,ply)

func _add_hand_counts(tokens: Array, parent: Node3D) -> void:
	_clear_children(parent)
	for group in Hand.layout(tokens).groups.values():
		if group.ids.size() < 2:
			continue
		var number = Label3D.new()
		number.text = str(group.ids.size())
		number.set_meta("hand_group",group.side*group.kind)
		number.font = count_font
		number.font_size = 56
		number.pixel_size = 0.005
		number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		number.modulate = Color("fff8df")
		number.outline_modulate = Color("443d31")
		number.outline_size = 7
		number.position = group.count_position
		number.no_depth_test = true
		parent.add_child(number)

func _refresh_hands() -> void:
	var tokens = _display_tokens()
	_clear_children(hand_models)
	hand_by_id.clear()
	hand_layout = Hand.layout(tokens)
	for group in hand_layout.groups.values():
		var id = group.top
		var pose = hand_layout.poses[id]
		var model = _piece(tokens[id].value)
		model.scale = Vector3.ONE*pose.scale
		model.position = pose.position
		model.rotation.y = pose.rotation
		model.set_meta("hand",absi(tokens[id].value))
		model.set_meta("side",signi(tokens[id].value))
		model.set_meta("token_id",id)
		model.set_meta("rest",pose.position)
		hand_models.add_child(model)
		hand_by_id[id] = model
	_add_hand_counts(tokens,hand_counts)

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _refresh_markers() -> void:
	_clear_children(markers)
	if screen != "game":
		return
	var ply = game.moves.size() if replay_index < 0 else replay_index
	if preferences.last_move and ply > 0:
		var last = game.moves[ply-1]
		if last.from >= 0:
			_mark(last.from,Color(0.9,0.87,0.68,0.13),false)
		_mark(last.to,Color(0.95,0.92,0.67,0.28),false)
	var p = _display_position()
	if p.in_check(p.turn):
		_mark(p.board.find(p.turn*8),Color(0.65,0.21,0.16,0.23),false)
	if selection >= 0:
		_mark(selection,Color(0.96,0.95,0.76,0.44),false)
	if selected_drop > 0 and hand_layout.groups.has(p.turn*selected_drop):
		var group = hand_layout.groups[p.turn*selected_drop]
		var highlight = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = group.bounds.size
		highlight.mesh = plane
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.78,0.86,0.63,0.30)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		highlight.material_override = material
		highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		highlight.position = group.center+Vector3(0,0.005,0)
		markers.add_child(highlight)
	if preferences.hints:
		var seen: Array[int] = []
		for move in legal:
			if (selection >= 0 and move.from == selection) or (selected_drop > 0 and move.drop == selected_drop):
				if move.to not in seen:
					_mark(move.to,Color(0.22,0.34,0.26,0.60),true)
					seen.append(move.to)
	if dragging and drag_hover >= 0:
		_mark(drag_hover,Color(0.8,0.9,0.64,0.4) if not _candidates(drag_hover).is_empty() else Color(0.75,0.3,0.22,0.20),false)
	# A small physical indicator on the active player's stand replaces status text.
	if game.result.is_empty() or replay_index >= 0:
		var stone = MeshInstance3D.new()
		var shape = SphereMesh.new()
		shape.radius = 0.065
		shape.height = 0.045
		stone.mesh = shape
		var material = StandardMaterial3D.new()
		material.albedo_color = Color("f7edd4")
		stone.material_override = material
		stone.position = Scene.tray_center(p.turn)+Vector3(p.turn*(Scene.data.tray_width/2-0.20),0.025,p.turn*(Scene.data.tray_depth/2-0.20))
		markers.add_child(stone)

func _mark(square: int, color: Color, dot: bool) -> void:
	if square < 0:
		return
	var mesh = MeshInstance3D.new()
	if dot:
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.085
		cylinder.bottom_radius = 0.085
		cylinder.height = 0.012
		mesh.mesh = cylinder
	else:
		var plane = PlaneMesh.new()
		plane.size = Vector2(0.93,1.03)
		mesh.mesh = plane
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = dot and _display_position().board[square] != 0
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = _square_position(square)+Vector3(0,0.018,0)
	markers.add_child(mesh)

func _is_ai_turn() -> bool:
	return game.mode == "ai" and game.position.turn != game.human_side

func _can_interact() -> bool:
	return screen == "game" and not busy and ui.modal == null and replay_index < 0 and game.result.is_empty() and not _is_ai_turn() and not (camera_tween != null and camera_tween.is_running())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if pointer_id != -2:
			_cancel_pointer()
		elif ui.modal != null:
			ui.close_modal()
		elif replay_index >= 0:
			_toggle_replay()
		elif screen == "game":
			ui.show_pause()
		else:
			ui.show_home()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pointer_down(event.position,-1)
	elif event is InputEventScreenTouch and event.pressed and not event.canceled:
		_pointer_down(event.position,event.index)

func _input(event: InputEvent) -> void:
	# Release/move are captured before UI routing, even when dragged over a menu.
	if pointer_id == -2:
		return
	if event is InputEventMouseMotion and pointer_id == -1 and event.device != InputEvent.DEVICE_ID_EMULATION:
		_pointer_move(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and pointer_id == -1 and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
		_pointer_up(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == pointer_id:
		_pointer_move(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.index == pointer_id:
		if event.canceled:
			_cancel_pointer()
		elif not event.pressed:
			_pointer_up(event.position)
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		_cancel_pointer()

func _board_hit(point: Vector2, height: float = -1.0) -> Variant:
	return Plane(Vector3.UP,Scene.BOARD_Y if height < 0 else height).intersects_ray(camera.project_ray_origin(point),camera.project_ray_normal(point))

func _square_at(point: Vector2) -> int:
	var hit = _board_hit(point)
	if hit == null:
		return -1
	var col = int(floor(hit.x/Scene.CELL_X+4.5))
	var row = int(floor(hit.z/Scene.CELL_Z+4.5))
	return row*9+col if col >= 0 and col < 9 and row >= 0 and row < 9 else -1

func _hand_at(point: Vector2) -> Node3D:
	var nearest: Node3D
	var distance = INF
	for node in hand_models.get_children():
		if node.get_meta("side") != game.position.turn:
			continue
		var polygon = PackedVector2Array()
		for corner in [Vector3(-0.48,0.20,-0.54),Vector3(0.48,0.20,-0.54),Vector3(0.48,0.20,0.54),Vector3(-0.48,0.20,0.54)]:
			polygon.append(camera.unproject_position(node.transform*corner))
		if Geometry2D.is_point_in_polygon(point,polygon):
			var d = camera.position.distance_squared_to(node.position)
			if d < distance:
				distance = d
				nearest = hand_by_id[hand_layout.groups[game.position.turn*int(node.get_meta("hand"))].top]
	if nearest == null:
		var hit = _board_hit(point,Scene.TRAY_Y)
		if hit != null:
			for group in hand_layout.groups.values():
				if group.side == game.position.turn and group.bounds.has_point(Vector2(hit.x,hit.z)):
					return hand_by_id[group.top]
	return nearest

func _pointer_down(point: Vector2, id: int) -> void:
	if pointer_id != -2 or not _can_interact():
		return
	pointer_id = id
	pointer_start = point
	pointer_eligible = false
	pointer_same_selection = false
	var hand = _hand_at(point)
	var square = _square_at(point)
	if hand != null:
		pointer_same_selection = selected_drop == hand.get_meta("hand")
		_select_hand(hand.get_meta("hand"))
		drag_hand_source = hand
		pointer_eligible = true
	elif square >= 0 and game.position.board[square]*game.position.turn > 0:
		pointer_same_selection = selection == square
		_select_square(square)
		pointer_eligible = true
	get_viewport().set_input_as_handled()

func _pointer_move(point: Vector2) -> void:
	if not _can_interact():
		_cancel_pointer()
		return
	if not dragging and pointer_eligible and point.distance_to(pointer_start) >= (12.0 if pointer_id >= 0 else 8.0):
		if selection_tween != null:
			selection_tween.kill()
		dragging = true
		if selected_drop > 0:
			drag_node = _piece(game.position.turn*selected_drop)
			piece_layer.add_child(drag_node)
			if drag_hand_source != null:
				drag_node.rotation.y = drag_hand_source.rotation.y
				drag_node.set_meta("token_id",drag_hand_source.get_meta("token_id"))
				# A held group is one display object, even when it contains 18 pawns.
				# During a drag it represents the remaining inventory at rest.
				drag_hand_source.visible = hand_layout.groups[game.position.turn*selected_drop].ids.size() > 1
				drag_hand_source.position = drag_hand_source.get_meta("rest")
				var remaining = _display_tokens()
				remaining[drag_hand_source.get_meta("token_id")].value = 0
				_add_hand_counts(remaining,hand_counts)
		else:
			drag_node = pieces[selection]
	if dragging:
		var lifted = _board_hit(point+Vector2(0,-22 if pointer_id >= 0 else -4),Scene.BOARD_Y+0.68)
		if lifted != null:
			drag_node.position = lifted
		var square = _square_at(point)
		if square != drag_hover:
			drag_hover = square
			_refresh_markers()

func _pointer_up(point: Vector2) -> void:
	if pointer_id == -2:
		return
	var was_dragging = dragging
	var same = pointer_same_selection
	var eligible = pointer_eligible
	var distance = point.distance_to(pointer_start)
	var released_position = drag_node.position if drag_node != null else Vector3.INF
	var destination = _square_at(point)
	_cancel_pointer()
	if not _can_interact():
		return
	if was_dragging:
		if not _try_destination(destination,released_position):
			_clear_selection()
	elif distance < 12:
		if eligible:
			if same:
				_clear_selection()
		elif not _try_destination(destination):
			_clear_selection()

func _cancel_pointer() -> void:
	if drag_node != null and is_instance_valid(drag_node):
		if selected_drop > 0:
			drag_node.queue_free()
		elif selection >= 0:
			drag_node.position = _square_position(selection)+Vector3(0,0.11,0)
	if drag_hand_source != null and is_instance_valid(drag_hand_source):
		drag_hand_source.visible = true
		drag_hand_source.position = drag_hand_source.get_meta("rest")+Vector3(0,0.12,0)
		_add_hand_counts(_display_tokens(),hand_counts)
	drag_node = null
	drag_hand_source = null
	pointer_id = -2
	dragging = false
	drag_hover = -1
	if is_node_ready():
		_refresh_markers()

func _candidates(square: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for move in legal:
		if move.to == square and ((selection >= 0 and move.from == selection) or (selected_drop > 0 and move.drop == selected_drop)):
			out.append(move)
	return out

func _try_destination(square: int, from_position: Vector3 = Vector3.INF) -> bool:
	var candidates = _candidates(square)
	if candidates.size() == 2:
		ui.show_promotion(candidates)
	elif candidates.size() == 1:
		_commit(candidates[0],from_position)
	return not candidates.is_empty()

func _select_square(square: int) -> void:
	_clear_selection()
	selection = square
	if pieces.has(square):
		selection_tween = create_tween()
		selection_tween.tween_property(pieces[square],"position:y",Scene.BOARD_Y+0.12,0.10)
	_refresh_markers()

func _select_hand(kind: int) -> void:
	_clear_selection()
	selected_drop = kind
	var group = hand_layout.groups.get(game.position.turn*kind)
	if group != null:
		var top = hand_by_id[group.top]
		selection_tween = create_tween()
		selection_tween.tween_property(top,"position:y",top.get_meta("rest").y+0.12,0.10)
	_refresh_markers()

func _clear_selection() -> void:
	if selection_tween != null:
		selection_tween.kill()
	if selection >= 0 and pieces.has(selection):
		pieces[selection].position = _square_position(selection)
	for hand in hand_models.get_children():
		hand.position = hand.get_meta("rest")
	selection = -1
	selected_drop = 0
	_refresh_markers()

func _motion_steps(initial: ShogiRules, moves: Array, source: int, target: int, position: ShogiRules) -> Array:
	var steps: Array = []
	for tracks in HistoryMotion.stages(initial,moves,source,target):
		steps.append({"position":position,"tracks":tracks})
	return steps

func _commit(move: Dictionary, from_position: Vector3 = Vector3.INF) -> void:
	if screen != "game" or busy or replay_index >= 0:
		return
	var source = game.moves.size()
	var position = game.position.copy()
	if not game.play(move):
		return
	revision += 1
	_save()
	var steps = _motion_steps(game.positions[0],game.moves,source,source+1,position)
	var mover_id = -1
	var held_pose: Dictionary = {}
	for track in steps.back().tracks:
		if track.after.square == move.to and track.before.square != move.to:
			mover_id = track.id
			held_pose = track.start_pose.duplicate()
			break
	if mover_id >= 0:
		var source_node = hand_by_id.get(mover_id) if move.drop else pieces.get(move.from)
		if source_node != null:
			held_pose.position = source_node.position
			held_pose.rotation = source_node.rotation.y
		if from_position.is_finite():
			held_pose.position = from_position
			held_pose.scale = 1.0
		for step in steps:
			for track in step.tracks:
				if track.id == mover_id:
					track.start = held_pose.position
					track.start_pose = held_pose.duplicate()
					if track.after.square == track.before.square:
						track.end = held_pose.position
						track.end_pose = held_pose.duplicate()
	_begin_history(steps,func():
		if game.mode == "local" and preferences.auto_flip:
			flipped = game.position.turn == -1
			_update_camera(true)
		if not game.result.is_empty():
			ui.show_result()
	)

func _ai_allowed() -> bool:
	return screen == "game" and ui.modal == null and replay_index < 0 and not busy and game.result.is_empty() and _is_ai_turn()

func _process(_delta: float) -> void:
	if thread != null and thread.is_started() and not thread.is_alive():
		var response = thread.wait_to_finish()
		thread = null
		ai_engine = null
		if ai_revision == revision and _ai_allowed() and response is Dictionary and response.has("move"):
			_commit(response.move)
	if not testing and thread == null and _ai_allowed():
		ai_revision = revision
		thread = Thread.new()
		ai_engine = AI.new()
		var error = thread.start(ai_engine.choose.bind(game.position.copy(),300 if game.difficulty == 0 else 900,1 if game.difficulty == 0 else 3))
		if error != OK:
			thread = null
			_commit(legal[0])

func _exit_tree() -> void:
	if thread != null and thread.is_started():
		thread.wait_to_finish()

func _undo() -> void:
	if busy or replay_index >= 0 or (game.mode == "ai" and game.human_side == -1 and game.moves.size() <= 1):
		return
	revision += 1
	_cancel_pointer()
	var source = game.moves.size()
	var old_moves = game.moves.duplicate(true)
	var old_positions = game.positions.duplicate()
	game.undo()
	_save()
	var steps: Array = []
	for ply in range(source,game.moves.size(),-1):
		steps.append_array(_motion_steps(old_positions[0],old_moves,ply,ply-1,old_positions[ply]))
	_begin_history(steps,func():
		if game.mode == "local" and preferences.auto_flip:
			flipped = game.position.turn == -1
			_update_camera(true)
	)

func _begin_history(steps: Array, finished: Callable) -> void:
	_clear_selection()
	history_steps = steps
	history_finished = finished
	busy = true
	piece_layer.visible = false
	hand_models.visible = false
	hand_counts.visible = false
	_clear_children(markers)
	ui.refresh()
	_run_history_step()

func _run_history_step() -> void:
	if history_layer != null:
		history_layer.queue_free()
		history_layer = null
	if history_steps.is_empty():
		history_position = null
		piece_layer.visible = true
		hand_models.visible = true
		hand_counts.visible = true
		_clear_children(history_counts)
		busy = false
		var finished = history_finished
		history_finished = Callable()
		finished.call()
		_refresh()
		return
	var step = history_steps.pop_front()
	history_position = step.position
	history_layer = Node3D.new()
	add_child(history_layer)
	active_tween = create_tween().set_parallel(true)
	var count_tokens: Array = []
	for track in step.tracks:
		var token = track.before.duplicate()
		if token.square < 0 and (track.after.square >= 0 or token.value != track.after.value):
			token.value = 0
		count_tokens.append(token)
	_add_hand_counts(count_tokens,history_counts)
	var resting_groups = Hand.layout(count_tokens).groups
	var final_tokens: Array = []
	for track in step.tracks:
		final_tokens.append(track.after)
	var final_groups = Hand.layout(final_tokens).groups
	var moving_count = 0
	for track in step.tracks:
		var changed = track.start_pose != track.end_pose or track.before.value != track.after.value
		if not changed and track.before.square < 0 and resting_groups[track.before.value].top != track.id:
			continue
		var node = _piece(track.before.value)
		node.set_meta("token_id",track.id)
		node.set_meta("history_from",track.before.square)
		node.set_meta("history_to",track.after.square)
		history_layer.add_child(node)
		node.position = track.start
		node.scale = Vector3.ONE*track.start_pose.scale
		node.rotation.y = track.start_pose.rotation
		# Replace the old representative at contact; never leave coincident
		# duplicate models on a stand after captures or multi-ply replay jumps.
		if track.after.square < 0 and final_groups[track.after.value].top != track.id:
			active_tween.tween_callback(node.hide).set_delay(0.435)
		if not changed:
			continue
		moving_count += 1
		if track.before.square < 0 and track.after.square < 0 and track.before.value == track.after.value:
			active_tween.tween_property(node,"position",track.end,0.18).set_trans(Tween.TRANS_SINE)
			active_tween.tween_property(node,"rotation:y",track.end_pose.rotation,0.18)
			continue
		var raised = maxf(track.start.y,track.end.y)+0.65
		active_tween.tween_property(node,"position",Vector3(track.start.x,raised,track.start.z),0.10).set_trans(Tween.TRANS_SINE)
		active_tween.tween_property(node,"position",Vector3(track.end.x,raised,track.end.z),0.22).set_delay(0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		active_tween.tween_property(node,"position",track.end,0.12).set_delay(0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		active_tween.tween_property(node,"scale",Vector3.ONE*track.end_pose.scale,0.22).set_delay(0.10)
		active_tween.tween_property(node,"rotation:y",track.end_pose.rotation,0.22).set_delay(0.10)
		var promoted = absi(track.after.value) > 8
		active_tween.tween_property(node.get_child(0),"rotation:z",PI if promoted else 0.0,0.22).set_delay(0.10)
		active_tween.tween_property(node.get_child(0),"position:y",HEIGHTS[Rules.base(track.after.value)] if promoted else 0.0,0.22).set_delay(0.10)
	if moving_count == 0:
		active_tween.tween_interval(0.01)
	else:
		active_tween.chain().tween_callback(_play_sound)
	active_tween.chain().tween_callback(_run_history_step)

func _flip() -> void:
	_cancel_pointer()
	flipped = not flipped
	_update_camera(true)

func _set_replay(index: int) -> void:
	if busy:
		return
	revision += 1
	_cancel_pointer()
	var source = game.moves.size() if replay_index < 0 else replay_index
	var target = clampi(index,0,game.moves.size())
	replay_index = source
	if source == target:
		_refresh()
		return
	var steps = _motion_steps(game.positions[0],game.moves,source,target,game.positions[source])
	_begin_history(steps,func(): replay_index = target)

func _toggle_replay() -> void:
	if busy:
		return
	revision += 1
	_cancel_pointer()
	if replay_index < 0:
		replay_index = game.moves.size()
		_refresh()
	elif replay_index == game.moves.size():
		replay_index = -1
		_refresh()
	else:
		var steps = _motion_steps(game.positions[0],game.moves,replay_index,game.moves.size(),game.positions[replay_index])
		_begin_history(steps,func(): replay_index = -1)

func _go_home() -> void:
	if busy:
		return
	revision += 1
	_cancel_pointer()
	screen = "home"
	replay_index = -1
	_refresh()
	_update_camera()

func _resume_game() -> void:
	screen = "game"
	flipped = game.human_side == -1 if game.mode == "ai" else (preferences.auto_flip and game.position.turn == -1)
	ui.show_game()
	_refresh()
	_update_camera(true)

func _start_game(mode: String, human_side: int = 1, difficulty: int = 1) -> void:
	revision += 1
	_cancel_pointer()
	game = Game.new()
	game.mode = mode
	game.human_side = (1 if randi()%2 else -1) if human_side == 0 else human_side
	game.difficulty = difficulty
	has_game = true
	replay_index = -1
	_save()
	_resume_game()

func _resign() -> void:
	revision += 1
	game.resign()
	_save()
	_refresh()
	ui.show_result()

func _save() -> void:
	if testing or "--ui-test" in OS.get_cmdline_user_args():
		return
	last_save_error = game.save_to(SAVE_PATH)
	if last_save_error != OK:
		var column = ui.dialog("保存未成功")
		column.add_child(ui.label("请检查可用存储空间。",18))

func _preference(key: String, value: Variant) -> void:
	preferences.set(key,value)
	if not testing and "--ui-test" not in OS.get_cmdline_user_args():
		if preferences.save_to() != OK:
			push_warning("Preferences could not be saved")
	coordinate_layer.visible = preferences.coordinates and screen == "game"
	_refresh_markers()

func _play_sound(preview: bool = false) -> void:
	if (preferences.sound or preview) and preferences.volume > 0:
		audio_player.volume_db = -1.0+linear_to_db(preferences.volume)
		audio_player.play()
