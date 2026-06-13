extends Node3D

## Game root. Builds lighting, the streamed voxel world (ChunkManager), the player,
## the HUD, the pause menu and a few placeholder animals. Tuned for low-end hardware.

const ANIMAL_COUNT := 4
const ORE_COUNT := 6
const ORE_PATH := "res://assets/models/props/gold_ore.glb"

func _ready() -> void:
	Engine.max_fps = 60

	_setup_environment()
	_setup_sun()

	var world := preload("res://scripts/world/chunk_manager.gd").new()
	world.name = "ChunkManager"
	add_child(world)
	world.preload_around(Vector2i(0, 0))   # ground under spawn

	var hud := preload("res://scripts/ui/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)

	var spawn_h: int = world.surface_height(0, 0) + 3
	var player := preload("res://scripts/player/player.gd").new()
	player.name = "Player"
	player.position = Vector3(0.0, float(spawn_h), 0.0)
	player.hud = hud
	player.world_manager = world
	add_child(player)
	world.player = player

	_spawn_animals(world)
	_spawn_ore(world)

	var pause := preload("res://scripts/ui/pause_menu.gd").new()
	pause.name = "PauseMenu"
	add_child(pause)

func _setup_environment() -> void:
	# Natural daytime sky: blue above, soft horizon, earthy ground.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.52, 0.86)
	sky_mat.sky_horizon_color = Color(0.78, 0.86, 0.95)
	sky_mat.ground_horizon_color = Color(0.78, 0.86, 0.95)
	sky_mat.ground_bottom_color = Color(0.52, 0.46, 0.38)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

func _setup_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.rotation_degrees = Vector3(-55.0, -45.0, 0.0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

func _spawn_animals(world) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var colors := [
		Color(0.95, 0.92, 0.86),
		Color(0.90, 0.62, 0.62),
		Color(0.55, 0.45, 0.35),
	]
	for i in range(ANIMAL_COUNT):
		var ax := rng.randf_range(-6, 6)
		var az := rng.randf_range(-6, 6)
		var ah: int = world.surface_height(int(ax), int(az)) + 2
		var a := preload("res://scripts/world/animal.gd").new()
		a.set_color(colors[i % colors.size()])
		a.position = Vector3(ax, float(ah), az)
		add_child(a)

func _spawn_ore(world) -> void:
	if not ResourceLoader.exists(ORE_PATH):
		return
	var packed := load(ORE_PATH) as PackedScene
	if packed == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(ORE_COUNT):
		var ox := rng.randf_range(-16, 16)
		var oz := rng.randf_range(-16, 16)
		var oy: int = world.surface_height(int(ox), int(oz))
		var ore := packed.instantiate() as Node3D
		if ore == null:
			continue
		ore.position = Vector3(ox, float(oy), oz)
		add_child(ore)
