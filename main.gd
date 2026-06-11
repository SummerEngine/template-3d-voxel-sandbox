extends Node3D

## Game root. Builds lighting, the voxel world, the player, wandering animals,
## the HUD and the pause menu at runtime. Tuned light for low-end hardware.

const ANIMAL_COUNT := 6

func _ready() -> void:
	Engine.max_fps = 60                      # cap GPU work on laptops

	_setup_environment()
	_setup_sun()

	var world := preload("res://voxel_world.gd").new()
	world.name = "VoxelWorld"
	add_child(world)

	var hud := preload("res://scripts/ui/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)

	var player := preload("res://player.gd").new()
	player.name = "Player"
	player.position = Vector3(0.0, 4.0, 0.0)
	player.hud = hud
	add_child(player)

	_spawn_animals()

	var pause := preload("res://scripts/ui/pause_menu.gd").new()
	pause.name = "PauseMenu"
	add_child(pause)

func _setup_environment() -> void:
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Keep post-processing off for performance (no SSAO / glow / SDFGI).
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

func _setup_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.rotation_degrees = Vector3(-50.0, -40.0, 0.0)
	sun.shadow_enabled = true
	# Cheapest shadow setup: single split, short range.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

func _spawn_animals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var colors := [
		Color(0.95, 0.92, 0.86),  # sheep
		Color(0.90, 0.62, 0.62),  # pig
		Color(0.55, 0.45, 0.35),  # cow
	]
	for i in range(ANIMAL_COUNT):
		var a := preload("res://scripts/world/animal.gd").new()
		a.set_color(colors[i % colors.size()])
		a.position = Vector3(rng.randf_range(-6, 6), 2.0, rng.randf_range(-6, 6))
		add_child(a)
