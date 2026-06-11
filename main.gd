extends Node3D

## Root of the voxel sandbox.
## Builds sky/ambient lighting, a sun, the voxel world and the player at runtime.

func _ready() -> void:
	_setup_environment()
	_setup_sun()

	var world := preload("res://voxel_world.gd").new()
	world.name = "VoxelWorld"
	add_child(world)

	var player := preload("res://player.gd").new()
	player.name = "Player"
	player.world = world
	player.position = Vector3(0.0, 4.0, 0.0)
	add_child(player)

func _setup_environment() -> void:
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

func _setup_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.rotation_degrees = Vector3(-50.0, -40.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
