extends CanvasLayer

## Toggled with C: a combined inventory + crafting screen. The top mirrors the player's
## materials; below it a category-grouped, scrollable recipe list. Recipes are data-driven
## and support MULTIPLE inputs (e.g. smelting = ore + coal) and a `kind`:
##   "item"  -> adds out_id x out_n to the inventory (default)
##   "tool"  -> unlocks/equips a tool on the player (out_name/out_color for display)
##   "armor" -> sets the player's armor tier
## Doesn't pause the game; it just frees the mouse so the buttons are clickable.

const CATS := ["Crafting", "Smelt", "Tools", "Armor"]
const ItemIcons := preload("res://scripts/ui/item_icons.gd")

# in: array of [id, count]. out via out_id (VoxelTypes) or explicit out_name/out_color.
const RECIPES := [
	{"cat": "Crafting", "in": [[VoxelTypes.WOOD, 1]],        "out_id": VoxelTypes.PLANKS, "out_n": 4},
	{"cat": "Crafting", "in": [[VoxelTypes.PLANKS, 2]],      "out_id": VoxelTypes.STICK,  "out_n": 4},
	{"cat": "Crafting", "in": [[VoxelTypes.SAND, 1]],        "out_id": VoxelTypes.GLASS,  "out_n": 1},
	{"cat": "Crafting", "in": [[VoxelTypes.COBBLESTONE, 1]], "out_id": VoxelTypes.STONE,  "out_n": 1},
	{"cat": "Crafting", "in": [[VoxelTypes.DIRT, 1]],        "out_id": VoxelTypes.GRASS,  "out_n": 1},
	{"cat": "Crafting", "in": [[VoxelTypes.PLANKS, 4]],      "out_id": VoxelTypes.CRAFTING_TABLE, "out_n": 1},
	{"cat": "Crafting", "in": [[VoxelTypes.COBBLESTONE, 8]], "out_id": VoxelTypes.FURNACE, "out_n": 1},
	{"cat": "Crafting", "in": [[VoxelTypes.PLANKS, 8]],      "out_id": VoxelTypes.CHEST,   "out_n": 1},
	{"cat": "Crafting", "in": [[VoxelTypes.STONE, 4]],       "out_id": VoxelTypes.STONE_BRICKS,   "out_n": 4},
	{"cat": "Crafting", "in": [[VoxelTypes.COBBLESTONE, 4]], "out_id": VoxelTypes.BRICKS, "out_n": 4},
	{"cat": "Crafting", "in": [[VoxelTypes.STONE, 1]],       "out_id": VoxelTypes.POLISHED_STONE, "out_n": 1},
	{"cat": "Smelt",    "in": [[VoxelTypes.IRON_ORE, 1], [VoxelTypes.COAL, 1]], "out_id": VoxelTypes.IRON_INGOT, "out_n": 1},
	{"cat": "Smelt",    "in": [[VoxelTypes.GOLD_ORE, 1], [VoxelTypes.COAL, 1]], "out_id": VoxelTypes.GOLD_INGOT, "out_n": 1},
	{"cat": "Smelt",    "in": [[VoxelTypes.RAW_MEAT, 1], [VoxelTypes.COAL, 1]], "out_id": VoxelTypes.COOKED_MEAT, "out_n": 1},
	# Tools (kind "tool" -> unlock + equip on the player). out_id = representative colour.
	{"cat": "Tools", "kind": "tool", "tool": "Wooden Pickaxe",  "out_name": "Wooden Pickaxe",  "out_id": VoxelTypes.PLANKS,      "in": [[VoxelTypes.PLANKS, 3], [VoxelTypes.STICK, 2]]},
	{"cat": "Tools", "kind": "tool", "tool": "Stone Pickaxe",   "out_name": "Stone Pickaxe",   "out_id": VoxelTypes.COBBLESTONE, "in": [[VoxelTypes.COBBLESTONE, 3], [VoxelTypes.STICK, 2]]},
	{"cat": "Tools", "kind": "tool", "tool": "Iron Pickaxe",    "out_name": "Iron Pickaxe",    "out_id": VoxelTypes.IRON_INGOT,  "in": [[VoxelTypes.IRON_INGOT, 3], [VoxelTypes.STICK, 2]]},
	{"cat": "Tools", "kind": "tool", "tool": "Diamond Pickaxe", "out_name": "Diamond Pickaxe", "out_id": VoxelTypes.DIAMOND,     "in": [[VoxelTypes.DIAMOND, 3], [VoxelTypes.STICK, 2]]},
	{"cat": "Tools", "kind": "tool", "tool": "Gold Pickaxe",    "out_name": "Gold Pickaxe",    "out_id": VoxelTypes.GOLD_INGOT,  "in": [[VoxelTypes.GOLD_INGOT, 3], [VoxelTypes.STICK, 2]]},
	{"cat": "Tools", "kind": "tool", "tool": "Wooden Sword",    "out_name": "Wooden Sword",    "out_id": VoxelTypes.PLANKS,      "in": [[VoxelTypes.PLANKS, 2], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Stone Sword",     "out_name": "Stone Sword",     "out_id": VoxelTypes.COBBLESTONE, "in": [[VoxelTypes.COBBLESTONE, 2], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Iron Sword",      "out_name": "Iron Sword",      "out_id": VoxelTypes.IRON_INGOT,  "in": [[VoxelTypes.IRON_INGOT, 2], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Diamond Sword",   "out_name": "Diamond Sword",   "out_id": VoxelTypes.DIAMOND,     "in": [[VoxelTypes.DIAMOND, 2], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Gold Sword",      "out_name": "Gold Sword",      "out_id": VoxelTypes.GOLD_INGOT,  "in": [[VoxelTypes.GOLD_INGOT, 2], [VoxelTypes.STICK, 1]]},
	# Armor (kind "armor" -> set the player's damage-reduction tier).
	{"cat": "Armor", "kind": "armor", "armor": 1, "out_name": "Iron Armor",    "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 5]]},
	{"cat": "Armor", "kind": "armor", "armor": 2, "out_name": "Diamond Armor", "out_id": VoxelTypes.DIAMOND,     "in": [[VoxelTypes.DIAMOND, 5]]},
]

const SWATCH := 44

# Which recipe categories each interaction context shows. "hand" = the C key (basics
# you can make anywhere); a placed Crafting Table unlocks Tools/Armor and a Furnace
# unlocks Smelting, so those stations are actually needed.
const CONTEXT_CATS := {
	"hand":    ["Crafting"],
	"table":   ["Crafting", "Tools", "Armor"],
	"furnace": ["Smelt"],
}
const CONTEXT_TITLE := {
	"hand":    "INVENTORY  &  CRAFTING",
	"table":   "CRAFTING  TABLE",
	"furnace": "FURNACE",
}

var _context := "hand"
var _title: Label
var _cat_sections := {}     # cat -> {header, rows:[]}
var player
var _panel: Control
var _toast: Label
var _mat_slots: Array = []     # {panel, swatch, count} per inventory slot
var _recipe_rows: Array = []   # {btn, idx}
var _snd_click: AudioStreamPlayer
var _snd_open: AudioStreamPlayer
var open := false

func _ready() -> void:
	layer = 8
	add_to_group("crafting_ui")
	_build()
	_snd_click = _make_ui_snd("res://assets/audio/sfx/ui/click.mp3", -8.0)
	_snd_open  = _make_ui_snd("res://assets/audio/sfx/ui/open.mp3",  -10.0)
	_panel.visible = false

func _make_ui_snd(path: String, vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.volume_db = vol_db
	if AudioServer.get_bus_index("SFX") != -1:
		p.bus = "SFX"
	add_child(p)
	return p

func _play(p: AudioStreamPlayer) -> void:
	if p and p.stream:
		p.pitch_scale = randf_range(0.97, 1.03)
		p.play()

# --- recipe display helpers (outputs may be items OR tools/armor) ---
func _out_name(r: Dictionary) -> String:
	return String(r.get("out_name", VoxelTypes.name_of(int(r.get("out_id", 0)))))

func _out_color(r: Dictionary) -> Color:
	return r.get("out_color", VoxelTypes.color_of(int(r.get("out_id", 0))))

func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow clicks so they don't reach the game
	_panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)

	var frame := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.10, 0.11, 0.14, 0.97)
	box.set_border_width_all(3)
	box.border_color = Color(0.55, 0.58, 0.66, 0.9)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(22)
	frame.add_theme_stylebox_override("panel", box)
	center.add_child(frame)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	frame.add_child(vb)

	_title = Label.new()
	_title.text = "INVENTORY  &  CRAFTING"
	_title.add_theme_font_size_override("font_size", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)

	vb.add_child(_subheading("Materials"))
	var grid_center := HBoxContainer.new()
	grid_center.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(grid_center)
	var grid := GridContainer.new()
	grid.columns = Inventory.HOTBAR
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid_center.add_child(grid)
	for i in range(Inventory.SIZE):
		var cell := _make_swatch(SWATCH)
		grid.add_child(cell.panel)
		_mat_slots.append({"panel": cell.panel, "swatch": cell.swatch, "count": cell.count})

	vb.add_child(_separator())

	# Scrollable recipe list, grouped by category.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for cat in CATS:
		var rows: Array = []
		for i in range(RECIPES.size()):
			if String(RECIPES[i].cat) == cat:
				rows.append(i)
		if rows.is_empty():
			continue
		var header := _subheading(cat)
		list.add_child(header)
		var row_nodes: Array = []
		for idx in rows:
			var rn := _build_recipe_row(idx)
			list.add_child(rn)
			row_nodes.append(rn)
		_cat_sections[cat] = {"header": header, "rows": row_nodes}

	var hint := Label.new()
	hint.text = "Press C to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(hint)

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate = Color(1, 1, 0.8)
	vb.add_child(_toast)

func _subheading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.modulate = Color(0.75, 0.82, 0.95)
	return l

func _separator() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 8)
	return s

## A square slot: a bordered panel holding a colour swatch and a corner count label.
func _make_swatch(size: int) -> Dictionary:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(size, size)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.4)
	st.set_border_width_all(2)
	st.border_color = Color(0.6, 0.6, 0.65, 0.6)
	panel.add_theme_stylebox_override("panel", st)
	var swatch := ColorRect.new()
	swatch.size = Vector2(size - 14, size - 14)
	swatch.position = Vector2(7, 7)
	swatch.color = Color(0, 0, 0, 0)
	swatch.mouse_filter = Control.MOUSE_FILTER_PASS   # let hover reach the panel for tooltips
	panel.add_child(swatch)
	var icon := TextureRect.new()
	icon.size = Vector2(size - 14, size - 14)
	icon.position = Vector2(7, 7)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(icon)
	var count := Label.new()
	count.add_theme_font_size_override("font_size", 13)
	count.position = Vector2(size - 20, size - 20)
	count.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(count)
	return {"panel": panel, "swatch": swatch, "icon": icon, "count": count}

func _build_recipe_row(idx: int) -> Control:
	var r: Dictionary = RECIPES[idx]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	# Input swatches with "+" between them.
	var inputs: Array = r.in
	for j in range(inputs.size()):
		if j > 0:
			var plus := Label.new()
			plus.text = "+"
			plus.add_theme_font_size_override("font_size", 20)
			row.add_child(plus)
		var ing: Array = inputs[j]
		var cell := _make_swatch(SWATCH)
		var ing_tex: Texture2D = ItemIcons.icon(int(ing[0]))
		cell.icon.texture = ing_tex
		cell.swatch.color = Color(0, 0, 0, 0) if ing_tex != null else VoxelTypes.color_of(int(ing[0]))
		cell.count.text = str(int(ing[1]))
		cell.panel.tooltip_text = "%d %s" % [int(ing[1]), VoxelTypes.name_of(int(ing[0]))]
		row.add_child(cell.panel)

	var arrow := Label.new()
	arrow.text = "→"
	arrow.add_theme_font_size_override("font_size", 22)
	row.add_child(arrow)

	var out_cell := _make_swatch(SWATCH)
	var out_tex: Texture2D = ItemIcons.icon(int(r.get("out_id", 0)))
	out_cell.icon.texture = out_tex
	out_cell.swatch.color = Color(0, 0, 0, 0) if out_tex != null else _out_color(r)
	out_cell.count.text = str(int(r.get("out_n", 1)))
	out_cell.panel.tooltip_text = "%d %s" % [int(r.get("out_n", 1)), _out_name(r)]
	row.add_child(out_cell.panel)

	var name_lbl := Label.new()
	name_lbl.text = _out_name(r)
	name_lbl.custom_minimum_size = Vector2(130, 0)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_lbl)

	var btn := Button.new()
	btn.text = "Craft"
	btn.custom_minimum_size = Vector2(100, SWATCH)
	btn.pressed.connect(_craft.bind(idx))
	row.add_child(btn)

	_recipe_rows.append({"btn": btn, "idx": idx})
	return row

## True if the inventory holds every input of a recipe.
func _can_afford(r: Dictionary) -> bool:
	if player == null:
		return false
	for ing in r.in:
		if player.inventory.total(int(ing[0])) < int(ing[1]):
			return false
	return true

func _inputs_label(r: Dictionary) -> String:
	var parts: Array = []
	for ing in r.in:
		parts.append("%d %s" % [int(ing[1]), VoxelTypes.name_of(int(ing[0]))])
	return " + ".join(parts)

## Refresh the materials grid and grey out recipes you can't currently afford.
func _refresh() -> void:
	if player == null:
		return
	for i in range(_mat_slots.size()):
		var s = player.inventory.slots[i]
		var ui = _mat_slots[i]
		if s.count > 0:
			var tex: Texture2D = ItemIcons.icon(s.id)
			ui.icon.texture = tex
			ui.swatch.color = Color(0, 0, 0, 0) if tex != null else VoxelTypes.color_of(s.id)
			ui.count.text = str(s.count)
			ui.panel.tooltip_text = "%s  ×%d" % [VoxelTypes.name_of(s.id), s.count]
		else:
			ui.icon.texture = null
			ui.swatch.color = Color(0, 0, 0, 0)
			ui.count.text = ""
			ui.panel.tooltip_text = "Empty"
	for rr in _recipe_rows:
		var r: Dictionary = RECIPES[rr.idx]
		var kind := String(r.get("kind", "item"))
		var owned := false
		if kind == "tool":
			owned = player.has_method("owns_tool") and player.owns_tool(String(r.get("tool", "")))
		elif kind == "armor":
			owned = int(player.armor_tier) >= int(r.get("armor", 0))
		var afford: bool = _can_afford(r)
		rr.btn.disabled = owned or not afford
		rr.btn.text = "Owned" if owned else "Craft"
		rr.btn.modulate = Color(1, 1, 1, 1) if (afford and not owned) else Color(1, 1, 1, 0.5)
		rr.btn.tooltip_text = "%s → %d %s" % [_inputs_label(r), int(r.get("out_n", 1)), _out_name(r)]

func _craft(idx: int) -> void:
	if player == null:
		return
	var r: Dictionary = RECIPES[idx]
	if not _can_afford(r):
		_toast.text = "Need %s" % _inputs_label(r)
		_refresh()
		return
	for ing in r.in:
		player.inventory.consume(int(ing[0]), int(ing[1]))
	match String(r.get("kind", "item")):
		"tool":
			if player.has_method("unlock_tool"):
				player.unlock_tool(String(r.get("tool", "")))
			_toast.text = "Crafted %s" % _out_name(r)
		"armor":
			if player.has_method("set_armor_tier"):
				player.set_armor_tier(int(r.get("armor", 0)), _out_name(r))
			_toast.text = "Equipped %s" % _out_name(r)
		_:
			player.give_or_drop(int(r.out_id), int(r.get("out_n", 1)))
			_toast.text = "Crafted %d %s" % [int(r.get("out_n", 1)), _out_name(r)]
			if player.has_signal("item_crafted"):
				player.emit_signal("item_crafted", int(r.out_id))
	_play(_snd_click)
	if player.has_method("on_inventory_changed"):
		player.on_inventory_changed()
	if player.has_method("play_craft_sound"):
		player.play_craft_sound()
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	# Ignore C while the game is paused so crafting can't open over the pause menu.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		if not get_tree().paused:
			toggle()
			get_viewport().set_input_as_handled()

func toggle() -> void:
	if open:
		close()
		return
	var c = get_tree().get_first_node_in_group("chest_ui")
	if c and c.has_method("is_open") and c.is_open():
		return                                  # don't open over an open chest
	open_for("hand")

## Open the screen in a context: "hand" (C key — basics anywhere), "table" (Crafting
## Table, adds Tools/Armor) or "furnace" (adds Smelt). Stations call this on interact.
func open_for(ctx: String) -> void:
	_context = ctx
	open = true
	_panel.visible = true
	_play(_snd_open)
	_toast.text = ""
	_set_title()
	_apply_context()
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _set_title() -> void:
	if _title:
		_title.text = String(CONTEXT_TITLE.get(_context, "INVENTORY  &  CRAFTING"))

## Show only the recipe categories the current context allows.
func _apply_context() -> void:
	var allowed: Array = CONTEXT_CATS.get(_context, ["Crafting"])
	for cat in _cat_sections:
		var vis: bool = cat in allowed
		_cat_sections[cat].header.visible = vis
		for r in _cat_sections[cat].rows:
			r.visible = vis

## Called by the pause menu / death so the overlays never stack.
func close() -> void:
	if not open:
		return
	open = false
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
