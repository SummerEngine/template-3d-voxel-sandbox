extends Node

## Feature #2 — The Wrong Block.
## The world quietly edits itself OFF-CAMERA — a torch shifts one cell, a stone turns to
## cobble, a stump appears behind you — then reverts before you can prove it. One reversible
## edit at a time; it undoes itself the moment you look at it (>0.4s) or after ~90s. Frequency
## rides a hidden "unease" meter that climbs at night, underground, in storms and on blood moons.
##
## Every edit goes through set_block / the torch API, and setting a cell back to its natural
## value auto-erases the override — so the revert is seamless and save-safe for free.
## Gated by GameSettings.world_unease so it can ship bold and be toggled off.

const W_SANDSTORM := 3
const W_STORM := 2
const LOOK_REVERT := 0.4      # seconds of you looking at it before it snaps back
const MAX_AGE := 90.0         # auto-revert even if never seen
const MIN_RANGE := 8.0        # never act this close to the player
const MAX_RANGE := 16.0

var world: ChunkManager
var player: Player
var day_night
var weather

var _active := {}             # empty = nothing live
var _age := 0.0
var _look := 0.0
var _cd := 20.0
var _rng := RandomNumberGenerator.new()

func setup(w, p, dn, wx) -> void:
	world = w
	player = p
	day_night = dn
	weather = wx

func _ready() -> void:
	_rng.randomize()

func _process(delta: float) -> void:
	if player == null or world == null:
		return
	if not _active.is_empty():
		_tend_active(delta)
		return
	if not GameSettings.world_unease:
		return
	_cd -= delta
	if _cd > 0.0:
		return
	# Next attempt sooner when unease is high.
	var u := _unease()
	_cd = lerpf(58.0, 16.0, u)
	_try_oddity()

func _unease() -> float:
	var u := 0.1
	if day_night:
		if day_night.is_night():
			u += 0.4
		if day_night.blood_moon:
			u += 0.3
	if weather and (int(weather.weather) == W_SANDSTORM or int(weather.weather) == W_STORM):
		u += 0.2
	var px := int(player.global_position.x)
	var pz := int(player.global_position.z)
	if player.global_position.y < float(world.surface_height(px, pz)) - 5.0:
		u += 0.35                                  # the dark underground unsettles
	return clampf(u, 0.0, 1.0)

func _cam():
	if player.camera and is_instance_valid(player.camera):
		return player.camera
	return null

func _out_of_view(world_pos: Vector3) -> bool:
	var cam = _cam()
	if cam == null:
		return true
	return not cam.is_position_in_frustum(world_pos)

func _centre(cell: Vector3i) -> Vector3:
	return Vector3(cell) + Vector3(0.5, 0.5, 0.5)

# ----- pick an oddity -----
func _try_oddity() -> void:
	# Prefer moving a torch (highest-signal, lowest-grief) — EXCEPT deep underground, where torches are
	# load-bearing nav and shuffling them every ~16-40s reads as griefy; there, prefer swap/stump.
	var px := int(player.global_position.x)
	var pz := int(player.global_position.z)
	var deep := player.global_position.y < float(world.surface_height(px, pz)) - 5.0
	if not deep and _try_move_torch():
		return
	var r := _rng.randf()
	if r < 0.6:
		if _try_swap_block():
			return
		_try_stump()
	else:
		if _try_stump():
			return
		_try_swap_block()

func _try_move_torch() -> bool:
	if world.torches.is_empty():
		return false
	var cells: Array = world.torches.keys()
	cells.shuffle()
	for cell in cells:
		var p := _centre(cell)
		var d := player.global_position.distance_to(p)
		if d < MIN_RANGE or d > MAX_RANGE + 6.0:
			continue
		if not _out_of_view(p):
			continue
		# A free adjacent air cell to slide it into.
		var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
		dirs.shuffle()
		for dd in dirs:
			var nc: Vector3i = cell + dd
			if world.get_block(nc.x, nc.y, nc.z) != VoxelTypes.AIR:
				continue
			if world.has_torch(nc):
				continue
			if not _out_of_view(_centre(nc)):
				continue
			if world.remove_torch(cell) and world.place_torch(nc):
				_active = {"kind": "torch", "from": cell, "to": nc}
				_age = 0.0
				_look = 0.0
				return true
	return false

func _try_swap_block() -> bool:
	for _i in range(14):
		var ang := _rng.randf_range(0.0, TAU)
		var rad := _rng.randf_range(MIN_RANGE, MAX_RANGE)
		var wx := int(player.global_position.x + cos(ang) * rad)
		var wz := int(player.global_position.z + sin(ang) * rad)
		var wy := world.surface_height(wx, wz)
		var cell := Vector3i(wx, wy, wz)
		if world.overrides.has(cell):
			continue                               # only natural terrain — never the player's builds
		var id := world.get_block(wx, wy, wz)
		var swap := _sibling(id)
		if swap == id:
			continue
		if not _out_of_view(_centre(cell)):
			continue
		world.set_block(wx, wy, wz, swap)
		_active = {"kind": "swap", "cell": cell, "orig": id, "swapped": swap}
		_age = 0.0
		_look = 0.0
		return true
	return false

func _sibling(id: int) -> int:
	match id:
		VoxelTypes.STONE:       return VoxelTypes.COBBLESTONE
		VoxelTypes.COBBLESTONE: return VoxelTypes.STONE
		VoxelTypes.GRASS:       return VoxelTypes.DIRT
		VoxelTypes.STONE_BRICKS: return VoxelTypes.POLISHED_STONE
		_:                      return id

func _try_stump() -> bool:
	# A small wooden stump appears in your blind spot — most jarring directly behind you.
	var cam = _cam()
	var back := Vector3(0, 0, 1)
	if cam:
		back = cam.global_transform.basis.z       # +z is *behind* the camera
	back.y = 0.0
	if back.length() < 0.01:
		back = Vector3(0, 0, 1)
	back = back.normalized()
	for _i in range(8):
		var side := _rng.randf_range(-4.0, 4.0)
		var dist := _rng.randf_range(MIN_RANGE, MAX_RANGE)
		var base := player.global_position + back * dist + Vector3(-back.z, 0, back.x) * side
		var wx := int(base.x)
		var wz := int(base.z)
		var wy := world.surface_height(wx, wz) + 1
		var cell := Vector3i(wx, wy, wz)
		if world.get_block(wx, wy, wz) != VoxelTypes.AIR:
			continue
		if not VoxelTypes.is_solid(world.get_block(wx, wy - 1, wz)):
			continue
		if world.overrides.has(cell):
			continue
		if not _out_of_view(_centre(cell)):
			continue
		world.set_block(wx, wy, wz, VoxelTypes.WOOD)
		_active = {"kind": "stump", "cell": cell, "orig": VoxelTypes.AIR}
		_age = 0.0
		_look = 0.0
		return true
	return false

# ----- maintain / revert the live oddity -----
func _tend_active(delta: float) -> void:
	_age += delta
	var watched := _is_watched()
	if watched:
		_look += delta
	else:
		_look = 0.0
	if _look >= LOOK_REVERT or _age >= MAX_AGE:
		_revert()

func _is_watched() -> bool:
	var p: Vector3
	match _active.get("kind", ""):
		"torch": p = _centre(_active.to)
		_:       p = _centre(_active.cell)
	if player.global_position.distance_to(p) > 22.0:
		return false
	return not _out_of_view(p)

func _revert() -> void:
	match _active.get("kind", ""):
		"torch":
			if world.has_torch(_active.to):
				world.remove_torch(_active.to)
			if not world.has_torch(_active.from):
				world.place_torch(_active.from)
		"swap":
			var cs: Vector3i = _active.cell
			if world.get_block(cs.x, cs.y, cs.z) == int(_active.get("swapped", -1)):
				world.set_block(cs.x, cs.y, cs.z, int(_active.orig))   # only undo if it's still the swapped block
		"stump":
			var ct: Vector3i = _active.cell
			if world.get_block(ct.x, ct.y, ct.z) == VoxelTypes.WOOD:
				world.set_block(ct.x, ct.y, ct.z, int(_active.orig))   # only remove if our stump is still there
	_active = {}
	_cd = lerpf(40.0, 12.0, _unease())
