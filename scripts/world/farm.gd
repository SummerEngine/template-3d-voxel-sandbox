class_name FarmManager
extends Node3D

## Owns the world's growing crops: planting on farmland, harvesting ripe crops, and removing
## crops whose farmland is destroyed. Each Crop self-ticks its own growth/animation; this just
## tracks them by their world cell (the air cell directly above the farmland) and persists them.

const CropScene := preload("res://scripts/world/crop.gd")

var world                                  # ChunkManager
var player                                 # Player
var _crops: Dictionary = {}                # Vector3i (crop cell) -> Crop node

func setup(w, p) -> void:
	world = w
	player = p

func has_crop(cell: Vector3i) -> bool:
	return _crops.has(cell) and is_instance_valid(_crops[cell])

func is_mature(cell: Vector3i) -> bool:
	return has_crop(cell) and _crops[cell].is_mature()

## Plant a crop in `cell` (the air cell above farmland). The caller verifies the cell is empty
## and farmland sits below. `stage`/`grow_t` are only non-default when restoring a save.
func plant(cell: Vector3i, stage := 0, grow_t := 0.0) -> bool:
	if has_crop(cell):
		return false
	var c := CropScene.new()
	c.stage = clampi(stage, 0, CropScene.STAGES - 1)
	c.grow_t = grow_t
	add_child(c)
	c.global_position = Vector3(cell) + Vector3(0.5, 0.0, 0.5)
	_crops[cell] = c
	return true

func _remove(cell: Vector3i) -> void:
	if _crops.has(cell):
		if is_instance_valid(_crops[cell]):
			_crops[cell].queue_free()
		_crops.erase(cell)

## A block was removed at `cell`: drop any crop in that cell, and any crop whose supporting
## farmland (the block directly below it) was just destroyed.
func on_block_removed(cell: Vector3i) -> void:
	_remove(cell)
	_remove(cell + Vector3i(0, 1, 0))

## Harvest the ripe crop at `cell`: remove it and return [wheat_count, seed_count]. Returns
## [0, 0] if there's no mature crop there.
func harvest(cell: Vector3i) -> Array:
	if not is_mature(cell):
		return [0, 0]
	_remove(cell)
	return [2, 1]               # 2 wheat (toward bread) + 1 seed back (keeps the plot going)

func to_data() -> Array:
	var out: Array = []
	for cell in _crops.keys():
		var c = _crops[cell]
		if is_instance_valid(c):
			out.append([cell.x, cell.y, cell.z, c.stage, c.grow_t])
	return out

func load_data(arr) -> void:
	for e in arr:
		if e is Array and e.size() >= 5:
			plant(Vector3i(int(e[0]), int(e[1]), int(e[2])), int(e[3]), float(e[4]))
