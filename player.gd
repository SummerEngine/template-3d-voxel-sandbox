class_name Player
extends CharacterBody3D

## Third-person creative controller (single-player).
## Orbit camera (mouse), camera-relative move, sprint/jump/fly, break/place at screen
## centre. Shows the character model from assets/models/player_animated.glb and drives
## idle/walk/mine clips if present. Hearts with fall damage (first landing free).

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const FLY_SPEED := 10.0
const JUMP_VELOCITY := 5.0
const MOUSE_SENS := 0.0025
const REACH := 6.0
const FALL_DAMAGE_SPEED := 16.0
const VOID_Y := -40.0

const CAM_HEIGHT := 1.5
const CAM_DISTANCE := 4.5
const PITCH_MIN := -1.2
const PITCH_MAX := 0.6
const TURN_SPEED := 12.0

# Character model tuning — tweak if it's the wrong size or faces backwards.
const MODEL_PATH := "res://assets/models/player_animated.glb"
const MODEL_SCALE := 1.0
const MODEL_YAW_OFFSET := PI   # most GLB chars face -Z; set 0 if it faces backwards

var hud
var world_manager

var yaw_pivot: Node3D
var pitch_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var ray: RayCast3D
var model: Node3D
var anim_player: AnimationPlayer

var idle_anim := ""
var walk_anim := ""
var mine_anim := ""

var flying := false
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _mine_timer := 0.0

var max_health := 6
var health := 6
var spawn_point := Vector3(0, 4, 0)
var _was_on_floor := true
var _fall_speed := 0.0
var _landed_once := false

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

	yaw_pivot = Node3D.new()
	yaw_pivot.position = Vector3(0, CAM_HEIGHT, 0)
	add_child(yaw_pivot)
	pitch_pivot = Node3D.new()
	yaw_pivot.add_child(pitch_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = CAM_DISTANCE
	spring.add_excluded_object(get_rid())
	pitch_pivot.add_child(spring)
	camera = Camera3D.new()
	spring.add_child(camera)

	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -(CAM_DISTANCE + REACH))
	ray.enabled = true
	ray.add_exception(self)
	camera.add_child(ray)

	_setup_model()

	spawn_point = global_position
	_landed_once = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_hud()

func _setup_model() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		push_warning("Player model missing: " + MODEL_PATH)
		return
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		return
	model = packed.instantiate() as Node3D
	if model == null:
		return
	model.scale = Vector3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE)
	add_child(model)
	anim_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player:
		idle_anim = _find_anim(["idle"])
		walk_anim = _find_anim(["walk"])
		mine_anim = _find_anim(["minig", "mining", "mine", "attack"])
		_set_loop(idle_anim)
		_set_loop(walk_anim)
		if idle_anim != "":
			anim_player.play(idle_anim)

func _find_anim(keywords: Array) -> String:
	if anim_player == null:
		return ""
	for a in anim_player.get_animation_list():
		var low := String(a).to_lower()
		for k in keywords:
			if low.contains(k):
				return a
	return ""

func _set_loop(anim_name: String) -> void:
	if anim_name == "" or anim_player == null:
		return
	var a := anim_player.get_animation(anim_name)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR

func _update_hud() -> void:
	if hud:
		hud.set_health(health, max_health)
		hud.set_block(block_names[selected], selected + 1, block_types.size())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw_pivot.rotate_y(-event.relative.x * MOUSE_SENS)
		pitch_pivot.rotation.x = clampf(pitch_pivot.rotation.x - event.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
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
	if on_floor and not _was_on_floor:
		if not _landed_once:
			_landed_once = true
		elif _fall_speed > FALL_DAMAGE_SPEED:
			_take_damage(int((_fall_speed - FALL_DAMAGE_SPEED) / 4.0) + 1)
	_was_on_floor = on_floor

	var yb := yaw_pivot.global_transform.basis
	var fwd := yb.z * -1.0
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := yb.x
	right.y = 0.0
	right = right.normalized()
	var iz := 0.0
	var ix := 0.0
	if Input.is_physical_key_pressed(KEY_W): iz -= 1.0
	if Input.is_physical_key_pressed(KEY_S): iz += 1.0
	if Input.is_physical_key_pressed(KEY_A): ix -= 1.0
	if Input.is_physical_key_pressed(KEY_D): ix += 1.0
	var dir := fwd * (-iz) + right * ix
	if dir.length() > 0.0:
		dir = dir.normalized()

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

	if model and dir.length() > 0.1:
		var ty := atan2(dir.x, dir.z) + MODEL_YAW_OFFSET
		model.rotation.y = lerp_angle(model.rotation.y, ty, delta * TURN_SPEED)

	if _mine_timer > 0.0:
		_mine_timer -= delta
	_update_animation()

	if global_position.y < VOID_Y:
		health = max_health
		_respawn()
		_update_hud()

func _update_animation() -> void:
	if anim_player == null:
		return
	var want := idle_anim
	if _mine_timer > 0.0 and mine_anim != "":
		want = mine_anim
	elif not flying and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.6 and walk_anim != "":
		want = walk_anim
	if want != "" and anim_player.current_animation != want:
		anim_player.play(want, 0.15)

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
	_landed_once = false

func _break_block() -> void:
	if world_manager == null or not ray.is_colliding():
		return
	if mine_anim != "":
		_mine_timer = 0.5
	var cell := _cell_from_hit(-0.5)
	world_manager.set_block(cell.x, cell.y, cell.z, VoxelTypes.AIR)

func _place_block() -> void:
	if world_manager == null or not ray.is_colliding():
		return
	var cell := _cell_from_hit(0.5)
	world_manager.set_block(cell.x, cell.y, cell.z, block_types[selected])

func _cell_from_hit(offset: float) -> Vector3i:
	var p := ray.get_collision_point()
	var nrm := ray.get_collision_normal()
	var inside := p + nrm * offset
	return Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))
