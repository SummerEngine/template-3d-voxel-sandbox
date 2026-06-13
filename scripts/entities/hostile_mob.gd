class_name HostileMob
extends CharacterBody3D

## Night-time enemy (textured zombie). Wanders until the player is in range, then
## chases and attacks on a cooldown. Damageable via the "mob" group; despawns on
## death or when it falls into the void.

const MODEL_PATH := "res://assets/models/mobs/zombie.glb"
const SPEED := 2.4
const CHASE_SPEED := 3.4
const SIGHT_RANGE := 20.0
const ATTACK_RANGE := 1.6
const ATTACK_CD := 1.0
const DAMAGE := 1

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var health := 10
var player                       # Player
var world                        # ChunkManager — for edge/water avoidance
var _attack_cd := 0.0
var _dir := Vector3.ZERO
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _flash_meshes: Array = []

func _ready() -> void:
	add_to_group("mob")
	_rng.randomize()

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.6
	cap.radius = 0.35
	col.shape = cap
	col.position = Vector3(0, 0.8, 0)
	add_child(col)

	_build_visual()
	_pick_dir()

func _build_visual() -> void:
	if ResourceLoader.exists(MODEL_PATH):
		var packed := load(MODEL_PATH) as PackedScene
		if packed:
			var model := packed.instantiate() as Node3D
			if model:
				add_child(model)
				_fit_model(model, 1.7)
				model.rotation.y = PI
				_flash_meshes = model.find_children("*", "MeshInstance3D", true, false)
				return
	_build_box_fallback()

func _build_box_fallback() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.30, 0.55, 0.32)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 1.0, 0.4)
	body.mesh = bm
	body.material_override = skin
	body.position = Vector3(0, 0.7, 0)
	add_child(body)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.5, 0.5, 0.5)
	head.mesh = hm
	head.material_override = skin
	head.position = Vector3(0, 1.45, 0)
	add_child(head)
	_flash_meshes = [body, head]

## White hit-flash when struck.
func flash() -> void:
	if _flash_meshes.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 2.0
	for m in _flash_meshes:
		if is_instance_valid(m):
			m.material_override = mat
	var tw := create_tween()
	tw.tween_interval(0.09)
	tw.tween_callback(_clear_flash)

func _clear_flash() -> void:
	for m in _flash_meshes:
		if is_instance_valid(m):
			m.material_override = null

## Scale the model to target height and rest its feet on y=0.
func _fit_model(model: Node3D, target_h: float) -> void:
	var b := _merged_local_aabb(model)
	if b.size.y <= 0.001:
		return
	var s := target_h / b.size.y
	model.scale = Vector3(s, s, s)
	model.position = Vector3(
		-(b.position.x + b.size.x * 0.5) * s,
		-b.position.y * s,
		-(b.position.z + b.size.z * 0.5) * s)

func _merged_local_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var has := false
	var stack: Array = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		for ch in node.get_children():
			stack.push_back(ch)
		if node is VisualInstance3D:
			var a: AABB = (node as VisualInstance3D).get_aabb()
			a = (root.global_transform.affine_inverse() * node.global_transform) * a
			if has:
				result = result.merge(a)
			else:
				result = a
				has = true
	return result

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		queue_free()

func _physics_process(delta: float) -> void:
	if _attack_cd > 0.0:
		_attack_cd -= delta

	var chasing := false
	if player and is_instance_valid(player):
		var to: Vector3 = player.global_position - global_position
		var flat := Vector3(to.x, 0.0, to.z)
		var dist := flat.length()
		if dist < SIGHT_RANGE:
			chasing = true
			if dist > 0.05:
				_dir = flat.normalized()
			if dist < ATTACK_RANGE and _attack_cd <= 0.0:
				_attack_cd = ATTACK_CD
				if player.has_method("hurt"):
					player.hurt(DAMAGE)

	if not chasing:
		_timer -= delta
		if _timer <= 0.0:
			_pick_dir()
		_avoid_hazards()

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		if is_on_wall() and (chasing or _dir.length() > 0.1):
			velocity.y = 4.5            # hop over a 1-block step instead of getting stuck
	var spd := CHASE_SPEED if chasing else SPEED
	velocity.x = _dir.x * spd
	velocity.z = _dir.z * spd

	if _dir.length() > 0.1:
		look_at(global_position + Vector3(_dir.x, 0.0, _dir.z), Vector3.UP)

	move_and_slide()

	if global_position.y < -20.0:
		queue_free()

func _pick_dir() -> void:
	_timer = _rng.randf_range(1.5, 4.0)
	if _rng.randf() < 0.35:
		_dir = Vector3.ZERO
	else:
		var a := _rng.randf_range(0.0, TAU)
		_dir = Vector3(cos(a), 0.0, sin(a))

## Turn away from water and steep drops while wandering.
func _avoid_hazards() -> void:
	if world == null or _dir.length() < 0.1:
		return
	var ahead := global_position + _dir * 1.4
	var gx := floori(ahead.x)
	var gz := floori(ahead.z)
	var sh: int = world.surface_height(gx, gz)
	if sh < int(world.SEA_LEVEL) or float(sh) < global_position.y - 2.0:
		var a := atan2(_dir.x, _dir.z) + PI + _rng.randf_range(-0.7, 0.7)
		_dir = Vector3(sin(a), 0.0, cos(a))
		_timer = _rng.randf_range(1.0, 2.0)
