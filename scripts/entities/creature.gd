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
var _anim_player: AnimationPlayer     # the model's own AnimationPlayer, if it's a rigged model
var _has_clip := false                # true -> a baked clip drives the body (skip procedural anim)
var _flap := 0.5                      # bird flap intensity envelope: flap to climb, glide to dive
var _wing_l: Node3D                    # voxel-bird wing pivots (flapped in _anim_air)
var _wing_r: Node3D
var _tail: Node3D                      # voxel-bird tail (steers like a rudder when banking)
var _fit_w := 0.8                      # the fitted model's real dimensions (set by _fit_model)
var _fit_h := 0.8
var _fit_d := 0.8
var _snd_amb: AudioStreamPlayer3D     # positional ambient: bird call (chirp/caw/quack) or water bloop
var _amb_t := 0.0                     # countdown to the next ambient sound
var _voice_pitch := 1.0               # per-individual pitch so a flock doesn't sound cloned
var _bubbles: CPUParticles3D          # fish bubble trail (water mode)

const SND_CALLS := {
	"chirp":  "res://assets/audio/sfx/fauna/chirp.mp3",   # songbird, parrot
	"caw":    "res://assets/audio/sfx/fauna/caw.mp3",     # vulture
	"quack":  "res://assets/audio/sfx/fauna/quack.mp3",   # duck
	"moo":    "res://assets/audio/sfx/fauna/moo.mp3",     # cow
	"baa":    "res://assets/audio/sfx/fauna/baa.mp3",     # sheep
	"oink":   "res://assets/audio/sfx/fauna/oink.mp3",    # pig
	"hiss":   "res://assets/audio/sfx/fauna/hiss.mp3",    # snake, lizard, crocodile
	"splash": "res://assets/audio/sfx/fauna/splash.mp3",  # fish, turtle (water default)
}

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

	_build_visual()      # fits the model and records its real dimensions (_fit_w/_fit_h/_fit_d)
	_setup_collider()    # collider sized to the FITTED model, not the longest-dimension guess
	_setup_audio()
	_setup_vfx()
	_pick_dir()

## Collision box matched to the model's actual fitted size, so a long flat snake gets a flat
## box (not a tall cube) — that stops oversized colliders catching on terrain and floating the
## creature a block above the ground. Feet sit at the body origin (y=0).
func _setup_collider() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(0.35, _fit_w * 0.85), maxf(0.35, _fit_h), maxf(0.35, _fit_d * 0.85))
	col.shape = box
	col.position = Vector3(0, box.size.y * 0.5, 0)
	add_child(col)

## Positional ambient sound: birds get their call (chirp/caw/quack), water creatures a soft
## splash bloop. Each individual gets a pitch so a flock/shoal doesn't sound copy-pasted.
func _setup_audio() -> void:
	_voice_pitch = _rng.randf_range(0.9, 1.15)
	var call_name := String(cfg.get("call", ""))
	if call_name == "" and _mode == WATER:
		call_name = "splash"               # fish/turtle bloop by default if no specific call
	var path := String(SND_CALLS.get(call_name, ""))
	if path == "" or not ResourceLoader.exists(path):
		return                             # silent species (rabbit, frog, monkey, camel)
	_amb_t = _rng.randf_range(2.0, 7.0) if _mode == AIR else _rng.randf_range(5.0, 12.0)
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.volume_db = -7.0 if _mode == AIR else -9.0
	p.unit_size = 10.0
	p.max_distance = 42.0
	if AudioServer.get_bus_index("SFX") != -1:
		p.bus = "SFX"
	add_child(p)
	_snd_amb = p

## Tick the ambient sound; only actually play when the player is near (no distant chatter — and
## it saves audio voices, the real cost). Re-arms to a fresh random interval each time.
func _amb_tick(delta: float, lo: float, hi: float) -> void:
	if _snd_amb == null:
		return
	_amb_t -= delta
	if _amb_t > 0.0:
		return
	_amb_t = _rng.randf_range(lo, hi)
	if player and is_instance_valid(player) \
			and global_position.distance_to(player.global_position) < 36.0 \
			and not _snd_amb.playing:
		_snd_amb.pitch_scale = _voice_pitch * _rng.randf_range(0.96, 1.04)
		_snd_amb.play()

## Fish leave a trail of tiny rising bubbles (voxel-cube bubbles, on theme). One small CPU
## emitter per water creature (~10 particles), only emitting while actually swimming.
func _setup_vfx() -> void:
	if _mode != WATER:
		return
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, 0.06)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.88, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.85, 1.0)
	mat.emission_energy_multiplier = 0.4
	bm.material = mat
	p.mesh = bm
	p.amount = 10
	p.lifetime = 1.3
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0, 1.1, 0)         # bubbles rise
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	p.position = Vector3(0, float(cfg.get("size", 0.6)) * 0.4, 0)
	p.emitting = false                     # toggled by swim speed
	add_child(p)
	_bubbles = p

func _build_visual() -> void:
	if _mode == AIR:
		_build_bird_rig()        # voxel bird with real flapping wings (replaces the GLB for birds)
		return
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
				_setup_clip(model)
				return
	_build_box_fallback(target_h)

## If the model ships with a rigged AnimationPlayer, loop the clip that best matches this
## creature's locomotion (walk / fly / swim / slither, then idle, then the first clip) and
## let it drive the body — the procedural bob/sway is only for static models.
func _setup_clip(model: Node3D) -> void:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_anim_player = players[0] as AnimationPlayer
	if _anim_player == null:
		return
	var clip := _pick_clip(_anim_player.get_animation_list())
	if clip == "":
		return
	var anim := _anim_player.get_animation(clip)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR
	_anim_player.play(clip)
	_anim_player.speed_scale = 1.0
	_has_clip = true

func _pick_clip(list: PackedStringArray) -> String:
	var prefer: Array
	match _mode:
		AIR:   prefer = ["fly", "flying", "flap", "glide"]
		WATER: prefer = ["swim", "swimming"]
		_:     prefer = ["walk", "run", "move", "crawl", "slither", "hop", "trot"]
	prefer.append_array(["idle", "loop", "rest"])
	for key in prefer:
		for a in list:
			if key in String(a).to_lower():
				return a
	for a in list:               # fallback: anything that isn't the import RESET pose
		if String(a) != "RESET":
			return a
	return ""

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
	_fit_w = h * 0.7     # fallback box dimensions, for the collider
	_fit_h = h * 0.7
	_fit_d = h

## A blocky voxel bird — body + head + beak + tail and two flapping wings on shoulder pivots.
## Coloured from cfg, faces -Z (the flight/look_at direction). Wings are animated in _anim_air.
## Replaces the GLB for birds so they match the voxel art and actually flap.
func _build_bird_rig() -> void:
	var rig := Node3D.new()
	rig.name = "BirdRig"
	add_child(rig)
	var col: Color = cfg.get("color", Color(0.6, 0.5, 0.4))
	var wing_col := col.darkened(0.18)
	var beak_col := Color(0.95, 0.7, 0.2)
	_flash_meshes = []
	_base_overrides = []
	_bird_box(rig, Vector3(0.22, 0.20, 0.50), Vector3(0, 0, 0), col)              # body (length on Z)
	_bird_box(rig, Vector3(0.22, 0.22, 0.22), Vector3(0, 0.06, -0.30), col)       # head (front -Z)
	_bird_box(rig, Vector3(0.07, 0.07, 0.14), Vector3(0, 0.04, -0.46), beak_col)  # beak
	_tail = _bird_box(rig, Vector3(0.20, 0.04, 0.22), Vector3(0, 0.02, 0.34), wing_col)
	_tail.rotation.x = -0.25                                                      # tail fans up a touch
	_bird_eye(rig, Vector3(-0.10, 0.10, -0.34))
	_bird_eye(rig, Vector3(0.10, 0.10, -0.34))
	# Wings: a pivot at each shoulder with a flat wide plank; _anim_air rotates the pivots to flap.
	_wing_l = Node3D.new()
	_wing_l.position = Vector3(-0.10, 0.07, 0.0)
	rig.add_child(_wing_l)
	_bird_box(_wing_l, Vector3(0.40, 0.04, 0.34), Vector3(-0.22, 0, 0.02), wing_col)
	_wing_r = Node3D.new()
	_wing_r.position = Vector3(0.10, 0.07, 0.0)
	rig.add_child(_wing_r)
	_bird_box(_wing_r, Vector3(0.40, 0.04, 0.34), Vector3(0.22, 0, 0.02), wing_col)
	var sz := float(cfg.get("size", 0.6))
	rig.scale = Vector3.ONE * (sz / 0.9)   # natural wingspan ~0.9 m; scale to the species size
	_model = rig
	_rest_y = 0.0
	_fit_w = 1.0 * (sz / 0.9)               # collider sized to the rig
	_fit_h = 0.3 * (sz / 0.9)
	_fit_d = 0.7 * (sz / 0.9)

func _bird_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	_flash_meshes.append(mi)
	_base_overrides.append(mat)
	return mi

func _bird_eye(parent: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 0.04)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.05)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)        # eyes stay dark (not in _flash_meshes)

# --- damage ---------------------------------------------------------------------------
func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		if _mode == AIR:
			_feather_burst()          # a puff of down where the bird drops
		else:
			_death_poof()             # a burst of the creature's colour for ground/water animals
		if _meat:
			_drop_meat()
		queue_free()
		return
	_flee = 1.4
	_pick_dir(true)

## A small one-shot puff of fluttering feathers (species-coloured) when a bird is killed.
func _feather_burst() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.02, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cfg.get("color", Color(0.85, 0.85, 0.85))
	bm.material = mat
	p.mesh = bm
	p.amount = 12
	p.one_shot = true
	p.lifetime = 1.1
	p.explosiveness = 0.85
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, -2.0, 0)            # feathers flutter gently down
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.emitting = true
	parent.add_child(p)
	p.global_position = global_position + Vector3(0, 0.3, 0)
	p.finished.connect(p.queue_free)

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

## A short burst of the creature's colour when a ground/water animal dies (birds use
## _feather_burst). One-shot, parented to the scene so it outlives the freed creature.
func _death_poof() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.1, 0.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cfg.get("color", Color(0.7, 0.7, 0.7))
	bm.material = mat
	p.mesh = bm
	p.amount = 12
	p.one_shot = true
	p.lifetime = 0.6
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 1.4
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -7.0, 0)
	p.emitting = true
	parent.add_child(p)
	p.global_position = global_position + Vector3(0.0, float(cfg.get("size", 0.8)) * 0.35, 0.0)
	p.finished.connect(p.queue_free)

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
	_amb_tick(delta, 7.0, 14.0)   # cows moo, sheep baa, snakes hiss, etc.

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
	if _model == null or _has_clip:
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
	_amb_tick(delta, 4.0, 9.0)

func _anim_air(delta: float, vy: float) -> void:
	if _model == null or _has_clip:
		return
	# Flap-glide rhythm: flap hard to climb, ease into a glide when descending/cruising — an
	# emergent wingbeat instead of a constant bob. Flap also beats faster the harder it works.
	var flap_target := clampf(0.35 + vy * 0.30, 0.12, 1.0)
	_flap = lerpf(_flap, flap_target, delta * 3.0)
	_phase += delta * (9.0 + _flap * 7.0)
	var beat := sin(_phase)
	_model.position.y = _rest_y + beat * 0.10 * _flap          # body lifts on the downstroke
	var turn := wrapf(rotation.y - _last_yaw, -PI, PI)
	_last_yaw = rotation.y
	_bank = lerpf(_bank, clampf(turn * 7.0, -0.6, 0.6), delta * 5.0)
	_model.rotation.z = _bank                                  # body banks into turns
	_model.rotation.x = lerpf(_model.rotation.x, clampf(-vy * 0.14, -0.45, 0.45), delta * 4.0)  # nose up climbing
	# Flap the actual wings: both sweep together around a resting dihedral. When gliding (low flap
	# envelope) the wings hold a shallow upward V and barely move; when climbing they beat hard.
	if _wing_l != null and _wing_r != null:
		var stroke := beat * (0.35 + 0.70 * _flap)
		var dihedral := lerpf(0.50, 0.12, _flap)   # glide → held up in a V; flapping → flatter
		_wing_l.rotation.z = -(dihedral + stroke)
		_wing_r.rotation.z =  (dihedral + stroke)
	if _tail != null:
		_tail.rotation.y = _bank * 0.6             # tail swings with the bank like a rudder

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
	_anim_water(delta, vy)
	if _bubbles:
		_bubbles.emitting = velocity.length() > 0.4   # bubble only while actually swimming
	_amb_tick(delta, 6.0, 12.0)

## Turn back when the water ahead becomes land/shallows.
func _avoid_shore() -> void:
	if world == null or Vector2(_dir.x, _dir.z).length() < 0.1:
		return
	var ahead := global_position + _dir * 1.6
	if world.surface_height(floori(ahead.x), floori(ahead.z)) >= int(world.SEA_LEVEL):
		var a := atan2(_dir.x, _dir.z) + PI + _rng.randf_range(-0.6, 0.6)
		_dir = Vector3(sin(a), _rng.randf_range(-0.15, 0.15), cos(a)).normalized()
		_timer = _rng.randf_range(1.0, 2.0)

func _anim_water(delta: float, vy: float) -> void:
	if _model == null or _has_clip:
		return
	_phase += delta * (8.0 + _speed * 1.5)
	var wig := sin(_phase)
	# Stronger tail wiggle (yaw) + body roll, AND pitch the body to its dive/climb so it noses
	# up/down through the water instead of swimming dead flat (the old bug).
	_model.rotation.y = _yaw + wig * 0.34
	_model.rotation.z = sin(_phase * 0.6) * 0.12
	_model.rotation.x = lerpf(_model.rotation.x, clampf(-vy * 0.5, -0.5, 0.5), delta * 5.0)

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
	_fit_w = b.size.x * s     # record the fitted footprint + height so the collider can match it
	_fit_h = b.size.y * s
	_fit_d = b.size.z * s

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
