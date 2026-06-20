class_name Player
extends CharacterBody3D

## Emitted on gameplay milestones so the advancements system can track progress
## without the player needing to know about it.
signal block_harvested(id: int)
signal item_crafted(id: int)
@warning_ignore("unused_signal")   # emitted by HostileMob on death
signal mob_killed
@warning_ignore("unused_signal")   # emitted by main.gd on the day transition
signal night_survived
@warning_ignore("unused_signal")   # main.gd listens to clear spawn-camping hostiles
signal respawned

## Third-person (toggle first-person) Minecraft-style controller.
## Move WASD, look mouse, Space jump (double-tap or F = fly), Ctrl sprint, Shift
## descend while flying. 1-9 / scroll pick a hotbar slot, Q/E switch weapon.
## HOLD Left Mouse to mine a block (timed by hardness vs weapon mining power) or to
## attack a mob; Right Mouse places the selected block (consumed from the hotbar).
## G eats an apple, C opens crafting, F5 toggles view. Esc is owned by PauseMenu.

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const FLY_SPEED := 10.0
const InputActions := preload("res://scripts/core/input_actions.gd")
const JUMP_VELOCITY := 5.0
const SWIM_UP_SPEED := 4.0
const MOUSE_SENS := 0.0025          # base look sensitivity; mouse_sens scales this via settings
var mouse_sens := MOUSE_SENS
const REACH := 6.0
const FALL_DAMAGE_SPEED := 16.0
const VOID_Y := -40.0
const DOUBLE_TAP_MS := 300
const STEP_INTERVAL := 0.38

const CAM_HEIGHT := 1.5
const CAM_DISTANCE := 4.5
const PITCH_MIN := -1.2
const PITCH_MAX := 0.6
const TURN_SPEED := 12.0

# Movement feel: a touch of FOV widening when sprinting + a subtle walk bob.
const BASE_FOV := 75.0
const SPRINT_FOV := 83.0
const BOB_FREQ := 9.0      # bob cycles per second of stride
const BOB_AMP := 0.035     # metres of vertical camera travel at full speed

# Original mascot: the voxel explorer-bot (replaces the old humanoid to keep the
# character unique / copyright-clean). The base glb carries the walk cycle; run +
# idle are merged in from sibling clips (same rig) at load.
const MODEL_PATH := "res://assets/models/characters/anim/bot_walk.glb"
const ANIM_RUN_PATH := "res://assets/models/characters/anim/bot_run.glb"
const ANIM_IDLE_PATH := "res://assets/models/characters/anim/bot_idle.glb"
const ANIM_ATTACK_PATH := "res://assets/models/characters/anim/bot_attack.glb"
const ANIM_JUMP_PATH := "res://assets/models/characters/anim/bot_jump.glb"
const MODEL_SCALE := 1.0
const MODEL_YAW_OFFSET := 0.0

# hunger / vitals
const MAX_HUNGER := 6
const HUNGER_IDLE := 0.006        # ~3x slower than before — hunger is a slow burn, not a metronome
const HUNGER_MOVE := 0.016
const HUNGER_SPRINT := 0.04
const VITAL_TICK := 2.0
const REGEN_BLOCK_TIME := 5.0     # no passive heal for this long after taking a hit

var hud
var world_manager
var farm                          # FarmManager (planting / harvesting crops); set by main.gd

var yaw_pivot: Node3D
var pitch_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var ray: RayCast3D
var model: Node3D
var anim_player: AnimationPlayer
var weapon_holder
var owned_tools: Array = []   # tools/weapons the player has earned (earn-your-gear)
var highlight: MeshInstance3D
var _crack: MeshInstance3D
var _crack_mat: ShaderMaterial

var _swing_cd := 0.0
var _place_cd := 0.0
var _last_space_ms := 0
var _step_timer := 0.0
var _bob_phase := 0.0
var _land_squash := 0.0       # 1->0 camera dip on landing, scaled by fall speed
var _rmb_down := false
var _dead := false
var _death_prev_fp := true       # view to restore after the death cam
var _death_tween: Tween
var _hurt_cd := 0.0
var _invuln := 0.0               # brief spawn protection so you can't be instantly re-killed
var _vital_timer := VITAL_TICK
var _cam_trauma := 0.0          # 0..1 screen-shake accumulator (quadratic falloff)

var walk_anim := ""
var mine_anim := ""
var run_anim := ""
var idle_anim := ""
var jump_anim := ""

var flying := false
var first_person := true   # default to first-person: a clean animated weapon viewmodel
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _mine_timer := 0.0

var max_health := 6
var health := 6
var armor_tier := 0          # 0 none, 1 iron, 2 diamond
var armor_name := ""
const ARMOR_REDUCTION := {1: 0.4, 2: 0.7}   # fraction of incoming damage blocked
var hunger := float(MAX_HUNGER)
var spawn_point := Vector3(0, 4, 0)
var _was_on_floor := true
var _fall_speed := 0.0
var _horiz_speed := 0.0          # horizontal speed, computed once per frame after move_and_slide
var _jump_sfx_cd := 0.0          # throttles jump push-off feedback so a held bounce can't spam it
var _landed_once := false
var _ext_push := Vector3.ZERO   # one-frame external shove (e.g. mob knockback), applied with collision
var _regen_block := 0.0         # seconds remaining where passive health regen is suppressed (post-hit)

var inventory: Inventory
var selected := 0
var _mine_cell := Vector3i(2147483647, 0, 0)
var _mine_progress := 0.0

# sounds — the snd_* players are config holders (stream + volume); actual playback goes
# through a small pool of voices so rapid one-shots layer instead of cutting each other off.
const _SFX_VOICES := 10
var _voices: Array[AudioStreamPlayer] = []
var _voice_i := 0
var _was_submerged := false        # head-underwater state, drives the muffle effect
var _was_in_water := false         # feet-in-water state, drives the entry splash
# Pooled one-shot burst emitters (block-break crumbs, land-dust) — reused instead of
# allocating a fresh CPUParticles3D + mesh + material on every mine/landing.
const _VFX_POOL := 12
var _vfx_pool: Array[CPUParticles3D] = []
var _vfx_i := 0
static var _vfx_mesh: BoxMesh
static var _vfx_mat: StandardMaterial3D
var snd_break_soft: AudioStreamPlayer
var snd_break_hard: AudioStreamPlayer
var snd_break_dirt: AudioStreamPlayer
var snd_break_wood: AudioStreamPlayer
var snd_break_glass: AudioStreamPlayer
var snd_place: AudioStreamPlayer
var snd_step_grass: AudioStreamPlayer
var snd_step_stone: AudioStreamPlayer
var snd_step_sand: AudioStreamPlayer
var snd_step_wood: AudioStreamPlayer
var snd_hurt: AudioStreamPlayer
var snd_death: AudioStreamPlayer
var snd_swing: AudioStreamPlayer
var snd_eat: AudioStreamPlayer
var snd_pickup: AudioStreamPlayer
var snd_monster: AudioStreamPlayer
var snd_swim: AudioStreamPlayer

func _ready() -> void:
	InputActions.setup()   # ensure movement actions exist (idempotent; main.gd also calls it)
	inventory = Inventory.new()
	_give_starter_kit()

	# Cylinder, not capsule: a flat bottom stands firmly on block edges instead of
	# sliding off ledges, while round sides still slide smoothly along walls.
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.height = 1.8
	cyl.radius = 0.4
	col.shape = cyl
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
	_setup_audio()
	_setup_vfx()
	_setup_highlight()
	_setup_light()
	_setup_ambient_motes()   # drifting dust motes in the air for atmosphere
	_apply_view()   # first-person by default: hide the body, show the animated viewmodel

	spawn_point = global_position
	_landed_once = false
	_invuln = 2.0                  # brief grace on first spawn / world load
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if hud and hud.has_signal("respawn_requested"):
		hud.respawn_requested.connect(_do_respawn)
	_update_hud()

## Faint, near-weightless dust motes drifting in the air around the player. World-space
## (local_coords off) so you move THROUGH them; the emitter follows the player so the air
## always has a little life. Unshaded + softly emissive so they catch the eye day or night.
func _setup_ambient_motes() -> void:
	# Always-on ambient dust. Runs on GPUParticles3D so its 60 particles simulate on the GPU
	# (which has headroom) instead of costing main-thread time every frame for the whole game.
	var p := GPUParticles3D.new()
	p.local_coords = false
	p.amount = 60
	p.lifetime = 9.0
	p.preprocess = 5.0                                   # start with the air already full
	p.position = Vector3(0, 2.0, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(15, 7, 15)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.gravity = Vector3(0, 0.02, 0)                     # almost weightless, faint upward drift
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.22
	pm.damping_min = 0.05
	pm.damping_max = 0.15
	pm.scale_min = 0.02                                  # CPUParticles3D.scale_amount_* -> scale_min/max here
	pm.scale_max = 0.045
	p.process_material = pm
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.96, 0.82, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.95, 0.8)
	mat.emission_energy_multiplier = 0.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	p.draw_pass_1 = m
	p.emitting = true
	add_child(p)

func _give_starter_kit() -> void:
	inventory.add(VoxelTypes.GRASS, 32)
	inventory.add(VoxelTypes.DIRT, 32)
	inventory.add(VoxelTypes.STONE, 32)
	inventory.add(VoxelTypes.COBBLESTONE, 16)
	inventory.add(VoxelTypes.PLANKS, 16)
	inventory.add(VoxelTypes.GLASS, 16)
	inventory.add(VoxelTypes.WOOD, 8)
	inventory.add(VoxelTypes.TORCH, 16)   # light for the now-dark caves/nights

var body_meshes: Array = []   # the player's body meshes (hidden in first person)
var _viewmodel: Node3D        # held tool shown in front of the camera in first person
const VM_REST_POS := Vector3(0.3, -0.32, -0.62)   # viewmodel resting offset from camera
const VM_REST_ROT := Vector3(8, 90, -45)          # yaw faces the pick head toward the crosshair; -45 roll counters the baked tilt
var _vm_phase := 0.0          # bob/sway phase
var _vm_swing := 0.0          # 1->0 swing progress when mining/attacking
var _vm_place := 0.0          # 1->0 forward "push" when placing a block

func _setup_model() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
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
		_install_bot_animations()
		_set_loop(walk_anim)
		_set_loop(run_anim)
		if walk_anim != "":
			anim_player.play(walk_anim)
			anim_player.speed_scale = 0.0

	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	# Collect the body meshes BEFORE the weapon is attached, so first-person can hide
	# the body while keeping the held tool visible.
	body_meshes = model.find_children("*", "MeshInstance3D", true, false)
	weapon_holder = preload("res://scripts/player/weapon_holder.gd").new()
	add_child(weapon_holder)
	owned_tools = _starter_tools()
	weapon_holder.setup(skel, owned_tools)

## Earn-your-gear: you begin owning only a Wooden Hammer (equipped) + Bare Hands.
## Everything else is crafted (tiered tools/swords) or unlocked via advancements.
func _starter_tools() -> Array:
	var out: Array = []
	for n in ["Wooden Hammer", "Bare Hands"]:
		var w := WeaponRegistry.by_name(n)
		if not w.is_empty():
			out.append(w)
	return out

func owns_tool(tool_name: String) -> bool:
	for w in owned_tools:
		if String(w.get("name", "")) == tool_name:
			return true
	return false

## Acquired a tool/weapon: add it to the owned set. Crafting equips it; an advancement
## reward (do_equip=false) just adds it so it doesn't yank your weapon mid-fight.
func unlock_tool(tool_name: String, do_equip := true) -> void:
	if owns_tool(tool_name):
		return
	var w := WeaponRegistry.by_name(tool_name)
	if w.is_empty():
		return
	owned_tools.append(w)
	if weapon_holder:
		weapon_holder.add_weapon(w, do_equip)
	if do_equip:
		_build_viewmodel()
	_update_hud()
	emit_signal("item_crafted", -1)   # advancements watch tool crafting too

## Crafted armor: only upgrades (never downgrades). Reduces incoming damage in hurt().
func set_armor_tier(tier: int, aname: String) -> void:
	if tier <= armor_tier:
		return
	armor_tier = tier
	armor_name = aname
	if hud:
		if hud.has_method("set_armor"):
			hud.set_armor(armor_name)
		if hud.has_method("show_toast"):
			hud.show_toast("Equipped %s" % aname, Color(0.7, 0.9, 1.0))
	emit_signal("item_crafted", -1)

func _setup_audio() -> void:
	snd_break_soft = _make_snd("res://assets/audio/sfx/blocks/break_soft.mp3", -4.0)
	snd_break_hard = _make_snd("res://assets/audio/sfx/blocks/break_hard.mp3", -4.0)
	snd_break_dirt = _make_snd("res://assets/audio/sfx/blocks/break_dirt.mp3", -4.0)
	snd_break_wood = _make_snd("res://assets/audio/sfx/blocks/break_wood.mp3", -4.0)
	snd_break_glass = _make_snd("res://assets/audio/sfx/blocks/break_glass.mp3", -4.0)
	snd_place      = _make_snd("res://assets/audio/sfx/blocks/place.mp3",      -6.0)
	snd_step_grass = _make_snd("res://assets/audio/sfx/player/step_grass.mp3", -8.0)
	snd_step_stone = _make_snd("res://assets/audio/sfx/player/step_stone.mp3", -8.0)
	snd_step_sand  = _make_snd("res://assets/audio/sfx/player/step_sand.mp3",  -8.0)
	snd_step_wood  = _make_snd("res://assets/audio/sfx/player/step_wood.mp3",  -9.0)
	snd_hurt       = _make_snd("res://assets/audio/sfx/player/hurt.mp3",       -3.0)
	snd_death      = _make_snd("res://assets/audio/sfx/player/death.mp3",      -2.0)
	snd_swing      = _make_snd("res://assets/audio/sfx/player/swing.mp3",      -7.0)
	snd_eat        = _make_snd("res://assets/audio/sfx/player/eat.mp3",        -4.0)
	snd_pickup     = _make_snd("res://assets/audio/sfx/items/pickup.mp3",      -6.0)
	snd_monster    = _make_snd("res://assets/audio/sfx/mobs/monster_hurt.mp3", -5.0)
	snd_swim       = _make_snd("res://assets/audio/sfx/fauna/splash.mp3",      -13.0)   # swim-stroke splash

	# Pooled playback voices: one-shots (mining swings, footsteps, a burst of pickups) play on
	# a free voice so they overlap naturally instead of restarting the one shared player.
	for _i in range(_SFX_VOICES):
		var v := AudioStreamPlayer.new()
		if AudioServer.get_bus_index("SFX") != -1:
			v.bus = "SFX"
		add_child(v)
		_voices.append(v)

func _make_snd(path: String, vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.volume_db = vol_db
	if AudioServer.get_bus_index("SFX") != -1:
		p.bus = "SFX"
	add_child(p)
	return p

func _play_snd(p: AudioStreamPlayer) -> void:
	if p == null or p.stream == null:
		return
	var v := _free_voice()
	if v == null:
		v = p                          # pool not ready yet — fall back to the holder itself
	v.stream = p.stream
	v.volume_db = p.volume_db
	v.pitch_scale = randf_range(0.9, 1.1)
	v.play()

## A pooled voice that isn't currently playing, else the next round-robin one (steals the
## oldest). Returns null only before the pool is built (very early calls fall back to the holder).
func _free_voice() -> AudioStreamPlayer:
	if _voices.is_empty():
		return null
	for _i in range(_voices.size()):
		var cand := _voices[_voice_i]
		_voice_i = (_voice_i + 1) % _voices.size()
		if not cand.playing:
			return cand
	var v := _voices[_voice_i]
	_voice_i = (_voice_i + 1) % _voices.size()
	return v

func play_craft_sound() -> void:
	_play_snd(snd_place)

## Settings hook: scale look speed off the base sensitivity (1.0 = default).
func set_sensitivity(mult: float) -> void:
	mouse_sens = MOUSE_SENS * clampf(mult, 0.1, 4.0)

# --- pooled one-shot particle bursts -------------------------------------------------
# One BoxMesh + one material are shared by every burst; per-burst tint rides the particle
# COLOR (vertex_color_use_as_albedo), so a burst costs zero resource allocation.

static func _shared_vfx_mesh() -> BoxMesh:
	if _vfx_mesh == null:
		_vfx_mesh = BoxMesh.new()
		_vfx_mesh.size = Vector3(0.11, 0.11, 0.11)
		_vfx_mesh.material = _shared_vfx_mat()
	return _vfx_mesh

static func _shared_vfx_mat() -> StandardMaterial3D:
	if _vfx_mat == null:
		# Default (lit) shading, matching the original per-burst materials; the per-burst
		# CPUParticles3D.color rides the instance COLOR via vertex_color_use_as_albedo.
		_vfx_mat = StandardMaterial3D.new()
		_vfx_mat.vertex_color_use_as_albedo = true
	return _vfx_mat

func _setup_vfx() -> void:
	if world_manager == null:
		return
	for _i in range(_VFX_POOL):
		var p := CPUParticles3D.new()
		p.mesh = _shared_vfx_mesh()
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 0.9
		p.direction = Vector3.UP
		world_manager.add_child(p)
		_vfx_pool.append(p)

## Fire a reused one-shot burst at `pos`, tinted `color`. Falls back to nothing if the pool
## isn't ready (very early calls). gravity is the downward accel magnitude (positive number).
func _emit_burst(pos: Vector3, color: Color, amount: int, life: float, spread: float,
		vmin: float, vmax: float, grav: float) -> void:
	var p := _free_vfx()
	if p == null:
		return
	p.amount = amount
	p.lifetime = life
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, -grav, 0)
	p.color = color
	p.global_position = pos
	p.restart()
	p.emitting = true

## A pooled burst emitter that isn't currently emitting, else the next round-robin one.
func _free_vfx() -> CPUParticles3D:
	if _vfx_pool.is_empty():
		return null
	for _i in range(_vfx_pool.size()):
		var cand := _vfx_pool[_vfx_i]
		_vfx_i = (_vfx_i + 1) % _vfx_pool.size()
		if not cand.emitting:
			return cand
	var p := _vfx_pool[_vfx_i]
	_vfx_i = (_vfx_i + 1) % _vfx_pool.size()
	return p

func _setup_highlight() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var lo := -0.002
	var hi := 1.002
	var c := [Vector3(lo, lo, lo), Vector3(hi, lo, lo), Vector3(hi, lo, hi), Vector3(lo, lo, hi),
			Vector3(lo, hi, lo), Vector3(hi, hi, lo), Vector3(hi, hi, hi), Vector3(lo, hi, hi)]
	var edges := [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]
	for e in edges:
		st.add_vertex(c[e[0]])
		st.add_vertex(c[e[1]])
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0, 0, 0, 0.9)
	highlight = MeshInstance3D.new()
	highlight.mesh = st.commit()
	highlight.material_override = mat
	highlight.visible = false
	if world_manager:
		world_manager.add_child(highlight)
	else:
		add_child(highlight)
	_setup_crack()

## Procedural crack overlay: a unit cube whose `crack.gdshader` spreads cracks as mining
## progresses. Centred on the block being mined and shown only while progress > 0.
func _setup_crack() -> void:
	var shader := load("res://assets/materials/crack.gdshader")
	if shader == null:
		return
	_crack_mat = ShaderMaterial.new()
	_crack_mat.shader = shader
	_crack_mat.set_shader_parameter("progress", 0.0)
	var box := BoxMesh.new()
	box.size = Vector3(1.006, 1.006, 1.006)   # a hair larger than the block, no z-fighting
	_crack = MeshInstance3D.new()
	_crack.mesh = box
	_crack.material_override = _crack_mat
	_crack.visible = false
	if world_manager:
		world_manager.add_child(_crack)
	else:
		add_child(_crack)

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

## The bot's base glb ships one clip (the walk cycle); pull run + idle in from the
## sibling clip glbs (identical rig, so the bone tracks resolve) and register them
## under stable names so the animation logic doesn't depend on glb-internal naming.
func _install_bot_animations() -> void:
	var existing := anim_player.get_animation_list()
	walk_anim = String(existing[0]) if existing.size() > 0 else ""
	var lib := anim_player.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		anim_player.add_animation_library("", lib)
	run_anim = _add_external_anim(ANIM_RUN_PATH, "run", lib)
	mine_anim = _add_external_anim(ANIM_ATTACK_PATH, "attack", lib)   # body swings when mining/fighting
	jump_anim = _add_external_anim(ANIM_JUMP_PATH, "jump", lib)       # airborne pose
	idle_anim = _add_external_anim(ANIM_IDLE_PATH, "idle", lib)

## Load a clip glb, copy its first animation into our AnimationPlayer's library under
## `anim_name`, and return that name (or "" on failure). Frees the temp instance.
func _add_external_anim(path: String, anim_name: String, lib: AnimationLibrary) -> String:
	if not ResourceLoader.exists(path):
		return ""
	var packed := load(path) as PackedScene
	if packed == null:
		return ""
	var inst := packed.instantiate()
	var src := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var result := ""
	if src:
		for a in src.get_animation_list():
			var clip := src.get_animation(a)
			if clip:
				var dup: Animation = clip.duplicate(true)
				dup.loop_mode = Animation.LOOP_LINEAR   # loop so it never reverts to the T-pose
				lib.add_animation(anim_name, dup)
				result = anim_name
				break
	inst.free()
	return result

func _update_hud() -> void:
	if hud == null:
		return
	hud.set_health(health, max_health)
	hud.set_hunger(int(ceil(hunger)), MAX_HUNGER)
	hud.update_hotbar(inventory.slots, selected)
	if weapon_holder:
		var w: Dictionary = weapon_holder.current()
		if not w.is_empty():
			hud.set_tool("%s  (dmg %d  spd %.1f  mine x%.1f)" % [String(w.name), int(w.damage), float(w.attack_speed), float(w.mining_power)])

func on_inventory_changed() -> void:
	if hud:
		hud.update_hotbar(inventory.slots, selected)

func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		# While dead, only R respawns; ignore everything else so a stray click can't
		# re-capture the mouse and steal it from the Respawn button.
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
			_do_respawn()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw_pivot.rotate_y(-event.relative.x * mouse_sens)
		pitch_pivot.rotation.x = clampf(pitch_pivot.rotation.x - event.relative.y * mouse_sens, PITCH_MIN, PITCH_MAX)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select(selected - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select(selected + 1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return                  # a menu (crafting/chest/pause) or the death screen owns input — ignore gameplay hotkeys
		if event.is_action_pressed("jump"):
			var now := Time.get_ticks_msec()
			if now - _last_space_ms < DOUBLE_TAP_MS:
				flying = not flying
				if flying: velocity = Vector3.ZERO
			_last_space_ms = now
			return
		match event.keycode:
			KEY_F:
				flying = not flying
				if flying: velocity = Vector3.ZERO
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				_select(event.keycode - KEY_1)
			KEY_Q:
				if weapon_holder: weapon_holder.prev()
				_build_viewmodel()
				_update_hud()
			KEY_E:
				if weapon_holder: weapon_holder.next()
				_build_viewmodel()
				_update_hud()
			KEY_G:
				_try_eat()
			KEY_F5:
				_toggle_view()

func _select(idx: int) -> void:
	selected = (idx + Inventory.HOTBAR) % Inventory.HOTBAR
	on_inventory_changed()
	if hud:
		hud.update_hotbar(inventory.slots, selected)

func _toggle_view() -> void:
	first_person = not first_person
	_apply_view()

## Apply the current view: first-person hides the whole character (body AND the weapon
## attached to its hand) and shows the animated viewmodel; third-person shows the body.
func _apply_view() -> void:
	if model and is_instance_valid(model):
		model.visible = not first_person   # hides body + hand-held weapon together in FP
	if weapon_holder:
		weapon_holder.set_world_visible(not first_person)   # belt-and-suspenders: no duplicate weapon in FP
	if first_person:
		spring.spring_length = 0.0
		ray.target_position = Vector3(0, 0, -REACH)
	else:
		spring.spring_length = CAM_DISTANCE
		ray.target_position = Vector3(0, 0, -(CAM_DISTANCE + REACH))
		if camera:
			camera.position = Vector3.ZERO   # clear any leftover first-person view bob
			camera.rotation.z = 0.0
	_build_viewmodel()

## In first person, show what the player is holding as a SINGLE object in front of the
## camera: the equipped weapon/tool when one is held, otherwise the bare fist. We never
## draw the fist AND a weapon together — two separate generated meshes never align cleanly
## and read as "holding two things"; a single object always looks right.
func _build_viewmodel() -> void:
	if _viewmodel and is_instance_valid(_viewmodel):
		_viewmodel.free()          # immediate (not queue_free) so the old weapon never overlaps the new
		_viewmodel = null
	if not first_person or camera == null:
		return
	# Root sits in front of the camera and is animated as one unit (bob / sway / swing).
	var root := Node3D.new()
	camera.add_child(root)
	root.position = VM_REST_POS
	_viewmodel = root
	_vm_phase = 0.0

	# Resolve the held weapon's model. Bare hands (or a tool with no model) falls back to the
	# fist, which then becomes the single held object — never shown alongside a weapon.
	var path := ""
	var cat := ""
	if weapon_holder:
		var w: Dictionary = weapon_holder.current()
		if not w.is_empty():
			path = String(w.get("path", ""))
			cat = String(w.get("category", ""))
	var packed: PackedScene = null
	if path != "" and ResourceLoader.exists(path):
		packed = load(path) as PackedScene
	var m: Node3D = null
	if packed:
		m = packed.instantiate() as Node3D
	if m == null:
		_build_fp_arm(root)                          # bare hands: the fist is the one held object
		return

	# A grip node holds the weapon's resting angle; the model is centred + scaled inside it.
	var grip := Node3D.new()
	root.add_child(grip)
	grip.position = Vector3(0.05, 0.0, 0.02)
	grip.rotation_degrees = VM_REST_ROT
	grip.add_child(m)
	var box := _merged_aabb(m)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	# The pickaxe is shown as the biggest weapon we have (the maul) and held large.
	var target := 0.66 if cat == "pickaxe" else 0.28
	var s := target / longest if longest > 0.0001 else 1.0
	m.scale = Vector3(s, s, s)
	# Offset along the weapon's longest axis so the handle runs down toward the lower-right
	# corner and the blade/head extends up into view (held-tool framing), not centred.
	var axis := 0
	if box.size.y >= box.size.x and box.size.y >= box.size.z:
		axis = 1
	elif box.size.z >= box.size.x and box.size.z >= box.size.y:
		axis = 2
	m.position = -box.get_center() * s
	# Shift ~40% along the handle so the head sits up in view and the handle trails off-screen
	# toward the corner — reads as a tool being held, not a weapon floating dead-centre.
	m.position[axis] += box.size[axis] * 0.42 * s

## First-person arm: a generated robot forearm + gripping fist (matches the explorer-bot),
## fitted to hand size and posed via a wrapper so the fist sits at the grip and the
## forearm runs back toward the lower-right of the view. Tune FP_ARM_POS / FP_ARM_ROT.
func _build_fp_arm(root: Node3D) -> void:
	const FP_ARM_PATH := "res://assets/models/characters/fp_hand.glb"
	const FP_ARM_POS := Vector3(0.07, -0.05, 0.07)
	const FP_ARM_ROT := Vector3(6.0, 214.0, 10.0)
	const FP_ARM_SIZE := 0.30
	if not ResourceLoader.exists(FP_ARM_PATH):
		return
	var packed := load(FP_ARM_PATH) as PackedScene
	if packed == null:
		return
	var arm := packed.instantiate() as Node3D
	if arm == null:
		return
	var wrapper := Node3D.new()                     # places + angles the whole arm
	root.add_child(wrapper)
	wrapper.position = FP_ARM_POS
	wrapper.rotation_degrees = FP_ARM_ROT
	wrapper.add_child(arm)
	var box := _merged_aabb(arm)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var s := FP_ARM_SIZE / longest if longest > 0.0001 else 1.0
	arm.scale = Vector3(s, s, s)
	arm.position = -box.get_center() * s            # centre the model on the wrapper

## Animate the first-person weapon each frame: a gentle idle sway, a stronger walk bob
## synced to movement, and a quick downward chop when mining/attacking (triggered by
## setting _vm_swing = 1.0). Keeps the floating weapon feeling alive instead of static.
func _animate_viewmodel(delta: float) -> void:
	if _viewmodel == null or not is_instance_valid(_viewmodel):
		return
	var horiz := _horiz_speed
	var moving := horiz > 0.5 and is_on_floor()
	_vm_phase += delta * (9.0 if moving else 2.5)
	var amp := 0.03 if moving else 0.008
	var sway := Vector3(sin(_vm_phase * 0.5) * amp, absf(sin(_vm_phase)) * amp, 0.0)
	var swing_pos := Vector3.ZERO
	var swing_rot := Vector3.ZERO
	if _vm_swing > 0.0:
		_vm_swing = maxf(0.0, _vm_swing - delta * 4.5)
		var arc := sin((1.0 - _vm_swing) * PI)        # 0 -> 1 -> 0 across the swing
		swing_rot = Vector3(-58.0 * arc, 0.0, 0.0)    # chop the weapon down and back up
		swing_pos = Vector3(0.0, -0.07 * arc, 0.05 * arc)
	elif _vm_place > 0.0:
		_vm_place = maxf(0.0, _vm_place - delta * 5.0)
		var parc := sin((1.0 - _vm_place) * PI)       # quick jab forward + down, then back
		swing_pos = Vector3(0.0, -0.05 * parc, -0.12 * parc)
		swing_rot = Vector3(18.0 * parc, 0.0, 0.0)
	_viewmodel.position = VM_REST_POS + sway + swing_pos
	_viewmodel.rotation_degrees = swing_rot

func _merged_aabb(root: Node3D) -> AABB:
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

## A warm glow around the player so night and caves are never pitch black.
## A faint personal glow so you're never in pitch black — but dim and short-ranged, so caves
## and blood-moon nights stay genuinely dark and tense. (Bright on-demand light = a future
## torch/lantern item; this is just enough to take the next step safely.)
func _setup_light() -> void:
	var lamp := OmniLight3D.new()
	lamp.light_energy = 0.95
	lamp.omni_range = 8.0
	lamp.light_color = Color(1.0, 0.90, 0.74)
	lamp.position = Vector3(0, 1.6, 0)
	lamp.shadow_enabled = false
	add_child(lamp)

func _in_water() -> bool:
	if world_manager == null:
		return false
	return world_manager.get_block(floori(global_position.x), floori(global_position.y + 0.9), floori(global_position.z)) == VoxelTypes.WATER

## Muffle all audio (a low-pass on the Master bus) while the camera/head is submerged — the
## classic "underwater" effect — and clear it the instant we surface. Only fires on a state
## change, so it's a cheap per-frame check.
func _update_underwater_audio() -> void:
	if world_manager == null:
		return
	var hx := floori(global_position.x)
	var hy := floori(global_position.y + CAM_HEIGHT)
	var hz := floori(global_position.z)
	var submerged: bool = world_manager.get_block(hx, hy, hz) == VoxelTypes.WATER
	if submerged == _was_submerged:
		return
	_was_submerged = submerged
	get_tree().call_group("ducker", "set_underwater", submerged)

## True when a solid (non-water) block is directly under the feet — the seabed.
func _on_water_bed() -> bool:
	if world_manager == null:
		return false
	var b: int = world_manager.get_block(floori(global_position.x), floori(global_position.y - 0.1), floori(global_position.z))
	return VoxelTypes.is_solid(b) and b != VoxelTypes.WATER

## True when the chunk under our feet exists but hasn't applied its collider yet — we
## hold vertical position instead of falling through terrain that is still streaming in.
func _ground_streaming() -> bool:
	return world_manager != null and not world_manager.is_chunk_ready(floori(global_position.x), floori(global_position.z))

func _physics_process(delta: float) -> void:
	if _dead:
		velocity = Vector3.ZERO   # frozen until the player respawns
		return
	var on_floor := is_on_floor()
	var in_water := _in_water()
	_update_underwater_audio()
	# Splash when plunging into water (a falling/jumping entry, not a slow wade-in).
	if in_water and not _was_in_water and velocity.y < -2.0:
		_emit_burst(global_position + Vector3(0, 0.3, 0), Color(0.72, 0.85, 1.0), 14, 0.5, 82.0, 1.5, 3.8, 6.0)
	_was_in_water = in_water
	if on_floor and not _was_on_floor:
		if not _landed_once:
			_landed_once = true
		else:
			# A real drop kicks up a dust puff + a small land-thud shake (scaled by fall speed).
			if _fall_speed > 4.0 and not in_water:
				_spawn_land_dust()
				add_trauma(clampf((_fall_speed - 4.0) * 0.03, 0.0, 0.3))
				_land_squash = clampf((_fall_speed - 3.0) * 0.06, 0.0, 0.5)   # camera knees-bend dip
			if _fall_speed > FALL_DAMAGE_SPEED and not in_water:
				hurt(int((_fall_speed - FALL_DAMAGE_SPEED) / 4.0) + 1)
	_was_on_floor = on_floor

	# Camera-relative movement
	var yb := yaw_pivot.global_transform.basis
	var fwd := yb.z * -1.0
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := yb.x
	right.y = 0.0
	right = right.normalized()
	var iz := 0.0
	var ix := 0.0
	if Input.is_action_pressed("move_forward"): iz -= 1.0
	if Input.is_action_pressed("move_back"): iz += 1.0
	if Input.is_action_pressed("move_left"): ix -= 1.0
	if Input.is_action_pressed("move_right"): ix += 1.0
	var dir := fwd * (-iz) + right * ix
	if dir.length() > 0.0:
		dir = dir.normalized()

	# A menu (inventory/crafting) frees the mouse without pausing — don't act on movement
	# keys while it's open, so you can't walk off a cliff while crafting.
	var ui_open := Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if ui_open:
		dir = Vector3.ZERO

	var sprinting := Input.is_action_pressed("sprint") and not ui_open
	if flying:
		var v := dir * FLY_SPEED
		if Input.is_action_pressed("jump") and not ui_open: v.y += FLY_SPEED
		if Input.is_action_pressed("descend") and not ui_open: v.y -= FLY_SPEED
		velocity = v
	else:
		var speed := SPRINT_SPEED if sprinting else WALK_SPEED
		if in_water:
			speed *= 0.65
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		if in_water:
			# Buoyant swimming: Space rises, rest on the lakebed, else sink gently.
			# (The seabed has no collider since its top face is culled under water,
			#  so we stop the sink here instead of falling through it.)
			if Input.is_action_pressed("jump") and not ui_open:
				velocity.y = SWIM_UP_SPEED
			elif _on_water_bed():
				velocity.y = maxf(velocity.y, 0.0)
			else:
				velocity.y = lerpf(velocity.y, -1.2, delta * 4.0)
		elif not on_floor:
			# Don't fall through ground that hasn't streamed its collider in yet (prevents
			# a long phantom fall + lethal fall-damage "death from nowhere").
			velocity.y = 0.0 if _ground_streaming() else velocity.y - gravity * delta
		elif Input.is_action_pressed("jump") and not ui_open:
			velocity.y = JUMP_VELOCITY
			_jump_feedback()
		elif on_floor and dir.length() > 0.1:
			_try_auto_step(dir)   # Minecraft-style: hop up a single-block ledge automatically

	# External pushes (e.g. mob knockback shoving the player back) — applied here so
	# move_and_slide resolves them against terrain, then cleared for the next frame.
	if _ext_push != Vector3.ZERO:
		if not ui_open:                  # don't get shoved (e.g. off a ledge) while a menu is open
			velocity += _ext_push
		_ext_push = Vector3.ZERO
	_fall_speed = maxf(0.0, -velocity.y)
	move_and_slide()
	_horiz_speed = Vector2(velocity.x, velocity.z).length()   # once per frame; the feel helpers reuse it

	if model and dir.length() > 0.1:
		var ty := atan2(dir.x, dir.z) + MODEL_YAW_OFFSET
		model.rotation.y = lerp_angle(model.rotation.y, ty, delta * TURN_SPEED)

	if _swing_cd > 0.0: _swing_cd -= delta
	if _place_cd > 0.0: _place_cd -= delta
	if _mine_timer > 0.0: _mine_timer -= delta
	if _hurt_cd > 0.0: _hurt_cd -= delta
	if _invuln > 0.0: _invuln -= delta
	if _jump_sfx_cd > 0.0: _jump_sfx_cd -= delta
	_update_shake(delta)

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_handle_left()
		else:
			_reset_mining()
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			# Right-click a station (table/furnace/chest) opens it (once, on press);
			# otherwise it places the held block.
			var handled := false
			if ray.is_colliding() and world_manager:
				var tcell := _cell_from_hit(-0.5)
				var tid: int = world_manager.get_block(tcell.x, tcell.y, tcell.z)
				if tid == VoxelTypes.CRAFTING_TABLE or tid == VoxelTypes.FURNACE or tid == VoxelTypes.CHEST:
					handled = true
					if not _rmb_down:
						_interact_station(tid, tcell)
				elif not _rmb_down and _try_farm(tcell, tid):
					handled = true                # tilled / planted / harvested on this press
			if not handled:
				_try_place()
			_rmb_down = true
		else:
			_rmb_down = false
	else:
		_reset_mining()
		_rmb_down = false

	_update_highlight()
	_update_animation()
	_animate_viewmodel(delta)
	_update_footsteps(delta, in_water)
	_update_camera_feel(delta, sprinting and not flying, on_floor)
	_update_vitals(delta, dir.length() > 0.5, sprinting)

	if global_position.y < VOID_Y:
		health = max_health
		_respawn()
		_update_hud()

## Open the UI for a placed utility block (right-clicked station).
func _interact_station(tid: int, cell: Vector3i) -> void:
	_play_snd(snd_place)
	match tid:
		VoxelTypes.CRAFTING_TABLE:
			get_tree().call_group("crafting_ui", "open_for", "table")
		VoxelTypes.FURNACE:
			get_tree().call_group("crafting_ui", "open_for", "furnace")
		VoxelTypes.CHEST:
			get_tree().call_group("chest_ui", "open_chest", cell)

## Right-click farming on the block being looked at (`tid` at `tcell`). Returns true if it
## tilled soil, planted a seed, or harvested a ripe crop — so the caller skips block placement.
## Called once per RMB press (the caller gates on _rmb_down).
func _try_farm(tcell: Vector3i, tid: int) -> bool:
	if farm == null or world_manager == null:
		return false
	var above := tcell + Vector3i(0, 1, 0)
	var held := inventory.id_of(selected)
	var held_n := inventory.count_of(selected)
	# Hoe → till bare dirt/grass into farmland (only if the space above is clear).
	if held == VoxelTypes.HOE and held_n > 0 and (tid == VoxelTypes.DIRT or tid == VoxelTypes.GRASS):
		if world_manager.get_block(above.x, above.y, above.z) != VoxelTypes.AIR:
			return false
		world_manager.set_block(tcell.x, tcell.y, tcell.z, VoxelTypes.FARMLAND)
		_play_snd(snd_place)
		_emit_burst(Vector3(tcell) + Vector3(0.5, 1.0, 0.5), VoxelTypes.color_of(VoxelTypes.DIRT), 8, 0.4, 82.0, 0.8, 2.0, 5.0)
		_vm_place = 1.0
		return true
	# Farmland → harvest a ripe crop, or plant seeds on bare tilled soil.
	if tid == VoxelTypes.FARMLAND:
		if farm.has_crop(above):
			if farm.is_mature(above):
				var got: Array = farm.harvest(above)
				for i in range(int(got[0])):
					_spawn_drop(above, VoxelTypes.WHEAT)
				for i in range(int(got[1])):
					_spawn_drop(above, VoxelTypes.WHEAT_SEEDS)
				_play_snd(_break_sound_for(VoxelTypes.GRASS))
				_emit_burst(Vector3(above) + Vector3(0.5, 0.4, 0.5), Color(0.95, 0.82, 0.35), 12, 0.5, 70.0, 1.2, 2.6, 7.0)
			return true                       # a crop occupies the cell — never place a block here
		if held == VoxelTypes.WHEAT_SEEDS and held_n > 0:
			if world_manager.get_block(above.x, above.y, above.z) == VoxelTypes.AIR and not _cell_overlaps_player(above):
				farm.plant(above)
				inventory.remove_one(selected)
				_play_snd(snd_place)
				on_inventory_changed()
				return true
	return false

func _update_footsteps(delta: float, in_water: bool) -> void:
	var horiz := _horiz_speed
	if is_on_floor() and horiz > 1.0:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = STEP_INTERVAL
			if world_manager:
				var bt: int = world_manager.get_block(int(global_position.x), int(global_position.y) - 1, int(global_position.z))
				_play_snd(_step_sound_for(bt))
	elif in_water and horiz > 0.5:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = STEP_INTERVAL * 1.6        # slower stroke cadence than footsteps
			_play_snd(snd_swim)                      # rhythmic splash so swimming isn't silent
	else:
		_step_timer = 0.0

## Push-off feedback so a jump has weight to match the (heavily juiced) landing — a soft thud of
## the block underfoot plus a little dust at the feet. Cooled down so a held bounce can't spam it.
func _jump_feedback() -> void:
	if _jump_sfx_cd > 0.0:
		return
	_jump_sfx_cd = 0.25
	if world_manager:
		var bt: int = world_manager.get_block(int(global_position.x), int(global_position.y) - 1, int(global_position.z))
		_play_snd(_step_sound_for(bt))
	_emit_burst(global_position + Vector3(0, 0.05, 0), Color(0.72, 0.66, 0.52), 6, 0.35, 80.0, 0.6, 1.6, 5.0)

## The footstep / placement sound matching the material underfoot (or being placed):
## stone-family clack, sandy crunch, hollow wood knock, soft grass/dirt otherwise.
func _step_sound_for(id: int) -> AudioStreamPlayer:
	match id:
		VoxelTypes.STONE, VoxelTypes.COBBLESTONE, VoxelTypes.LAVA, VoxelTypes.BEDROCK, \
		VoxelTypes.COAL_ORE, VoxelTypes.IRON_ORE, VoxelTypes.GOLD_ORE, VoxelTypes.DIAMOND_ORE:
			return snd_step_stone
		VoxelTypes.SAND:
			return snd_step_sand
		VoxelTypes.WOOD, VoxelTypes.PLANKS:
			return snd_step_wood
		_:
			return snd_step_grass

func _solid_at(x: int, y: int, z: int) -> bool:
	var id: int = world_manager.get_block(x, y, z)
	return id != VoxelTypes.AIR and id != VoxelTypes.WATER

## Auto step-up: if a single solid block blocks our path at foot height with clear
## head room above it, give a small hop so we climb it without pressing jump.
func _try_auto_step(dir: Vector3) -> void:
	if world_manager == null or velocity.y > 0.1:
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		return
	var ahead := global_position + flat.normalized() * 0.7
	var sx := floori(ahead.x)
	var sz := floori(ahead.z)
	var fy := floori(global_position.y + 0.1)   # bias up off the floor we stand on
	if not _solid_at(sx, fy, sz):
		return                                   # nothing to climb (flat ground / open air)
	if _solid_at(sx, fy + 1, sz) or _solid_at(sx, fy + 2, sz):
		return                                   # a wall ≥2 high, not a step — don't hop
	velocity.y = sqrt(2.0 * gravity * 1.15)      # just enough to clear one block

## Sprint widens FOV a touch; walking adds a subtle first-person view bob. Both ease
## back to neutral when you stop, so aiming while standing still stays rock-steady.
func _update_camera_feel(delta: float, sprinting: bool, on_floor: bool) -> void:
	if camera == null:
		return
	var horiz := _horiz_speed
	var target_fov := SPRINT_FOV if (sprinting and horiz > WALK_SPEED + 0.5) else BASE_FOV
	camera.fov = lerpf(camera.fov, target_fov, delta * 8.0)
	# Decay the landing dip unconditionally so it can't get stuck when in third person.
	if _land_squash > 0.0:
		_land_squash = maxf(0.0, _land_squash - delta * 3.2)
	if not first_person:
		return
	var moving := on_floor and horiz > 0.5
	var amt: float = clampf(horiz / SPRINT_SPEED, 0.0, 1.0)
	var tgt_y := 0.0
	var tgt_x := 0.0
	if moving:
		_bob_phase += delta * BOB_FREQ
		tgt_y = -absf(sin(_bob_phase)) * BOB_AMP * amt
		tgt_x = cos(_bob_phase) * BOB_AMP * 0.5 * amt
	# Landing dip: the view drops on impact then springs back, reading as the knees absorbing
	# the fall (the squash magnitude was set on landing, scaled by fall speed).
	tgt_y -= _land_squash * BOB_AMP * 6.0
	camera.position.x = lerpf(camera.position.x, tgt_x, delta * 10.0)
	camera.position.y = lerpf(camera.position.y, tgt_y, delta * 14.0)
	camera.rotation.z = lerpf(camera.rotation.z, tgt_x * 0.6, delta * 10.0)

func _update_vitals(delta: float, moving: bool, sprinting: bool) -> void:
	if _regen_block > 0.0:
		_regen_block -= delta
	var drain := HUNGER_IDLE
	if moving: drain += HUNGER_MOVE
	if sprinting: drain += HUNGER_SPRINT
	hunger = clampf(hunger - drain * delta, 0.0, float(MAX_HUNGER))
	_vital_timer -= delta
	if _vital_timer <= 0.0:
		_vital_timer = VITAL_TICK
		# Heal only when well-fed AND not recently hit (can't out-heal a fight any more).
		if hunger >= MAX_HUNGER * 0.6 and health < max_health and _regen_block <= 0.0:
			health += 1
			_update_hud()
		elif hunger <= 0.0 and health > 0:
			health -= 1                      # starvation is now lethal — there are real stakes
			_play_snd(snd_hurt)
			if health <= 0:
				health = 0
				_enter_death()
			_update_hud()
		elif hud:
			hud.set_hunger(int(ceil(hunger)), MAX_HUNGER)

func _update_animation() -> void:
	if anim_player == null:
		return
	var horiz := _horiz_speed
	var sprinting := Input.is_action_pressed("sprint")
	var want := walk_anim
	var freeze := false
	if _mine_timer > 0.0 and mine_anim != "":
		want = mine_anim                    # mining / attacking — the whole body swings
	elif not flying and not is_on_floor() and jump_anim != "":
		want = jump_anim                    # airborne (jump / fall)
	elif not flying and is_on_floor() and horiz > 0.6:
		want = run_anim if (sprinting and run_anim != "") else walk_anim   # sprint = run, else walk
	elif idle_anim != "":
		want = idle_anim                    # real idle clip (natural resting pose)
	else:
		want = walk_anim
		freeze = true                       # fallback: freeze the walk cycle at rest
	if want != "" and anim_player.current_animation != want:
		anim_player.play(want, 0.12)
	anim_player.speed_scale = 0.0 if freeze else 1.0

# --- interaction ---

func _handle_left() -> void:
	if world_manager == null or not ray.is_colliding():
		_reset_mining()
		return
	var collider := ray.get_collider()
	if collider and collider is Node and (collider as Node).is_in_group("mob"):
		_reset_mining()
		_attack_mob(collider)
		return
	# A torch on the targeted face is what you remove first (before the block behind it).
	var tcell := _cell_from_hit(0.5)
	if world_manager.has_torch(tcell):
		_reset_mining()
		if world_manager.remove_torch(tcell):
			give_or_drop(VoxelTypes.TORCH, 1)   # back to the bag, or dropped if full — never destroyed
			_play_snd(snd_break_soft)
		return
	_mine_terrain()

func _attack_mob(mob) -> void:
	if _swing_cd > 0.0:
		return
	var dmg := 3
	var spd := 1.5
	if weapon_holder:
		var w: Dictionary = weapon_holder.current()
		if not w.is_empty():
			dmg = int(w.damage)
			spd = float(w.attack_speed)
	_swing_cd = 1.0 / maxf(spd, 0.1)
	if mine_anim != "":
		_mine_timer = minf(0.45, _swing_cd)
	_play_snd(snd_swing)
	_weapon_swing(_swing_cd)
	add_trauma(0.22)                       # combat impact shake
	get_tree().call_group("ducker", "duck", 0.4, 0.4)
	if mob.has_method("flash"):
		mob.flash()                        # white hit-flash on the mob
	if mob.has_method("take_damage"):
		mob.take_damage(dmg)
		_play_snd(snd_monster)
	if mob is Node3D:
		# A red impact burst confirms the hit; heavier weapons (more damage) stagger harder.
		_emit_burst((mob as Node3D).global_position + Vector3(0, 1.0, 0), Color(0.75, 0.10, 0.10), 8, 0.4, 65.0, 1.5, 3.5, 7.0)
		if mob.has_method("apply_knockback"):
			mob.apply_knockback((mob as Node3D).global_position - global_position, clampf(float(dmg) * 0.7, 2.0, 9.0))

func _mine_terrain() -> void:
	var cell := _cell_from_hit(-0.5)
	var id: int = world_manager.get_block(cell.x, cell.y, cell.z)
	var hard := VoxelTypes.hardness(id)
	if hard < 0.0:                     # unbreakable (bedrock)
		_mine_progress = 0.0
		if hud: hud.set_mine_progress(0.0)
		return
	# Tier gate: too weak a pickaxe still digs the block out (so you can never get boxed in),
	# but yields no drop (handled in _break_block). Warn once per target so it's not a surprise.
	if VoxelTypes.mine_tier(id) > _pickaxe_tier() and cell != _mine_cell \
			and hud and hud.has_method("flash_tool_weak"):
		hud.flash_tool_weak(id)
	if cell != _mine_cell:
		_mine_cell = cell
		_mine_progress = 0.0
	var mp := 1.0
	if weapon_holder:
		var w: Dictionary = weapon_holder.current()
		if not w.is_empty():
			mp = float(w.mining_power)
	var ttb := maxf(0.08, hard / maxf(mp, 0.1))
	_mine_progress += get_physics_process_delta_time() / ttb
	if _swing_cd <= 0.0:               # periodic swing feedback while mining
		_swing_cd = 0.35
		if mine_anim != "": _mine_timer = 0.3
		_play_snd(snd_swing)
		_weapon_swing(0.35)
	if hud: hud.set_mine_progress(_mine_progress)
	if _mine_progress >= 1.0:
		_break_block(cell, id)
		_reset_mining()

## Pick the break sound matching the material being mined (glass shatters, wood cracks,
## dirt/sand crumble, stone/ore crack hard, grass/leaves rustle).
func _break_sound_for(id: int) -> AudioStreamPlayer:
	match id:
		VoxelTypes.GLASS:
			return snd_break_glass
		VoxelTypes.WOOD, VoxelTypes.PLANKS:
			return snd_break_wood
		VoxelTypes.DIRT, VoxelTypes.SAND:
			return snd_break_dirt
		VoxelTypes.STONE, VoxelTypes.COBBLESTONE, VoxelTypes.LAVA, VoxelTypes.BEDROCK, \
		VoxelTypes.COAL_ORE, VoxelTypes.IRON_ORE, VoxelTypes.GOLD_ORE, VoxelTypes.DIAMOND_ORE:
			return snd_break_hard
		_:
			return snd_break_soft   # grass, leaves and anything else

## The mining tier of the held tool: only the pickaxe category harvests gated blocks.
func _pickaxe_tier() -> int:
	if weapon_holder == null:
		return 0
	var w: Dictionary = weapon_holder.current()
	if w.is_empty() or String(w.get("category", "")) != "pickaxe":
		return 0
	return int(w.get("tier", 1))

func _break_block(cell: Vector3i, id: int) -> void:
	_play_snd(_break_sound_for(id))
	_spawn_break_particles(Vector3(cell) + Vector3(0.5, 0.5, 0.5), VoxelTypes.color_of(id))
	add_trauma(0.1)                        # subtle pop when a block breaks
	get_tree().call_group("ducker", "duck", 0.22, 0.35)
	world_manager.set_block(cell.x, cell.y, cell.z, VoxelTypes.AIR)
	if farm:
		farm.on_block_removed(cell)        # clear a crop sitting here / above broken farmland
	# Tier gate: too weak a pickaxe still breaks the block but yields no drop. (The warning is
	# shown once when you first target the block in _mine_terrain — no need to repeat it here.)
	if VoxelTypes.mine_tier(id) > _pickaxe_tier():
		return
	# Breaking a chest spills its stored contents back to you so nothing is lost.
	if id == VoxelTypes.CHEST and world_manager.chests.has(cell):
		var inv = world_manager.chests[cell]
		for slot in inv.slots:
			if slot.count > 0:
				give_or_drop(slot.id, slot.count)
		world_manager.chests.erase(cell)
	var drop := VoxelTypes.drop_of(id)
	if drop != VoxelTypes.AIR:
		_spawn_drop(cell, drop)
	if id == VoxelTypes.LEAVES and randf() < 0.2:
		_spawn_drop(cell, VoxelTypes.APPLE)
	if id == VoxelTypes.GRASS and randf() < 0.35:
		_spawn_drop(cell, VoxelTypes.WHEAT_SEEDS)   # grass yields seeds to bootstrap farming
	emit_signal("block_harvested", id)

func _weapon_swing(dur: float) -> void:
	if weapon_holder == null:
		return
	var cat := "sword"
	var w: Dictionary = weapon_holder.current()
	if not w.is_empty():
		cat = String(w.category)
	weapon_holder.swing(cat, dur); _vm_swing = 1.0   # also drive the first-person viewmodel chop

func _reset_mining() -> void:
	if _mine_progress != 0.0:
		_mine_progress = 0.0
		if hud: hud.set_mine_progress(0.0)
	_mine_cell = Vector3i(2147483647, 0, 0)

func _try_place() -> void:
	if _place_cd > 0.0 or world_manager == null or not ray.is_colliding():
		return
	var id := inventory.id_of(selected)
	if not VoxelTypes.is_placeable(id) or inventory.count_of(selected) <= 0:
		return
	var cell := _cell_from_hit(0.5)
	if _cell_overlaps_player(cell):
		return
	_place_cd = 0.18
	# Torches are light props placed into the empty cell, not voxels.
	if id == VoxelTypes.TORCH:
		if world_manager.get_block(cell.x, cell.y, cell.z) == VoxelTypes.AIR and world_manager.place_torch(cell):
			inventory.remove_one(selected)
			_play_snd(snd_place)
			_vm_place = 1.0
			_emit_burst(Vector3(cell) + Vector3(0.5, 0.5, 0.5), Color(1.0, 0.85, 0.5), 6, 0.35, 70.0, 0.6, 1.6, 4.0)   # warm placement poof
			on_inventory_changed()
		return
	world_manager.set_block(cell.x, cell.y, cell.z, id)
	# If we built straight down at our own feet, step up onto the new block so we don't
	# end up stuck inside it (Minecraft-style pillar-up).
	if cell.x == floori(global_position.x) and cell.z == floori(global_position.z) and cell.y == floori(global_position.y):
		global_position.y = float(cell.y) + 1.0
		velocity.y = 0.0
	inventory.remove_one(selected)
	_play_snd(snd_place)
	_vm_place = 1.0                        # first-person placing "push" on the viewmodel
	# A small dust poof on placement (matches the break-particle feedback).
	_emit_burst(Vector3(cell) + Vector3(0.5, 0.5, 0.5), VoxelTypes.color_of(id), 8, 0.4, 78.0, 0.8, 2.0, 5.0)
	on_inventory_changed()

func _try_eat() -> void:
	if hunger >= MAX_HUNGER:
		return
	# Eat the held item if it's food; otherwise eat the first food found anywhere in the bag,
	# so food doesn't get stranded in a storage slot.
	var slot := selected
	if VoxelTypes.food_value(inventory.id_of(selected)) <= 0 or inventory.count_of(selected) <= 0:
		slot = -1
		for i in range(inventory.slots.size()):
			if inventory.slots[i].count > 0 and VoxelTypes.food_value(inventory.slots[i].id) > 0:
				slot = i
				break
	if slot < 0:
		return
	var restore: int = VoxelTypes.food_value(inventory.id_of(slot))
	inventory.remove_one(slot)
	hunger = minf(MAX_HUNGER, hunger + restore)
	_play_snd(snd_eat)
	_vm_place = 1.0                        # raise-to-mouth motion on the viewmodel
	if camera:                            # a few crumbs at the mouth so eating reads, not just a sound
		_emit_burst(camera.global_position - camera.global_transform.basis.z * 0.5 + Vector3(0, -0.15, 0),
			Color(0.80, 0.62, 0.42), 8, 0.45, 55.0, 0.6, 1.6, 4.0)
	_update_hud()
	if hud and hud.has_method("flash_hunger"):
		hud.flash_hunger()

## External shove applied on the next physics frame (e.g. mob knockback). Ignored
## while flying so the storm can't fling a flying player around.
func push(v: Vector3) -> void:
	if not flying:
		_ext_push += v

func _update_highlight() -> void:
	if highlight == null:
		return
	if ray.is_colliding():
		var collider := ray.get_collider()
		if collider and collider is Node and (collider as Node).is_in_group("mob"):
			highlight.visible = false
			_hide_crack()
			return
		var cell := _cell_from_hit(-0.5)
		highlight.global_position = Vector3(cell)
		highlight.visible = true
		_update_crack(cell)
	else:
		highlight.visible = false
		_hide_crack()

func _update_crack(cell: Vector3i) -> void:
	if _crack == null:
		return
	if _mine_progress > 0.0:
		_crack.global_position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
		_crack.visible = true
		_crack_mat.set_shader_parameter("progress", _mine_progress)
	else:
		_crack.visible = false

func _hide_crack() -> void:
	if _crack:
		_crack.visible = false

## Returns how many were actually stored (0 if the inventory was full, so the drop
## can stay on the ground instead of being destroyed).
func collect_item(id: int, n: int) -> int:
	var left := inventory.add(id, n)
	var taken := n - left
	if taken > 0:
		_play_snd(snd_pickup)
		on_inventory_changed()
	return taken

## Add items to the inventory; anything that doesn't fit is dropped at the player's
## feet so a full inventory never destroys crafted/awarded items.
func give_or_drop(id: int, n: int) -> void:
	var left := inventory.add(id, n)
	on_inventory_changed()
	if left > 0 and world_manager:
		var cell := Vector3i(floori(global_position.x), floori(global_position.y), floori(global_position.z))
		for i in range(left):                   # drop EVERY overflow item (no 64-cap data loss) — rare full-bag path
			_spawn_drop(cell, id)

## Quadratic-falloff camera shake via the camera's frustum offset — this shakes the
## view WITHOUT moving the aim raycast (which is a child of the camera node).
func add_trauma(amount: float) -> void:
	_cam_trauma = clampf(_cam_trauma + amount, 0.0, 1.0)

func _update_shake(delta: float) -> void:
	if camera == null:
		return
	if _cam_trauma > 0.0:
		var s := _cam_trauma * _cam_trauma
		camera.h_offset = randf_range(-1.0, 1.0) * 0.18 * s
		camera.v_offset = randf_range(-1.0, 1.0) * 0.18 * s
		_cam_trauma = maxf(0.0, _cam_trauma - 4.0 * delta)
	elif camera.h_offset != 0.0 or camera.v_offset != 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

func hurt(amount: int) -> void:
	if amount <= 0 or _hurt_cd > 0.0 or _dead or _invuln > 0.0:
		return
	if armor_tier > 0:
		# Armor reduces damage but a connecting hit always lands for at least 1, so even
		# diamond armor can't make you immune to the mobs.
		amount = maxi(1, int(round(float(amount) * (1.0 - float(ARMOR_REDUCTION[armor_tier])))))
	_hurt_cd = 0.5
	_regen_block = REGEN_BLOCK_TIME
	_play_snd(snd_hurt)
	add_trauma(0.5)                        # heavy shake when the player is hit
	get_tree().call_group("ducker", "duck", 0.6, 0.5)
	if hud and hud.has_method("flash_damage"):
		hud.flash_damage()                 # red screen flash
	health -= amount
	if health <= 0:
		health = 0
		_enter_death()
	_update_hud()

## On death: freeze the player, fire heavy feedback (shake + duck + game-over sting)
## and show the respawn screen with the cursor freed so the button is clickable.
func _enter_death() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector3.ZERO
	_reset_mining()
	if highlight:
		highlight.visible = false
	_hide_crack()
	_play_snd(snd_death)
	add_trauma(0.9)
	get_tree().call_group("ducker", "duck", 1.0, 1.2)
	get_tree().call_group("crafting_ui", "close")   # never leave a menu stuck under the death screen
	get_tree().call_group("chest_ui", "close")      # ditto the chest (it's on a layer above the death screen)
	# Death cam: drop to third person so you watch the robot topple, freeze its walk
	# cycle, fall it over, and burst it into sparks.
	_death_prev_fp = first_person
	if first_person:
		first_person = false
		_apply_view()
	# Snap the rig to a neutral, limp pose and fully stop it — a dead body shouldn't be
	# frozen mid-stride or keep cycling its walk animation.
	if anim_player:
		if idle_anim != "":
			anim_player.play(idle_anim)
			anim_player.seek(0.0, true)   # neutral rest pose, applied immediately
		anim_player.speed_scale = 0.0     # frozen — no walk cycle on a corpse
	if weapon_holder and weapon_holder.has_method("stop_swing"):
		weapon_holder.stop_swing()        # don't leave a weapon mid-swing
	_death_collapse()
	_spawn_death_vfx()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud and hud.has_method("show_death"):
		hud.show_death()

## Topple the player model over (around its feet) with a small ground bounce.
func _death_collapse() -> void:
	if model == null or not is_instance_valid(model):
		return
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.tween_property(model, "rotation:x", deg_to_rad(-94.0), 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)        # accelerate as it topples
	_death_tween.tween_property(model, "rotation:x", deg_to_rad(-86.0), 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)       # settle on the ground

## A burst of orange robot sparks + grey bolts where the player died.
func _spawn_death_vfx() -> void:
	if world_manager == null:
		return
	for spec in [{"c": Color(0.97, 0.6, 0.22), "n": 26, "v": 6.0, "s": 0.13},
				 {"c": Color(0.55, 0.56, 0.6), "n": 14, "v": 4.5, "s": 0.16}]:
		var p := CPUParticles3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * float(spec.s)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec.c
		mat.emission_enabled = spec.c.r > 0.8
		mat.emission = spec.c
		bm.material = mat
		p.mesh = bm
		p.amount = int(spec.n)
		p.one_shot = true
		p.lifetime = 1.3
		p.explosiveness = 0.95
		p.direction = Vector3.UP
		p.spread = 80.0
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = float(spec.v)
		p.gravity = Vector3(0, -13.0, 0)
		p.angular_velocity_min = -540.0
		p.angular_velocity_max = 540.0
		p.emitting = true
		world_manager.add_child(p)
		p.global_position = global_position + Vector3(0, 1.0, 0)
		p.finished.connect(p.queue_free)

## True while the death screen is up (pre-respawn). Lets the pause menu refuse to grab the
## mouse over the death overlay (which would hide the cursor and block the Respawn button).
func is_dead() -> bool:
	return _dead

func _do_respawn() -> void:
	health = max_health
	hunger = float(MAX_HUNGER)
	_dead = false
	_invuln = 3.0                  # 3s grace so spawn-camping mobs can't instantly re-kill you
	_respawn()
	# Undo the death cam: stand the model back up, resume its animation, restore the view.
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
	if anim_player:
		anim_player.speed_scale = 1.0
	if model and is_instance_valid(model):
		model.rotation.x = 0.0
		model.rotation.z = 0.0
	first_person = _death_prev_fp
	_apply_view()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if hud and hud.has_method("hide_death"):
		hud.hide_death()
	_update_hud()

func _respawn() -> void:
	flying = false                 # always respawn grounded (creative fly is off until re-toggled)
	velocity = Vector3.ZERO
	global_position = spawn_point
	_fall_speed = 0.0
	_was_on_floor = true
	_landed_once = false
	_invuln = maxf(_invuln, 2.0)   # spawn grace on EVERY respawn path (death + void-fall)
	respawned.emit()               # let main clear any hostiles camping the spawn (no death-loop)

func _spawn_drop(cell: Vector3i, id: int) -> void:
	if world_manager == null:
		return
	var drop := preload("res://scripts/world/block_drop.gd").new()
	drop.setup(id, world_manager, self)
	world_manager.add_child(drop)
	drop.global_position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)

## A low, outward puff of dusty tan particles at the feet when landing from a fall.
func _spawn_land_dust() -> void:
	# spread 88° -> near-horizontal, dust kicks out sideways
	_emit_burst(global_position + Vector3(0, 0.1, 0), Color(0.72, 0.66, 0.52), 14, 0.5, 88.0, 1.0, 2.4, 6.0)

func _spawn_break_particles(pos: Vector3, color: Color) -> void:
	_emit_burst(pos, color, 12, 0.6, 70.0, 1.5, 3.0, 9.0)

func _cell_from_hit(offset: float) -> Vector3i:
	var p := ray.get_collision_point()
	var nrm := ray.get_collision_normal()
	# The chunk collider uses mixed-winding faces with backface collision, so the reported
	# normal can point INTO the block. Flip it to face the camera (the true outward direction
	# of the hit face) so placement (+offset) and mining (-offset) work on EVERY face — most
	# importantly the side faces, which previously reported inward normals.
	if nrm.dot(ray.global_position - p) < 0.0:
		nrm = -nrm
	var inside := p + nrm * offset
	return Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))

func _cell_overlaps_player(cell: Vector3i) -> bool:
	var fx := floori(global_position.x)
	var fz := floori(global_position.z)
	var fy := floori(global_position.y)
	# Only the head cell is off-limits. The feet cell IS allowed so you can build directly
	# underneath yourself (pillar up); _try_place then steps you up onto the placed block.
	if cell.x == fx and cell.z == fz and cell.y == fy + 1:
		return true
	return false

# --- save / load support ---

func apply_save(p: Dictionary) -> void:
	if p.has("x"):
		var sx := float(p.x)
		var sy := float(p.y)
		var sz := float(p.z)
		# Guard against corrupt coords, and against being buried/floating after a terrain
		# change: reject non-finite values and lift the player onto the surface if below it.
		if not (is_finite(sx) and is_finite(sy) and is_finite(sz)):
			sx = 0.5
			sy = 80.0
			sz = 0.5
		if world_manager and world_manager.has_method("surface_height"):
			var ground := float(world_manager.surface_height(int(sx), int(sz)))
			if sy < ground + 2.0:
				sy = ground + 2.0
		global_position = Vector3(sx, sy, sz)
		spawn_point = global_position
	health = clampi(int(p.get("health", health)), 0, max_health)   # never load out-of-range / negative HP
	hunger = clampf(float(p.get("hunger", hunger)), 0.0, float(MAX_HUNGER))
	selected = clampi(int(p.get("selected", 0)), 0, Inventory.HOTBAR - 1)
	for tn in p.get("tools", []):
		unlock_tool(String(tn), false)          # re-grant crafted tools without re-equipping
	var at := int(p.get("armor_tier", 0))
	if at > 0:
		set_armor_tier(at, String(p.get("armor_name", "Armor")))
	_update_hud()
