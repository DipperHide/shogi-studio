extends SubViewportContainer
## An independent, disposable showroom: no game input or AI state lives here.
signal chosen(index: int)
var viewport: SubViewport
var preview: SubViewport
var preview_camera: Camera3D
var ring: MeshInstance3D
var selected = 1
var spacing = SPACING
var objects: Array[Node3D] = []
var pointer_start = Vector2.ZERO
var pointer_active = false
var ring_tween: Tween
const SPACING = 6.8
const BG = Color("e4e7dc")

func setup(app) -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280,370)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world = Node3D.new()
	viewport.add_child(world)
	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = BG
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.50
	world.add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-28,0)
	light.light_energy = 1.05
	light.shadow_enabled = false
	light.shadow_bias = 0.045
	light.shadow_normal_bias = 0.15
	light.directional_shadow_max_distance = 35
	light.shadow_blur = 2.5
	light.shadow_opacity = 0.36
	world.add_child(light)
	var floor_mesh = PlaneMesh.new()
	floor_mesh.size = Vector2(90,90)
	var floor_node = MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_node.material_override = material(BG,true)
	world.add_child(floor_node)
	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11.54
	camera.v_offset = 2.16
	camera.position = Vector3(0,11,12)
	world.add_child(camera)
	camera.look_at(Vector3(0,0.4,0))
	var saved = Node3D.new()
	saved.position.x = -SPACING
	world.add_child(saved)
	var source = preload("res://assets/shogi-scene.glb").instantiate()
	for child in source.get_children():
		if str(child.name).begins_with("Board"):
			child.owner = null
			source.remove_child(child)
			saved.add_child(child)
			app._retone(child)
	source.free()
	for square in range(81):
		if app.game.position.board[square] != 0:
			var piece = app._piece(app.game.position.board[square],app.Scene.data.board_top*0.26+0.003)
			piece.position = app._square_position(square)
			saved.add_child(piece)
	saved.scale = Vector3.ONE*0.26
	var ai = Node3D.new()
	world.add_child(ai)
	var monitor = box(Vector3(1.8,1.22,0.16),Color("526761"))
	monitor.position = Vector3(0.43,1.14,-0.15)
	ai.add_child(monitor)
	var screen = box(Vector3(1.57,0.94,0.04),Color("cad6c1"))
	screen.position = Vector3(0.43,1.17,-0.045)
	ai.add_child(screen)
	var stem = box(Vector3(0.17,0.38,0.17),Color("526761"))
	stem.position = Vector3(0.43,0.38,-0.15)
	ai.add_child(stem)
	var foot = box(Vector3(0.85,0.12,0.58),Color("526761"))
	foot.position = Vector3(0.43,0.1,0)
	ai.add_child(foot)
	var pawn = app._piece(1,0.006)
	pawn.scale = Vector3.ONE*2.2
	pawn.position = Vector3(-0.78,0.1,0.5)
	ai.add_child(pawn)
	# A tiny board motif on the screen keeps the computer object specific to shogi.
	for col in range(3):
		for row in range(2):
			var pixel = box(Vector3(0.13,0.13,0.03),Color("698479"))
			pixel.position = Vector3(0.05+col*0.38,1.0+row*0.32,-0.016)
			ai.add_child(pixel)
	var local = Node3D.new()
	local.position.x = SPACING
	world.add_child(local)
	for side in [-1,1]:
		var king = app._piece(side*8,0.006)
		king.scale = Vector3.ONE*2.25
		king.position = Vector3(side*0.67,0.08,side*0.5)
		king.rotation.y += side*0.12
		local.add_child(king)
	ring = MeshInstance3D.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(128):
		if i%32 < 3:
			continue
		var a = TAU*i/128.0
		var b = TAU*(i+1)/128.0
		for item in [[a,1.73],[b,1.73],[b,1.78],[a,1.73],[b,1.78],[a,1.78]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(cos(item[0])*item[1],0.025,sin(item[0])*item[1]))
	ring.mesh = st.commit()
	ring.material_override = material(Color("b83d30"),true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ring)
	preview = SubViewport.new()
	preview.size = Vector2i(400,230)
	preview.world_3d = viewport.find_world_3d()
	preview.msaa_3d = Viewport.MSAA_4X
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var preview_holder = Node.new()
	add_child(preview_holder)
	preview_holder.add_child(preview)
	preview_camera = Camera3D.new()
	preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	preview_camera.size = 3.3
	preview.add_child(preview_camera)
	objects = [saved,ai,local]
	for object in objects:
		var shadow = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(5.4,4.2)
		shadow.mesh = plane
		shadow.top_level = true
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shade = ShaderMaterial.new()
		shade.shader = preload("res://assets/materials/contact_shadow.gdshader")
		shade.set_shader_parameter("pentagon",false)
		shade.set_shader_parameter("footprint",Vector2(2.5,1.6))
		shade.set_shader_parameter("quad_size",plane.size)
		shade.set_shader_parameter("softness",0.55)
		shade.set_shader_parameter("opacity",0.15)
		shadow.material_override = shade
		object.add_child(shadow)
		shadow.set_meta("showroom_shadow",true)
	resized.connect(layout_objects)
	select(0 if app.has_game else 1,false)

static func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var result = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.78
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return result

static func box(dimensions: Vector3, color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var shape = BoxMesh.new()
	shape.size = dimensions
	node.mesh = shape
	node.material_override = material(color)
	return node

func select(index: int, animate: bool = true) -> void:
	selected = index
	var x = (index-1)*spacing
	if ring_tween != null:
		ring_tween.kill()
	if animate:
		ring_tween = create_tween()
		ring_tween.tween_property(ring,"position:x",x,0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		ring.position.x = x
	preview_camera.position = Vector3(x,6,8)
	preview_camera.look_at(Vector3(x,0.65,0))

func layout_objects() -> void:
	if size.y <= 0 or objects.is_empty():
		return
	spacing = 11.54*size.x/size.y/3.0
	for index in range(3):
		objects[index].position.x = (index-1)*spacing
		for child in objects[index].get_children():
			if child.has_meta("showroom_shadow"):
				child.global_position = Vector3((index-1)*spacing+0.28,0.004,0.24)
	select(selected,false)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed:
			pointer_start = event.position
			pointer_active = true
		elif pointer_active:
			finish_pointer(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			pointer_start = event.position
			pointer_active = true
		elif not event.canceled and pointer_active:
			finish_pointer(event.position)
		else:
			pointer_active = false
	elif event is InputEventKey and event.pressed:
		if event.keycode in [KEY_LEFT,KEY_RIGHT]:
			chosen.emit(clampi(selected+(-1 if event.keycode==KEY_LEFT else 1),0,2))
		elif event.keycode in [KEY_ENTER,KEY_SPACE]:
			chosen.emit(selected)

func finish_pointer(point: Vector2) -> void:
	pointer_active = false
	if absf(point.x-pointer_start.x)>40:
		chosen.emit(clampi(selected+(-1 if point.x>pointer_start.x else 1),0,2))
	else:
		chosen.emit(clampi(int(point.x/size.x*3),0,2))
