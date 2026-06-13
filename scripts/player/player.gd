class_name Player
extends CharacterBody3D

## Third-person (toggle first-person) Minecraft-style controller.
## Move WASD, look mouse, Space jump (double-tap or F = fly), Ctrl sprint, Shift
## descend while flying. 1-9 / scroll pick a hotbar slot, Q/E switch weapon.
## HOLD Left Mouse to mine a block (timed by hardness vs weapon mining power) or to
## attack a mob; Right Mouse places the selected block (consumed from the hotbar).
## G eats an apple, C opens crafting, F5 toggles view. Esc is owned by PauseMenu.

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const FLY_SPEED := 10.0
const JUMP_VELOCITY := 5.0
const SWIM_UP_SPEED := 4.0
const MOUSE_SENS := 0.0025
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

const MODEL_PATH := "res://assets/models/characters/player_rigged.glb"
const MODEL_SCALE := 1.0
const MODEL_YAW_OFFSET := 0.0

# hunger / vitals
const MAX_HUNGER := 6
const HUNGER_IDLE := 0.02
const HUNGER_MOVE := 0.05
const HUNGER_SPRINT := 0.10
const APPLE_RESTORE := 3
const VITAL_TICK := 2.0

var hud
var world_manager

var yaw_pivot: Node3D
var pitch_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var ray: RayCast3D
var model: Node3D
var anim_player: AnimationPlayer
var weapon_holder
var highlight: MeshInstance3D

var _swing_cd := 0.0
var _place_cd := 0.0
var _last_space_ms := 0
var _step_timer := 0.0
var _hurt_cd := 0.0
var _vital_timer := VITAL_TICK
var _cam_trauma := 0.0          # 0..1 screen-shake accumulator (quadratic falloff)

var walk_anim := ""
var mine_anim := ""
var run_anim := ""

var flying := false
var first_person := false
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _mine_timer := 0.0

var max_health := 6
var health := 6
var hunger := float(MAX_HUNGER)
var spawn_point := Vector3(0, 4, 0)
var _was_on_floor := true
var _fall_speed := 0.0
var _landed_once := false

var inventory: Inventory
var selected := 0
var _mine_cell := Vector3i(2147483647, 0, 0)
var _mine_progress := 0.0

# sounds
var snd_break_soft: AudioStreamPlayer
var snd_break_hard: AudioStreamPlayer
var snd_place: AudioStreamPlayer
var snd_step_grass: AudioStreamPlayer
var snd_step_stone: AudioStreamPlayer
var snd_hurt: AudioStreamPlayer
var snd_swing: AudioStreamPlayer
var snd_eat: AudioStreamPlayer
var snd_pickup: AudioStreamPlayer
var snd_monster: AudioStreamPlayer

func _ready() -> void:
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
	_setup_highlight()
	_setup_light()

	spawn_point = global_position
	_landed_once = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_hud()

func _give_starter_kit() -> void:
	inventory.add(VoxelTypes.GRASS, 32)
	inventory.add(VoxelTypes.DIRT, 32)
	inventory.add(VoxelTypes.STONE, 32)
	inventory.add(VoxelTypes.COBBLESTONE, 16)
	inventory.add(VoxelTypes.PLANKS, 16)
	inventory.add(VoxelTypes.GLASS, 16)
	inventory.add(VoxelTypes.WOOD, 8)

var body_meshes: Array = []   # the player's body meshes (hidden in first person)
var _viewmodel: Node3D        # held tool shown in front of the camera in first person

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
		walk_anim = _find_anim(["walk"])
		run_anim = _find_anim(["run"])
		mine_anim = _find_anim(["mine", "minig", "mining", "attack"])
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
	weapon_holder.setup(skel, preload("res://scripts/player/weapon_registry.gd").list())

func _setup_audio() -> void:
	snd_break_soft = _make_snd("res://assets/audio/sfx/blocks/break_soft.mp3", -4.0)
	snd_break_hard = _make_snd("res://assets/audio/sfx/blocks/break_hard.mp3", -4.0)
	snd_place      = _make_snd("res://assets/audio/sfx/blocks/place.mp3",      -6.0)
	snd_step_grass = _make_snd("res://assets/audio/sfx/player/step_grass.mp3", -8.0)
	snd_step_stone = _make_snd("res://assets/audio/sfx/player/step_stone.mp3", -8.0)
	snd_hurt       = _make_snd("res://assets/audio/sfx/player/hurt.mp3",       -3.0)
	snd_swing      = _make_snd("res://assets/audio/sfx/player/swing.mp3",      -7.0)
	snd_eat        = _make_snd("res://assets/audio/sfx/player/eat.mp3",        -4.0)
	snd_pickup     = _make_snd("res://assets/audio/sfx/items/pickup.mp3",      -6.0)
	snd_monster    = _make_snd("res://assets/audio/sfx/mobs/monster_hurt.mp3", -5.0)

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
	p.pitch_scale = randf_range(0.9, 1.1)
	p.play()

func play_craft_sound() -> void:
	_play_snd(snd_place)

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
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw_pivot.rotate_y(-event.relative.x * MOUSE_SENS)
		pitch_pivot.rotation.x = clampf(pitch_pivot.rotation.x - event.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select(selected - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select(selected + 1)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				var now := Time.get_ticks_msec()
				if now - _last_space_ms < DOUBLE_TAP_MS:
					flying = not flying
					if flying: velocity = Vector3.ZERO
				_last_space_ms = now
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
	selected = (idx + Inventory.SIZE) % Inventory.SIZE
	on_inventory_changed()
	if hud:
		hud.update_hotbar(inventory.slots, selected)

func _toggle_view() -> void:
	first_person = not first_person
	if first_person:
		spring.spring_length = 0.0
		ray.target_position = Vector3(0, 0, -REACH)
		for m in body_meshes:
			if is_instance_valid(m): m.visible = false   # hide body, keep held tool
	else:
		spring.spring_length = CAM_DISTANCE
		ray.target_position = Vector3(0, 0, -(CAM_DISTANCE + REACH))
		for m in body_meshes:
			if is_instance_valid(m): m.visible = true
	_build_viewmodel()

## In first person, show the current weapon as a viewmodel in front of the camera.
func _build_viewmodel() -> void:
	if _viewmodel and is_instance_valid(_viewmodel):
		_viewmodel.queue_free()
		_viewmodel = null
	if not first_person or weapon_holder == null or camera == null:
		return
	var w: Dictionary = weapon_holder.current()
	if w.is_empty():
		return
	var path: String = w.get("path", "")
	if path == "" or not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var m := packed.instantiate() as Node3D
	if m == null:
		return
	# Holder node decouples centring from rotation: the model is centred on the holder
	# origin, and the holder is positioned + angled in front of the camera.
	var holder := Node3D.new()
	camera.add_child(holder)
	holder.add_child(m)
	var box := _merged_aabb(m)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var s := 0.42 / longest if longest > 0.0001 else 1.0
	m.scale = Vector3(s, s, s)
	m.position = -box.get_center() * s            # centre the model on the holder
	holder.position = Vector3(0.3, -0.32, -0.62)
	holder.rotation_degrees = Vector3(25, 120, 35)
	_viewmodel = holder

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
func _setup_light() -> void:
	var lamp := OmniLight3D.new()
	lamp.light_energy = 1.4
	lamp.omni_range = 14.0
	lamp.light_color = Color(1.0, 0.92, 0.78)
	lamp.position = Vector3(0, 1.6, 0)
	lamp.shadow_enabled = false
	add_child(lamp)

func _in_water() -> bool:
	if world_manager == null:
		return false
	return world_manager.get_block(floori(global_position.x), floori(global_position.y + 0.9), floori(global_position.z)) == VoxelTypes.WATER

## True when a solid (non-water) block is directly under the feet — the seabed.
func _on_water_bed() -> bool:
	if world_manager == null:
		return false
	var b: int = world_manager.get_block(floori(global_position.x), floori(global_position.y - 0.1), floori(global_position.z))
	return VoxelTypes.is_solid(b) and b != VoxelTypes.WATER

func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	var in_water := _in_water()
	if on_floor and not _was_on_floor:
		if not _landed_once:
			_landed_once = true
		elif _fall_speed > FALL_DAMAGE_SPEED and not in_water:
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
	if Input.is_physical_key_pressed(KEY_W): iz -= 1.0
	if Input.is_physical_key_pressed(KEY_S): iz += 1.0
	if Input.is_physical_key_pressed(KEY_A): ix -= 1.0
	if Input.is_physical_key_pressed(KEY_D): ix += 1.0
	var dir := fwd * (-iz) + right * ix
	if dir.length() > 0.0:
		dir = dir.normalized()

	var sprinting := Input.is_physical_key_pressed(KEY_CTRL)
	if flying:
		var v := dir * FLY_SPEED
		if Input.is_physical_key_pressed(KEY_SPACE): v.y += FLY_SPEED
		if Input.is_physical_key_pressed(KEY_SHIFT): v.y -= FLY_SPEED
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
			if Input.is_physical_key_pressed(KEY_SPACE):
				velocity.y = SWIM_UP_SPEED
			elif _on_water_bed():
				velocity.y = maxf(velocity.y, 0.0)
			else:
				velocity.y = lerpf(velocity.y, -1.2, delta * 4.0)
		elif not on_floor:
			velocity.y -= gravity * delta
		elif Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP_VELOCITY

	_fall_speed = maxf(0.0, -velocity.y)
	move_and_slide()

	if model and dir.length() > 0.1:
		var ty := atan2(dir.x, dir.z) + MODEL_YAW_OFFSET
		model.rotation.y = lerp_angle(model.rotation.y, ty, delta * TURN_SPEED)

	if _swing_cd > 0.0: _swing_cd -= delta
	if _place_cd > 0.0: _place_cd -= delta
	if _mine_timer > 0.0: _mine_timer -= delta
	if _hurt_cd > 0.0: _hurt_cd -= delta
	_update_shake(delta)

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_handle_left()
		else:
			_reset_mining()
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_try_place()
	else:
		_reset_mining()

	_update_highlight()
	_update_animation()
	_update_footsteps(delta)
	_update_vitals(delta, dir.length() > 0.5, sprinting)

	if global_position.y < VOID_Y:
		health = max_health
		_respawn()
		_update_hud()

func _update_footsteps(delta: float) -> void:
	var horiz := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horiz > 1.0:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = STEP_INTERVAL
			if world_manager:
				var bt: int = world_manager.get_block(int(global_position.x), int(global_position.y) - 1, int(global_position.z))
				if bt == VoxelTypes.STONE or bt == VoxelTypes.COBBLESTONE or bt == VoxelTypes.LAVA:
					_play_snd(snd_step_stone)
				else:
					_play_snd(snd_step_grass)
	else:
		_step_timer = 0.0

func _update_vitals(delta: float, moving: bool, sprinting: bool) -> void:
	var drain := HUNGER_IDLE
	if moving: drain += HUNGER_MOVE
	if sprinting: drain += HUNGER_SPRINT
	hunger = clampf(hunger - drain * delta, 0.0, float(MAX_HUNGER))
	_vital_timer -= delta
	if _vital_timer <= 0.0:
		_vital_timer = VITAL_TICK
		if hunger >= MAX_HUNGER * 0.6 and health < max_health:
			health += 1
			_update_hud()
		elif hunger <= 0.0 and health > 1:
			health -= 1
			_play_snd(snd_hurt)
			_update_hud()
		elif hud:
			hud.set_hunger(int(ceil(hunger)), MAX_HUNGER)

func _update_animation() -> void:
	if anim_player == null:
		return
	var horiz := Vector2(velocity.x, velocity.z).length()
	var want := walk_anim
	var freeze := false
	if _mine_timer > 0.0 and mine_anim != "":
		want = mine_anim
	elif not flying and not is_on_floor() and run_anim != "":
		want = run_anim
	elif not flying and is_on_floor() and horiz > 0.6:
		want = walk_anim
	else:
		want = walk_anim
		freeze = true
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

func _mine_terrain() -> void:
	var cell := _cell_from_hit(-0.5)
	var id: int = world_manager.get_block(cell.x, cell.y, cell.z)
	var hard := VoxelTypes.hardness(id)
	if hard < 0.0:                     # unbreakable (bedrock)
		_mine_progress = 0.0
		if hud: hud.set_mine_progress(0.0)
		return
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

func _break_block(cell: Vector3i, id: int) -> void:
	if id == VoxelTypes.STONE or id == VoxelTypes.COBBLESTONE or id == VoxelTypes.LAVA \
			or (id >= VoxelTypes.COAL_ORE and id <= VoxelTypes.DIAMOND_ORE):
		_play_snd(snd_break_hard)
	else:
		_play_snd(snd_break_soft)
	_spawn_break_particles(Vector3(cell) + Vector3(0.5, 0.5, 0.5), VoxelTypes.color_of(id))
	add_trauma(0.1)                        # subtle pop when a block breaks
	get_tree().call_group("ducker", "duck", 0.22, 0.35)
	world_manager.set_block(cell.x, cell.y, cell.z, VoxelTypes.AIR)
	var drop := VoxelTypes.drop_of(id)
	if drop != VoxelTypes.AIR:
		_spawn_drop(cell, drop)
	if id == VoxelTypes.LEAVES and randf() < 0.2:
		_spawn_drop(cell, VoxelTypes.APPLE)

func _weapon_swing(dur: float) -> void:
	if weapon_holder == null:
		return
	var cat := "sword"
	var w: Dictionary = weapon_holder.current()
	if not w.is_empty():
		cat = String(w.category)
	weapon_holder.swing(cat, dur)

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
	world_manager.set_block(cell.x, cell.y, cell.z, id)
	inventory.remove_one(selected)
	_play_snd(snd_place)
	on_inventory_changed()

func _try_eat() -> void:
	if inventory.id_of(selected) == VoxelTypes.APPLE and inventory.count_of(selected) > 0 and hunger < MAX_HUNGER:
		inventory.remove_one(selected)
		hunger = minf(MAX_HUNGER, hunger + APPLE_RESTORE)
		_play_snd(snd_eat)
		_update_hud()

func _update_highlight() -> void:
	if highlight == null:
		return
	if ray.is_colliding():
		var collider := ray.get_collider()
		if collider and collider is Node and (collider as Node).is_in_group("mob"):
			highlight.visible = false
			return
		var cell := _cell_from_hit(-0.5)
		highlight.global_position = Vector3(cell)
		highlight.visible = true
	else:
		highlight.visible = false

func collect_item(id: int, n: int) -> void:
	var left := inventory.add(id, n)
	if left < n:
		_play_snd(snd_pickup)
	on_inventory_changed()

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
	if amount <= 0 or _hurt_cd > 0.0:
		return
	_hurt_cd = 0.5
	_play_snd(snd_hurt)
	add_trauma(0.5)                        # heavy shake when the player is hit
	get_tree().call_group("ducker", "duck", 0.6, 0.5)
	if hud and hud.has_method("flash_damage"):
		hud.flash_damage()                 # red screen flash
	health -= amount
	if health <= 0:
		health = max_health
		hunger = float(MAX_HUNGER)
		_respawn()
	_update_hud()

func _respawn() -> void:
	velocity = Vector3.ZERO
	global_position = spawn_point
	_fall_speed = 0.0
	_was_on_floor = true
	_landed_once = false

func _spawn_drop(cell: Vector3i, id: int) -> void:
	if world_manager == null:
		return
	var drop := preload("res://scripts/world/block_drop.gd").new()
	drop.setup(id, world_manager, self)
	world_manager.add_child(drop)
	drop.global_position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)

func _spawn_break_particles(pos: Vector3, color: Color) -> void:
	if world_manager == null:
		return
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	p.mesh = bm
	p.amount = 12
	p.one_shot = true
	p.lifetime = 0.6
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -9.0, 0)
	p.emitting = true
	world_manager.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)

func _cell_from_hit(offset: float) -> Vector3i:
	var p := ray.get_collision_point()
	var nrm := ray.get_collision_normal()
	var inside := p + nrm * offset
	return Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))

func _cell_overlaps_player(cell: Vector3i) -> bool:
	var fx := floori(global_position.x)
	var fz := floori(global_position.z)
	var fy := floori(global_position.y)
	if cell.x == fx and cell.z == fz and (cell.y == fy or cell.y == fy + 1):
		return true
	return false

# --- save / load support ---

func apply_save(p: Dictionary) -> void:
	if p.has("x"):
		global_position = Vector3(p.x, p.y, p.z)
		spawn_point = global_position
	health = int(p.get("health", health))
	hunger = float(p.get("hunger", hunger))
	selected = int(p.get("selected", 0)) % Inventory.SIZE
	_update_hud()
