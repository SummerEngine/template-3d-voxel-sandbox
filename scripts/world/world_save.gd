class_name WorldSave

## JSON save/load to user://. Stores the player's block edits (overrides), the
## player's transform/vitals/inventory and the time of day. Terrain itself is not
## stored — it regenerates deterministically from the seed.

const PATH := "user://world_save.json"

static func has_save() -> bool:
	return FileAccess.file_exists(PATH)

static func save(world, player, day_night) -> bool:
	var edits: Array = []
	for k in world.overrides.keys():
		edits.append([k.x, k.y, k.z, world.overrides[k]])
	var data := {
		"version": 1,
		"time": day_night.time_of_day if day_night else 0.3,
		"overrides": edits,
		"player": {
			"x": player.global_position.x,
			"y": player.global_position.y,
			"z": player.global_position.z,
			"health": player.health,
			"hunger": player.hunger,
			"selected": player.selected,
		},
		"inventory": player.inventory.to_data(),
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true

static func load_data() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

## Rebuilds the overrides dictionary (Vector3i -> int) from saved data.
static func overrides_from(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for e in data.get("overrides", []):
		out[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = int(e[3])
	return out
