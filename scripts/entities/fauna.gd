extends Node

## Maintains a living population of biome-appropriate fauna around the player. Each tick it
## tops up toward a cap by sampling a point nearby, classifying its biome (desert / water /
## forest / meadow) from the terrain, and spawning a matching creature; creatures that
## wander too far are culled. Locomotion + animation live in creature.gd.

const CAP := 12
const SPAWN_INTERVAL := 2.5
const SPAWN_MIN := 16.0
const SPAWN_MAX := 42.0
const CULL_DIST := 72.0
const A := "res://assets/models/animals/"

# mode: 0 = ground, 1 = air (birds), 2 = water (fish / aquatic). gait: walk / hop / slither.
# "size" = the creature's LONGEST dimension in metres (creature.gd scales the model to it).
var CREATURES := [
	# --- desert ---
	{"biomes": ["desert"], "model": A + "camel.glb", "mode": 0, "size": 2.1, "speed": 1.6, "run": 4.0, "meat": true, "color": Color(0.78, 0.66, 0.40)},
	{"biomes": ["desert"], "model": A + "vulture.glb", "mode": 1, "size": 1.0, "speed": 5.0, "alt": 16.0, "color": Color(0.25, 0.20, 0.18)},
	{"biomes": ["desert"], "model": A + "sand_lizard.glb", "mode": 0, "gait": "slither", "size": 0.9, "speed": 2.6, "run": 5.0, "color": Color(0.80, 0.70, 0.45)},
	# --- meadow / plains (+ the existing farm animals) ---
	{"biomes": ["meadow", "forest"], "model": A + "cow.glb", "mode": 0, "size": 1.3, "speed": 1.8, "meat": true, "color": Color(0.90, 0.90, 0.88)},
	{"biomes": ["meadow", "forest"], "model": A + "sheep.glb", "mode": 0, "size": 1.1, "speed": 1.8, "meat": true, "color": Color(0.95, 0.95, 0.92)},
	{"biomes": ["meadow"], "model": A + "pig.glb", "mode": 0, "size": 1.0, "speed": 2.0, "meat": true, "color": Color(0.92, 0.70, 0.70)},
	{"biomes": ["meadow"], "model": A + "rabbit.glb", "mode": 0, "gait": "hop", "size": 0.5, "speed": 2.6, "run": 6.0, "color": Color(0.60, 0.45, 0.32)},
	{"biomes": ["meadow", "forest"], "model": A + "songbird.glb", "mode": 1, "size": 0.35, "speed": 6.0, "alt": 9.0, "color": Color(0.70, 0.30, 0.20)},
	{"biomes": ["meadow"], "model": A + "frog.glb", "mode": 0, "gait": "hop", "size": 0.4, "speed": 1.6, "run": 3.5, "color": Color(0.30, 0.60, 0.25)},
	# --- forest / jungle ---
	{"biomes": ["forest"], "model": A + "monkey.glb", "mode": 0, "size": 0.9, "speed": 2.4, "run": 5.0, "color": Color(0.50, 0.35, 0.22)},
	{"biomes": ["forest"], "model": A + "parrot.glb", "mode": 1, "size": 0.5, "speed": 5.0, "alt": 11.0, "color": Color(0.20, 0.70, 0.30)},
	{"biomes": ["forest", "meadow"], "model": A + "snake.glb", "mode": 0, "gait": "slither", "size": 1.5, "speed": 2.0, "color": Color(0.30, 0.55, 0.25)},
	# --- river / sea ---
	{"biomes": ["water"], "model": A + "fish.glb", "mode": 2, "size": 0.6, "speed": 3.0, "run": 5.0, "color": Color(0.90, 0.50, 0.20)},
	{"biomes": ["water"], "model": A + "crocodile.glb", "mode": 2, "size": 2.4, "speed": 2.2, "meat": true, "color": Color(0.30, 0.40, 0.25)},
	{"biomes": ["water"], "model": A + "turtle.glb", "mode": 2, "size": 0.8, "speed": 1.4, "color": Color(0.35, 0.50, 0.30)},
	{"biomes": ["water"], "model": A + "duck.glb", "mode": 1, "size": 0.6, "speed": 3.5, "alt": 6.0, "color": Color(0.90, 0.90, 0.85)},
]

var world
var player
var _t := 1.0
var _rng := RandomNumberGenerator.new()
var _mine: Array = []

func setup(w, p) -> void:
	world = w
	player = p

func _ready() -> void:
	_rng.randomize()
	for i in range(6):                  # a little life at the spawn area straight away
		_try_spawn()

func _process(delta: float) -> void:
	if world == null or player == null or not is_instance_valid(player):
		return
	for i in range(_mine.size() - 1, -1, -1):
		var c = _mine[i]
		if not is_instance_valid(c):
			_mine.remove_at(i)
		elif c.global_position.distance_to(player.global_position) > CULL_DIST:
			c.queue_free()
			_mine.remove_at(i)
	_t -= delta
	if _t > 0.0:
		return
	_t = SPAWN_INTERVAL
	if _mine.size() < CAP:
		_try_spawn()

## Map the world's terrain biome onto a creature-registry tag. Jungle reuses forest fauna,
## snowfields reuse meadow grazers, and "mountain" has no tag (so nothing spawns on bare rock).
func _biome_at(x: int, z: int) -> String:
	var b := "meadow"
	if world.has_method("biome_at"):
		b = world.biome_at(x, z)
	match b:
		"jungle": return "forest"
		"snow":   return "meadow"
		_:        return b

func _try_spawn() -> void:
	var ang := _rng.randf_range(0.0, TAU)
	var rad := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
	var sx := int(player.global_position.x + cos(ang) * rad)
	var sz := int(player.global_position.z + sin(ang) * rad)
	var biome := _biome_at(sx, sz)
	var choices: Array = []
	for c in CREATURES:
		if biome in c.biomes:
			choices.append(c)
	if choices.is_empty():
		return
	var cfg: Dictionary = choices[_rng.randi() % choices.size()]
	var creature := preload("res://scripts/entities/creature.gd").new()
	creature.setup(cfg, world, player)
	creature.position = Vector3(float(sx) + 0.5, _spawn_y(sx, sz, int(cfg.get("mode", 0))), float(sz) + 0.5)
	get_parent().add_child(creature)
	_mine.append(creature)

func _spawn_y(x: int, z: int, mode: int) -> float:
	var sh := float(world.surface_height(x, z))
	match mode:
		1:
			return sh + _rng.randf_range(7.0, 14.0)                      # air
		2:
			var lo := sh + 0.8
			var hi := float(world.SEA_LEVEL) - 0.8
			if lo >= hi:
				return hi                                # too-shallow water: just under the surface
			return clampf((sh + float(world.SEA_LEVEL)) * 0.5, lo, hi)  # mid-column
		_:
			return sh + 2.0                                              # ground
