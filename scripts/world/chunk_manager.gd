class_name ChunkManager
extends Node3D

## Streams 16x16x256 chunks around the player and owns terrain generation.
## Terrain is a PURE FUNCTION of world coordinates (noise + hashes) plus per-block
## edit overrides, so any voxel can be sampled even if its chunk isn't loaded and
## the world stays seamless. generate_block() layers: bedrock floor, 3D-noise caves,
## depth-banded ores, grass/dirt/stone columns, sand beaches, sea-level water, and
## hash-placed trees (trunk + leaf canopy).

const CHUNK_W := 16
const CHUNK_D := 16
const WORLD_H := 256
const SEA_LEVEL := 40          # water fills below this: oceans, lakes, rivers
const MOUNTAIN_ROCK := 64      # bare-stone peaks at/above this height
const RENDER_RADIUS := 3       # chunks around the player (longer view distance)
const LOADS_PER_FRAME := 1

const CAVE_SQUASH := 1.4       # >1 flattens caves vertically
const CAVE_THRESHOLD := 0.55   # carve where 3D cave noise exceeds this
const TREE_R := 3              # max tree canopy radius (jungle)
const TREE_H := 10             # max tree height (jungle)

var player: Node3D
var noise := FastNoiseLite.new()           # continent / base elevation (oceans vs land)
var detail_noise := FastNoiseLite.new()    # rolling hills + meadows
var mountain_noise := FastNoiseLite.new()  # ridged mountain ranges
var river_noise := FastNoiseLite.new()     # winding river channels
var forest_noise := FastNoiseLite.new()    # forest / jungle density regions
var moisture_noise := FastNoiseLite.new()  # dry deserts vs grassy land
var cave_noise := FastNoiseLite.new()
var chunks: Dictionary = {}    # Vector2i -> Chunk node
var overrides: Dictionary = {} # Vector3i -> int (player edits)
var _queue: Array = []
var _center := Vector2i(999999, 999999)

func _ready() -> void:
	noise.seed = 1337
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.0035                # low freq -> large continents & oceans
	detail_noise.seed = 2207
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.frequency = 0.02
	mountain_noise.seed = 5151
	mountain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	mountain_noise.frequency = 0.009
	river_noise.seed = 7777
	river_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	river_noise.frequency = 0.006
	forest_noise.seed = 4242
	forest_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	forest_noise.frequency = 0.0045         # large forest / jungle patches
	moisture_noise.seed = 3131
	moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	moisture_noise.frequency = 0.004        # large dry / desert patches
	cave_noise.seed = 9001
	cave_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	cave_noise.frequency = 0.045

# --- terrain ---

## Surface height from a layered noise stack: a continent shapes oceans/plains, a
## detail layer adds hills/meadows, a ridged layer raises mountains on high ground,
## and a river layer carves winding channels down to water level.
func surface_height(wx: int, wz: int) -> int:
	var fx := float(wx)
	var fz := float(wz)
	var cont := noise.get_noise_2d(fx, fz)              # -1..1
	var h := float(SEA_LEVEL) + cont * 7.0              # gentle land/ocean — shallow water
	var relief := clampf(cont + 0.3, 0.0, 1.0)
	h += detail_noise.get_noise_2d(fx, fz) * 5.0 * (0.4 + relief)   # gentle rolling hills
	if cont > 0.5:                                      # mountains: rarer + shorter
		var m := 1.0 - absf(mountain_noise.get_noise_2d(fx, fz))   # ridged 0..1
		h += pow(m, 1.7) * 16.0 * ((cont - 0.5) / 0.5)
	var rv := river_noise.get_noise_2d(fx, fz)          # wide, shallow rivers (gentle banks)
	if absf(rv) < 0.05 and h > float(SEA_LEVEL) and h < float(SEA_LEVEL + 12):
		h = lerpf(h, float(SEA_LEVEL - 1), 1.0 - absf(rv) / 0.05)
	return int(round(h))

## The natural (un-edited) block at a world coordinate. Pass the column surface in
## `s` to avoid recomputing the 2D noise when the caller already has it.
func generate_block(wx: int, wy: int, wz: int, s: int = -9999) -> int:
	if wy < 0 or wy >= WORLD_H:
		return VoxelTypes.AIR
	if wy == 0:
		return VoxelTypes.BEDROCK
	if s == -9999:
		s = surface_height(wx, wz)

	if wy > s:
		# Above the ground: trees grow on dry land, otherwise water up to sea level.
		if s > SEA_LEVEL:
			var tb := _tree_block(wx, wy, wz)
			if tb != VoxelTypes.AIR:
				return tb
		return VoxelTypes.WATER if wy <= SEA_LEVEL else VoxelTypes.AIR
	return _solid_block(wx, wy, wz, s)

## Terrain WITHOUT trees, used by the per-chunk cache fill (trees are layered on
## separately so the hot meshing path never runs the per-voxel tree search).
func ground_block(wx: int, wy: int, wz: int, s: int) -> int:
	if wy < 0 or wy >= WORLD_H:
		return VoxelTypes.AIR
	if wy == 0:
		return VoxelTypes.BEDROCK
	if wy > s:
		return VoxelTypes.WATER if wy <= SEA_LEVEL else VoxelTypes.AIR
	return _solid_block(wx, wy, wz, s)

func _solid_block(wx: int, wy: int, wz: int, s: int) -> int:
	# Caves: carve below a solid crust and above the bedrock floor.
	if wy >= 2 and wy <= s - 3:
		var c := cave_noise.get_noise_3d(float(wx), float(wy) * CAVE_SQUASH, float(wz))
		if c > CAVE_THRESHOLD:
			return VoxelTypes.AIR
	var beachy := s <= SEA_LEVEL + 1
	var rocky := s >= MOUNTAIN_ROCK
	if wy == s:
		if beachy: return VoxelTypes.SAND
		if rocky: return VoxelTypes.STONE
		return VoxelTypes.SAND if _is_desert(wx, wz) else VoxelTypes.GRASS
	if wy >= s - 3:
		if beachy: return VoxelTypes.SAND
		if rocky: return VoxelTypes.STONE
		return VoxelTypes.SAND if _is_desert(wx, wz) else VoxelTypes.DIRT
	return _ore_or_stone(wx, wy, wz)

func _is_desert(wx: int, wz: int) -> bool:
	return moisture_noise.get_noise_2d(float(wx), float(wz)) < -0.3

func _ore_or_stone(wx: int, wy: int, wz: int) -> int:
	var r := _hash3(wx, wy, wz) % 1000
	if wy <= 12 and r < 5:   return VoxelTypes.DIAMOND_ORE
	if wy <= 22 and r < 11:  return VoxelTypes.GOLD_ORE
	if wy <= 40 and r < 20:  return VoxelTypes.IRON_ORE
	if wy <= 52 and r < 34:  return VoxelTypes.COAL_ORE
	return VoxelTypes.STONE

## Tree density by biome: jungle = very dense + tall, woods = dense, scattered
## elsewhere, and open plains/meadows stay treeless.
func is_tree(cx: int, cz: int) -> bool:
	if _is_desert(cx, cz):
		return false                    # deserts stay sandy and bare
	var f := forest_noise.get_noise_2d(float(cx), float(cz))
	var rarity := 0
	if f > 0.45:      rarity = 7    # jungle
	elif f > 0.15:    rarity = 13   # woods / forest
	elif f > -0.15:   rarity = 34   # scattered
	else:             return false  # open meadow / plains
	return (_hash2(cx, cz) % rarity) == 0

func is_jungle(cx: int, cz: int) -> bool:
	return forest_noise.get_noise_2d(float(cx), float(cz)) > 0.45

## Block contributed by any tree whose base sits within TREE_R columns of (wx,wz).
func _tree_block(wx: int, wy: int, wz: int) -> int:
	for ox in range(-TREE_R, TREE_R + 1):
		for oz in range(-TREE_R, TREE_R + 1):
			var cx := wx - ox
			var cz := wz - oz
			if not is_tree(cx, cz):
				continue
			var sc := surface_height(cx, cz)
			if sc <= SEA_LEVEL + 1 or sc >= MOUNTAIN_ROCK:
				continue                            # trees only on grassland
			var v := tree_voxel(ox, wy - sc, oz, is_jungle(cx, cz))
			if v != VoxelTypes.AIR:
				return v
	return VoxelTypes.AIR

## Tree shape relative to its base block. tall = jungle (7-high trunk, radius-3
## canopy); otherwise a 4-high trunk with a small leaf ball.
func tree_voxel(rx: int, ry: int, rz: int, tall: bool) -> int:
	var th := 7 if tall else 4
	if rx == 0 and rz == 0 and ry >= 1 and ry <= th:
		return VoxelTypes.WOOD
	var r2 := rx * rx + rz * rz
	var cr2 := 9 if tall else 4
	if ry >= th - 1 and ry <= th + 1 and r2 <= cr2:
		return VoxelTypes.LEAVES
	if ry == th + 2 and r2 <= (cr2 - 4 if tall else 2):
		return VoxelTypes.LEAVES
	if tall and ry == th + 3 and r2 <= 1:
		return VoxelTypes.LEAVES
	return VoxelTypes.AIR

func get_block(wx: int, wy: int, wz: int) -> int:
	var key := Vector3i(wx, wy, wz)
	if overrides.has(key):
		return overrides[key]
	return generate_block(wx, wy, wz)

func set_block(wx: int, wy: int, wz: int, t: int) -> void:
	if wy <= 0 or wy >= WORLD_H:
		return                                  # never edit the bedrock floor
	var key := Vector3i(wx, wy, wz)
	if t == generate_block(wx, wy, wz):
		overrides.erase(key)                    # edit matches nature -> no override needed
	else:
		overrides[key] = t
	_rebuild(chunk_x(wx), chunk_z(wz))
	# rebuild neighbours when editing a border block (their culling depends on us)
	var lx := local_x(wx)
	var lz := local_z(wz)
	if lx == 0: _rebuild(chunk_x(wx) - 1, chunk_z(wz))
	elif lx == CHUNK_W - 1: _rebuild(chunk_x(wx) + 1, chunk_z(wz))
	if lz == 0: _rebuild(chunk_x(wx), chunk_z(wz) - 1)
	elif lz == CHUNK_D - 1: _rebuild(chunk_x(wx), chunk_z(wz) + 1)

# --- integer hashes (deterministic, position-seeded) ---

static func _hash2(x: int, z: int) -> int:
	var n := (x * 73856093) ^ (z * 19349663)
	n = (n ^ (n >> 13)) * 1274126177
	return absi(n)

static func _hash3(x: int, y: int, z: int) -> int:
	var n := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	return absi(n)

# --- coordinate helpers ---

func chunk_x(wx: int) -> int: return floori(float(wx) / CHUNK_W)
func chunk_z(wz: int) -> int: return floori(float(wz) / CHUNK_D)
func local_x(wx: int) -> int: return ((wx % CHUNK_W) + CHUNK_W) % CHUNK_W
func local_z(wz: int) -> int: return ((wz % CHUNK_D) + CHUNK_D) % CHUNK_D

# --- streaming ---

func preload_around(center: Vector2i) -> void:
	# Synchronously load the immediate area so the player has ground at spawn.
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			_load(Vector2i(center.x + dx, center.y + dz))

func _process(_delta: float) -> void:
	if player == null:
		return
	var pc := Vector2i(chunk_x(int(player.global_position.x)), chunk_z(int(player.global_position.z)))
	if pc != _center:
		_center = pc
		_refresh_queue(pc)
		_unload_far(pc)
	var n := 0
	while n < LOADS_PER_FRAME and not _queue.is_empty():
		_load(_queue.pop_front())
		n += 1

func _refresh_queue(center: Vector2i) -> void:
	var list: Array = []
	for dz in range(-RENDER_RADIUS, RENDER_RADIUS + 1):
		for dx in range(-RENDER_RADIUS, RENDER_RADIUS + 1):
			var c := Vector2i(center.x + dx, center.y + dz)
			if not chunks.has(c):
				list.append(c)
	list.sort_custom(func(a, b): return (a - center).length_squared() < (b - center).length_squared())
	_queue = list

func _unload_far(center: Vector2i) -> void:
	var remove: Array = []
	for c in chunks.keys():
		if absi(c.x - center.x) > RENDER_RADIUS + 1 or absi(c.y - center.y) > RENDER_RADIUS + 1:
			remove.append(c)
	for c in remove:
		if is_instance_valid(chunks[c]):
			chunks[c].queue_free()
		chunks.erase(c)

func _load(c: Vector2i) -> void:
	if chunks.has(c):
		return
	var ch := preload("res://scripts/world/chunk.gd").new()
	ch.manager = self
	ch.coord = c
	ch.position = Vector3(c.x * CHUNK_W, 0.0, c.y * CHUNK_D)
	chunks[c] = ch
	add_child(ch)   # Chunk._ready() builds the mesh

func _rebuild(cx: int, cz: int) -> void:
	var c := Vector2i(cx, cz)
	if chunks.has(c) and is_instance_valid(chunks[c]):
		chunks[c].build()

## Force every loaded chunk to remesh (used after bulk-applying a loaded save).
func rebuild_all() -> void:
	for c in chunks.keys():
		if is_instance_valid(chunks[c]):
			chunks[c].build()
