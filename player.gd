class_name Player
extends CharacterBody3D

## First-person creative controller for the voxel sandbox.
## Walk (WASD), jump (Space), toggle fly (F), pick block colour (1-5),
## break block (Left Mouse), place block (Right Mouse), release mouse (Esc).

const WALK_SPEED := 6.0
const FLY_SPEED := 10.0
const JUMP_VELOCITY := 5.0
const MOUSE_SENS := 0.0025
const REACH := 6.0

var world: VoxelWorld
var camera: Camera3D
var ray: RayCast3D
var flying := false
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

var palette: Array[Color] = [
	Color(0.85, 0.22, 0.22),  # red
	Color(0.22, 0.52, 0.90),  # blue
	Color(0.95, 0.80, 0.20),  # yellow
	Color(0.32, 0.78, 0.34),  # green
	Color(0.92, 0.92, 0.92),  # white
]
var selected := 0
var hotbar_label: Label

func _ready() -> void:
	# Body collider
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.4
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	# Eye camera
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	add_child(camera)

	# Forward raycast for break/place targeting
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.enabled = true
	camera.add_child(ray)
	ray.add_exception(self)

	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-6, -16)
	layer.add_child(cross)

	var help := Label.new()
	help.text = "WASD move   Space jump   F fly   1-5 colour   LMB break   RMB place   Esc release mouse"
	help.position = Vector2(14, 10)
	layer.add_child(help)

	hotbar_label = Label.new()
	hotbar_label.position = Vector2(14, 36)
	layer.add_child(hotbar_label)
	_update_hotbar()

func _update_hotbar() -> void:
	var names := ["Red", "Blue", "Yellow", "Green", "White"]
	if hotbar_label:
		hotbar_label.text = "Block: %s  (%d/5)%s" % [names[selected], selected + 1, "   [FLYING]" if flying else ""]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clampf(camera.rotation.x, -1.5, 1.5)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_break_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_place_block()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				flying = not flying
				if flying:
					velocity = Vector3.ZERO
				_update_hotbar()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				selected = event.keycode - KEY_1
				_update_hotbar()

func _physics_process(delta: float) -> void:
	var input_dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): input_dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S): input_dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1.0
	var dir := (transform.basis * input_dir).normalized()

	if flying:
		var v := dir * FLY_SPEED
		if Input.is_physical_key_pressed(KEY_SPACE): v.y += FLY_SPEED
		if Input.is_physical_key_pressed(KEY_SHIFT): v.y -= FLY_SPEED
		velocity = v
	else:
		velocity.x = dir.x * WALK_SPEED
		velocity.z = dir.z * WALK_SPEED
		if not is_on_floor():
			velocity.y -= gravity * delta
		elif Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP_VELOCITY

	move_and_slide()

func _break_block() -> void:
	if world == null or not ray.is_colliding():
		return
	var body := ray.get_collider()
	if body and body.has_meta("cell"):
		world.remove_block(body.get_meta("cell"))

func _place_block() -> void:
	if world == null or not ray.is_colliding():
		return
	var body := ray.get_collider()
	if body == null or not body.has_meta("cell"):
		return
	var cell: Vector3i = body.get_meta("cell")
	var normal: Vector3 = ray.get_collision_normal()
	var target: Vector3i = cell + Vector3i(normal.round())
	world.add_block(target, palette[selected])
