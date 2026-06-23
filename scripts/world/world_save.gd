class_name WorldSave

## JSON save/load to user://. Stores the player's block edits (overrides), the
## player's transform/vitals/inventory and the time of day. Terrain itself is not
## stored — it regenerates deterministically from the seed.

const PATH := "user://world_save.json"

static func has_save() -> bool:
	return FileAccess.file_exists(PATH)

static func _chests_data(world) -> Array:
	var out: Array = []
	for cell in world.chests.keys():
		var inv = world.chests[cell]
		if _inv_empty(inv):
			continue                                # don't persist empty/ghost chests (they bloat the save)
		out.append([cell.x, cell.y, cell.z, inv.to_data()])
	return out

static func _inv_empty(inv) -> bool:
	for s in inv.slots:
		if s.count > 0:
			return false
	return true

## Rebuilds the chests dictionary (Vector3i -> Inventory) from saved data.
static func chests_from(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for e in data.get("chests", []):
		var inv := Inventory.new()
		if e.size() >= 4 and e[3] is Array:
			inv.from_data(e[3])
		out[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = inv
	return out

## Torches are placeable light props (not voxels), kept in chunk_manager.torches — persist
## just their cells so they survive a save/load (otherwise the placed item is silently lost).
static func _torches_data(world) -> Array:
	var out: Array = []
	for cell in world.torches.keys():
		out.append([cell.x, cell.y, cell.z])
	return out

static func torches_from(data: Dictionary) -> Array:
	var out: Array = []
	for e in data.get("torches", []):
		if e.size() >= 3:
			out.append(Vector3i(int(e[0]), int(e[1]), int(e[2])))
	return out

static func _tool_names(player) -> Array:
	var names: Array = []
	for w in player.owned_tools:
		names.append(String(w.get("name", "")))
	return names

# --- world-memory collections (Hauntfields graves, Hollows pressure, Chronicle monoliths) ---
static func _graves_data(world) -> Array:
	var out: Array = []
	for cell in world.graves.keys():
		out.append([cell.x, cell.y, cell.z, int(world.graves[cell])])
	return out

static func graves_from(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for e in data.get("graves", []):
		if e.size() >= 4:
			out[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = int(e[3])
	return out

static func hollows_from(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var raw = data.get("hollows", {})
	if raw is Dictionary:
		for k in raw.keys():
			out[String(k)] = int(raw[k])
	return out

static func hollow_calmed_from(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var raw = data.get("hollow_calmed", {})
	if raw is Dictionary:
		for k in raw.keys():
			out[String(k)] = true
	return out

static func _monoliths_data(world) -> Array:
	var out: Array = []
	for cell in world.monoliths.keys():
		out.append([cell.x, cell.y, cell.z, world.monoliths[cell]])
	return out

static func monoliths_from(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for e in data.get("monoliths", []):
		if e.size() >= 4 and e[3] is Array:
			var lines: Array = []
			for s in e[3]:
				lines.append(String(s))
			out[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = lines
	return out

static func save(world, player, day_night, weather = null) -> bool:
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
			"tools": _tool_names(player),
			"armor_tier": player.armor_tier,
			"armor_name": player.armor_name,
		},
		"inventory": player.inventory.to_data(),
		"chests": _chests_data(world),
		"torches": _torches_data(world),
		"weather": weather.save_state() if weather else {},
		"crops": player.farm.to_data() if player.farm != null else [],
		"graves": _graves_data(world),
		"hollows": world.hollow_scores.duplicate(),
		"hollow_calmed": world.hollow_calmed.duplicate(),
		"monoliths": _monoliths_data(world),
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
