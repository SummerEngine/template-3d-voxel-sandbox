class_name Inventory
extends RefCounted

## A simple 9-slot stacking inventory (the hotbar). Each slot is {id, count}.
## Picked-up blocks stack into a matching slot first, then fill an empty one.

const SIZE := 9
const STACK_MAX := 99

var slots: Array = []

func _init() -> void:
	for i in range(SIZE):
		slots.append({"id": VoxelTypes.AIR, "count": 0})

## Adds n of an id; returns how many didn't fit (0 = all stored).
func add(id: int, n: int = 1) -> int:
	for s in slots:
		if s.id == id and s.count > 0 and s.count < STACK_MAX:
			var take: int = mini(STACK_MAX - s.count, n)
			s.count += take
			n -= take
			if n <= 0:
				return 0
	for s in slots:
		if s.count == 0:
			var take: int = mini(STACK_MAX, n)
			s.id = id
			s.count = take
			n -= take
			if n <= 0:
				return 0
	return n

func id_of(idx: int) -> int:
	return slots[idx].id if idx >= 0 and idx < SIZE else VoxelTypes.AIR

func count_of(idx: int) -> int:
	return slots[idx].count if idx >= 0 and idx < SIZE else 0

## Removes one item from a slot; returns the id removed (AIR if the slot was empty).
func remove_one(idx: int) -> int:
	if idx < 0 or idx >= SIZE:
		return VoxelTypes.AIR
	var s = slots[idx]
	if s.count <= 0:
		return VoxelTypes.AIR
	var id: int = s.id
	s.count -= 1
	if s.count == 0:
		s.id = VoxelTypes.AIR
	return id

## Total count of an id across all slots.
func total(id: int) -> int:
	var t := 0
	for s in slots:
		if s.id == id:
			t += s.count
	return t

## Removes n of an id from anywhere; returns true if it had enough.
func consume(id: int, n: int) -> bool:
	if total(id) < n:
		return false
	for s in slots:
		if s.id == id and n > 0:
			var take: int = mini(s.count, n)
			s.count -= take
			n -= take
			if s.count == 0:
				s.id = VoxelTypes.AIR
	return true

func to_data() -> Array:
	var out: Array = []
	for s in slots:
		out.append([int(s.id), int(s.count)])
	return out

func from_data(data: Array) -> void:
	for i in range(mini(SIZE, data.size())):
		slots[i].id = int(data[i][0])
		slots[i].count = int(data[i][1])
