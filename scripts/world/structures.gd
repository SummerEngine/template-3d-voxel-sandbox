extends Node

## Scatters discoverable structures across the world as you explore — ruined towers, buried
## crypts (with a lurking guardian), and surface treasure caches, each holding a loot chest.
## Placement is DETERMINISTIC per grid cell (seeded by cell coords) and stamped via
## world.set_block, so it persists in the save as overrides; the loot lives in a real chest.
## A cell counts as "already placed" if its chest already exists (chests persist in the save),
## so structures are never duplicated across reloads.

const SPACING := 52           # world blocks between candidate grid cells
const RADIUS := 2             # grid cells around the player to consider each scan
const SPAWN_CHANCE := 26      # percent of cells that hold a structure
const MIN_FROM_ORIGIN := 40   # keep the spawn area clear of structures
const MAX_PLACED := 40        # session cap (bounds overrides + guardians)
const TICK := 1.0             # seconds between scans (also caps placement to 1/sec)
const GUARD_NEAR := 22.0      # spawn a crypt's guardian once the player is this close

var world                     # ChunkManager
var player                    # Player
var _t := 1.0
var _placed := 0
var _pending_guardians: Array = []   # Vector3 spots awaiting a guardian when the player nears
var _stamped: Dictionary = {}        # grid cells already handled this session — never re-stamp
                                     # (re-stamping a crypt re-added its guardian -> instant respawns)

func setup(w, p) -> void:
	world = w
	player = p

func _process(delta: float) -> void:
	if world == null or player == null or not is_instance_valid(player):
		return
	_check_guardians()
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	if _placed >= MAX_PLACED:
		return
	var pgx := floori(player.global_position.x / SPACING)
	var pgz := floori(player.global_position.z / SPACING)
	for gz in range(pgz - RADIUS, pgz + RADIUS + 1):
		for gx in range(pgx - RADIUS, pgx + RADIUS + 1):
			if _try_place(gx, gz):
				_placed += 1
				return                # one structure per scan — spreads the cost

## Deterministic cell -> structure. Returns true if it placed one this call.
func _try_place(gx: int, gz: int) -> bool:
	var gkey := Vector2i(gx, gz)
	if _stamped.has(gkey):
		return false                              # already handled this session — never re-stamp / re-guard
	_stamped[gkey] = true                         # evaluate each grid cell exactly once (outcome is deterministic)
	var h := _hash(gx, gz)
	if h % 100 >= SPAWN_CHANCE:
		return false
	var ax := gx * SPACING + int(h % 18) + 17     # jitter the anchor off the grid
	var az := gz * SPACING + int((h >> 8) % 18) + 17
	if absi(ax) < MIN_FROM_ORIGIN and absi(az) < MIN_FROM_ORIGIN:
		return false
	var sy: int = world.surface_height(ax, az)
	if sy <= world.SEA_LEVEL + 1:
		return false                              # not on water / beach
	var chest_cell := Vector3i(ax, sy + 1, az)
	# Already placed if the chest BLOCK exists here — its override persists in the save even after
	# the player loots the chest empty (an empty inventory is no longer written). Checking the dict
	# alone would re-stamp + re-fill loot for looted-but-unbroken chests (infinite-resource exploit).
	if world.get_block(chest_cell.x, chest_cell.y, chest_cell.z) == VoxelTypes.CHEST:
		return false
	var kind := _pick_kind(world.biome_at(ax, az), h)   # biome-biased so regions feel distinct
	match kind:
		0: _build_tower(ax, sy, az)
		1: _build_crypt(ax, sy, az)
		2: _build_obelisk(ax, sy, az)
		_: _build_cache(ax, sy, az)
	_fill_loot(chest_cell, kind)
	return true

## Bias which structure a cell gets by biome so regions feel like they "have their own" landmark,
## while staying a pure function of the cell hash (deterministic, no RNG, no save field).
func _pick_kind(biome: String, h: int) -> int:
	var r := int((h >> 16) % 4)
	match biome:
		"desert", "snow", "mountain":
			return 2 if r < 2 else 0                      # open/harsh land -> a standing landmark (obelisk/tower)
		"jungle", "forest":
			return 1 if r < 2 else (3 if r == 2 else 0)  # overgrown -> buried crypt favoured
		_:
			return r                                      # meadow / mixed: full variety

func _put(wx: int, wy: int, wz: int, t: int) -> void:
	if wy > 0 and wy < world.WORLD_H:
		world.set_block(wx, wy, wz, t)

## A hollow cobblestone tower with a broken top and a chest at its base.
func _build_tower(ax: int, sy: int, az: int) -> void:
	var top := sy + 6
	for y in range(sy + 1, top + 1):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if absi(dx) != 1 and absi(dz) != 1:
					continue                       # interior column stays hollow
				if y >= top - 1 and _hash(ax + dx + y * 7, az + dz) % 3 == 0:
					continue                       # crumbled upper courses
				_put(ax + dx, y, az + dz, VoxelTypes.COBBLESTONE)
	_put(ax, sy + 1, az, VoxelTypes.CHEST)

## A 5x5 stone-brick crypt (dug into the ground), roofed with an entry hole, chest + guardian.
func _build_crypt(ax: int, sy: int, az: int) -> void:   
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			_put(ax + dx, sy, az + dz, VoxelTypes.STONE_BRICKS)        # floor
			for y in range(sy + 1, sy + 4):
				if absi(dx) == 2 or absi(dz) == 2:
					_put(ax + dx, y, az + dz, VoxelTypes.STONE_BRICKS)  # walls
				else:
					_put(ax + dx, y, az + dz, VoxelTypes.AIR)          # hollow interior
			if not (dx == 0 and dz == 0):
				_put(ax + dx, sy + 4, az + dz, VoxelTypes.STONE_BRICKS)  # roof (hole at centre)
	_put(ax, sy + 1, az, VoxelTypes.CHEST)
	_pending_guardians.append(Vector3(float(ax) + 0.5, float(sy) + 1.2, float(az) + 0.5))

## A surface treasure cache: a small cobblestone ring around an exposed chest.
func _build_cache(ax: int, sy: int, az: int) -> void:
	_put(ax - 1, sy + 1, az, VoxelTypes.COBBLESTONE)
	_put(ax + 1, sy + 1, az, VoxelTypes.COBBLESTONE)
	_put(ax, sy + 1, az - 1, VoxelTypes.COBBLESTONE)
	_put(ax, sy + 1, az + 1, VoxelTypes.COBBLESTONE)
	_put(ax, sy + 1, az, VoxelTypes.CHEST)

## A tall tan SAND spire beside an exposed chest — the world's first non-grey, taller-than-a-tower
## landmark, so a region reads as "marked" from a distance. Chest sits at the canonical chest_cell.
func _build_obelisk(ax: int, sy: int, az: int) -> void:
	var cx := ax + 1
	for dz in range(0, 2):
		for dx in range(0, 2):
			_put(cx + dx, sy + 1, az + dz, VoxelTypes.SAND)   # 2x2 footing
	for y in range(sy + 2, sy + 8):
		_put(cx, y, az, VoxelTypes.SAND)
		_put(cx, y, az + 1, VoxelTypes.SAND)                  # 2-wide shaft
	for y in range(sy + 8, sy + 12):
		_put(cx, y, az, VoxelTypes.SAND)                      # narrow tip (~11 tall)
	_put(ax, sy + 1, az, VoxelTypes.CHEST)

## Stock the chest with tier-appropriate loot — crypts richest, caches modest.
func _fill_loot(chest_cell: Vector3i, kind: int) -> void:
	var inv = world.chest_at(chest_cell)
	var pool: Array
	match kind:
		1: pool = [[VoxelTypes.DIAMOND, 1, 3], [VoxelTypes.GOLD_INGOT, 2, 5],
				[VoxelTypes.IRON_INGOT, 3, 6], [VoxelTypes.COOKED_MEAT, 2, 4]]
		0: pool = [[VoxelTypes.IRON_INGOT, 1, 4], [VoxelTypes.COAL, 2, 6],
				[VoxelTypes.APPLE, 1, 3], [VoxelTypes.PLANKS, 4, 10]]
		_: pool = [[VoxelTypes.COAL, 1, 4], [VoxelTypes.APPLE, 1, 2],
				[VoxelTypes.GOLD_INGOT, 1, 2], [VoxelTypes.STICK, 2, 5]]
	var seed_h := _hash(chest_cell.x, chest_cell.z)
	for i in range(pool.size()):
		if (seed_h >> i) % 4 != 0:                # ~75% of slots roll an item
			var e: Array = pool[i]
			var lo: int = e[1]
			var span: int = e[2] - e[1] + 1
			inv.add(int(e[0]), lo + int((seed_h >> (i + 3)) % span))
	# Crypts: a guaranteed standout + a rare jackpot + a far-distance richer tier, OUTSIDE the slot
	# roll — so a looted crypt is a real payoff, not just a time-saver for self-craftable items.
	if kind == 1:
		inv.add(VoxelTypes.DIAMOND, 1)                                    # always at least one diamond
		if (seed_h >> 11) % 6 == 0:
			inv.add(VoxelTypes.DIAMOND, 4 + int((seed_h >> 17) % 5))      # ~1 in 6 crypts: a diamond jackpot
		if maxi(absi(chest_cell.x), absi(chest_cell.z)) > 600:
			inv.add(VoxelTypes.GOLD_INGOT, 4 + int((seed_h >> 21) % 6))   # far-flung crypts reward the journey

## Spawn a crypt guardian only once the player is close, so they don't accumulate far away.
func _check_guardians() -> void:
	for i in range(_pending_guardians.size() - 1, -1, -1):
		var spot: Vector3 = _pending_guardians[i]
		if player.global_position.distance_to(spot) < GUARD_NEAR:
			_pending_guardians.remove_at(i)
			var z = preload("res://scripts/entities/hostile_mob.gd").new()
			z.player = player
			z.world = world
			z.health = 16                         # tougher than a basic night zombie
			z.position = spot                       # no day_night ref -> it never burns in the crypt
			get_parent().add_child(z)

func _hash(x: int, z: int) -> int:
	var n := (x * 73856093) ^ (z * 19349663) ^ 0x57A7C
	n = (n ^ (n >> 13)) * 1274126177
	return absi(n)
