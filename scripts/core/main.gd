extends Node3D

## Game root. Builds lighting + a day/night cycle, the streamed voxel world, the
## player, HUD, hotbar/crafting UI and pause menu, loads a saved world when asked,
## and spawns passive animals (always) and hostile mobs (at night). Low-end tuned.

const InputActions := preload("res://scripts/core/input_actions.gd")
const ANIMAL_COUNT := 6
const NIGHT_MOB_COUNT := 3     # a real first-night threat; +2 per night survived up to the cap
const MAX_NIGHT_MOBS := 16
const BLOOD_MOON_EVERY := 5    # every Nth night is a red-sky siege peak (more mobs + brutes)
const CAVE_MOB_MAX := 4        # lurkers maintained around a player who is deep underground
const CAVE_DEPTH := 5.0        # blocks below the surface before caves spawn hostiles
const SIEGE_SPAWN_PER_FRAME := 2   # stagger the horde spawn so nightfall doesn't hitch

var _nights := 0          # nights survived — drives escalating siege difficulty
var _spawn_queue: Array = []   # pending siege spawns, drained a few per frame
var _cave_mobs: Array = []
var _cave_t := 0.0

var world: ChunkManager
var player
var hud
var day_night: DayNight
var crafting_ui
var hauntfields            # the ground-memory system (biases spawns + blood-moon eruptions)

var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _hostiles: Array = []
var _stinger: AudioStreamPlayer        # blood-moon sting
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	Engine.max_fps = 60
	_rng.randomize()
	InputActions.setup()   # register remappable movement actions (saved binds applied here)
	# Zombies are now a lightweight code-built rig (no 20 MB skinned GLB to warm-load).
	add_child(preload("res://scripts/core/audio_ducker.gd").new())   # creates audio buses
	GameSettings.apply_audio(get_tree())                              # saved volume levels
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
		world.graves = WorldSave.graves_from(save)            # Hauntfields: restore the killing grounds
		world.hollow_scores = WorldSave.hollows_from(save)    # Hollows: restore carved-air pressure
		world.hollow_calmed = WorldSave.hollow_calmed_from(save)  # Hollows: which rewards already paid out
		world.monoliths = WorldSave.monoliths_from(save)      # Chronicle: restore engraved monuments
		for tc in WorldSave.torches_from(save):
			world.place_torch(tc)                    # rebuild placed torch lights

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
	player.respawned.connect(_on_player_respawned)   # clear spawn-campers so death isn't a loop

	# Day/night drives the sun, sky and night-mob spawning.
	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup(_sun, _env, _sky_mat)
	day_night.phase_changed.connect(_on_phase_changed)

	# Seasons + weather (sandstorms in the desert, rain / thunderstorms / snow).
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

	# Living-world ambience: fireflies at night, pollen motes by day, occasional shooting stars.
	var ambience := preload("res://scripts/world/ambience.gd").new()
	ambience.name = "Ambience"
	ambience.setup(player, day_night)
	add_child(ambience)

	# Discoverable structures: ruined towers, crypts (with a guardian), and treasure caches,
	# scattered as you explore — each holding a loot chest. Makes exploration rewarding.
	var structures := preload("res://scripts/world/structures.gd").new()
	structures.name = "Structures"
	structures.setup(world, player)
	add_child(structures)

	# Farming: tilled soil + growing crops the player plants and harvests.
	var farm := preload("res://scripts/world/farm.gd").new()
	farm.name = "FarmManager"
	farm.setup(world, player)
	add_child(farm)
	player.farm = farm

	# --- Novel world systems ---------------------------------------------------------------
	# Mirages (weather phantoms), oddities (blind-spot edits), hauntfields (the ground remembers),
	# the Chronicle Stone, Echo-Sounding sonar, the Hunger of Hollows, and the Doppelganger builder.
	var mirage := preload("res://scripts/world/mirage.gd").new()
	mirage.name = "Mirage"
	mirage.setup(world, player, day_night, weather)
	add_child(mirage)

	var oddities := preload("res://scripts/world/oddities.gd").new()
	oddities.name = "Oddities"
	oddities.setup(world, player, day_night, weather)
	add_child(oddities)

	hauntfields = preload("res://scripts/world/hauntfields.gd").new()
	hauntfields.name = "Hauntfields"
	hauntfields.setup(world, player)
	add_child(hauntfields)

	var chronicle := preload("res://scripts/world/chronicle.gd").new()
	chronicle.name = "Chronicle"
	chronicle.setup(world, player, day_night, weather)
	add_child(chronicle)

	var echo := preload("res://scripts/world/echo_sounding.gd").new()
	echo.name = "EchoSounding"
	echo.setup(world, player)
	add_child(echo)

	var hollows := preload("res://scripts/world/hollows.gd").new()
	hollows.name = "Hollows"
	hollows.setup(world, player)
	add_child(hollows)

	var mimic := preload("res://scripts/world/mimic_builder.gd").new()
	mimic.name = "MimicBuilder"
	mimic.setup(world, player)
	add_child(mimic)

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
		if save.has("crops") and save.crops is Array:
			farm.load_data(save.crops)

	GameSettings.apply_gameplay(player, world)   # saved sensitivity + view distance

	# Initial day/night readout, and a first-time welcome on a brand-new world.
	if hud and hud.has_method("set_time_state") and day_night:
		hud.set_time_state(day_night.is_night(), _nights + 1, day_night.blood_moon)
	if save.is_empty():
		_welcome()
		if hud and hud.has_method("auto_retire_controls"):
			hud.auto_retire_controls()

## A brief two-beat welcome the first time into a fresh world (loaded saves skip it).
func _welcome() -> void:
	if hud == null or not hud.has_method("show_toast"):
		return
	hud.show_toast("Welcome, builder. Gather wood and stone before dark.", Color(0.92, 0.96, 1.0))
	var t := get_tree().create_timer(4.2)
	t.timeout.connect(func() -> void:
		if hud and hud.has_method("show_toast"):
			hud.show_toast("When night falls the horde rises — make torches or build shelter.", Color(1.0, 0.85, 0.6)))

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
	# The sky shader animates every frame (stars/clouds/blood-moon) and DayNight rewrites its colors
	# each frame, so with AMBIENT_SOURCE_SKY the radiance cubemap (which feeds only the low-frequency
	# diffuse ambient — nothing samples it for reflections) would regenerate near every frame. Amortize
	# that across frames and halve its resolution: the visible sky dome is drawn directly by the shader
	# (unchanged), only the ambient-lighting input updates more cheaply. Over the 8-min day cycle the
	# per-frame ambient delta is tiny, so the spread is imperceptible.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 6.0
	# HDR bloom: lets bright emissives (lava, torches, the sun disc, sonar ghosts) actually glow.
	# Screen-blend, conservative threshold — pure post, zero extra draw calls on this GPU-idle build.
	_env.glow_enabled = true
	_env.glow_intensity = 0.5
	_env.glow_strength = 0.9
	_env.glow_bloom = 0.12
	_env.glow_hdr_threshold = 1.1
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# Atmospheric fog: distant terrain fades into the sky horizon — gives depth and hides
	# the chunk-streaming edge. DayNight refreshes fog_light_color each frame to match the
	# sky (blue by day, orange at dusk, dark at night).
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.78, 0.86, 0.95)   # day horizon; DayNight refreshes it
	_env.fog_density = 0.02                            # matched to the farther render distance (Weather.BASE_FOG)
	_env.fog_sky_affect = 0.0
	_env.fog_aerial_perspective = 0.4
	# Height fog: a thin layer pooling around sea level so valleys/water read with depth and the
	# golden hour catches the mist. Separate from fog_density (which Weather owns), so no conflict.
	_env.fog_height = 40.0
	_env.fog_height_density = 0.04
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
	# Blood-moon stinger (one-shot, played on the siege-night phase change).
	_stinger = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/weather/blood_moon.wav"):
		_stinger.stream = load("res://assets/audio/weather/blood_moon.wav")
	_stinger.volume_db = -3.0
	if AudioServer.get_bus_index("SFX") != -1:
		_stinger.bus = "SFX"
	add_child(_stinger)

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
		var found := false
		for _try in range(6):
			ax = cx + _rng.randi_range(-14, 14)
			az = cz + _rng.randi_range(-14, 14)
			if world.surface_height(ax, az) > world.SEA_LEVEL:
				found = true
				break
		if not found:
			continue                       # all tries hit water — skip rather than spawn a land animal in the sea
		var ah: int = world.surface_height(ax, az) + 2
		var a := preload("res://scripts/entities/animal.gd").new()
		a.world = world
		a.player = player
		a.position = Vector3(float(ax), float(ah), float(az))
		add_child(a)

## A "blood moon" every 5th night: a bigger horde with brutes, under a red sky — the siege
## peak the day's prep builds toward. Other nights still escalate via _nights.
func _on_phase_changed(is_night: bool) -> void:
	if is_night:
		var night_no := _nights + 1
		var blood := night_no % BLOOD_MOON_EVERY == 0
		if day_night:
			day_night.blood_moon = blood
		if hud:
			if hud.has_method("set_blood_moon"): hud.set_blood_moon(blood)
			if hud.has_method("set_time_state"): hud.set_time_state(true, night_no, blood)
		var count: int = mini(MAX_NIGHT_MOBS, NIGHT_MOB_COUNT + _nights * 2)
		if night_no == 1:
			count = maxi(2, int(count / 3.0))   # gentle first night so new players can find their feet before the siege escalates
		if blood:
			count = mini(MAX_NIGHT_MOBS + 6, count + 5)   # they come in force
			if _stinger and _stinger.stream:
				_stinger.play()                            # ominous blood-moon sting
		_spawn_hostiles(count, blood)
		# On a blood moon, part of the horde erupts straight out of your densest killing grounds.
		if blood and hauntfields:
			var targets: Array = hauntfields.blood_moon_targets(3)
			for ep in targets:
				_spawn_clawup(ep)
			if targets.size() > 0 and hud and hud.has_method("show_toast"):
				hud.show_toast("They claw up from where you fought...", Color(1.0, 0.4, 0.35))
		if player and player.hud and player.hud.has_method("show_toast"):
			if blood:
				player.hud.show_toast("BLOOD MOON  -  Night %d. They come in force." % night_no, Color(1.0, 0.3, 0.25))
			else:
				player.hud.show_toast("Night %d  -  the horde rises." % night_no, Color(0.92, 0.86, 0.6))
	else:
		_ignite_hostiles()      # dawn: the horde catches fire and burns down rather than blinking out
		if day_night:
			day_night.blood_moon = false
		_nights += 1
		if hud:
			if hud.has_method("set_blood_moon"): hud.set_blood_moon(false)
			if hud.has_method("set_time_state"): hud.set_time_state(false, _nights + 1, false)
		if player:
			if player.has_method("play_dawn_sound"):
				player.play_dawn_sound()   # birdsong relief beat at sunrise
			if player.has_signal("night_survived"):
				player.emit_signal("night_survived")
			if player.hud and player.hud.has_method("show_toast"):
				player.hud.show_toast("Night %d survived" % _nights, Color(0.7, 1.0, 0.8))

## QUEUE the horde rather than instantiating it all at once — instantiating 16 skinned zombies
## in a single frame hitched nightfall hard. _process drains the queue a few per frame.
func _spawn_hostiles(n: int, blood := false) -> void:
	_clear_hostiles()
	if player == null:
		return
	var bonus_hp := mini(_nights * 4, 28)                  # cap so late mobs aren't damage sponges
	var bonus_dmg := mini(floori(float(_nights) / 2.0), 4) # ramps faster; base damage is now 2
	for i in range(n):
		# Brutes anchor the horde: several on blood moons, one on tougher regular nights.
		var is_brute: bool = (blood and i % 4 == 0) or (not blood and _nights >= 4 and i == 0)
		# Some of the rest run — lean, fast, frail. Keeps the horde varied and the chase tense.
		var is_runner: bool = (not is_brute) and _nights >= 1 and _rng.randf() < 0.35
		_spawn_queue.append({
			"brute": is_brute,
			"runner": is_runner,
			"hp": (10 + bonus_hp) * (3 if is_brute else 1) - (4 if is_runner else 0),  # runners are frail
			"dmg": (1 + bonus_dmg) + (2 if is_brute else 0),   # toned down — zombies were too punishing
			"smarts": clampf(1.0 + float(_nights) * 0.05, 1.0, 1.5),   # each surviving night: sense you farther + close in quicker + pursue longer
		})

## Instantiate one queued siege mob around the player's CURRENT position (so a staggered spawn
## still surrounds them even if they've moved).
## True when the standable top of the column under (x, z) is a player-built (override) block.
## ONE predicate shared by every mob spawner so the "never on the base wall" rule can't drift.
## floori (not int) so negative coordinates check the column the mob actually stands in.
func _spot_on_player_build(x: float, z: float) -> bool:
	var cx := floori(x)
	var cz := floori(z)
	return world.overrides.has(Vector3i(cx, world.solid_top_y(cx, cz), cz))

func _spawn_one_hostile(spec: Dictionary) -> void:
	var ang := _rng.randf_range(0.0, TAU)
	var rad := _rng.randf_range(12.0, 20.0)
	# Hauntfields biases some of the horde to march in from your bloodiest ground.
	if hauntfields:
		var b: Dictionary = hauntfields.bias_spawn(player.global_position, ang, rad)
		ang = float(b.get("ang", ang))
		rad = float(b.get("rad", rad))
	var mx: float = player.global_position.x + cos(ang) * rad
	var mz: float = player.global_position.z + sin(ang) * rad
	# Spawn on the REAL solid top (cave/edit/tree-stump aware), not the 2D-noise surface — otherwise
	# a mob embeds in terrain (and falls) or lands perched on a 1-wide tree stump and gets stuck.
	# floori, NOT int(): truncation picks the wrong column at negative coords (the mob's collider
	# occupies floor(x), so an int() guard misses player walls across half the map).
	var my: int = world.solid_top_y(floori(mx), floori(mz)) + 1
	# ...but never standing ON a player-built block: solid_top_y is edit-aware, so without this a
	# zombie materializes on the base wall/roof and drops INSIDE the defenses. Bounded re-roll;
	# if the player is fully ringed by builds the last roll stands (degrades to today, never worse).
	for _retry in range(4):
		if not _spot_on_player_build(mx, mz):
			break
		ang = _rng.randf_range(0.0, TAU)
		rad = _rng.randf_range(12.0, 20.0)
		mx = player.global_position.x + cos(ang) * rad
		mz = player.global_position.z + sin(ang) * rad
		my = world.solid_top_y(floori(mx), floori(mz)) + 1
	var mob := preload("res://scripts/entities/hostile_mob.gd").new()
	mob.player = player
	mob.world = world
	mob.brute = bool(spec.brute)
	mob.runner = bool(spec.get("runner", false))
	mob.day_night = day_night          # so it burns if it's still out under open sky at dawn
	mob.health = int(spec.hp)
	mob.damage = int(spec.dmg)
	mob.smarts = float(spec.get("smarts", 1.0))
	mob.position = Vector3(mx, float(my), mz)
	add_child(mob)
	_hostiles.append(mob)
	# A low, dark dust poof softens the "pop into existence" when a siege mob materializes in view.
	if player and player.has_method("_emit_burst"):
		player._emit_burst(mob.global_position + Vector3(0, 0.1, 0), Color(0.35, 0.32, 0.30), 6, 0.45, 80.0, 0.6, 1.8, 7.0)

## A blood-moon claw-up: a hostile erupts from a marked grave cell with a dirt burst.
func _spawn_clawup(pos: Vector3) -> void:
	# Never erupt in the player's lap — push close targets out to the spawn-ring floor so they
	# still get reaction time (the eruption count is unchanged; only the position moves).
	if player:
		var dx: float = pos.x - player.global_position.x
		var dz: float = pos.z - player.global_position.z
		var hd := sqrt(dx * dx + dz * dz)
		if hd < 10.0:
			var a := atan2(dz, dx) if hd > 0.01 else _rng.randf_range(0.0, TAU)
			var nx: float = player.global_position.x + cos(a) * 14.0
			var nz: float = player.global_position.z + sin(a) * 14.0
			# Same never-on-a-built-block guard as the siege spawner (re-roll the angle).
			for _retry in range(4):
				if not _spot_on_player_build(nx, nz):
					break
				a = _rng.randf_range(0.0, TAU)
				nx = player.global_position.x + cos(a) * 14.0
				nz = player.global_position.z + sin(a) * 14.0
			pos = Vector3(nx, float(world.solid_top_y(floori(nx), floori(nz)) + 1), nz)
	if hauntfields:
		hauntfields.clawup_vfx(pos)
	var mob := preload("res://scripts/entities/hostile_mob.gd").new()
	mob.player = player
	mob.world = world
	mob.day_night = day_night
	mob.health = 12 + mini(_nights * 3, 24)
	mob.damage = 2 + mini(floori(float(_nights) / 2.0), 4)
	mob.position = pos
	add_child(mob)
	_hostiles.append(mob)
	if mob.has_method("emerge"):
		mob.emerge()                          # rise up out of the marked ground

func _clear_hostiles() -> void:
	_spawn_queue.clear()                  # cancel any pending spawns (e.g. at dawn)
	for m in _hostiles:
		if is_instance_valid(m):
			m.queue_free()
	_hostiles.clear()

## On respawn, despawn hostiles camping the spawn point so a night death isn't an instant re-kill
## loop. Distant horde members are left alone (you still have a world to deal with).
func _on_player_respawned() -> void:
	if player == null:
		return
	var r2 := 14.0 * 14.0
	var kept: Array = []
	for m in _hostiles:
		if is_instance_valid(m):
			if m.global_position.distance_squared_to(player.spawn_point) <= r2:
				m.queue_free()
			else:
				kept.append(m)
	_hostiles = kept

## Dawn: set the surviving horde alight instead of deleting it — they smoke, sear, and topple
## over a couple of seconds (self-freeing on death). Cancels any pending spawns first.
func _ignite_hostiles() -> void:
	_spawn_queue.clear()
	for m in _hostiles:
		if is_instance_valid(m) and m.has_method("ignite"):
			m.ignite()
	_hostiles.clear()                     # they self-manage from here (burn → topple → queue_free)

## Caves are dangerous now: while the player is well below the surface, keep a few lurking
## hostiles nearby. They emerge from the dark and are culled once the player climbs out or
## moves away — so descending for ore is a real risk, not a free vending machine.
func _process(delta: float) -> void:
	if player == null or world == null:
		return
	# Drain the staggered siege spawn a few per frame (only while it's still night).
	if not _spawn_queue.is_empty() and day_night != null and day_night.is_night():
		var sk := 0
		while sk < SIEGE_SPAWN_PER_FRAME and not _spawn_queue.is_empty():
			_spawn_one_hostile(_spawn_queue.pop_front())
			sk += 1
	# Cheap per-frame prune: drop freed or far-away cave lurkers.
	for i in range(_cave_mobs.size() - 1, -1, -1):
		var m = _cave_mobs[i]
		if not is_instance_valid(m):
			_cave_mobs.remove_at(i)
		elif m.global_position.distance_squared_to(player.global_position) > 900.0:   # 30² — avoid per-frame sqrt
			m.queue_free()
			_cave_mobs.remove_at(i)
	_cave_t -= delta
	if _cave_t > 0.0:
		return                                  # the rest (terrain queries) only runs every 3.5 s
	_cave_t = 3.5
	# A cave lurker that has climbed out into the open despawns — no daylight cave zombies.
	for i in range(_cave_mobs.size() - 1, -1, -1):
		var m = _cave_mobs[i]
		if is_instance_valid(m):
			var ms: int = world.surface_height(int(m.global_position.x), int(m.global_position.z))
			if m.global_position.y >= float(ms) - 1.5:
				m.queue_free()
				_cave_mobs.remove_at(i)
	# Spawn only while genuinely underground, and never on top of an active night siege.
	var siege: bool = day_night != null and day_night.is_night() and not _hostiles.is_empty()
	var px := int(player.global_position.x)
	var pz := int(player.global_position.z)
	var underground: bool = player.global_position.y < float(world.surface_height(px, pz)) - CAVE_DEPTH
	if underground and not siege and _cave_mobs.size() < CAVE_MOB_MAX:
		_spawn_cave_mob()

func _spawn_cave_mob() -> void:
	var cy := int(player.global_position.y)
	for _try in range(10):
		var ox := _rng.randi_range(-11, 11)
		var oz := _rng.randi_range(-11, 11)
		if absi(ox) < 4 and absi(oz) < 4:
			continue                                   # never right on top of the player
		var cx := int(player.global_position.x) + ox
		var cz := int(player.global_position.z) + oz
		# A standable air pocket in the dark: head + body clear, solid floor under it.
		if world.get_block(cx, cy, cz) == VoxelTypes.AIR \
				and world.get_block(cx, cy + 1, cz) == VoxelTypes.AIR \
				and VoxelTypes.is_solid(world.get_block(cx, cy - 1, cz)):
			var mob := preload("res://scripts/entities/hostile_mob.gd").new()
			mob.player = player
			mob.world = world
			mob.health = 8 + mini(_nights * 2, 16)
			mob.damage = 2 + mini(floori(float(_nights) / 2.0), 3)
			mob.position = Vector3(float(cx) + 0.5, float(cy), float(cz) + 0.5)
			add_child(mob)
			_cave_mobs.append(mob)
			return
