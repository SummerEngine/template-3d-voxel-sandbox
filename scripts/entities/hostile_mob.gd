class_name HostileMob
extends CharacterBody3D
# Night/cave enemy with a jointed rig (walks, reaches, grabs).

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
const CHASE_SPEED := 3.8          # below the player's 5.0 walk — you can back away while fighting
const SIGHT_RANGE := 20.0
const ATTACK_RANGE := 1.6
const ATTACK_CD := 1.3            # slower swings — less burst damage in a pile-up
const ATTACK_WINDUP := 0.45       # brief telegraph before the FIRST hit on contact (no instant ambush)
const DAMAGE := 1
const SEP_RADIUS := 2.0           # mobs closer than this push apart so the horde spreads, not stacks
const SEP_PUSH := 3.6             # strong enough to compete with the chase pull and form a loose ring
const BODY_H := 2.0              # the live code-built rig stands ~2.0 m (head box tops ~1.97) — a touch over the 1.8 m player
const ZOMBIE_HEIGHT := 2.0       # rest-fit target for the UNUSED GLB fallback (_fit_skinned); the rig is the live visual
const HUNCH := -0.18              # permanent forward lean (rad) — a shambling, lunging posture
const ARM_REST := 1.45            # arms reach straight out FRONT (+x rot tips the arm toward -Z, the facing dir)
const RIG_HUNCH := -0.14          # resting forward lean — a shambling posture

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var health := 10
var damage := DAMAGE              # scaled up on harder nights by main.gd
var smarts := 1.0                 # day-scaled intelligence: farther sight, quicker closing, relentless pursuit (set by main.gd)
var _alerted := false             # once it has spotted you it keeps coming within an extended range (pursuit memory)
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
var _emerging := false                 # rising up out of the ground (blood-moon claw-up); freezes movement
var _articulated := false              # true -> code-built blocky rig (swing limbs)
var _anim_player: AnimationPlayer      # the rigged GLB's clip player (null -> procedural rig)
var _clip_walk := ""
var _clip_attack := ""
var _clip_idle := ""
var _attacking := false                # true while the attack clip plays through
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
var _voice_pitch := 1.0                 # per-mob base pitch so each zombie sounds distinct
var _dying := false                     # true once killed — plays a topple before despawning
var _col: CollisionShape3D              # body collider, disabled on death so corpses don't block
var brute := false                      # set by main.gd: bigger, tougher, slower, knockback-resistant
var runner := false                     # set by main.gd: lean, faster, frailer — keeps the horde varied
var day_night                           # DayNight ref (siege mobs only) — they burn in daylight
var _size := 1.0                        # body scale (brutes are larger)
var _speed_mul := 1.0                   # per-type chase speed multiplier (brute slow, runner fast)
var _knockback := Vector3.ZERO          # decaying shove from a player hit
var _sep := Vector3.ZERO                # steer-apart from nearby mobs (recomputed on a throttle)
var _sep_t := 0.0
var _in_range := false                  # in attack range last frame — drives the first-hit wind-up
var _burning := false                   # caught in daylight: smoking, ticking damage, about to drop
var _burn_t := 0.0
var _burn_dmg_t := 0.0
var _sun_check_t := 0.0                  # throttles the daylight-exposure test
var _fire: CPUParticles3D               # ember/smoke VFX while burning

func _ready() -> void:
	add_to_group("mob")
	_rng.randomize()
	if brute:
		_size = 1.5                # a looming, slower heavy that anchors the horde
		_speed_mul = 0.6           # heavy and slow — you can outrun it, not ignore it
	elif runner:
		_size = 0.95               # lean and wiry
		_speed_mul = 1.3           # quick — roughly walk pace, but you can still sprint clear of it

	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = BODY_H * _size              # match the rendered body so headshots register
	cap.radius = 0.32 * _size
	_col.shape = cap
	_col.position = Vector3(0, BODY_H * 0.5 * _size, 0)   # centred so the feet rest on y=0
	add_child(_col)

	_build_visual()
	_setup_sounds()
	_pick_dir()

## Positional zombie audio that emanates from the mob's location.
func _setup_sounds() -> void:
	_snd_groan = _make_snd3d("res://assets/audio/sfx/mobs/zombie_groan.mp3", -3.0)
	_snd_attack = _make_snd3d("res://assets/audio/sfx/mobs/zombie_attack.mp3", -3.5)   # was -1.0 (hottest SFX in the game); N bites summed over the player's own hurt/swing during a siege
	_snd_hurt = _make_snd3d("res://assets/audio/sfx/mobs/zombie_hurt.mp3", -2.0)
	_groan_timer = _rng.randf_range(1.0, 4.0)
	_voice_pitch = _rng.randf_range(0.82, 1.12)   # this zombie's individual voice register
	if brute:
		_voice_pitch *= 0.65                       # brutes growl deeper

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

const ANIMATED_MODEL := "res://assets/models/mobs/animated_zombie.glb"

## The zombie is a CODE-BUILT, jointed blocky rig (real swinging limbs, glowing eyes) — it
## matches the voxel art, animates a proper stride/reach/grab, and has none of the imported
## skinned-GLB pathologies (the provided GLB rendered a 100 m giant / flew off its body). The
## GLB loader below is kept dead-but-available; _build_visual deliberately uses the rig.
func _build_visual() -> void:
	_build_zombie_rig()

func _build_animated_model() -> bool:
	if not ResourceLoader.exists(ANIMATED_MODEL):
		return false
	var packed := load(ANIMATED_MODEL) as PackedScene
	if packed == null:
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		return false
	add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		model.queue_free()
		return false
	_anim_player = players[0] as AnimationPlayer
	model.rotation.y = PI                 # GLBs face +z; flip so the front faces look_at (-z)
	_model = model
	_articulated = false
	_flash_meshes = model.find_children("*", "MeshInstance3D", true, false)
	# Match clips by keyword (the GLB's names are descriptive, e.g. "generate walking motion…").
	var list := _anim_player.get_animation_list()
	_clip_walk = _find_clip(list, ["walk", "run"])
	_clip_attack = _find_clip(list, ["attack", "scream", "punch", "hit", "bite"])
	_clip_idle = _find_clip(list, ["idle"])
	if _clip_idle == "":
		_clip_idle = _clip_walk
	_set_loop(_clip_walk, true)
	_set_loop(_clip_idle, true)
	_set_loop(_clip_attack, false)
	if _clip_idle != "":
		_anim_player.play(_clip_idle)
	_fit_skinned(model, ZOMBIE_HEIGHT * _size)
	return true

## AABB-based fitting (_fit_model) is WRONG for this skinned GLB: its mesh stores a tiny
## internal-scale AABB (~0.0156 m), so dividing target/aabb yields a ~96x scale that drives
## the SKELETON to ~108 m tall — the "giant zombie" bug. Scale by the skeleton's BIND/REST
## bone span instead, measured synchronously: the rest pose is static (no animation/physics
## frame race) and clean (no transient pose extremes that fling the model into the sky).
func _fit_skinned(model: Node3D, target_h: float) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		_fit_model(model, target_h)        # no skeleton: AABB fit is fine for a static mesh
		_model_rest_y = model.position.y
		return
	var skel := skels[0] as Skeleton3D
	# Rest-pose bone origins in MODEL space (handles any internal Armature scale between them).
	var rel := model.global_transform.affine_inverse() * skel.global_transform
	var lo := 1.0e9
	var hi := -1.0e9
	for i in skel.get_bone_count():
		var y: float = (rel * _bone_global_rest(skel, i).origin).y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	var span := hi - lo
	if span <= 0.001:
		return
	var s := target_h / span
	model.scale = Vector3(s, s, s)
	model.position.y = -lo * s              # lowest bone (feet) now rests at the mob origin (y=0)
	_model_rest_y = model.position.y
	# This GLB's skinned mesh stores a near-degenerate AABB (~2 cm), so Godot can frustum-cull
	# the visible body when its tiny box leaves view (zombie "vanishes"). A cull margin spanning
	# the real body keeps it drawn whenever any part is on screen.
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as GeometryInstance3D).extra_cull_margin = maxf(2.0, target_h)

## Accumulate local bone rests up the parent chain → the bind-pose transform in skeleton space.
func _bone_global_rest(skel: Skeleton3D, idx: int) -> Transform3D:
	var t := skel.get_bone_rest(idx)
	var p := skel.get_bone_parent(idx)
	while p != -1:
		t = skel.get_bone_rest(p) * t
		p = skel.get_bone_parent(p)
	return t

## Match by keyword in PRIORITY order: try the first keyword across all clips, then the next,
## so "attack" wins over the "scream" fallback regardless of clip order in the file.
func _find_clip(list: PackedStringArray, keys: Array) -> String:
	for k in keys:
		for n in list:
			if String(n).to_lower().contains(k):
				return n
	return ""

func _set_loop(clip: String, on: bool) -> void:
	if clip == "" or _anim_player == null or not _anim_player.has_animation(clip):
		return
	var a := _anim_player.get_animation(clip)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR if on else Animation.LOOP_NONE

func _build_zombie_rig() -> void:
	var rig := Node3D.new()
	rig.name = "ZombieRig"
	add_child(rig)

	# Per-type palette + build width so the horde reads as varied at a glance.
	var skin := Color(0.36, 0.56, 0.30)   # normal: rotting green
	var shirt := Color(0.27, 0.36, 0.42)
	var pants := Color(0.24, 0.22, 0.32)
	var w := 1.0                          # torso/limb width factor
	if brute:
		skin = Color(0.30, 0.40, 0.22); shirt = Color(0.19, 0.21, 0.20); pants = Color(0.15, 0.14, 0.18)
		w = 1.18                          # thick-set heavy
	elif runner:
		skin = Color(0.52, 0.60, 0.40); shirt = Color(0.42, 0.39, 0.34); pants = Color(0.27, 0.26, 0.30)
		w = 0.8                           # lean and wiry
	_flash_meshes = []

	_box(rig, Vector3(0.52 * w, 0.75, 0.28 * w), Vector3(0, 1.125, 0), shirt)   # torso
	_box(rig, Vector3(0.50, 0.50, 0.50), Vector3(0, 1.72, 0), skin)             # head
	# Eyes on the FRONT (-Z = the look_at facing / movement direction), so it faces where it walks.
	_eye(rig, Vector3(-0.12, 1.78, -0.255))
	_eye(rig, Vector3(0.12, 1.78, -0.255))
	# Arms pivot at the shoulders; ARM_REST swings them out front (toward -Z) — the reaching pose.
	_arm_l = _limb(rig, Vector3(0.18 * w, 0.72, 0.20 * w), Vector3(-0.36 * w, 1.45, 0), skin)
	_arm_r = _limb(rig, Vector3(0.18 * w, 0.72, 0.20 * w), Vector3(0.36 * w, 1.45, 0), skin)
	_arm_l.rotation.x = ARM_REST
	_arm_r.rotation.x = ARM_REST
	_leg_l = _limb(rig, Vector3(0.20 * w, 0.75, 0.22 * w), Vector3(-0.14, 0.75, 0), pants)
	_leg_r = _limb(rig, Vector3(0.20 * w, 0.75, 0.22 * w), Vector3(0.14, 0.75, 0), pants)

	rig.scale = Vector3.ONE * _size       # brutes/runners scaled (collider scaled to match in _ready)
	_model = rig
	_model_rest_y = 0.0
	_articulated = true
	# Night sun energy is ~0.04, so a horde of small blocky bodies each casting a shadow buys
	# almost no visual payoff (faint blocky self-shadows on voxel ground) for tens of extra dynamic
	# shadow casters. Turn shadow casting OFF on every rig mesh.
	for m in rig.find_children("*", "MeshInstance3D", true, false):
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# Rig meshes share one material per colour across EVERY zombie (instead of a fresh
# StandardMaterial3D per box per mob), so a 16-strong horde reuses ~4 materials, not ~112 —
# far fewer state changes for the renderer. flash()/burning use material_override (a separate
# slot), so they layer on top without disturbing these shared surface materials.
static var _MAT_CACHE: Dictionary = {}
static var _EYE_MAT: StandardMaterial3D

static func _shared_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_rgba32()
	if not _MAT_CACHE.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		_MAT_CACHE[key] = m
	return _MAT_CACHE[key]

static func _shared_eye_mat() -> StandardMaterial3D:
	if _EYE_MAT == null:
		_EYE_MAT = StandardMaterial3D.new()
		_EYE_MAT.albedo_color = Color(0.75, 0.05, 0.05)
		_EYE_MAT.emission_enabled = true
		_EYE_MAT.emission = Color(0.9, 0.1, 0.1)
		_EYE_MAT.emission_energy_multiplier = 1.6
	return _EYE_MAT

# The rig's box SIZES are a pure function of mob type (normal/brute/runner), so the 8-mesh set is
# identical across every mob of a given type. Share one BoxMesh per size (like creature.gd's
# _BIRD_MESH_CACHE) so a 24-mob horde reuses ~24 meshes instead of ~192. Scaling stays on rig.scale
# (never per-mesh), so a shared BoxMesh is never resized.
static var _BOX_MESH_CACHE: Dictionary = {}   # Vector3 size -> BoxMesh

static func _box_mesh(size: Vector3) -> BoxMesh:
	if not _BOX_MESH_CACHE.has(size):
		var bm := BoxMesh.new()
		bm.size = size
		_BOX_MESH_CACHE[size] = bm
	return _BOX_MESH_CACHE[size]

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.set_surface_override_material(0, _shared_mat(color))
	mi.position = pos
	parent.add_child(mi)
	_flash_meshes.append(mi)
	return mi

func _eye(parent: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(Vector3(0.10, 0.10, 0.02))
	mi.set_surface_override_material(0, _shared_eye_mat())
	mi.position = pos
	parent.add_child(mi)

func _limb(parent: Node3D, size: Vector3, joint_pos: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = joint_pos
	parent.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.set_surface_override_material(0, _shared_mat(color))
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

## One shared white-emissive flash material for ALL hostiles — constant properties, so a
## blood-moon horde (or a burning mob flashing every 0.5s) doesn't churn identical materials.
static var _FLASH_MAT: StandardMaterial3D
static func _flash_mat() -> StandardMaterial3D:
	if _FLASH_MAT == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 1, 1)
		m.emission_enabled = true
		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = 3.8   # well over the glow HDR threshold so the silhouette blooms white for a frame
		_FLASH_MAT = m
	return _FLASH_MAT

## White hit-flash when struck.
func flash() -> void:
	if _flash_meshes.is_empty():
		return
	var mat := _flash_mat()
	for m in _flash_meshes:
		if is_instance_valid(m):
			m.material_override = mat
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(_clear_flash)

func _clear_flash() -> void:
	for m in _flash_meshes:
		if is_instance_valid(m):
			m.material_override = null

## Shared crumb/ember meshes (with their material baked on) for the death burst and fire VFX, built
## once for ALL mobs — on a blood-moon dawn the whole surviving horde ignites in one frame, so this
## drops ~30 BoxMesh + ~30 (emissive) StandardMaterial3D allocations off the dawn frame. Only the
## per-instance CPUParticles3D still allocates (it must follow/parent to its own moving mob).
static var _DEATH_MESH: BoxMesh
static func _death_mesh() -> BoxMesh:
	if _DEATH_MESH == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.12, 0.12)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.10, 0.10)
		bm.material = mat
		_DEATH_MESH = bm
	return _DEATH_MESH

static var _FIRE_MESH: BoxMesh
static func _fire_mesh() -> BoxMesh:
	if _FIRE_MESH == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.11, 0.11, 0.11)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.55, 0.12)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.1)
		mat.emission_energy_multiplier = 2.5
		bm.material = mat
		_FIRE_MESH = bm
	return _FIRE_MESH

## A burst of dark-red crumbs where the mob fell, parented to the scene so it outlives the
## mob's despawn. One-shot create+free — death is rare, so no pooling needed.
func _death_burst() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var p := CPUParticles3D.new()
	p.mesh = _death_mesh()
	p.amount = 16
	p.one_shot = true
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -9.0, 0)
	p.emitting = true
	parent.add_child(p)
	p.global_position = global_position + Vector3(0, 0.9 * _size, 0)
	p.finished.connect(p.queue_free)

## True when nothing covers this mob's column up to the surface — i.e. it stands in open sky.
func _sky_exposed() -> bool:
	if world == null:
		return true
	var sh: int = world.surface_height(int(global_position.x), int(global_position.z))
	return global_position.y >= float(sh) - 1.0

## Catch fire (daylight, or forced at dawn by main). Emits embers and ticks damage to death.
func ignite() -> void:
	if _burning or _dying:
		return
	_burning = true
	_burn_t = 0.0
	_burn_dmg_t = 0.4
	_spawn_fire_vfx()
	# A low searing whoosh as it catches — staggered per-mob, a burning horde crescendos at dawn.
	if _snd_hurt and _snd_hurt.stream and not _snd_hurt.playing:
		_snd_hurt.pitch_scale = _voice_pitch * _rng.randf_range(0.7, 0.85)
		_snd_hurt.play()

func _burn_tick(delta: float) -> void:
	_burn_t += delta
	_burn_dmg_t -= delta
	if _burn_dmg_t <= 0.0:
		_burn_dmg_t = 0.5
		flash()                          # sear flash each tick
		health -= 2
		if health <= 0:
			_die()

## Rising orange embers + a wisp of smoke, parented to the mob so the fire follows it.
func _spawn_fire_vfx() -> void:
	var p := CPUParticles3D.new()
	p.mesh = _fire_mesh()
	p.amount = 20
	p.lifetime = 0.55
	p.direction = Vector3.UP
	p.spread = 22.0
	p.initial_velocity_min = 1.3
	p.initial_velocity_max = 2.8
	p.gravity = Vector3(0, 1.6, 0)        # embers rise
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	p.position = Vector3(0, BODY_H * 0.5 * _size, 0)
	p.emitting = true
	add_child(p)
	_fire = p

## Drop a little rotten flesh the player can grab (combat reward — not when it burns at dawn).
func _drop_loot() -> void:
	if world == null:
		return
	var n := 2 if brute else (0 if _rng.randf() > 0.7 else 1)
	for i in range(n):
		var drop := preload("res://scripts/world/block_drop.gd").new()
		drop.setup(VoxelTypes.ROTTEN_FLESH, world, player)
		world.add_child(drop)
		drop.global_position = global_position + Vector3(_rng.randf_range(-0.3, 0.3), 0.6, _rng.randf_range(-0.3, 0.3))

## A shove from a player hit (direction = away from the player). Brutes barely budge.
func apply_knockback(dir: Vector3, force: float) -> void:
	if _dying:
		return
	var f := force * (0.2 if brute else 1.0)
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:              # hit from directly above (same column): shove it back from its facing
		flat = -global_transform.basis.z
	_knockback = flat.normalized() * f

func take_damage(amount: int) -> void:
	if _dying:
		return                                  # already toppling — ignore further hits
	if _snd_hurt and _snd_hurt.stream:
		_snd_hurt.pitch_scale = _voice_pitch * _rng.randf_range(0.95, 1.05)
		_snd_hurt.play()
	flash()
	health -= amount
	if health <= 0:
		_die()

## Death: stop the AI, drop the collider so the corpse doesn't block, and topple the body
## over (rotate down + sink + shrink) before despawning — a beat of feedback for the kill.
## Blood-moon claw-up: the body holds still while its visual model rises out of the ground, then
## resumes normal shambling. Driven by main._spawn_clawup right after the dirt burst.
func emerge() -> void:
	if _model == null or not is_instance_valid(_model):
		return
	_emerging = true
	_model.position.y = _model_rest_y - 1.8
	var tw := create_tween()
	tw.tween_property(_model, "position:y", _model_rest_y, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _emerging = false)

func _die() -> void:
	if _dying:
		return                            # already dying — never topple/drop/emit twice
	_dying = true
	# Death rattle: one final low, fading groan so the kill (the best combat beat) actually LANDS.
	# Lower pitch than the alive groan; _dying gates it to exactly once.
	if _snd_groan and _snd_groan.stream:
		_snd_groan.pitch_scale = _voice_pitch * _rng.randf_range(0.5, 0.65)
		_snd_groan.play()
	velocity = Vector3.ZERO
	if _anim_player:
		_anim_player.stop()           # freeze the clip so the corpse doesn't walk while toppling
	if _fire and is_instance_valid(_fire):
		_fire.emitting = false        # stop spewing embers as it topples
	if not _burning:
		_drop_loot()                  # combat kills reward flesh; dawn-burned corpses don't litter
	_death_burst()
	# Only a real combat kill counts toward the player's kill stat — a horde burning at dawn
	# shouldn't credit the player with kills they never made.
	if not _burning and player and is_instance_valid(player) and player.has_signal("mob_killed"):
		player.emit_signal("mob_killed")
		if player.has_signal("mob_died_at"):
			player.emit_signal("mob_died_at", global_position)   # Hauntfields: mark this kill spot
	if _col:
		_col.set_deferred("disabled", true)
	if _model and is_instance_valid(_model):
		var tw := create_tween()
		tw.tween_property(_model, "rotation:x", _model.rotation.x + deg_to_rad(-95.0), 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_model, "position:y", _model_rest_y - 0.5, 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_model, "scale", _model.scale * 0.6, 0.55) \
			.set_delay(0.1)
		tw.tween_callback(func() -> void:
			if player and is_instance_valid(player) and player.has_method("_emit_burst"):
				player._emit_burst(global_position + Vector3(0, 0.25, 0), Color(0.32, 0.30, 0.28), 10, 0.5, 78.0, 0.7, 1.8, 2.5))   # dark puff masks the pop-out
		tw.tween_callback(queue_free)
	else:
		queue_free()

func _physics_process(delta: float) -> void:
	if _dying:
		return                                  # frozen while the death topple tween plays
	if _emerging:
		# Clawing up out of the ground: hold AI + horizontal movement, but STILL apply gravity so a
		# body whose feet were placed over air (solid_top_y+1) settles down instead of hanging
		# suspended for the ~0.7s emerge tween. Must return BEFORE _animate() — the emerge tween owns
		# _model.position.y, so the walk/bob animator must not fight it.
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	if _attack_cd > 0.0:
		_attack_cd -= delta

	# Daylight kills the undead: a siege mob caught under open sky once day breaks catches
	# fire and burns down (the classic Minecraft rule). Cave lurkers have no day_night ref,
	# so they never burn underground.
	if day_night != null and not _burning:
		_sun_check_t -= delta
		if _sun_check_t <= 0.0:
			_sun_check_t = 0.7
			if not day_night.is_night() and _sky_exposed():
				ignite()
	if _burning:
		_burn_tick(delta)
		if _dying:
			return                              # burned to death this frame — stop here

	# Periodic menacing groan from the mob's position.
	_groan_timer -= delta
	if _groan_timer <= 0.0:
		_groan_timer = _rng.randf_range(3.5, 8.0)
		if _snd_groan and _snd_groan.stream and not _snd_groan.playing:
			_snd_groan.pitch_scale = _voice_pitch * _rng.randf_range(0.95, 1.05)
			_snd_groan.play()

	var chasing := false
	if player and is_instance_valid(player):
		var to: Vector3 = player.global_position - global_position
		var flat := Vector3(to.x, 0.0, to.z)
		var dist := flat.length()
		var sight := SIGHT_RANGE * smarts
		if _alerted:
			sight *= 1.6                        # already spotted you — it keeps coming (relentless pursuit memory)
		if dist < sight:
			chasing = true
			_alerted = true
			if dist > 0.05:
				_dir = flat.normalized()
			if dist < ATTACK_RANGE and absf(to.y) < 1.6:
				if not _in_range:
					_in_range = true               # just reached the player — wind up, don't hit instantly
					if _attack_cd < ATTACK_WINDUP:
						_attack_cd = ATTACK_WINDUP
					if _snd_groan and _snd_groan.stream and not _snd_groan.playing:
						_snd_groan.pitch_scale = _voice_pitch * _rng.randf_range(1.05, 1.2)   # tense pre-strike snarl telegraphs the hit
						_snd_groan.play()
				elif _attack_cd <= 0.0:
					_attack_cd = ATTACK_CD
					_punch = 1.0                       # procedural-rig lunge
					_attacking = true                  # rigged-model: trigger the attack clip
					if _snd_attack and _snd_attack.stream:
						_snd_attack.pitch_scale = _voice_pitch * _rng.randf_range(0.95, 1.05)
						_snd_attack.play()
					if player.has_method("hurt"):
						player.hurt(damage, global_position)   # position lets the HUD flash the edge facing us
						if player.has_method("push"):
							var kb := Vector3(to.x, 0.0, to.z).normalized()   # shove the player back
							player.push(kb * (5.0 if brute else 3.0) + Vector3.UP * 1.2)
			else:
				_in_range = false                  # left range — next contact gets a fresh wind-up

	if not chasing:
		_in_range = false              # out of sight — a fresh approach earns a new first-hit wind-up
		_alerted = false               # truly lost you (beyond even the extended pursuit range)
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
	# Steer apart from nearby mobs (throttled) so the horde fans out around the player and
	# shambles past each other instead of piling into one jittering stack on the same spot.
	_sep_t -= delta
	if _sep_t <= 0.0:
		_sep_t = 0.2
		_compute_separation()
	var spd := (CHASE_SPEED if chasing else SPEED) * _speed_mul   # brutes slow, runners fast
	if chasing:
		spd *= clampf(smarts, 1.0, 1.25)                          # a smarter, later-night horde closes in quicker
	velocity.x = _dir.x * spd + _knockback.x + _sep.x
	velocity.z = _dir.z * spd + _knockback.z + _sep.z
	_knockback = _knockback.lerp(Vector3.ZERO, delta * 8.0)   # shove decays fast

	if _dir.length() > 0.1:
		look_at(global_position + Vector3(_dir.x, 0.0, _dir.z), Vector3.UP)

	move_and_slide()
	_animate(delta)

	if global_position.y < -20.0:
		queue_free()

## Accumulate a push away from up to a few nearby mobs (zombies + fauna share the "mob" group),
## so a converging horde spreads into a loose ring instead of stacking on one point. Throttled
## (every 0.2 s) and capped at 6 neighbours, so it's cheap even on a full blood-moon siege.
# Memoize the "mob" group query to ONE call per frame, shared by every HostileMob AND every
# Animal (they call HostileMob.mobs_snapshot too). Was a fresh whole-group Array allocation per
# mob per ~0.2s throttle tick — O(N) allocs on top of the O(N²) neighbour scan every siege frame.
# Same membership as get_nodes_in_group, so it's output-identical; iterators still guard with
# is_instance_valid since a cached snapshot can briefly outlive a queue_free'd node.
static var _mob_cache: Array = []
static var _mob_frame := -1
static func mobs_snapshot(tree: SceneTree) -> Array:
	var f := Engine.get_process_frames()
	if f != _mob_frame:
		_mob_frame = f
		_mob_cache = tree.get_nodes_in_group("mob")
	return _mob_cache

func _compute_separation() -> void:
	_sep = Vector3.ZERO
	var count := 0
	var r2 := SEP_RADIUS * SEP_RADIUS   # compare squared distances; skip the sqrt for the far majority
	for m in HostileMob.mobs_snapshot(get_tree()):
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
	if _anim_player != null:
		_anim_clips()                 # rigged GLB: real skeletal walk/attack/idle clips
		return
	if _model == null:
		return
	if _articulated:
		_anim_articulated(delta)
	else:
		_anim_shamble(delta)

## Drive the rigged model's clips: the attack clip plays to completion, otherwise walk while
## moving / idle while still.
func _anim_clips() -> void:
	if _attacking:
		if _anim_player.current_animation != _clip_attack:
			if _clip_attack == "":
				_attacking = false
			else:
				_anim_player.play(_clip_attack)
				return
		elif _anim_player.is_playing():
			return                    # let the grab finish before resuming locomotion
		else:
			_attacking = false
	var horiz := Vector2(velocity.x, velocity.z).length()
	var want := _clip_walk if horiz > 0.2 else _clip_idle
	if want != "" and _anim_player.current_animation != want:
		_anim_player.play(want, 0.15)

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

## The jointed rig animation: legs stride while walking, arms held out front and waving (the
## classic "reaching for you" pose, animated even when standing still), body hunched and bobbing,
## and both arms thrust forward in a grabbing lunge when it attacks.
func _anim_articulated(delta: float) -> void:
	# Attack: lunge the body forward and thrust both arms out to grab.
	if _punch > 0.0:
		_punch = maxf(0.0, _punch - delta * 3.5)        # ~0.3s grab
		var arc := sin((1.0 - _punch) * PI)             # 0 -> 1 -> 0
		_model.rotation.x = RIG_HUNCH - 0.5 * arc       # body lunges forward from the hunch
		_model.position.y = _model_rest_y - 0.05 * arc
		var thrust := ARM_REST + 0.5 * arc              # arms snap further forward/up to grab
		_arm_l.rotation.x = thrust
		_arm_r.rotation.x = thrust
		_arm_l.rotation.z = 0.0
		_arm_r.rotation.z = 0.0
		return
	_model.rotation.x = lerpf(_model.rotation.x, RIG_HUNCH, delta * 8.0)   # ease back to the hunch
	var horiz := Vector2(velocity.x, velocity.z).length()
	# Phase runs fast while walking, slow while standing — so the arms keep waving either way.
	_walk_phase += delta * ((4.0 + horiz * 1.2) if horiz > 0.2 else 1.8)
	var wave := sin(_walk_phase)
	if horiz > 0.2:
		_leg_l.rotation.x = wave * 0.8                  # legs stride
		_leg_r.rotation.x = -wave * 0.8
		_model.position.y = _model_rest_y + absf(wave) * 0.06   # body bob
		_model.rotation.z = wave * 0.06                 # weight shift side to side
	else:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, delta * 8.0)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, delta * 8.0)
		_model.position.y = lerpf(_model.position.y, _model_rest_y, delta * 6.0)
		_model.rotation.z = lerpf(_model.rotation.z, 0.0, delta * 6.0)
	# Arms always reach out front, bobbing up/down (opposite) and splayed/swaying side to side.
	_arm_l.rotation.x = ARM_REST + wave * 0.20
	_arm_r.rotation.x = ARM_REST - wave * 0.20
	_arm_l.rotation.z = 0.14 + sin(_walk_phase * 0.6) * 0.10
	_arm_r.rotation.z = -0.14 - sin(_walk_phase * 0.6) * 0.10
