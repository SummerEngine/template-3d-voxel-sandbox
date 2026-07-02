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
const RENDER_RADIUS := 4       # default chunks around the player; render_radius (settings) overrides
var render_radius := RENDER_RADIUS
const PRELOAD := 1             # extra ring(s) built BEYOND the visible radius, so the horizon is
                              # already meshed before you reach it (no pop-in as you move)
const LOADS_PER_FRAME := 6     # async chunk builds dispatched per frame (they run in parallel)
const APPLIES_PER_FRAME := 3   # finished chunk meshes applied to the scene per frame (smooths pop-in)

const CAVE_SQUASH := 1.4       # >1 flattens caves vertically
const CAVE_THRESHOLD := 0.26   # carve where 3D cave noise exceeds this. The FBM cave noise rarely tops
                              # ~0.3, so the old 0.55 carved almost nothing (caves were near-nonexistent);
                              # 0.26 yields real, connected cave systems for the lurker/hollows layer.
# Biome thresholds — shared consts so EVERY biome test stays in lockstep (a desync between, say,
# _is_desert and the sand surface gives sand columns with forest trees). temp/moist are FBM noise
# remapped to ~0..1 but bell-shaped, so thresholds pulled too far out make a biome never appear.
const SNOW_T := 0.38           # below this temperature = snowy lowlands
const DESERT_T := 0.55         # hot AND dry -> desert
const DESERT_M := 0.45
const JUNGLE_T := 0.55         # hot AND wet -> jungle
const JUNGLE_M := 0.60
const FOREST_M := 0.55         # wet -> forest / woods
const SAVANNA_M := 0.40        # mid-wet -> scattered savanna trees; below = open meadow
const TREE_R := 3              # max tree canopy radius (jungle)
# Vertical voxel headroom a chunk meshes/scans above ground for a tree. Canopies are now 3D
# models (not voxels), so the only tree voxel is the 2-block stump — this just needs to clear
# that (was 10 from the old voxel-canopy era, which meshed ~6 empty rows per column for nothing).
const TREE_H := 4
const TREE_STUMP_H := 2        # minable log stump; the trunk+canopy is a 3D model (keep == Chunk.STUMP_H)

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
# --- world memory (persisted; populated by the novel-feature systems) ---
var graves: Dictionary = {}    # Vector3i cell -> int kill_count (Hauntfields: the ground remembers)
var hollow_scores: Dictionary = {}  # String "rx,ry,rz" region -> int carved-air pressure (Hunger of Hollows)
var hollow_calmed: Dictionary = {}  # String region -> true once its reward has paid out (no farm)
var monoliths: Dictionary = {}      # Vector3i cell -> Array[String] engravings (Chronicle Stone)

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
		# Rivers wind through temperate lowland only — never slicing across deserts. Wider and
		# deeper than before so they read as real waterways with the depth-shaded water.
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
			# Deep carved cells pool lava — lights caves via the emissive atlas tile + HDR glow,
			# and gives the Resonator ping (and the previously-dead lava branch) something real.
			if wy <= 8 and _hash3(wx, wy, wz) % 3 == 0:
				return VoxelTypes.LAVA
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
	if _temp01(wx, wz) < SNOW_T:
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
	return _temp01(wx, wz) > DESERT_T and _moist01(wx, wz) < DESERT_M

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
	if t < SNOW_T:
		return "snow"
	if t > DESERT_T and m < DESERT_M:
		return "desert"
	if t > JUNGLE_T and m > JUNGLE_M:
		return "jungle"
	if m > FOREST_M:
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
	if t > DESERT_T and m < DESERT_M:
		# Desert: palms only on the oasis greenery ring (matches the grass band), never bare sand.
		if oasis_noise.get_noise_2d(float(cx), float(cz)) <= 0.62:
			return false
		return (_hash2(cx, cz) % 8) == 0
	if t < SNOW_T:
		return (_hash2(cx, cz) % 30) == 0    # snowy: sparse conifers
	var rarity := 0
	if t > JUNGLE_T and m > JUNGLE_M:   rarity = 7    # jungle — very dense
	elif m > FOREST_M:                  rarity = 16   # forest / woods
	elif m > SAVANNA_M:                 rarity = 44   # scattered savanna trees
	else:                               return false  # open meadow / plains stay treeless
	return (_hash2(cx, cz) % rarity) == 0

func is_jungle(cx: int, cz: int) -> bool:
	return _temp01(cx, cz) > JUNGLE_T and _moist01(cx, cz) > JUNGLE_M

## Which 3D model a tree at this column uses: 1 = palm (desert oasis), 0 = broadleaf tree
## (forest / jungle / savanna / conifer). Only meaningful where is_tree() is true.
func tree_kind(cx: int, cz: int) -> int:
	if _temp01(cx, cz) > DESERT_T and _moist01(cx, cz) < DESERT_M:
		return 1
	return 0

## A tree's minable log STUMP at its own column (the trunk + leafy canopy is a 3D model the
## chunk places, not voxels). Only the trunk cell (wx,wz) carries wood; nothing overhangs.
func _tree_block(wx: int, wy: int, wz: int) -> int:
	if not is_tree(wx, wz):
		return VoxelTypes.AIR
	var sc := surface_height(wx, wz)
	if sc <= SEA_LEVEL + 1 or sc >= MOUNTAIN_ROCK:
		return VoxelTypes.AIR                       # trees only on grassland
	var ry := wy - sc
	if ry >= 1 and ry <= TREE_STUMP_H:
		return VoxelTypes.WOOD
	return VoxelTypes.AIR

func get_block(wx: int, wy: int, wz: int) -> int:
	var key := Vector3i(wx, wy, wz)
	if overrides.has(key):
		return overrides[key]
	return generate_block(wx, wy, wz)

## The REAL standable top of a column: the highest y whose block is solid-and-not-water with a
## non-solid (air/water) cell above it. Unlike surface_height (pure 2D noise) this consults
## get_block, so it respects player edits, stamped structures AND carved caves/lava — the cases
## where surface_height over-reports and a respawn would land in the air or inside a structure.
## Scans down from a safe ceiling; returns 0 (bedrock) if nothing solid is found.
func solid_top_y(wx: int, wz: int) -> int:
	var start: int = mini(surface_height(wx, wz) + TREE_H + 2, WORLD_H - 1)
	var above_open := true   # treat the ceiling as open air
	for wy in range(start, 0, -1):
		var b := get_block(wx, wy, wz)
		var solid := VoxelTypes.is_solid(b) and b != VoxelTypes.WATER
		if solid and above_open:
			return wy
		above_open = not solid
	return 0

## A clean, grounded RESPAWN position near (x,z). solid_top_y alone is not enough: at a tree
## column it returns the top of the 2-tall minable WOOD stump (the canopy is a collider-less 3D
## model), so the player would respawn PERCHED on a 1-wide wood pole under the leaves — which
## reads as "respawned in the sky." We instead spiral out (Chebyshev rings) to the nearest column
## that is dry land AND treeless, and stand on its real surface — open ground, every time. Only a
## handful of columns are scanned (trees are sparse, so r<=4 nearly always hits clear ground);
## falls back to the centre column's solid_top_y if somehow boxed in by trees/water.
func find_spawn_ground(x: float, z: float) -> Vector3:
	var ox := floori(x)
	var oz := floori(z)
	for r in range(0, 5):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if r > 0 and absi(dx) != r and absi(dz) != r:
					continue                      # only this ring's border (r==0 is the centre cell)
				var cx := ox + dx
				var cz := oz + dz
				if is_tree(cx, cz):
					continue                      # never stand on a tree column (the stump pole)
				if surface_height(cx, cz) <= SEA_LEVEL:
					continue                      # dry land only — no ocean/lake spawns
				var top := solid_top_y(cx, cz)    # treeless column -> the real terrain top (cave/edit aware)
				if top <= 0:
					continue
				return Vector3(float(cx) + 0.5, float(top) + 1.05, float(cz) + 0.5)
	# Boxed in (all-trees / all-water nearby): best effort on the original column.
	return Vector3(float(ox) + 0.5, float(solid_top_y(ox, oz)) + 1.05, float(oz) + 0.5)

func set_block(wx: int, wy: int, wz: int, t: int, s: int = -9999) -> void:
	if wy <= 0 or wy >= WORLD_H:
		return                                  # never edit the bedrock floor
	var key := Vector3i(wx, wy, wz)
	var old_t := get_block(wx, wy, wz)          # capture BEFORE mutating, to detect a solid<->air flip
	if t == generate_block(wx, wy, wz, s):      # pass the column surface to skip a noise recompute when known
		overrides.erase(key)                    # edit matches nature -> no override needed
	else:
		overrides[key] = t
	_rebuild(chunk_x(wx), chunk_z(wz))
	# Neighbour chunks only need rebuilding if the boundary cell's SOLIDITY changed — their culling
	# depends on us solely through the `!= AIR` test. A type/texture swap or a buried interior border
	# edit changes nothing for them, so skip those rebuilds (saves whole worker builds on seam edits).
	var flip := (old_t != VoxelTypes.AIR) != (t != VoxelTypes.AIR)
	var lx := local_x(wx)
	var lz := local_z(wz)
	var ndx := -1 if lx == 0 else (1 if lx == CHUNK_W - 1 else 0)
	var ndz := -1 if lz == 0 else (1 if lz == CHUNK_D - 1 else 0)
	if ndx != 0 and flip: _rebuild(chunk_x(wx) + ndx, chunk_z(wz))
	if ndz != 0 and flip: _rebuild(chunk_x(wx), chunk_z(wz) + ndz)
	if ndx != 0 and ndz != 0 and flip: _rebuild(chunk_x(wx) + ndx, chunk_z(wz) + ndz)   # diagonal corner

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

var _unload_t := 0.0   # accumulates between periodic unload sweeps

func _process(delta: float) -> void:
	if player == null:
		return
	_apply_budget = APPLIES_PER_FRAME   # reset each frame; chunks consume it as they finish (parent processes first)
	var pc := Vector2i(chunk_x(int(player.global_position.x)), chunk_z(int(player.global_position.z)))
	if pc != _center:
		_center = pc
		_refresh_queue(pc)
		_unload_far(pc)
	else:
		# Periodic re-sweep: a far chunk that was still building when the player crossed a boundary
		# is skipped (can't free mid-task); without this it would never be reclaimed if the player
		# then stops moving. Cheap (a dict scan) and only frees once builds have finished.
		_unload_t += delta
		if _unload_t >= 1.0:
			_unload_t = 0.0
			_unload_far(_center)
	var n := 0
	while n < LOADS_PER_FRAME and not _queue.is_empty():
		_load(_queue.pop_front())
		n += 1
	# Live flame flicker on every NEARBY torch — per-cell phase so a wall of torches doesn't
	# pulse in unison. The 2.6 base is the flicker midpoint, so lighting balance is unchanged.
	# Proximity gate (reclassified ~3x/s): far torches skip the flicker write AND get their
	# ember emitter + crackle voice paused, so per-frame cost is bounded by what's audible/visible,
	# not by every torch ever placed.
	if not torches.is_empty():
		_torch_clock += delta
		_torch_gate_t -= delta
		var reclassify := _torch_gate_t <= 0.0
		if reclassify:
			_torch_gate_t = 0.3
		var pp := player.global_position
		for cell in torches:
			var t = torches[cell]
			if not is_instance_valid(t):
				continue
			if reclassify:
				var near: bool = t.position.distance_squared_to(pp) < 1600.0   # ~40 m > light 9.5 + crackle 12
				t.set_meta("near", near)
				var emb: CPUParticles3D = t.get_meta("embers", null)
				if emb:
					emb.emitting = near
				var sp: AudioStreamPlayer3D = t.get_meta("crackle", null)
				if sp and sp.stream:
					sp.stream_paused = not near
			if not t.get_meta("near", false):
				continue
			var l: OmniLight3D = t.get_meta("light", null)
			# The > 1.6 check keeps the flicker's hands off a light the Hollows' gutter-dim tween
			# owns (it drags energy to 0.5 as a horror tell; the flicker must not overwrite it).
			if l and l.light_energy > 1.6:
				var ph := float((cell.x * 31 + cell.z * 17 + cell.y * 7) % 97)
				l.light_energy = 2.6 + 0.30 * sin(_torch_clock * 8.0 + ph) + 0.14 * sin(_torch_clock * 21.0 + ph * 1.7)

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

## Settings hook: change how many chunks stream around the player. Invalidating _center forces
## the next _process to re-queue the new rings and unload anything now out of range.
func set_render_radius(r: int) -> void:
	render_radius = clampi(r, 2, 8)
	_center = Vector2i(999999, 999999)

func _refresh_queue(center: Vector2i) -> void:
	# Queue the visible radius PLUS a preload buffer beyond it, nearest-first — so the rings just
	# past what you can see are already meshed before you move into them (kills horizon pop-in).
	var load_r := render_radius + PRELOAD
	var list: Array = []
	for dz in range(-load_r, load_r + 1):
		for dx in range(-load_r, load_r + 1):
			var c := Vector2i(center.x + dx, center.y + dz)
			if not chunks.has(c):
				list.append(c)
	list.sort_custom(func(a, b): return (a - center).length_squared() < (b - center).length_squared())
	_queue = list

func _unload_far(center: Vector2i) -> void:
	var keep := render_radius + PRELOAD + 1            # one ring of hysteresis past the preload buffer
	var remove: Array = []
	for c in chunks.keys():
		if absi(c.x - center.x) > keep or absi(c.y - center.y) > keep:
			remove.append(c)
	for c in remove:
		if is_instance_valid(chunks[c]):
			if chunks[c].is_building():
				continue                    # defer: freeing now would block the frame on its task
			chunks[c].queue_free()
		chunks.erase(c)

func _load(c: Vector2i, sync := false) -> void:
	if chunks.has(c):
		# A sync (spawn/respawn) request for a chunk that's still mid-async-build: force it to
		# finish and apply its collider NOW, so the ground exists this frame instead of a few
		# frames later (otherwise the player can briefly hover on a fresh-load respawn).
		if sync and is_instance_valid(chunks[c]) and not chunks[c].is_ready():
			chunks[c].build()
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

# --- torches (placeable light props; not voxels) ---------------------------------
var torches: Dictionary = {}   # Vector3i cell -> StaticBody3D (light + emissive head)
var _torch_clock := 0.0        # shared flicker clock (per-torch phase comes from the cell coords)
var _torch_gate_t := 0.0       # countdown to the next proximity reclassification (~3x/s)

func has_torch(cell: Vector3i) -> bool:
	return torches.has(cell)

## Place a torch light at a cell (returns false if one is already there). The torch is a
## small clickable body carrying a warm OmniLight3D, so caves/nights can actually be lit.
func place_torch(cell: Vector3i) -> bool:
	if torches.has(cell):
		return false
	var t := _make_torch(cell)
	t.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	add_child(t)
	torches[cell] = t
	# Start the crackle de-phased so a wall of torches doesn't chorus in sync.
	var sp := t.get_node_or_null("Crackle") as AudioStreamPlayer3D
	if sp and sp.stream:
		sp.play(randf() * minf(3.0, maxf(sp.stream.get_length() - 0.05, 0.0)))
	return true

func remove_torch(cell: Vector3i) -> bool:
	if not torches.has(cell):
		return false
	if is_instance_valid(torches[cell]):
		torches[cell].queue_free()
	torches.erase(cell)
	return true

# A non-colliding prop (so it never blocks movement); removal is by targeted cell, not a raycast.
# All torches are identical, so share one mesh + one emissive material across every placed torch
# (a lit base/cave can hold dozens) instead of allocating a fresh pair each time.
static var _torch_mesh: BoxMesh
static var _torch_mat: StandardMaterial3D
static func _shared_torch_mesh() -> BoxMesh:
	if _torch_mesh == null:
		_torch_mesh = BoxMesh.new()
		_torch_mesh.size = Vector3(0.13, 0.42, 0.13)
	return _torch_mesh
static func _shared_torch_mat() -> StandardMaterial3D:
	if _torch_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.5, 0.32, 0.14)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.62, 0.22)
		m.emission_energy_multiplier = 2.2
		_torch_mat = m
	return _torch_mat

# Shared ember particle mesh (one emissive box for every torch's drift emitter).
static var _ember_mesh: BoxMesh
static func _shared_ember_mesh() -> BoxMesh:
	if _ember_mesh == null:
		_ember_mesh = BoxMesh.new()
		_ember_mesh.size = Vector3(0.05, 0.05, 0.05)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.55, 0.12)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.5, 0.1)
		m.emission_energy_multiplier = 2.5
		_ember_mesh.material = m
	return _ember_mesh

func _make_torch(_cell: Vector3i) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _shared_torch_mesh()
	mi.material_override = _shared_torch_mat()
	root.add_child(mi)
	var light := OmniLight3D.new()
	light.light_energy = 2.6
	light.omni_range = 9.5
	light.light_color = Color(1.0, 0.68, 0.34)
	light.position = Vector3(0, 0.2, 0)
	light.shadow_enabled = false
	root.add_child(light)
	root.set_meta("light", light)   # the _process flicker looks the light up via this meta
	# Rising embers: a tiny live flame on the player's primary night/cave light source.
	var emb := CPUParticles3D.new()
	emb.mesh = _shared_ember_mesh()
	emb.amount = 3
	emb.lifetime = 0.9
	emb.direction = Vector3.UP
	emb.spread = 14.0
	emb.initial_velocity_min = 0.5
	emb.initial_velocity_max = 1.1
	emb.gravity = Vector3(0, 0.9, 0)   # embers rise
	emb.scale_amount_min = 0.4
	emb.scale_amount_max = 0.9
	emb.position = Vector3(0, 0.25, 0)
	root.add_child(emb)
	root.set_meta("embers", emb)    # proximity gate toggles far emitters off (CPU particles tick per-frame)
	# Positional fire crackle (quiet, ~12 m falloff) so a lit base is acoustically alive.
	var snd := AudioStreamPlayer3D.new()
	snd.name = "Crackle"
	var crackle_path := "res://assets/audio/sfx/blocks/torch_crackle.wav"
	if ResourceLoader.exists(crackle_path):
		var st = load(crackle_path)
		if st is AudioStreamMP3:
			st.loop = true
		elif st is AudioStreamWAV:
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			# A WAV imported without looping has loop_end = 0 — enabling LOOP_FORWARD against a
			# zero-length region renders silence. Set the region to the full sample explicitly.
			var bps: int = 2 if st.format == AudioStreamWAV.FORMAT_16_BITS else 1
			st.loop_begin = 0
			st.loop_end = st.data.size() / (bps * (2 if st.stereo else 1))
		snd.stream = st
	snd.volume_db = -16.0
	snd.unit_size = 2.5
	snd.max_distance = 12.0
	if AudioServer.get_bus_index("SFX") != -1:
		snd.bus = "SFX"
	root.add_child(snd)
	root.set_meta("crackle", snd)   # proximity gate pauses far voices (they'd still cost mixing time)
	return root

## Block edit: rebuild off the main thread so placing/breaking never freezes the frame
## (the heavy remesh + collider now run on a worker; the result applies a frame or two later).
func _rebuild(cx: int, cz: int) -> void:
	var c := Vector2i(cx, cz)
	if chunks.has(c) and is_instance_valid(chunks[c]):
		chunks[c].rebuild_async()

## Force every loaded chunk to remesh (used after bulk-applying a loaded save).
func rebuild_all() -> void:
	for c in chunks.keys():
		if is_instance_valid(chunks[c]):
			chunks[c].build()
