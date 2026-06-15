extends Node3D

## Game root. Builds lighting + a day/night cycle, the streamed voxel world, the
## player, HUD, hotbar/crafting UI and pause menu, loads a saved world when asked,
## and spawns passive animals (always) and hostile mobs (at night). Low-end tuned.

const ANIMAL_COUNT := 6
const NIGHT_MOB_COUNT := 3     # a real first-night threat; +2 per night survived up to the cap
const MAX_NIGHT_MOBS := 16

var _nights := 0          # nights survived — drives escalating siege difficulty

var world: ChunkManager
var player
var hud
var day_night: DayNight
var crafting_ui

var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial
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
	# We're CPU-bound with lots of GPU headroom (~130 draws), so spend a little of it on
	# anti-aliasing to clean up the jagged block/foliage edges.
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_2X

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
		world.chests = WorldSave.chests_from(save)

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

	# Seasons + weather (sandstorms in the desert, tsunamis at the coast, rain/storms/snow).
	# Added after DayNight so its fog/dimming/tint layers on top of the day cycle each frame.
	var weather := preload("res://scripts/world/weather.gd").new()
	weather.name = "Weather"
	add_child(weather)
	weather.setup(player, world, _env, _sun, _sky_mat, hud, day_night)

	crafting_ui = preload("res://scripts/ui/crafting_ui.gd").new()
	crafting_ui.name = "CraftingUI"
	crafting_ui.player = player
	add_child(crafting_ui)

	var chest_ui := preload("res://scripts/ui/chest_ui.gd").new()
	chest_ui.name = "ChestUI"
	chest_ui.player = player
	chest_ui.world = world
	add_child(chest_ui)

	# Advancements: tracks progression goals via the player's signals (J to view).
	var advancements := preload("res://scripts/core/advancements.gd").new()
	advancements.name = "Advancements"
	add_child(advancements)
	advancements.setup(player)

	var pause := preload("res://scripts/ui/pause_menu.gd").new()
	pause.name = "PauseMenu"
	pause.world = world
	pause.player = player
	pause.day_night = day_night
	pause.weather = weather
	add_child(pause)

	_setup_ambient()

	# Biome fauna: desert camels/vultures/lizards, meadow & forest animals/birds/reptiles,
	# and fish/crocodiles/turtles in the water — each spawned to match the local biome and
	# animated for its locomotion (walk/run/graze, fly, swim). Replaces the old flat spawn.
	var fauna := preload("res://scripts/entities/fauna.gd").new()
	fauna.name = "Fauna"
	fauna.setup(world, player)
	add_child(fauna)

	# Minimap (top-right; M expands it) so the player can locate themselves and read biomes.
	var minimap := preload("res://scripts/ui/minimap.gd").new()
	minimap.name = "Minimap"
	minimap.setup(world, player)
	add_child(minimap)

	# Apply saved player state after everything exists.
	if not save.is_empty():
		if save.has("player"):
			player.apply_save(save.player)
		if save.has("inventory"):
			player.inventory.from_data(save.inventory)
			player.on_inventory_changed()
		if save.has("time"):
			day_night.time_of_day = float(save.time)
		if save.has("weather") and save.weather is Dictionary and not save.weather.is_empty():
			weather.load_state(save.weather)

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
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://assets/materials/sky.gdshader")
	_sky_mat.set_shader_parameter("top_color", Color(0.30, 0.52, 0.86))
	_sky_mat.set_shader_parameter("horizon_color", Color(0.78, 0.86, 0.95))
	_sky_mat.set_shader_parameter("ground_color", Color(0.52, 0.46, 0.38))
	_sky_mat.set_shader_parameter("star_amount", 0.0)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 6.0
	# Atmospheric fog: distant terrain fades into the sky horizon — gives depth and hides
	# the chunk-streaming edge. DayNight refreshes fog_light_color each frame to match the
	# sky (blue by day, orange at dusk, dark at night).
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.78, 0.86, 0.95)   # day horizon; DayNight refreshes it
	_env.fog_density = 0.03
	_env.fog_sky_affect = 0.0
	_env.fog_aerial_perspective = 0.4
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
		# Each night survived raises the count and the mobs' health/damage.
		var count: int = mini(MAX_NIGHT_MOBS, NIGHT_MOB_COUNT + _nights * 2)
		_spawn_hostiles(count)
	else:
		_clear_hostiles()
		_nights += 1
		if player:
			if player.has_signal("night_survived"):
				player.emit_signal("night_survived")
			if player.hud and player.hud.has_method("show_toast"):
				player.hud.show_toast("Night %d survived" % _nights, Color(0.7, 1.0, 0.8))

func _spawn_hostiles(n: int) -> void:
	_clear_hostiles()
	if player == null:
		return
	var bonus_hp := mini(_nights * 4, 28)                  # cap so late mobs aren't damage sponges
	var bonus_dmg := mini(floori(float(_nights) / 2.0), 4) # ramps faster; base damage is now 2
	for i in range(n):
		var ang := _rng.randf_range(0.0, TAU)
		var rad := _rng.randf_range(12.0, 20.0)
		var mx: float = player.global_position.x + cos(ang) * rad
		var mz: float = player.global_position.z + sin(ang) * rad
		var my: int = world.surface_height(int(mx), int(mz)) + 2
		var mob := preload("res://scripts/entities/hostile_mob.gd").new()
		mob.player = player
		mob.world = world
		mob.health = 10 + bonus_hp
		mob.damage = 2 + bonus_dmg
		mob.position = Vector3(mx, float(my), mz)
		add_child(mob)
		_hostiles.append(mob)

func _clear_hostiles() -> void:
	for m in _hostiles:
		if is_instance_valid(m):
			m.queue_free()
	_hostiles.clear()
