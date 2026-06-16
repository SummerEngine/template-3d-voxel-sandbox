class_name HostileMob
extends CharacterBody3D

## Night-time enemy. Uses the player's own textured zombie models (a green shambler and an
## armoured one) as the visual, scaled to size and driven by a procedural whole-body shamble
## — a heavy bob + sway + forward hunch + attack lunge — since the GLBs are single static
## meshes with no skeleton. Falls back to a code-built articulated blocky zombie (real
## swinging limbs) if the models are missing. Wanders until the player is in range, then
## chases and attacks on a cooldown. Damageable via the "mob" group; despawns on death or
## when it falls into the void.

# The player's zombie models, weighted toward the natural-posed green one (the armoured mech
# is a hard T-pose, so it shows up less often). Picked per-spawn for variety.
const MODEL_PATHS := [
	"res://assets/models/mobs/zombie_fast.glb",   # green cartoon zombie, natural arms-down pose
	"res://assets/models/mobs/zombie.glb",        # armoured/mech zombie (T-pose, hunched to hide it)
]
const SPEED := 2.4
const CHASE_SPEED := 4.2          # a touch faster than a walk — you can't just stroll away
const SIGHT_RANGE := 20.0
const ATTACK_RANGE := 1.6
const ATTACK_CD := 1.0
const DAMAGE := 1
const HUNCH := -0.18              # permanent forward lean (rad) — a shambling, lunging posture
const ARM_REST := -1.45           # blocky-rig fallback: arms held straight out forward

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var health := 10
var damage := DAMAGE              # scaled up on harder nights by main.gd
var player                       # Player
var world                        # ChunkManager — for edge/water avoidance
var force_model := -1            # debug: pin to MODEL_PATHS[i] instead of the weighted pick (-1 = off)
var _attack_cd := 0.0
var _dir := Vector3.ZERO
var _timer := 0.0
var _avoid_t := 0.0
var _rng := RandomNumberGenerator.new()
var _flash_meshes: Array = []
var _model: Node3D                     # visual root, lurched/swayed while shambling
var _model_rest_y := 0.0               # its resting local height (feet on the ground)
var _articulated := false              # true -> code-built blocky rig (swing limbs); false -> GLB shamble
var _leg_l: Node3D                     # blocky-rig joints (only used when _articulated)
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _walk_phase := 0.0                 # advancing shamble/stride phase, scaled by movement speed
var _punch := 0.0                      # 1->0 punch-lunge progress when it hits the player
var _snd_groan: AudioStreamPlayer3D    # positional zombie sounds (come from the mob)
var _snd_attack: AudioStreamPlayer3D
var _snd_hurt: AudioStreamPlayer3D
var _groan_timer := 0.0

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
	_setup_sounds()
	_pick_dir()

## Positional zombie audio that emanates from the mob's location.
func _setup_sounds() -> void:
	_snd_groan = _make_snd3d("res://assets/audio/sfx/mobs/zombie_groan.mp3", -3.0)
	_snd_attack = _make_snd3d("res://assets/audio/sfx/mobs/zombie_attack.mp3", -1.0)
	_snd_hurt = _make_snd3d("res://assets/audio/sfx/mobs/zombie_hurt.mp3", -2.0)
	_groan_timer = _rng.randf_range(1.0, 4.0)

func _make_snd3d(path: String, vol_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.volume_db = vol_db
	p.unit_size = 8.0          # full volume within ~8 m, attenuating out to max_distance
	p.max_distance = 35.0
	if AudioServer.get_bus_index("SFX") != -1:
		p.bus = "SFX"
	add_child(p)
	return p

## Build the visual: prefer the player's textured zombie GLB (scaled + hunched, shamble-driven);
## fall back to the articulated blocky rig if no model loads.
func _build_visual() -> void:
	# Weighted pick: usually the natural-posed green zombie, occasionally the armoured one.
	var path: String = MODEL_PATHS[0]
	if _rng.randf() < 0.35 and ResourceLoader.exists(MODEL_PATHS[1]):
		path = MODEL_PATHS[1]
	if force_model >= 0 and force_model < MODEL_PATHS.size():
		path = MODEL_PATHS[force_model]
	if not ResourceLoader.exists(path):
		path = MODEL_PATHS[0] if ResourceLoader.exists(MODEL_PATHS[0]) else ""

	if path != "":
		var packed := load(path) as PackedScene
		if packed:
			var model := packed.instantiate() as Node3D
			if model:
				add_child(model)
				_fit_model(model, 1.85)
				model.rotation.y = PI            # GLBs face +z; flip so the front faces look_at (-z)
				model.rotation.x = HUNCH         # permanent forward hunch
				_model = model
				_model_rest_y = model.position.y
				_articulated = false
				_flash_meshes = model.find_children("*", "MeshInstance3D", true, false)
				return

	_build_zombie_rig()

## Fallback: a Minecraft-style articulated blocky zombie with real swinging limbs.
func _build_zombie_rig() -> void:
	var rig := Node3D.new()
	rig.name = "ZombieRig"
	add_child(rig)

	var skin := Color(0.36, 0.56, 0.30)
	var shirt := Color(0.27, 0.36, 0.42)
	var pants := Color(0.24, 0.22, 0.32)
	_flash_meshes = []

	_box(rig, Vector3(0.52, 0.75, 0.28), Vector3(0, 1.125, 0), shirt)
	_box(rig, Vector3(0.50, 0.50, 0.50), Vector3(0, 1.72, 0), skin)
	_eye(rig, Vector3(-0.12, 1.78, 0.255))
	_eye(rig, Vector3(0.12, 1.78, 0.255))
	_arm_l = _limb(rig, Vector3(0.18, 0.72, 0.20), Vector3(-0.36, 1.45, 0), skin)
	_arm_r = _limb(rig, Vector3(0.18, 0.72, 0.20), Vector3(0.36, 1.45, 0), skin)
	_arm_l.rotation.x = ARM_REST
	_arm_r.rotation.x = ARM_REST
	_leg_l = _limb(rig, Vector3(0.20, 0.75, 0.22), Vector3(-0.14, 0.75, 0), pants)
	_leg_r = _limb(rig, Vector3(0.20, 0.75, 0.22), Vector3(0.14, 0.75, 0), pants)

	rig.rotation.y = PI
	_model = rig
	_model_rest_y = 0.0
	_articulated = true

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.set_surface_override_material(0, m)
	mi.position = pos
	parent.add_child(mi)
	_flash_meshes.append(mi)
	return mi

func _eye(parent: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.10, 0.10, 0.02)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.05, 0.05)
	m.emission_enabled = true
	m.emission = Color(0.9, 0.1, 0.1)
	m.emission_energy_multiplier = 1.6
	mi.set_surface_override_material(0, m)
	mi.position = pos
	parent.add_child(mi)

func _limb(parent: Node3D, size: Vector3, joint_pos: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = joint_pos
	parent.add_child(pivot)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.set_surface_override_material(0, m)
	mi.position = Vector3(0, -size.y * 0.5, 0)
	pivot.add_child(mi)
	_flash_meshes.append(mi)
	return pivot

## Scale the model to target height and rest its feet on y=0, centred on x/z.
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

func take_damage(amount: int) -> void:
	if _snd_hurt and _snd_hurt.stream:
		_snd_hurt.play()
	flash()
	health -= amount
	if health <= 0:
		if player and is_instance_valid(player) and player.has_signal("mob_killed"):
			player.emit_signal("mob_killed")
		queue_free()

func _physics_process(delta: float) -> void:
	if _attack_cd > 0.0:
		_attack_cd -= delta

	# Periodic menacing groan from the mob's position.
	_groan_timer -= delta
	if _groan_timer <= 0.0:
		_groan_timer = _rng.randf_range(3.5, 8.0)
		if _snd_groan and _snd_groan.stream and not _snd_groan.playing:
			_snd_groan.play()

	var chasing := false
	if player and is_instance_valid(player):
		var to: Vector3 = player.global_position - global_position
		var flat := Vector3(to.x, 0.0, to.z)
		var dist := flat.length()
		if dist < SIGHT_RANGE:
			chasing = true
			if dist > 0.05:
				_dir = flat.normalized()
			if dist < ATTACK_RANGE and absf(to.y) < 1.6 and _attack_cd <= 0.0:
				_attack_cd = ATTACK_CD
				_punch = 1.0                       # play the punch-lunge animation
				if _snd_attack and _snd_attack.stream:
					_snd_attack.play()
				if player.has_method("hurt"):
					player.hurt(damage)

	if not chasing:
		_timer -= delta
		if _timer <= 0.0:
			_pick_dir()
		_avoid_t -= delta
		if _avoid_t <= 0.0:
			_avoid_t = 0.25            # don't probe terrain every frame
			_avoid_hazards()

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		if is_on_wall() and (chasing or _dir.length() > 0.1):
			# When chasing a player who has pillared up, leap ~2 blocks so a cheap 2-high
			# pillar no longer makes you untouchable; otherwise just hop a 1-block step.
			var py_above := 0.0
			if chasing and player and is_instance_valid(player):
				py_above = float(player.global_position.y) - global_position.y
			velocity.y = 6.6 if py_above > 1.2 else 4.5
	var spd := CHASE_SPEED if chasing else SPEED
	velocity.x = _dir.x * spd
	velocity.z = _dir.z * spd

	if _dir.length() > 0.1:
		look_at(global_position + Vector3(_dir.x, 0.0, _dir.z), Vector3.UP)

	move_and_slide()
	_animate(delta)

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

func _animate(delta: float) -> void:
	if _model == null:
		return
	if _articulated:
		_anim_articulated(delta)
	else:
		_anim_shamble(delta)

## GLB models: a heavy whole-body shamble — bob + sway + forward-hunch lurch, snapping into a
## forward lunge when it punches the player. (Single static mesh, so the body moves as a whole.)
func _anim_shamble(delta: float) -> void:
	if _punch > 0.0:
		_punch = maxf(0.0, _punch - delta * 3.5)        # ~0.3s jab
		var arc := sin((1.0 - _punch) * PI)             # 0 -> 1 -> 0
		_model.position.y = _model_rest_y - 0.06 * arc
		_model.rotation.x = HUNCH - 0.55 * arc          # lunge forward from the hunch rest
		_model.rotation.z = 0.0
		return
	var horiz := Vector2(velocity.x, velocity.z).length()
	if horiz > 0.2:
		_walk_phase += delta * (4.0 + horiz)
		_model.position.y = _model_rest_y + absf(sin(_walk_phase)) * 0.06
		_model.rotation.z = sin(_walk_phase) * 0.16
		_model.rotation.x = HUNCH + sin(_walk_phase * 0.5) * 0.05
	else:
		_model.position.y = lerpf(_model.position.y, _model_rest_y, delta * 8.0)
		_model.rotation.z = lerpf(_model.rotation.z, 0.0, delta * 8.0)
		_model.rotation.x = lerpf(_model.rotation.x, HUNCH, delta * 8.0)

## Blocky-rig fallback: legs stride, arms swing/counter-swing, body bobs; arms jab on a hit.
func _anim_articulated(delta: float) -> void:
	if _punch > 0.0:
		_punch = maxf(0.0, _punch - delta * 3.5)
		var arc := sin((1.0 - _punch) * PI)
		_model.position.y = _model_rest_y - 0.05 * arc
		_model.rotation.x = -0.35 * arc
		var jab := ARM_REST - 1.05 * arc
		_arm_l.rotation.x = jab
		_arm_r.rotation.x = jab
		return
	_model.rotation.x = lerpf(_model.rotation.x, 0.0, delta * 8.0)
	var horiz := Vector2(velocity.x, velocity.z).length()
	if horiz > 0.2:
		_walk_phase += delta * (4.0 + horiz * 1.2)
		var swing := sin(_walk_phase)
		_leg_l.rotation.x = swing * 0.7
		_leg_r.rotation.x = -swing * 0.7
		_arm_l.rotation.x = ARM_REST - swing * 0.25
		_arm_r.rotation.x = ARM_REST + swing * 0.25
		_model.position.y = _model_rest_y + absf(sin(_walk_phase)) * 0.05
		_model.rotation.z = sin(_walk_phase) * 0.05
	else:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, delta * 8.0)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, delta * 8.0)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, ARM_REST, delta * 8.0)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, ARM_REST, delta * 8.0)
		_walk_phase += delta * 1.5
		_model.position.y = _model_rest_y + sin(_walk_phase) * 0.012
		_model.rotation.z = lerpf(_model.rotation.z, 0.0, delta * 8.0)
