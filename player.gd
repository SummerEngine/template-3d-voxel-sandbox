class_name Player
extends CharacterBody3D

## First-person creative controller for the voxel sandbox.
## Walk/sprint (WASD/Shift), jump (Space), toggle fly (F), pick block colour (1-5),
## break (LMB), place (RMB). Has hearts (health) with fall damage + void respawn.
## Esc is NOT handled here — the PauseMenu owns it.

const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.0
const FLY_SPEED := 10.0
const JUMP_VELOCITY := 5.0
const MOUSE_SENS := 0.0025
const REACH := 6.0
const FALL_DAMAGE_SPEED := 16.0   # landing faster than this costs hearts
const VOID_Y := -20.0

var hud                            # HUD CanvasLayer (assigned by main.gd)
var world_manager                  # ChunkManager (assigned by main.gd)
var camera: Camera3D
var ray: RayCast3D
var flying := false
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

var max_health := 6
var health := 6
var spawn_point := Vector3(0, 4, 0)
var _was_on_floor := true
var _fall_speed := 0.0

# Block types the player can place (ids from VoxelTypes).
var block_types := [VoxelTypes.GRASS, VoxelTypes.DIRT, VoxelTypes.STONE, VoxelTypes.LAVA]
var block_names := ["Grass", "Dirt", "Stone", "Lava"]
var selected := 0

func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.4
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	camera = Camera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	add_child(camera)

	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.enabled = true
	camera.add_child(ray)
	ray.add_exception(self)

	spawn_point = global_position
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_hud()

func _update_hud() -> void:
	if hud:
		hud.set_health(health, max_health)
		hud.set_block(block_names[selected], selected + 1, block_types.size())

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
			KEY_1, KEY_2, KEY_3, KEY_4:
				selected = event.keycode - KEY_1
				_update_hud()

func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()

	# Fall damage on landing
	if on_floor and not _was_on_floor and _fall_speed > FALL_DAMAGE_SPEED:
		var dmg := int((_fall_speed - FALL_DAMAGE_SPEED) / 4.0) + 1
		_take_damage(dmg)
	_was_on_floor = on_floor

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
		var speed := SPRINT_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		if not on_floor:
			velocity.y -= gravity * delta
		elif Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP_VELOCITY

	_fall_speed = maxf(0.0, -velocity.y)
	move_and_slide()

	if global_position.y < VOID_Y:
		_take_damage(max_health)   # fell off the world -> respawn at full

func _take_damage(amount: int) -> void:
	if amount <= 0:
		return
	health -= amount
	if health <= 0:
		health = max_health
		_respawn()
	_update_hud()

func _respawn() -> void:
	velocity = Vector3.ZERO
	global_position = spawn_point
	_fall_speed = 0.0
	_was_on_floor = true

func _break_block() -> void:
	if world_manager == null or not ray.is_colliding():
		return
	var cell := _cell_from_hit(-0.5)   # step into the hit block
	world_manager.set_block(cell.x, cell.y, cell.z, VoxelTypes.AIR)

func _place_block() -> void:
	if world_manager == null or not ray.is_colliding():
		return
	var cell := _cell_from_hit(0.5)    # step out to the empty neighbour cell
	world_manager.set_block(cell.x, cell.y, cell.z, block_types[selected])

func _cell_from_hit(offset: float) -> Vector3i:
	var p := ray.get_collision_point()
	var nrm := ray.get_collision_normal()
	var inside := p + nrm * offset
	return Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))
