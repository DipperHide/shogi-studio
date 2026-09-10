extends Node3D
## Wooden board renderer. The shared application owns rules, clocks and input.
const Rules = preload("res://scripts/shogi_rules.gd")
const HistoryMotion = preload("res://scripts/shogi_history_motion.gd")
const Scene = preload("res://scripts/shogi_scene_layout.gd")
const Hand = preload("res://scripts/shogi_hand_layout.gd")
const PIECE_KEYS = ["", "pawn", "lance", "knight", "silver", "gold", "bishop", "rook", "jewel"]
const HEIGHTS = [0.0,0.16,0.17,0.18,0.19,0.2,0.21,0.215,0.23]
var app
var camera: Camera3D
var meshes: Dictionary = {}
var pieces: Dictionary = {}
var board_stage = Node3D.new()
var piece_layer = Node3D.new()
var markers = Node3D.new()
var hand_models = Node3D.new()
var hand_counts = Node3D.new()
var history_counts = Node3D.new()
var coordinate_layer = Node3D.new()
var hand_layout: Dictionary = {}
var hand_by_id: Dictionary = {}
var count_font: FontVariation
var portrait: bool = false
var tray_nodes: Array = []
var world_env: WorldEnvironment
var sunlight: DirectionalLight3D
var animated_layer = Node3D.new()
var animated_nodes: Dictionary = {}
var last_selection_key: String = ""
var dragged_node: Node3D
var drag_rest = Vector3.ZERO

func _ready() -> void:
	_build_world()
	add_child(animated_layer)
	apply_lighting()
	layout_board()
	sync()

func _display_position() -> ShogiRules:
	return app._display_position()

func _display_tokens() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(app._view_tokens())
	return result

func tray_offset(side: int) -> Vector3:
	return Vector3(side * (2.8 - Scene.data.tray_x), 0, side * (7.8 - Scene.data.tray_z)) if portrait else Vector3.ZERO

func tray_position(position: Vector3, side: int) -> Vector3:
	return position + tray_offset(side)

func adapt_hand_layout() -> void:
	for group in hand_layout.groups.values():
		var offset = tray_offset(group.side)
		group.center += offset
		group.count_position += offset
		group.bounds.position += Vector2(offset.x, offset.z)
		for id in group.ids: hand_layout.poses[id].position += offset

func layout_board() -> void:
	if camera == null: return
	# HUD and flat captured-piece trays share the same footprint as the 2D view.
	# Fit the 3D board itself instead of reserving space for decorative tray tables.
	for node in tray_nodes: node.visible = false
	var usable: Rect2 = app.board_rect
	# A 25-degree view makes the rectangular shogi board read almost square.
	# Fit the projected top, preserving the physical proportions of every piece.
	camera.size = maxf(9.85 * app.size.y / usable.size.x, 9.85 * app.size.y / usable.size.y)
	var target = Vector3(0, Scene.BOARD_Y, 0)
	var eye = target + Vector3(0, 30, -14.0 if app.flipped else 14.0)
	camera.transform = Transform3D(Basis.IDENTITY, eye).looking_at(target, Vector3(0, 0, 1 if app.flipped else -1))
	camera.position += camera.basis.y * ((usable.get_center().y - app.size.y / 2) * camera.size / app.size.y)
	camera.position -= camera.basis.x * ((usable.get_center().x - app.size.x / 2) * camera.size / app.size.y)

func apply_lighting() -> void:
	if world_env == null: return
	world_env.environment.background_color = app.palette().background
	world_env.environment.ambient_light_energy = 0.70 if app.dark else 0.76
	sunlight.light_energy = 1.25 if app.dark else 1.35
	sunlight.light_color = Color("fff4dc") if app.dark else Color("fff9ef")

func sync() -> void:
	if camera == null: return
	if not app.transition.is_empty():
		animate_tracks(app.transition, app.motion_progress)
		return
	_clear_children(animated_layer)
	animated_nodes.clear()
	piece_layer.visible = true
	hand_models.visible = true
	_rebuild_pieces()
	_refresh_hands()
	coordinate_layer.visible = app.preferences.coordinates
	last_selection_key = ""
	update_selection()
	hand_models.visible = false
	hand_counts.visible = false
	history_counts.visible = false

func update_selection() -> void:
	if camera == null: return
	var viewed = app._view_game()
	var ply: int = viewed.moves.size() if app.replay_index < 0 else app.replay_index
	var key = str([app.selection, app.selected_drop, ply, app.preferences.hints, app.preferences.last_move, app.dark, app.keyboard_square, _display_position().key()])
	if last_selection_key == key: return
	last_selection_key = key
	_clear_children(markers)
	if app.preferences.last_move and ply > 0:
		var last: Dictionary = viewed.moves[ply - 1]
		if last.from >= 0: _mark(last.from, Color(0.72, 0.8, 0.6, 0.16), false)
		_mark(last.to, Color(0.72, 0.85, 0.61, 0.40), false)
	if app.selection >= 0: _mark(app.selection, Color(0.8, 0.94, 0.65, 0.45), false)
	if app.preferences.hints:
		var seen: Dictionary = {}
		for move in app.legal:
			if ((app.selection >= 0 and move.from == app.selection) or (app.selected_drop > 0 and move.drop == app.selected_drop)) and not seen.has(move.to):
				seen[move.to] = true
				_mark(move.to, Color(0.24, 0.4, 0.2, 0.8), true)
	for square in app.checked_cells:
		_mark(square, app.palette().danger_fill, false)
	for square in pieces:
		pieces[square].position.y = Scene.BOARD_Y + (0.18 if square == app.selection else 0.0)
		pieces[square].get_node("PieceContact").sync_pose()
	for node in hand_models.get_children():
		node.position = node.get_meta("rest") + Vector3(0, 0.18 if node.get_meta("side") == _display_position().turn and node.get_meta("hand") == app.selected_drop else 0.0, 0)

func square_at(point: Vector2) -> int:
	var origin = camera.project_ray_origin(point)
	var direction = camera.project_ray_normal(point)
	var hit = Plane(Vector3.UP, Scene.BOARD_Y).intersects_ray(origin, direction)
	if hit == null: return -1
	var x = int(floor(hit.x / Scene.CELL_X + 4.5))
	var y = int(floor(hit.z / Scene.CELL_Z + 4.5))
	return y * 9 + x if x >= 0 and x < 9 and y >= 0 and y < 9 else -1

func update_drag() -> void:
	if not app.pointer_moved or (app.drag_source < 0 and app.drag_drop == 0):
		if is_instance_valid(dragged_node):
			dragged_node.position = drag_rest
			dragged_node.get_node("PieceContact").sync_pose()
		dragged_node = null
		return
	if not is_instance_valid(dragged_node):
		dragged_node = pieces.get(app.drag_source)
		if app.drag_drop > 0:
			for node in hand_models.get_children():
				if node.get_meta("hand") == app.drag_drop and node.get_meta("side") == _display_position().turn:
					dragged_node = node
					break
		if dragged_node == null: return
		drag_rest = dragged_node.position
	var hit = Plane(Vector3.UP, Scene.BOARD_Y + 0.35).intersects_ray(camera.project_ray_origin(app.pointer_current), camera.project_ray_normal(app.pointer_current))
	if hit != null:
		dragged_node.position = hit
		dragged_node.get_node("PieceContact").sync_pose()

func square_rect(square: int) -> Rect2:
	var center = _square_position(square)
	var extent = Vector3(Scene.CELL_X / 2, 0, Scene.CELL_Z / 2)
	return projected_rect(center - extent, center + extent)

func projected_rect(a: Vector3, b: Vector3) -> Rect2:
	var rect = Rect2(camera.unproject_position(a), Vector2.ZERO)
	for point in [b, Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, a.z)]: rect = rect.expand(camera.unproject_position(point))
	return rect

func hand_rect(side: int, kind: int) -> Rect2:
	var center = tray_position(Hand.center(side, kind), side)
	return projected_rect(center - Vector3(0.52, 0, 0.55), center + Vector3(0.52, 0, 0.55)).grow(3)

func animate_tracks(tracks: Array, progress: float) -> void:
	if tracks.is_empty(): return
	if animated_nodes.is_empty():
		piece_layer.visible = false
		hand_models.visible = false
		for track in tracks:
			# Captured pieces are represented by the shared 2D hand strip.
			if track.before.square < 0 and track.after.square < 0: continue
			var node = _piece(track.before.value)
			animated_layer.add_child(node)
			animated_nodes[track.id] = node
	for track in tracks:
		if not animated_nodes.has(track.id): continue
		var node: Node3D = animated_nodes[track.id]
		var start: Vector3 = track.get("visual_start", _motion_position(track.before, track.start))
		var finish: Vector3 = _motion_position(track.after, track.end)
		var moving: bool = start != finish or track.before.value != track.after.value
		node.position = start.lerp(finish, progress) + Vector3(0, sin(progress * PI) * 0.38 if moving and not track.has("visual_start") else 0.0, 0)
		node.rotation.y = lerp_angle(track.start_pose.rotation, track.end_pose.rotation, progress)
		var promoted: bool = absi(track.after.value) > 8
		node.get_child(0).rotation.z = lerp(PI if absi(track.before.value) > 8 else 0.0, PI if promoted else 0.0, progress)
		node.get_child(0).position.y = lerp(HEIGHTS[Rules.base(track.before.value)] if absi(track.before.value) > 8 else 0.0, HEIGHTS[Rules.base(track.after.value)] if promoted else 0.0, progress)
		node.scale = Vector3.ONE * lerpf(0.001 if track.before.square < 0 else 1.0, 0.001 if track.after.square < 0 else 1.0, progress)
		node.get_node("PieceContact").sync_pose()

func _motion_position(token: Dictionary, board_position: Vector3) -> Vector3:
	if token.square >= 0: return board_position
	var point: Vector2 = app.hand_slot(signi(token.value), Rules.base(token.value)).get_center()
	var hit = Plane(Vector3.UP, Scene.BOARD_Y).intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))
	return hit if hit != null else board_position

func _build_world() -> void:
	count_font = FontVariation.new()
	count_font.base_font = preload("res://assets/fonts/NotoSansSC.ttf")
	count_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):520.0}
	var model = load("res://assets/shogi-scene.glb").instantiate()
	add_child(board_stage)
	board_stage.add_child(model)
	for child in model.get_children():
		if str(child.name).begins_with("Komadai"):
			child.set_meta("original_position", child.position)
			child.set_meta("side", signi(child.position.x))
			tray_nodes.append(child)
		if child is MeshInstance3D:
			_retone(child)
		if str(child.name).begins_with("Tatami environment"):
			child.visible = false
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
	world_env = world
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("e9dfc7")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fffdf6")
	environment.ambient_light_energy = 0.52
	# Color ambient lighting needs no cubemap; switching skins releases all 3D resources.
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = environment
	add_child(world)
	var sun = DirectionalLight3D.new()
	sunlight = sun
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
	if absf(origin.x) > 4.8:
		shadow.set_meta("original_position", origin)
		shadow.set_meta("side", signi(origin.x))
		tray_nodes.append(shadow)

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
		number.position = tray_position(group.count_position, group.side)
		number.no_depth_test = true
		parent.add_child(number)

func _refresh_hands() -> void:
	var tokens = _display_tokens()
	_clear_children(hand_models)
	hand_by_id.clear()
	hand_layout = Hand.layout(tokens)
	adapt_hand_layout()
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
	mesh.position = _square_position(square)+Vector3(0,0.018 + markers.get_child_count() * 0.0004,0)
	markers.add_child(mesh)

