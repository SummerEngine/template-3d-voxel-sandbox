extends CanvasLayer

## Tracks progression goals ("advancements") by listening to the player's gameplay
## signals, fires a toast when one is earned, and grants some exotic weapons as rewards.
## Press J to toggle a read-only panel listing every goal with its done/locked state.

var player
var _stats := {"mobs": 0, "nights": 0}
var _harvested := {}     # block id -> true (blocks actually harvested)
var _crafted := {}       # item id  -> true (items crafted/smelted)
var _done := {}          # advancement id -> true
var _rows := {}          # advancement id -> Label
var _panel: Control
var open := false

# id, title, desc, and optional reward = an exotic weapon name unlocked on completion.
const ADV := [
	{"id": "wood",        "title": "Getting Wood",   "desc": "Harvest a block of wood."},
	{"id": "stone_pick",  "title": "Stone Age",      "desc": "Craft a Stone Pickaxe."},
	{"id": "smelt_iron",  "title": "Hot Topic",      "desc": "Smelt an Iron Ingot."},
	{"id": "iron_pick",   "title": "Iron Will",      "desc": "Craft an Iron Pickaxe.",   "reward": "Broadsword"},
	{"id": "diamond",     "title": "Diamonds!",      "desc": "Mine a diamond.",          "reward": "Bardiche"},
	{"id": "geared",      "title": "Fully Geared",   "desc": "Get a Diamond Pickaxe and Diamond Armor.", "reward": "Heavy Maul"},
	{"id": "night1",      "title": "Night Survivor", "desc": "Survive your first night.", "reward": "Spiked Mace"},
	{"id": "veteran",     "title": "Veteran",        "desc": "Survive three nights.",     "reward": "Sledgehammer"},
	{"id": "hunter",      "title": "Monster Hunter", "desc": "Defeat 10 hostile mobs.",   "reward": "War Axe"},
	{"id": "armed",       "title": "Armed",          "desc": "Craft an Iron Sword."},
]

func setup(p) -> void:
	player = p
	if player == null:
		return
	player.block_harvested.connect(_on_harvest)
	player.item_crafted.connect(_on_craft)
	player.mob_killed.connect(_on_mob_killed)
	player.night_survived.connect(_on_night)
	_build_panel()
	_check_all()

func _on_harvest(id: int) -> void:
	_harvested[id] = true
	_check_all()

func _on_craft(id: int) -> void:
	if id >= 0:
		_crafted[id] = true
	_check_all()

func _on_mob_killed() -> void:
	_stats.mobs += 1
	_check_all()

func _on_night() -> void:
	_stats.nights += 1
	_check_all()

## Has the condition for advancement `id` been met?
func _met(id: String) -> bool:
	match id:
		"wood":       return _harvested.has(VoxelTypes.WOOD)
		"stone_pick": return player.owns_tool("Stone Pickaxe")
		"smelt_iron": return _crafted.has(VoxelTypes.IRON_INGOT)
		"iron_pick":  return player.owns_tool("Iron Pickaxe")
		"diamond":    return _harvested.has(VoxelTypes.DIAMOND_ORE)
		"geared":     return player.owns_tool("Diamond Pickaxe") and int(player.armor_tier) >= 2
		"night1":     return _stats.nights >= 1
		"veteran":    return _stats.nights >= 3
		"hunter":     return _stats.mobs >= 10
		"armed":      return player.owns_tool("Iron Sword")
	return false

func _check_all() -> void:
	if player == null:
		return
	for a in ADV:
		if _done.has(a.id):
			continue
		if _met(a.id):
			_done[a.id] = true
			_grant(a)

func _grant(a: Dictionary) -> void:
	if player.hud and player.hud.has_method("show_toast"):
		player.hud.show_toast("Advancement: %s!" % a.title, Color(1.0, 0.88, 0.4))
	if a.has("reward") and player.has_method("unlock_tool"):
		player.unlock_tool(String(a.reward), false)   # add it, don't yank the held weapon
		if player.hud and player.hud.has_method("show_toast"):
			player.hud.show_toast("Reward unlocked: %s (Q/E to equip)" % a.reward, Color(0.9, 0.8, 1.0))
	_refresh_panel()

# --- panel ---
func _build_panel() -> void:
	layer = 7
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var frame := PanelContainer.new()
	frame.position = Vector2(40, 90)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	box.set_border_width_all(2)
	box.border_color = Color(0.5, 0.55, 0.62, 0.8)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(16)
	frame.add_theme_stylebox_override("panel", box)
	_panel.add_child(frame)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	frame.add_child(vb)

	var title := Label.new()
	title.text = "ADVANCEMENTS  (J to close)"
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)

	for a in ADV:
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 15)
		vb.add_child(row)
		_rows[a.id] = row
	_refresh_panel()
	_panel.visible = false

func _refresh_panel() -> void:
	for a in ADV:
		var row: Label = _rows.get(a.id)
		if row == null:
			continue
		var done: bool = _done.has(a.id)
		row.text = "%s  %s — %s" % ["[x]" if done else "[  ]", a.title, a.desc]
		row.modulate = Color(0.6, 1.0, 0.65) if done else Color(0.7, 0.72, 0.78)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J:
		# Don't open over another menu (crafting/pause free the mouse) or while paused.
		if get_tree().paused or (not open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED):
			return
		open = not open
		_refresh_panel()
		_panel.visible = open
		get_viewport().set_input_as_handled()
