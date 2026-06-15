class_name Creature
extends CharacterBody3D

## Biome fauna: one wandering creature driven by a config dict (see fauna.gd). Three
## locomotion modes, each procedurally animated (the low-poly models have no skeleton):
##   GROUND — walk / run / graze, gravity, hops 1-block ledges, avoids water & cliffs.
##            Gait variants: "walk" (bob+waddle), "hop" (rabbit/frog), "slither" (snake).
##   AIR    — birds cruise at an altitude above the terrain, wander in 3D, bank into turns
##            and flap; flee by climbing away.
##   WATER  — fish / aquatic reptiles stay inside the water column, swim with a tail wiggle
##            and turn back from the shore.
## Damageable (in the "mob" group); some drop raw meat. Falls back to a coloured box if the
## model is missing (so the registry can list models that haven't generated yet).

const GROUND := 0
const AIR := 1
const WATER := 2

var world
var player
var cfg: Dictionary = {}

var _mode := GROUND
var _gait := "walk"
var _speed := 2.0
var _run := 4.0
var _yaw := PI
var _alt := 12.0
var _meat := false
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

var health := 4
var _dir := Vector3.ZERO              # heading (horizontal for ground; 3D for air/water)
var _timer := 0.0
var _flee := 0.0
var _rng := RandomNumberGenerator.new()
var _flash_meshes: Array = []
var _base_overrides: Array = []       # per mesh: the material to restore after a hit-flash
var _model: Node3D
var _rest_y := 0.0
var _phase := 0.0
var _bank := 0.0
var _last_yaw := 0.0
var _avoid_t := 0.0                   # throttle terrain-avoidance world queries (not every frame)

func setup(c: Dictionary, w, p) -> void:
	cfg = c
	world = w
	player = p

func _ready() -> void:
	add_to_group("mob")
	_rng.randomize()
	_mode = int(cfg.get("mode", GROUND))
	_gait = String(cfg.get("gait", "walk"))
	_speed = float(cfg.get("speed", 2.0))
	_run = float(cfg.get("run", _speed * 2.0))
	_yaw = float(cfg.get("yaw", PI))
	_alt = float(cfg.get("alt", 12.0))
	_meat = bool(cfg.get("meat", false))
	health = int(cfg.get("health", 4))

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var sz := float(cfg.get("size", 0.9))
	box.size = Vector3(maxf(0.4, sz * 0.7), maxf(0.4, sz * 0.85), maxf(0.5, sz))
	col.shape = box
	col.position = Vector3(0, box.size.y * 0.5, 0)
	add_child(col)

	_build_visual()
	_pick_dir()

func _build_visual() -> void:
	var path := String(cfg.get("model", ""))
	var target_h := float(cfg.get("size", 0.9))
	if path != "" and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed:
			var model := packed.instantiate() as Node3D
			if model:
				add_child(model)
				_fit_model(model, target_h)
				model.rotation.y = _yaw
				_model = model
				_rest_y = model.position.y
				_flash_meshes = model.find_children("*", "MeshInstance3D", true, false)
				_tint_untextured()
				return
	_build_box_fallback(target_h)

## Some generated models import without a real texture and render as flat grey. Give those
## meshes the creature's species colour so it reads correctly; leave properly-textured
## meshes (e.g. the cows) alone. The applied material is remembered as the flash base.
func _tint_untextured() -> void:
	_base_overrides.clear()
	var col: Color = cfg.get("color", Color(0.8, 0.8, 0.8))
	for m in _flash_meshes:
		var base: Material = null
		if m is MeshInstance3D:
			var active := (m as MeshInstance3D).get_active_material(0)
			var textured: bool = active is BaseMaterial3D and (active as BaseMaterial3D).albedo_texture != null
			if not textured:
				var mat := StandardMaterial3D.new()
				mat.albedo_color = col
				(m as MeshInstance3D).material_override = mat
				base = mat
		_base_overrides.append(base)

func _build_box_fallback(h: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cfg.get("color", Color(0.8, 0.8, 0.8))
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(h * 0.7, h * 0.7, h)
	body.mesh = bm
	body.material_override = mat
	body.position = Vector3(0, h * 0.45, 0)
	add_child(body)
	_model = body
	_rest_y = body.position.y
	_flash_meshes = [body]
	_base_overrides = [mat]

# --- damage ---------------------------------------------------------------------------
func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		if _meat:
			_drop_meat()
		queue_free()
		return
	_flee = 1.4
	_pick_dir(true)

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
	for i in range(_flash_meshes.size()):
		var m = _flash_meshes[i]
		if is_instance_valid(m):
			m.material_override = _base_overrides[i] if i < _base_overrides.size() else null

func _drop_meat() -> void:
	if world == null:
		return
	for i in range(_rng.randi_range(1, 2)):
		var drop := preload("res://scripts/world/block_drop.gd").new()
		drop.setup(VoxelTypes.RAW_MEAT, world, player)
		world.add_child(drop)
		drop.global_position = global_position + Vector3(_rng.randf_range(-0.3, 0.3), 0.6, _rng.randf_range(-0.3, 0.3))

# --- per-frame ------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_timer -= delta
	_avoid_t -= delta
	if _flee > 0.0:
		_flee -= delta
	elif _timer <= 0.0:
		_pick_dir()

	match _mode:
		AIR:   _move_air(delta)
		WATER: _move_water(delta)
		_:     _move_ground(delta)

	if global_position.y < -20.0:
		queue_free()

func _pick_dir(fleeing := false) -> void:
	_timer = _rng.randf_range(1.6, 4.2)
	var a := _rng.randf_range(0.0, TAU)
	if fleeing and player and is_instance_valid(player):
		var away: Vector3 = global_position - player.global_position
		a = atan2(away.x, away.z) + _rng.randf_range(-0.5, 0.5)
		_dir = Vector3(sin(a), 0.0, cos(a))
	elif _mode == GROUND and _rng.randf() < 0.3:
		_dir = Vector3.ZERO                              # graze / rest
	else:
		var pitch := 0.0
		if _mode != GROUND:
			pitch = _rng.randf_range(-0.25, 0.25)
		_dir = Vector3(cos(a), pitch, sin(a)).normalized()

# --- GROUND ---------------------------------------------------------------------------
func _move_ground(delta: float) -> void:
	if _avoid_t <= 0.0:
		_avoid_t = 0.25
		_avoid_ground_hazards()
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		if is_on_wall() and Vector2(_dir.x, _dir.z).length() > 0.1:
			velocity.y = 4.5                             # hop a 1-block ledge
	var spd := _run if _flee > 0.0 else _speed
	velocity.x = _dir.x * spd
	velocity.z = _dir.z * spd
	if Vector2(_dir.x, _dir.z).length() > 0.1:
		look_at(global_position + Vector3(_dir.x, 0.0, _dir.z), Vector3.UP)
	move_and_slide()
	_anim_ground(delta)

func _avoid_ground_hazards() -> void:
	if world == null or Vector2(_dir.x, _dir.z).length() < 0.1:
		return
	var ahead := global_position + _dir * 1.4
	var sh: int = world.surface_height(floori(ahead.x), floori(ahead.z))
	# Turn away from water, cliffs (drop) AND walls (a step too tall to hop) so creatures
	# don't grind into terrain forever.
	if sh < int(world.SEA_LEVEL) or float(sh) < global_position.y - 2.0 or float(sh) > global_position.y + 1.6:
		var a := atan2(_dir.x, _dir.z) + PI + _rng.randf_range(-0.7, 0.7)
		_dir = Vector3(sin(a), 0.0, cos(a))
		_timer = _rng.randf_range(1.0, 2.0)

func _anim_ground(delta: float) -> void:
	if _model == null:
		return
	var horiz := Vector2(velocity.x, velocity.z).length()
	var moving := horiz > 0.2 and is_on_floor()
	if _gait == "slither":
		# Snake: side-to-side body sway, hugging the ground (no bob).
		_phase += delta * (4.0 + horiz * 2.0)
		_model.rotation.y = _yaw + sin(_phase) * 0.5
		_model.position.y = lerpf(_model.position.y, _rest_y, delta * 8.0)
		return
	if moving:
		var hop := _gait == "hop"
		_phase += delta * ((4.0 if hop else 6.0) + horiz * 1.5)
		var amp := 0.22 if hop else 0.10
		_model.position.y = _rest_y + absf(sin(_phase)) * amp
		_model.rotation.z = 0.0 if hop else sin(_phase) * 0.10
		_model.rotation.x = -0.05
	else:
		# Idle / grazing: ease down and dip the head a touch.
		_model.position.y = lerpf(_model.position.y, _rest_y, delta * 10.0)
		_model.rotation.z = lerpf(_model.rotation.z, 0.0, delta * 10.0)
		var graze: float = 0.16 if _gait == "walk" else 0.0
		_model.rotation.x = lerpf(_model.rotation.x, graze, delta * 4.0)

# --- AIR ------------------------------------------------------------------------------
func _move_air(delta: float) -> void:
	var spd := _run if _flee > 0.0 else _speed
	var ground := 0.0
	if world:
		ground = float(world.surface_height(floori(global_position.x), floori(global_position.z)))
	var target_alt := ground + _alt
	var vy := clampf(target_alt - global_position.y, -3.0, 3.0)
	if _flee > 0.0:
		vy += 3.0
	var h := Vector3(_dir.x, 0.0, _dir.z)
	if h.length() > 0.01:
		h = h.normalized()
	velocity = h * spd + Vector3(0.0, vy, 0.0)
	if h.length() > 0.1:
		look_at(global_position + h, Vector3.UP)
	move_and_slide()
	_anim_air(delta, vy)

func _anim_air(delta: float, vy: float) -> void:
	if _model == null:
		return
	_phase += delta * 9.0
	# Wing flap reads as a body bob; bank into the turn; pitch with climb/dive.
	_model.position.y = _rest_y + sin(_phase) * 0.10
	var turn := wrapf(rotation.y - _last_yaw, -PI, PI)
	_last_yaw = rotation.y
	_bank = lerpf(_bank, clampf(turn * 6.0, -0.5, 0.5), delta * 5.0)
	_model.rotation.z = _bank + sin(_phase) * 0.18
	_model.rotation.x = lerpf(_model.rotation.x, clampf(-vy * 0.12, -0.4, 0.4), delta * 4.0)

# --- WATER ----------------------------------------------------------------------------
func _move_water(delta: float) -> void:
	var spd := _run if _flee > 0.0 else _speed
	if _avoid_t <= 0.0:
		_avoid_t = 0.25
		_avoid_shore()
	var sea := float(world.SEA_LEVEL) if world else 40.0
	var bed := 0.0
	if world:
		bed = float(world.surface_height(floori(global_position.x), floori(global_position.z)))
	var lo := bed + 0.7
	var hi := sea - 0.6
	if hi < lo:
		hi = lo
	# Steer the depth back into the water band, otherwise drift with the heading.
	var vy := _dir.y * spd * 0.4
	if global_position.y < lo:
		vy = 1.5
	elif global_position.y > hi:
		vy = -1.5
	var h := Vector3(_dir.x, 0.0, _dir.z)
	if h.length() > 0.01:
		h = h.normalized()
	velocity = h * spd + Vector3(0.0, vy, 0.0)
	if h.length() > 0.1:
		look_at(global_position + h, Vector3.UP)
	move_and_slide()
	_anim_water(delta)

## Turn back when the water ahead becomes land/shallows.
func _avoid_shore() -> void:
	if world == null or Vector2(_dir.x, _dir.z).length() < 0.1:
		return
	var ahead := global_position + _dir * 1.6
	if world.surface_height(floori(ahead.x), floori(ahead.z)) >= int(world.SEA_LEVEL):
		var a := atan2(_dir.x, _dir.z) + PI + _rng.randf_range(-0.6, 0.6)
		_dir = Vector3(sin(a), _rng.randf_range(-0.15, 0.15), cos(a)).normalized()
		_timer = _rng.randf_range(1.0, 2.0)

func _anim_water(delta: float) -> void:
	if _model == null:
		return
	_phase += delta * (7.0 + _speed)
	# Tail wiggle (yaw sway) + a gentle body roll — reads as swimming.
	_model.rotation.y = _yaw + sin(_phase) * 0.28
	_model.rotation.z = sin(_phase * 0.5) * 0.10

# --- model fitting --------------------------------------------------------------------
## Scale so the model's LONGEST dimension equals `target` (preserving proportions), then
## centre it horizontally and rest it on y=0. Scaling by height alone made long, low
## creatures (snake, crocodile, fish) come out gigantic.
func _fit_model(model: Node3D, target: float) -> void:
	var b := _merged_local_aabb(model)
	var longest := maxf(b.size.x, maxf(b.size.y, b.size.z))
	if longest <= 0.001:
		return
	var s := target / longest
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
