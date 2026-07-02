class_name Animal
extends CharacterBody3D

## Passive wandering creature using a textured low-poly model (cow / pig / sheep).
## Picks a random heading, walks a few seconds, idles, repeats. Damageable (in the
## "mob" group): when hit it bolts away and dies if its health runs out. Falls back
## to a coloured box if the models are missing.

const SPEED := 2.0
const FLEE_SPEED := 4.5
const ANIMAL_YAW := PI                 # model art-forward vs Godot -Z forward
const SEP_RADIUS := 1.4                # mobs closer than this gently push apart (no stacking/floating)
const SEP_PUSH := 0.9                  # gentle spread — enough to unstack, not enough to shove off ledges
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
var _avoid_t := 0.0                     # throttles the terrain-avoidance world query (~4/sec)
var _amb_t := 8.0                       # countdown to the next ambient low/bleat/oink call
var _flee := 0.0
var _pending_color := Color(0.95, 0.92, 0.86)
var _rng := RandomNumberGenerator.new()
var _flash_meshes: Array = []
var _model: Node3D                     # the visual root, bobbed/waddled while walking
var _model_rest_y := 0.0               # its resting local height (feet on the ground)
var _walk_phase := 0.0                 # advancing stride phase, scaled by movement speed
var _col: CollisionShape3D             # disabled on death so the corpse doesn't block
var _dying := false                    # frozen while the death topple plays
var _voice_path := "res://assets/audio/sfx/fauna/moo.mp3"   # species call, set when the model is picked
var _voice_pitch := 1.0                # per-animal register so they don't all sound identical
var _snd: AudioStreamPlayer3D          # plays the species call on hurt + (lower) on death
var _sep := Vector3.ZERO               # steer-apart from nearby mobs (so a herd fans out, never stacks)
var _sep_t := 0.0

func set_color(c: Color) -> void:
	_pending_color = c

func _ready() -> void:
	add_to_group("mob")
	_rng.randomize()
	_voice_pitch = _rng.randf_range(0.9, 1.15)
	_amb_t = _rng.randf_range(6.0, 12.0)   # stagger first ambient call so a herd doesn't moo in unison

	_col = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.8, 1.1)
	_col.shape = box
	_col.position = Vector3(0, 0.45, 0)
	add_child(_col)

	_build_visual()
	_snd = _make_snd3d(_voice_path, -4.0)   # _voice_path was set to match the picked species
	_pick_dir()

## A positional one-shot voice (cow/pig/sheep call), attenuating with distance like the mobs.
func _make_snd3d(path: String, vol_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.volume_db = vol_db
	p.unit_size = 8.0
	p.max_distance = 35.0
	if AudioServer.get_bus_index("SFX") != -1:
		p.bus = "SFX"
	add_child(p)
	return p

func _play_voice(pitch_mul: float) -> void:
	if _snd and _snd.stream:
		_snd.pitch_scale = _voice_pitch * pitch_mul * _rng.randf_range(0.96, 1.04)
		_snd.play()

func _voice_for(model_path: String) -> String:
	if "pig" in model_path:
		return "res://assets/audio/sfx/fauna/oink.mp3"
	if "sheep" in model_path:
		return "res://assets/audio/sfx/fauna/baa.mp3"
	return "res://assets/audio/sfx/fauna/moo.mp3"

func _build_visual() -> void:
	var path: String = MODELS[_rng.randi() % MODELS.size()]
	_voice_path = _voice_for(path)
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed:
			var model := packed.instantiate() as Node3D
			if model:
				add_child(model)
				_fit_model(model, 0.95)
				model.rotation.y = ANIMAL_YAW; _model = model; _model_rest_y = model.position.y
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

## One shared white-emissive flash material for ALL animals — its properties never vary, so
## there's no need to allocate a fresh StandardMaterial3D on every hit.
static var _FLASH_MAT: StandardMaterial3D
static func _flash_mat() -> StandardMaterial3D:
	if _FLASH_MAT == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 1, 1)
		m.emission_enabled = true
		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = 2.0
		_FLASH_MAT = m
	return _FLASH_MAT

## White hit-flash when struck (briefly overrides the meshes' material).
func flash() -> void:
	if _flash_meshes.is_empty():
		return
	var mat := _flash_mat()
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
	if _dying:
		return                              # already toppling — ignore further hits
	_play_voice(1.0)
	flash()
	health -= amount
	if health <= 0:
		_die()
		return
	_flee = 1.2
	var a := _rng.randf_range(0.0, TAU)
	_dir = Vector3(cos(a), 0.0, sin(a))

## Death: a beat of feedback so a kill reads (instead of the animal silently popping out of
## existence) — a last lower call, a dust puff, a quick topple, then drop loot + despawn.
func _die() -> void:
	_dying = true
	velocity = Vector3.ZERO
	_play_voice(0.7)                        # a lower, dying call
	_death_burst()
	_drop_food()
	if _col:
		_col.set_deferred("disabled", true)
	if _model and is_instance_valid(_model):
		var tw := create_tween()
		tw.tween_property(_model, "rotation:z", _model.rotation.z + deg_to_rad(90.0), 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_model, "position:y", _model_rest_y - 0.3, 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_model, "scale", _model.scale * 0.7, 0.5).set_delay(0.1)
		tw.tween_callback(func() -> void:
			if player and is_instance_valid(player) and player.has_method("_emit_burst"):
				player._emit_burst(global_position + Vector3(0, 0.25, 0), Color(0.86, 0.80, 0.70), 8, 0.5, 78.0, 0.7, 1.8, 2.5))   # tan dust masks the pop-out
		tw.tween_callback(queue_free)
	else:
		queue_free()

## A soft tan dust puff at the kill, parented to the scene so it outlives the despawn.
func _death_burst() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.10, 0.10, 0.10)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.80, 0.70)
	bm.material = mat
	p.mesh = bm
	p.amount = 14
	p.one_shot = true
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 3.6
	p.gravity = Vector3(0, -7.0, 0)
	p.emitting = true
	parent.add_child(p)
	p.global_position = global_position + Vector3(0, 0.5, 0)
	p.finished.connect(p.queue_free)

## Drops raw meat on death so the player can hunt, then cook it in a furnace for far
## more hunger than eating it raw.
func _drop_food() -> void:
	if world == null:
		return
	for i in range(_rng.randi_range(1, 2)):
		var drop := preload("res://scripts/world/block_drop.gd").new()
		drop.setup(VoxelTypes.RAW_MEAT, world, player)
		world.add_child(drop)
		drop.global_position = global_position + Vector3(_rng.randf_range(-0.3, 0.3), 0.6, _rng.randf_range(-0.3, 0.3))

func _physics_process(delta: float) -> void:
	if _dying:
		return                              # frozen while the death topple tween plays
	_timer -= delta
	_avoid_t -= delta
	_amb_t -= delta
	if _amb_t <= 0.0:                        # occasional ambient call, like the biome fauna do
		_amb_t = _rng.randf_range(8.0, 16.0)
		if _snd and _snd.stream and not _snd.playing \
				and player and is_instance_valid(player) \
				and global_position.distance_to(player.global_position) < 36.0:
			_play_voice(0.9)                # gentle low / bleat / oink (not the hurt pitch)
	if _flee > 0.0:
		_flee -= delta
	elif _timer <= 0.0:
		_pick_dir()
	if _avoid_t <= 0.0:                  # terrain query is a noise lookup — throttle it (was every frame)
		_avoid_t = 0.25
		_avoid_hazards()

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		if is_on_wall() and _dir.length() > 0.1 and _can_step_up():
			velocity.y = 4.5            # hop a 1-block step — NOT a taller wall (that just bounces = "floating")
	# Steer apart from nearby mobs (throttled) so a clustered spawn fans out instead of piling
	# up and riding onto each other's colliders (which is what made them look like they float).
	_sep_t -= delta
	if _sep_t <= 0.0:
		_sep_t = 0.2
		_compute_separation()
	var spd := FLEE_SPEED if _flee > 0.0 else SPEED
	velocity.x = _dir.x * spd + _sep.x
	velocity.z = _dir.z * spd + _sep.z

	if _dir.length() > 0.1:
		look_at(global_position + Vector3(_dir.x, 0.0, _dir.z), Vector3.UP)

	move_and_slide()
	_animate_walk(delta)

	if global_position.y < -10.0:
		queue_free()

## Accumulate a push away from up to a few nearby mobs (shares the "mob" group with zombies +
## fauna), so a herd spreads into a loose cluster instead of stacking on one point. Throttled
## and capped, so it stays cheap. This is what keeps animals from riding up onto each other.
func _compute_separation() -> void:
	_sep = Vector3.ZERO
	var count := 0
	var r2 := SEP_RADIUS * SEP_RADIUS   # compare squared distances; skip the sqrt for the far majority
	for m in get_tree().get_nodes_in_group("mob"):
		if m == self or not is_instance_valid(m):
			continue
		var d: Vector3 = global_position - (m as Node3D).global_position
		d.y = 0.0
		var ds := d.length_squared()
		if ds > 0.0025 and ds < r2:            # 0.0025 == 0.05²; ds<r2 ⇔ dist<SEP_RADIUS (monotonic)
			var dist := sqrt(ds)
			_sep += d / dist * (SEP_RADIUS - dist)   # closer neighbours push harder
			count += 1
			if count >= 6:
				break
	if _sep.length() > 0.001:
		_sep = _sep.normalized() * SEP_PUSH

func _pick_dir() -> void:
	_timer = _rng.randf_range(2.0, 5.0)
	if _rng.randf() < 0.15:                 # mostly keep roaming; only occasionally graze in place
		_dir = Vector3.ZERO
	else:
		var a := _rng.randf_range(0.0, TAU)
		_dir = Vector3(cos(a), 0.0, sin(a))

func _solid_at(x: int, y: int, z: int) -> bool:
	if world == null:
		return false
	var id: int = world.get_block(x, y, z)
	return id != VoxelTypes.AIR and id != VoxelTypes.WATER

## True only when a single solid block blocks the path at foot height with clear space above it —
## a climbable 1-block step. Stops the animal from hopping endlessly against a 2+ high wall (which
## reads as bouncing / floating in place).
func _can_step_up() -> bool:
	if world == null or _dir.length() < 0.1:
		return false
	var ahead := global_position + Vector3(_dir.x, 0.0, _dir.z).normalized() * 0.7
	var sx := floori(ahead.x)
	var sz := floori(ahead.z)
	var fy := floori(global_position.y + 0.1)
	return _solid_at(sx, fy, sz) and not _solid_at(sx, fy + 1, sz)

## Turn away from water and steep drops so the animal stays on land.
func _avoid_hazards() -> void:
	if world == null or _dir.length() < 0.1:
		return
	var ahead := global_position + _dir * 1.4
	var gx := floori(ahead.x)
	var gz := floori(ahead.z)
	var sh: int = world.surface_height(gx, gz)
	if sh < int(world.SEA_LEVEL) or float(sh) < global_position.y - 2.0:
		# Skirt the hazard with a ~90° turn instead of reversing straight back, so animals follow
		# coastlines and ledges and keep exploring rather than ping-ponging in one little box.
		var turn := (PI * 0.5 + _rng.randf_range(-0.5, 0.5)) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var a := atan2(_dir.x, _dir.z) + turn
		_dir = Vector3(sin(a), 0.0, cos(a))
		_timer = _rng.randf_range(1.2, 2.5)

## Procedural walk cycle: a speed-synced vertical bob + side-to-side waddle so the
## static animal model reads as walking (it has no skeleton to animate). Eases back
## to rest when standing still.
func _animate_walk(delta: float) -> void:
	if _model == null:
		return
	var horiz := Vector2(velocity.x, velocity.z).length()
	if horiz > 0.2 and is_on_floor():
		_walk_phase += delta * (6.0 + horiz * 1.5)
		_model.position.y = _model_rest_y + absf(sin(_walk_phase)) * 0.10
		_model.rotation.z = sin(_walk_phase) * 0.10
		_model.rotation.x = -0.05
	else:
		_model.position.y = lerpf(_model.position.y, _model_rest_y, delta * 10.0)
		_model.rotation.z = lerpf(_model.rotation.z, 0.0, delta * 10.0)
		_model.rotation.x = lerpf(_model.rotation.x, 0.0, delta * 10.0)
