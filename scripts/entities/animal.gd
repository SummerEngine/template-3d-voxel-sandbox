class_name Animal
extends CharacterBody3D

## Passive wandering creature using a textured low-poly model (cow / pig / sheep).
## Picks a random heading, walks a few seconds, idles, repeats. Damageable (in the
## "mob" group): when hit it bolts away and dies if its health runs out. Falls back
## to a coloured box if the models are missing.

const SPEED := 2.0
const FLEE_SPEED := 4.5
const ANIMAL_YAW := PI                 # model art-forward vs Godot -Z forward
const MODELS := [
	"res://assets/models/animals/cow.glb",
	"res://assets/models/animals/pig.glb",
	"res://assets/models/animals/sheep.glb",
]

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var world                              # ChunkManager — for edge/water avoidance + drops
var player                             # Player — so dropped food can be collected
var health := 4
var _dir := Vector3.ZERO
var _timer := 0.0
var _flee := 0.0
var _pending_color := Color(0.95, 0.92, 0.86)
var _rng := RandomNumberGenerator.new()
var _flash_meshes: Array = []

func set_color(c: Color) -> void:
	_pending_color = c

func _ready() -> void:
	add_to_group("mob")
	_rng.randomize()

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.8, 1.1)
	col.shape = box
	col.position = Vector3(0, 0.45, 0)
	add_child(col)

	_build_visual()
	_pick_dir()

func _build_visual() -> void:
	var path: String = MODELS[_rng.randi() % MODELS.size()]
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed:
			var model := packed.instantiate() as Node3D
			if model:
				add_child(model)
				_fit_model(model, 0.95)
				model.rotation.y = ANIMAL_YAW
				_flash_meshes = model.find_children("*", "MeshInstance3D", true, false)
				return
	_build_box_fallback()

func _build_box_fallback() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _pending_color
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.8, 1.2)
	body.mesh = bm
	body.material_override = mat
	body.position = Vector3(0, 0.45, 0)
	add_child(body)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.5, 0.5, 0.5)
	head.mesh = hm
	head.material_override = mat
	head.position = Vector3(0, 0.7, 0.6)
	add_child(head)
	_flash_meshes = [body, head]

## White hit-flash when struck (briefly overrides the meshes' material).
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

## Scale a freshly-instanced model to `target_h` tall and rest its feet on y=0.
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
		_drop_food()
		queue_free()
		return
	_flee = 1.2
	var a := _rng.randf_range(0.0, TAU)
	_dir = Vector3(cos(a), 0.0, sin(a))

## Drops a couple of apples (food) on death so the player can hunt to survive.
func _drop_food() -> void:
	if world == null:
		return
	for i in range(2):
		var drop := preload("res://scripts/world/block_drop.gd").new()
		drop.setup(VoxelTypes.APPLE, world, player)
		world.add_child(drop)
		drop.global_position = global_position + Vector3(_rng.randf_range(-0.3, 0.3), 0.6, _rng.randf_range(-0.3, 0.3))

func _physics_process(delta: float) -> void:
	_timer -= delta
	if _flee > 0.0:
		_flee -= delta
	elif _timer <= 0.0:
		_pick_dir()
	_avoid_hazards()

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		if is_on_wall() and _dir.length() > 0.1:
			velocity.y = 4.5            # hop over a 1-block step instead of getting stuck
	var spd := FLEE_SPEED if _flee > 0.0 else SPEED
	velocity.x = _dir.x * spd
	velocity.z = _dir.z * spd

	if _dir.length() > 0.1:
		look_at(global_position + Vector3(_dir.x, 0.0, _dir.z), Vector3.UP)

	move_and_slide()

	if global_position.y < -10.0:
		queue_free()

func _pick_dir() -> void:
	_timer = _rng.randf_range(1.5, 4.0)
	if _rng.randf() < 0.3:
		_dir = Vector3.ZERO
	else:
		var a := _rng.randf_range(0.0, TAU)
		_dir = Vector3(cos(a), 0.0, sin(a))

## Turn away from water and steep drops so the animal stays on land.
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
