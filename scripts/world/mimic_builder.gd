extends Node

## Feature #7 — Doppelganger Tracks.
## Something builds like you. It profiles HOW you build (which block you favour, how much you've
## raised) and, in far loaded-but-unseen ground, stamps crude builds in your style — scraps at
## first, then a furnished hut with a chest stocked like your pack. A faint, far block-placing
## sound is the only herald. No monster ever appears; the payload is pure implication.
##
## Ships T1 (scraps) + T2 (profiled hut + chest). T3 (a near-replica of one of YOUR real builds)
## is left gated behind ENABLE_REPLICA per the design's "playtest first" note.
##
## Reuses: player.block_placed_at to profile, set_block + chest_at to stamp (overrides/chests
## persist for free), is_chunk_ready + camera frustum so it only ever acts where you can't see.

const ENABLE_REPLICA := false  # T3 — left off until playtested
const STAMP_CD := 120.0        # min seconds between artifacts
const MIN_PLACED := 8          # don't build "like you" until you've shown a style
const MAX_ARTIFACTS := 6
const DISCOVER_DIST := 7.0

var world: ChunkManager
var player: Player
var _counts := {}              # block id -> times placed
var _total := 0
var _cd := 45.0
var _artifacts: Array = []     # [{pos: Vector3, seen: bool}]
var _discovered := 0
var _rng := RandomNumberGenerator.new()
var _hint: AudioStreamPlayer

func setup(w, p) -> void:
	world = w
	player = p
	if player and player.has_signal("block_placed_at"):
		player.block_placed_at.connect(_on_placed)

func _ready() -> void:
	_rng.randomize()
	_hint = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/sfx/ui/click.mp3"):
		_hint.stream = load("res://assets/audio/sfx/ui/click.mp3")
	_hint.volume_db = -28.0                       # a barely-there knock from far off
	_hint.pitch_scale = 0.7
	add_child(_hint)

func _on_placed(_cell: Vector3i, id: int) -> void:
	if id >= VoxelTypes.GRASS and id <= VoxelTypes.MAX_BLOCK:
		_counts[id] = int(_counts.get(id, 0)) + 1
		_total += 1

func _favorite() -> int:
	var best := VoxelTypes.PLANKS
	var bestn := -1
	for id in _counts.keys():
		var n: int = int(_counts[id])
		if n > bestn and id != VoxelTypes.MONOLITH:
			bestn = n
			best = id
	return best

func _process(delta: float) -> void:
	if player == null or world == null:
		return
	# Discovery: walking near an artifact you've never seen ups the tier of the next one.
	for a in _artifacts:
		if not a.seen and player.global_position.distance_squared_to(a.pos) < DISCOVER_DIST * DISCOVER_DIST:
			a.seen = true
			_discovered += 1
	if _cd > 0.0:
		_cd -= delta
		return
	if _total < MIN_PLACED or _artifacts.size() >= MAX_ARTIFACTS:
		_cd = 30.0
		return
	if _try_stamp():
		_cd = STAMP_CD
	else:
		_cd = 25.0

func _try_stamp() -> bool:
	var r: int = 4
	if "render_radius" in world:
		r = int(world.render_radius)
	var reach := float(r) * 16.0 * 0.78
	for _i in range(8):
		var ang := _rng.randf_range(0.0, TAU)
		var dist := reach + _rng.randf_range(-6.0, 10.0)
		var wx := int(player.global_position.x + cos(ang) * dist)
		var wz := int(player.global_position.z + sin(ang) * dist)
		if not world.is_chunk_ready(wx, wz):
			continue                              # only stamp in generated, collidable ground
		var sy := world.surface_height(wx, wz)
		if sy <= world.SEA_LEVEL:
			continue                              # not in the sea
		var top := Vector3(float(wx) + 0.5, float(sy) + 1.5, float(wz) + 0.5)
		var cam = player.camera if player.camera else null
		if cam and is_instance_valid(cam) and cam.is_position_in_frustum(top):
			continue                              # never while you could be looking
		if _tier() >= 2:
			_stamp_hut(wx, sy, wz)
		else:
			_stamp_scraps(wx, sy, wz)
		_artifacts.append({"pos": top, "seen": false})
		if _hint and _hint.stream:
			_hint.play()                          # a faint knock from somewhere out there
		return true
	return false

func _tier() -> int:
	return 2 if _discovered >= 1 else 1

func _stamp_scraps(wx: int, sy: int, wz: int) -> void:
	var b := _favorite()
	world.set_block(wx, sy + 1, wz, b)
	world.set_block(wx + 1, sy + 1, wz, b)
	world.set_block(wx + 1, sy + 2, wz, b)
	world.set_block(wx, sy + 1, wz + 1, b)

func _stamp_hut(wx: int, sy: int, wz: int) -> void:
	var b := _favorite()
	var x0 := wx - 2
	var z0 := wz - 2
	# Precompute each column's surface ONCE (25 calls) and pass it to set_block so it doesn't
	# recompute terrain noise per of the ~88 block writes (one-shot off-screen spike reduction).
	var surf := {}
	for ix in range(0, 5):
		for iz in range(0, 5):
			surf[Vector2i(x0 + ix, z0 + iz)] = world.surface_height(x0 + ix, z0 + iz)
	# Walls (5x5, 3 tall) with a one-cell doorway on the south side, your style of block.
	for yy in range(1, 4):
		for i in range(0, 5):
			world.set_block(x0 + i, sy + yy, z0, b, int(surf[Vector2i(x0 + i, z0)]))
			world.set_block(x0 + i, sy + yy, z0 + 4, b, int(surf[Vector2i(x0 + i, z0 + 4)]))
			world.set_block(x0, sy + yy, z0 + i, b, int(surf[Vector2i(x0, z0 + i)]))
			world.set_block(x0 + 4, sy + yy, z0 + i, b, int(surf[Vector2i(x0 + 4, z0 + i)]))
	world.set_block(x0 + 2, sy + 1, z0, VoxelTypes.AIR, int(surf[Vector2i(x0 + 2, z0)]))   # doorway
	world.set_block(x0 + 2, sy + 2, z0, VoxelTypes.AIR, int(surf[Vector2i(x0 + 2, z0)]))
	# Flat roof.
	for ix in range(0, 5):
		for iz in range(0, 5):
			world.set_block(x0 + ix, sy + 4, z0 + iz, b, int(surf[Vector2i(x0 + ix, z0 + iz)]))
	# A chest inside, stocked like your pack.
	var cc := Vector3i(x0 + 2, sy + 1, z0 + 2)
	world.set_block(cc.x, cc.y, cc.z, VoxelTypes.CHEST, int(surf[Vector2i(cc.x, cc.z)]))
	var inv = world.chest_at(cc)
	for entry in _top_carried(3):
		inv.add(int(entry[0]), mini(int(entry[1]), 4))

func _top_carried(n: int) -> Array:
	var agg := {}
	if player and player.inventory:
		for s in player.inventory.slots:
			if s.count > 0:
				agg[s.id] = int(agg.get(s.id, 0)) + int(s.count)
	var arr: Array = []
	for id in agg.keys():
		arr.append([id, agg[id]])
	arr.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	return arr.slice(0, n)
