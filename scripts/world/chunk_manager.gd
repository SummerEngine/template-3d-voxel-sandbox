class_name ChunkManager
extends Node3D

## Streams 16x16x256 chunks around the player and owns terrain generation.
## Terrain is a pure function of (x,z) noise + per-block edit overrides, so any
## world coordinate can be sampled even if its chunk isn't loaded (seamless culling).

const CHUNK_W := 16
const CHUNK_D := 16
const WORLD_H := 256
const BASE_HEIGHT := 48
const AMPLITUDE := 22
const LAVA_LEVEL := 2          # bottom layers are lava
const RENDER_RADIUS := 3       # chunks around the player (low-end friendly)
const LOADS_PER_FRAME := 1

var player: Node3D
var noise := FastNoiseLite.new()
var chunks: Dictionary = {}    # Vector2i -> Chunk node
var overrides: Dictionary = {} # Vector3i -> int (player edits)
var _queue: Array = []
var _center := Vector2i(999999, 999999)

func _ready() -> void:
	noise.seed = 1337
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.011

# --- terrain ---

func surface_height(wx: int, wz: int) -> int:
	var n := noise.get_noise_2d(float(wx), float(wz))   # ~ -1..1
	return BASE_HEIGHT + int(round(n * AMPLITUDE))

func block_from_surface(wy: int, s: int) -> int:
	if wy < 0 or wy >= WORLD_H:
		return VoxelTypes.AIR
	if wy > s:
		return VoxelTypes.AIR
	if wy <= LAVA_LEVEL:
		return VoxelTypes.LAVA
	if wy == s:
		return VoxelTypes.GRASS
	if wy >= s - 3:
		return VoxelTypes.DIRT
	return VoxelTypes.STONE

func get_block(wx: int, wy: int, wz: int) -> int:
	var key := Vector3i(wx, wy, wz)
	if overrides.has(key):
		return overrides[key]
	return block_from_surface(wy, surface_height(wx, wz))

func set_block(wx: int, wy: int, wz: int, t: int) -> void:
	if wy < 0 or wy >= WORLD_H:
		return
	var key := Vector3i(wx, wy, wz)
	if t == block_from_surface(wy, surface_height(wx, wz)):
		overrides.erase(key)
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
