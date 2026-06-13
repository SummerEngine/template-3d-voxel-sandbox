extends Node3D

## Game root. Builds lighting + a day/night cycle, the streamed voxel world, the
## player, HUD, hotbar/crafting UI and pause menu, loads a saved world when asked,
## and spawns passive animals (always) and hostile mobs (at night). Low-end tuned.

const ANIMAL_COUNT := 6
const NIGHT_MOB_COUNT := 4

var world: ChunkManager
var player
var hud
var day_night: DayNight
var crafting_ui

var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _hostiles: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	Engine.max_fps = 60
	_rng.randomize()
	add_child(preload("res://scripts/core/audio_ducker.gd").new())   # creates audio buses
	var win := get_window()
	if win:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE

	_setup_environment()
	_setup_sun()

	world = preload("res://scripts/world/chunk_manager.gd").new()
	world.name = "ChunkManager"
	add_child(world)

	# Decide new game vs loaded game.
	var save: Dictionary = {}
	if GameState.load_on_start and WorldSave.has_save():
		save = WorldSave.load_data()
		world.overrides = WorldSave.overrides_from(save)

	# Spawn position (saved, else open dry ground near the origin — never under a tree).
	var spawn := _find_spawn()
	var px := spawn.x
	var py := spawn.y
	var pz := spawn.z
	if save.has("player"):
		px = float(save.player.x)
		py = float(save.player.y)
		pz = float(save.player.z)
	world.preload_around(Vector2i(world.chunk_x(int(px)), world.chunk_z(int(pz))))

	hud = preload("res://scripts/ui/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)

	player = preload("res://scripts/player/player.gd").new()
	player.name = "Player"
	player.position = Vector3(px, py, pz)
	player.hud = hud
	player.world_manager = world
	add_child(player)
	world.player = player

	# Day/night drives the sun, sky and night-mob spawning.
	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup(_sun, _env, _sky_mat)
	day_night.phase_changed.connect(_on_phase_changed)

	crafting_ui = preload("res://scripts/ui/crafting_ui.gd").new()
	crafting_ui.name = "CraftingUI"
	crafting_ui.player = player
	add_child(crafting_ui)

	var pause := preload("res://scripts/ui/pause_menu.gd").new()
	pause.name = "PauseMenu"
	pause.world = world
	pause.player = player
	pause.day_night = day_night
	add_child(pause)

	_setup_ambient()
	_spawn_animals()

	# Apply saved player state after everything exists.
	if not save.is_empty():
		if save.has("player"):
			player.apply_save(save.player)
		if save.has("inventory"):
			player.inventory.from_data(save.inventory)
			player.on_inventory_changed()
		if save.has("time"):
			day_night.time_of_day = float(save.time)

## Spiral out from the origin for a dry, above-sea column with no tree (or tree
## canopy) over it, so the player never spawns trapped inside leaves.
func _find_spawn() -> Vector3:
	for r in range(0, 28):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue                       # only the new ring each radius
				var s: int = world.surface_height(dx, dz)
				if s < world.SEA_LEVEL + 2 or s >= world.MOUNTAIN_ROCK - 2:
					continue                       # grassland only — not ocean, not peak
				if _tree_near(dx, dz) or not _is_flat(dx, dz, s):
					continue
				return Vector3(dx + 0.5, float(s + 3), dz + 0.5)
	# Fallback: any dry land near the origin.
	for r in range(0, 28):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var s2: int = world.surface_height(dx, dz)
				if s2 > world.SEA_LEVEL:
					return Vector3(dx + 0.5, float(s2 + 3), dz + 0.5)
	return Vector3(0.5, float(world.SEA_LEVEL + 6), 0.5)

func _tree_near(x: int, z: int) -> bool:
	for oz in range(-3, 4):
		for ox in range(-3, 4):
			if world.is_tree(x + ox, z + oz):
				return true
	return false

func _is_flat(x: int, z: int, s: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if absi(world.surface_height(x + d.x, z + d.y) - s) > 2:
			return false
	return true

func _setup_environment() -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = Color(0.30, 0.52, 0.86)
	_sky_mat.sky_horizon_color = Color(0.78, 0.86, 0.95)
	_sky_mat.ground_horizon_color = Color(0.78, 0.86, 0.95)
	_sky_mat.ground_bottom_color = Color(0.52, 0.46, 0.38)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = _env
	add_child(we)

func _setup_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "DirectionalLight3D"
	_sun.rotation_degrees = Vector3(-55.0, -45.0, 0.0)
	_sun.light_energy = 1.4
	_sun.light_color = Color(1.0, 0.97, 0.90)
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 60.0
	add_child(_sun)

func _setup_ambient() -> void:
	_play_loop("res://assets/audio/music/theme.mp3", -17.0, "Music")    # background theme
	_play_loop("res://assets/audio/ambient/wind.mp3", -24.0, "Ambient") # soft wind under it

func _play_loop(path: String, vol_db: float, bus: String = "Master") -> void:
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStreamMP3
	if stream:
		stream.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	p.autoplay = true
	if AudioServer.get_bus_index(bus) != -1:
		p.bus = bus
	add_child(p)

func _spawn_animals() -> void:
	var cx := 0
	var cz := 0
	if player:
		cx = int(player.global_position.x)
		cz = int(player.global_position.z)
	for i in range(ANIMAL_COUNT):
		# Find a dry spot near the player (a few tries; skip ocean/lake).
		var ax := cx
		var az := cz
		for _try in range(6):
			ax = cx + _rng.randi_range(-14, 14)
			az = cz + _rng.randi_range(-14, 14)
			if world.surface_height(ax, az) > world.SEA_LEVEL:
				break
		var ah: int = world.surface_height(ax, az) + 2
		var a := preload("res://scripts/entities/animal.gd").new()
		a.world = world
		a.player = player
		a.position = Vector3(float(ax), float(ah), float(az))
		add_child(a)

func _on_phase_changed(is_night: bool) -> void:
	if is_night:
		_spawn_hostiles(NIGHT_MOB_COUNT)
	else:
		_clear_hostiles()

func _spawn_hostiles(n: int) -> void:
	_clear_hostiles()
	if player == null:
		return
	for i in range(n):
		var ang := _rng.randf_range(0.0, TAU)
		var rad := _rng.randf_range(12.0, 20.0)
		var mx: float = player.global_position.x + cos(ang) * rad
		var mz: float = player.global_position.z + sin(ang) * rad
		var my: int = world.surface_height(int(mx), int(mz)) + 2
		var mob := preload("res://scripts/entities/hostile_mob.gd").new()
		mob.player = player
		mob.world = world
		mob.position = Vector3(mx, float(my), mz)
		add_child(mob)
		_hostiles.append(mob)

func _clear_hostiles() -> void:
	for m in _hostiles:
		if is_instance_valid(m):
			m.queue_free()
	_hostiles.clear()
