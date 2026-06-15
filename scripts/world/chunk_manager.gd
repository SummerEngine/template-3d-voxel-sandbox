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
const SNOW_LEVEL := 82         # snow-capped peaks at/above this height
const RENDER_RADIUS := 3       # chunks around the player (longer view distance)
const LOADS_PER_FRAME := 3     # async chunk builds dispatched per frame (they run in parallel)
const APPLIES_PER_FRAME := 2   # finished chunk meshes applied to the scene per frame (smooths pop-in)

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
var temp_noise := FastNoiseLite.new()      # temperature regions (hot deserts <-> cold snow)
var oasis_noise := FastNoiseLite.new()     # rare desert oasis pockets
var cave_noise := FastNoiseLite.new()
var chunks: Dictionary = {}    # Vector2i -> Chunk node
var overrides: Dictionary = {} # Vector3i -> int (player edits)
var chests: Dictionary = {}    # Vector3i -> Inventory (per-chest storage)

## The storage Inventory for the chest at a cell (created empty on first open).
func chest_at(cell: Vector3i) -> Inventory:
	if not chests.has(cell):
		chests[cell] = Inventory.new()
	return chests[cell]
var _queue: Array = []
var _center := Vector2i(999999, 999999)
var _apply_budget := 0         # per-frame budget chunks consume to apply their finished mesh

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
	temp_noise.seed = 8123
	temp_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	temp_noise.frequency = 0.0026           # large temperature regions (deserts <-> snowlands)
	oasis_noise.seed = 6464
	oasis_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	oasis_noise.frequency = 0.05            # small scattered oasis pockets in deserts
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
	var cont := noise.get_noise_2d(fx, fz)              # -1..1 continents vs oceans
	var h := float(SEA_LEVEL) + cont * 8.0
	# Ridged mountain ranges — prominent on land, so the world has real rocky peaks.
	var land := clampf((cont + 0.15) / 0.6, 0.0, 1.0)
	var ridge := 1.0 - absf(mountain_noise.get_noise_2d(fx, fz))   # 0..1 ridge lines
	var mtn := pow(ridge, 3.0) * land
	h += mtn * 52.0
	h += detail_noise.get_noise_2d(fx, fz) * 6.0        # rolling hills everywhere
	var desert := _is_desert(wx, wz)
	if mtn < 0.18 and not desert:
		# Rivers wind through temperate lowland only — never slicing across deserts.
		var rv := river_noise.get_noise_2d(fx, fz)
		if absf(rv) < 0.04 and h > float(SEA_LEVEL) and h < float(SEA_LEVEL + 9):
			h = lerpf(h, float(SEA_LEVEL - 1), 1.0 - absf(rv) / 0.04)
	elif desert:
		# Deserts get rare small oasis pools instead of rivers.
		var ov := oasis_noise.get_noise_2d(fx, fz)
		if ov > 0.80 and h > float(SEA_LEVEL) and h < float(SEA_LEVEL + 8):
			h = minf(h, float(SEA_LEVEL - 1))
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
	if wy == s:
		return _surface_block(wx, wz, s)
	if wy >= s - 3:
		return _subsurface_block(wx, wz, s)
	return _ore_or_stone(wx, wy, wz)

## Top block of a column, by biome: beach/desert sand (with a green ring around oases),
## bare rock then snow caps up high, snow over cold lowlands, grass elsewhere.
func _surface_block(wx: int, wz: int, s: int) -> int:
	if s <= SEA_LEVEL + 1:
		return VoxelTypes.SAND
	if s >= SNOW_LEVEL:
		return VoxelTypes.SNOW
	if s >= MOUNTAIN_ROCK:
		return VoxelTypes.STONE
	if _temp01(wx, wz) < 0.30:
		return VoxelTypes.SNOW                       # cold lowlands / snow hills
	if _is_desert(wx, wz):
		var ov := oasis_noise.get_noise_2d(float(wx), float(wz))
		if ov > 0.62 and ov <= 0.80:
			return VoxelTypes.GRASS                   # greenery ring around an oasis pool
		return VoxelTypes.SAND
	return VoxelTypes.GRASS

func _subsurface_block(wx: int, wz: int, s: int) -> int:
	if s <= SEA_LEVEL + 1:
		return VoxelTypes.SAND
	if s >= MOUNTAIN_ROCK:
		return VoxelTypes.STONE
	if _is_desert(wx, wz):
		return VoxelTypes.SAND
	return VoxelTypes.DIRT                            # snow & grass both sit on dirt

# --- climate / biomes ---------------------------------------------------------------
func _temp01(wx: int, wz: int) -> float:
	return temp_noise.get_noise_2d(float(wx), float(wz)) * 0.5 + 0.5

func _moist01(wx: int, wz: int) -> float:
	return moisture_noise.get_noise_2d(float(wx), float(wz)) * 0.5 + 0.5

## Hot AND dry → desert.
func _is_desert(wx: int, wz: int) -> bool:
	return _temp01(wx, wz) > 0.60 and _moist01(wx, wz) < 0.40

## Biome label for a column (used by weather + fauna). Height wins for water/mountain/
## snow-cap; otherwise temperature + moisture pick desert / jungle / forest / meadow / snow.
func biome_at(wx: int, wz: int) -> String:
	var s := surface_height(wx, wz)
	if s <= SEA_LEVEL:
		return "water"
	if s >= SNOW_LEVEL:
		return "snow"
	if s >= MOUNTAIN_ROCK:
		return "mountain"
	var t := _temp01(wx, wz)
	var m := _moist01(wx, wz)
	if t < 0.30:
		return "snow"
	if t > 0.60 and m < 0.40:
		return "desert"
	if t > 0.58 and m > 0.66:
		return "jungle"
	if m > 0.62:
		return "forest"
	return "meadow"                      # broad temperate middle = open green plains

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
	var t := _temp01(cx, cz)
	var m := _moist01(cx, cz)
	if t > 0.60 and m < 0.40:
		# Desert: palms only on the oasis greenery ring (matches the grass band), never bare sand.
		if oasis_noise.get_noise_2d(float(cx), float(cz)) <= 0.62:
			return false
		return (_hash2(cx, cz) % 8) == 0
	if t < 0.30:
		return (_hash2(cx, cz) % 30) == 0    # snowy: sparse conifers
	var rarity := 0
	if t > 0.58 and m > 0.66:   rarity = 7    # jungle — very dense
	elif m > 0.62:              rarity = 16   # forest / woods
	elif m > 0.45:              rarity = 44   # scattered savanna trees
	else:                       return false  # open meadow / plains stay treeless
	return (_hash2(cx, cz) % rarity) == 0

func is_jungle(cx: int, cz: int) -> bool:
	return _temp01(cx, cz) > 0.58 and _moist01(cx, cz) > 0.66

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
	var ndx := -1 if lx == 0 else (1 if lx == CHUNK_W - 1 else 0)
	var ndz := -1 if lz == 0 else (1 if lz == CHUNK_D - 1 else 0)
	if ndx != 0: _rebuild(chunk_x(wx) + ndx, chunk_z(wz))
	if ndz != 0: _rebuild(chunk_x(wx), chunk_z(wz) + ndz)
	if ndx != 0 and ndz != 0: _rebuild(chunk_x(wx) + ndx, chunk_z(wz) + ndz)   # diagonal corner

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
	# Synchronously build the immediate area so the player has ground at spawn (no fall-through).
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			_load(Vector2i(center.x + dx, center.y + dz), true)

func _process(_delta: float) -> void:
	if player == null:
		return
	_apply_budget = APPLIES_PER_FRAME   # reset each frame; chunks consume it as they finish (parent processes first)
	var pc := Vector2i(chunk_x(int(player.global_position.x)), chunk_z(int(player.global_position.z)))
	if pc != _center:
		_center = pc
		_refresh_queue(pc)
		_unload_far(pc)
	var n := 0
	while n < LOADS_PER_FRAME and not _queue.is_empty():
		_load(_queue.pop_front())
		n += 1

## A finishing chunk calls this on the main thread before applying its mesh; returns
## false once this frame's quota is spent, so applies spread across frames (no hitch).
func consume_apply_budget() -> bool:
	if _apply_budget > 0:
		_apply_budget -= 1
		return true
	return false

## Has the chunk covering this world column finished building its collider? Used by the
## player to avoid falling through terrain that is still streaming in (which otherwise
## causes a phantom long fall + fall-damage "death from nowhere").
func is_chunk_ready(wx: int, wz: int) -> bool:
	var c := Vector2i(chunk_x(wx), chunk_z(wz))
	return chunks.has(c) and is_instance_valid(chunks[c]) and chunks[c].is_ready()

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
			if chunks[c].is_building():
				continue                    # defer: freeing now would block the frame on its task
			chunks[c].queue_free()
		chunks.erase(c)

func _load(c: Vector2i, sync := false) -> void:
	if chunks.has(c):
		return
	var ch := preload("res://scripts/world/chunk.gd").new()
	ch.manager = self
	ch.coord = c
	ch.position = Vector3(c.x * CHUNK_W, 0.0, c.y * CHUNK_D)
	chunks[c] = ch
	add_child(ch)
	# Spawn area builds synchronously (instant ground); streamed chunks build on a worker
	# thread and apply their mesh on a later frame, so streaming never stutters.
	if sync:
		ch.build()
	else:
		ch.start_async()

func _rebuild(cx: int, cz: int) -> void:
	var c := Vector2i(cx, cz)
	if chunks.has(c) and is_instance_valid(chunks[c]):
		chunks[c].build()

## Force every loaded chunk to remesh (used after bulk-applying a loaded save).
func rebuild_all() -> void:
	for c in chunks.keys():
		if is_instance_valid(chunks[c]):
			chunks[c].build()
