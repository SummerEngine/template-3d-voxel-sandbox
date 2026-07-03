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
	{"cat": "Crafting", "in": [[VoxelTypes.PLANKS, 2], [VoxelTypes.STICK, 2]], "out_id": VoxelTypes.HOE,   "out_n": 1},
	{"cat": "Crafting", "in": [[VoxelTypes.WHEAT, 3]],       "out_id": VoxelTypes.BREAD,  "out_n": 1},
	{"cat": "Crafting", "in": [[VoxelTypes.POLISHED_STONE, 4], [VoxelTypes.DIAMOND, 1]], "out_id": VoxelTypes.MONOLITH, "out_n": 1},
	{"cat": "Crafting", "in": [[VoxelTypes.IRON_INGOT, 2], [VoxelTypes.DIAMOND, 1]],     "out_id": VoxelTypes.RESONATOR, "out_n": 1},
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
	{"cat": "Tools", "kind": "tool", "tool": "Reaper Scythe",   "out_name": "Reaper Scythe",   "out_id": VoxelTypes.IRON_INGOT,  "in": [[VoxelTypes.IRON_INGOT, 4], [VoxelTypes.STICK, 2]]},
	# Extra craftable weapons so the whole catalogue is obtainable (was registry-only). Tiered by class.
	{"cat": "Tools", "kind": "tool", "tool": "Chisel",         "out_name": "Chisel",         "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 1], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Heavy Chisel",   "out_name": "Heavy Chisel",   "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 2], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Sickle",         "out_name": "Sickle",         "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 2], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Short Dagger",   "out_name": "Short Dagger",   "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 1], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Rondel Dagger",  "out_name": "Rondel Dagger",  "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 2], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Karambit",       "out_name": "Karambit",       "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 2], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Baselard",       "out_name": "Baselard",       "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 2], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Kris",           "out_name": "Kris",           "out_id": VoxelTypes.GOLD_INGOT, "in": [[VoxelTypes.IRON_INGOT, 2], [VoxelTypes.GOLD_INGOT, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Round Stiletto", "out_name": "Round Stiletto", "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 2], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Shamshir",       "out_name": "Shamshir",       "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 2], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Messer",         "out_name": "Messer",         "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 2], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Scimitar",       "out_name": "Scimitar",       "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 3], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Cutlass",        "out_name": "Cutlass",        "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 3], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Falchion",       "out_name": "Falchion",       "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 3], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Broadaxe",       "out_name": "Broadaxe",       "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 3], [VoxelTypes.STICK, 2]]},
	{"cat": "Tools", "kind": "tool", "tool": "Greataxe",       "out_name": "Greataxe",       "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 6], [VoxelTypes.STICK, 2]]},
	{"cat": "Tools", "kind": "tool", "tool": "Wooden Mallet",  "out_name": "Wooden Mallet",  "out_id": VoxelTypes.PLANKS,     "in": [[VoxelTypes.PLANKS, 4], [VoxelTypes.STICK, 2]]},
	{"cat": "Tools", "kind": "tool", "tool": "Flanged Mace",   "out_name": "Flanged Mace",   "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 4], [VoxelTypes.STICK, 1]]},
	{"cat": "Tools", "kind": "tool", "tool": "Warhammer",      "out_name": "Warhammer",      "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 5], [VoxelTypes.STICK, 2]]},
	{"cat": "Tools", "kind": "tool", "tool": "Great Maul",     "out_name": "Great Maul",     "out_id": VoxelTypes.IRON_INGOT, "in": [[VoxelTypes.IRON_INGOT, 6], [VoxelTypes.STICK, 2]]},
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
	"hand":    "CRAFTING",
	"table":   "CRAFTING TABLE",
	"furnace": "FURNACE",
}

var _context := "hand"
var _title: Label
var _cat_sections := {}     # cat -> {header, rows:[]}
var player
var _panel: Control
var _toast: Label
var _taught_resonator := false   # teach the new right-click verbs once, on first craft
var _taught_monolith := false
var _mat_slots: Array = []     # {panel, swatch, count} per inventory slot
var _mat_empty: Label          # "gather materials" hint shown when you have nothing yet
var _gate_hint: Label          # context gate hint: tells hand-crafters that tools/armor need a Crafting Table
var _recipe_scroll: ScrollContainer   # recipe list scroll; its min height is capped to fit short windows
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

## Recipe-scroll height that keeps the Close button on-screen: full 380 on tall windows,
## shrinking (down to 200) on short ones (mirrors pause_menu.gd's viewport-fit approach).
func _recipe_scroll_cap() -> float:
	return clampf(get_viewport().get_visible_rect().size.y - 380.0, 200.0, 380.0)

## Re-fit the recipe scroll if the window is resized while the panel is open.
func _on_viewport_resized() -> void:
	if _recipe_scroll:
		_recipe_scroll.custom_minimum_size.y = _recipe_scroll_cap()

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
	frame.add_theme_stylebox_override("panel", UITheme.dialog_box())   # shared in-game dialog look
	center.add_child(frame)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	frame.add_child(vb)

	_title = Label.new()
	_title.text = "CRAFTING"
	_title.add_theme_font_size_override("font_size", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)

	vb.add_child(_subheading("Your Materials"))
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
		_mat_slots.append({"panel": cell.panel, "swatch": cell.swatch, "icon": cell.icon, "count": cell.count})

	_mat_empty = Label.new()
	_mat_empty.text = "Gather materials to start crafting."
	_mat_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mat_empty.modulate = Color(1, 1, 1, 0.5)
	vb.add_child(_mat_empty)

	vb.add_child(_separator())

	# Scrollable recipe list, grouped by category.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, _recipe_scroll_cap())   # capped so the Close button stays on-screen in short windows
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_recipe_scroll = scroll
	get_viewport().size_changed.connect(_on_viewport_resized)
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

	var close_btn := UITheme.make_button("Close", "normal", Vector2(140, 40))
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close)
	vb.add_child(close_btn)

	var hint := Label.new()
	hint.text = "Each row: ingredients  →  what you craft.   A red count = you're missing some.   Press C or Esc to close."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(hint)

	# Contextual gate hint (hand-crafting only): tells the player tools/armor need a Crafting Table.
	_gate_hint = Label.new()
	_gate_hint.add_theme_font_size_override("font_size", 13)
	_gate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gate_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gate_hint.modulate = Color(0.95, 0.82, 0.55, 0.85)   # soft amber
	vb.add_child(_gate_hint)

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
	count.add_theme_constant_override("outline_size", 3)   # legible over bright swatches/icons
	count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
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
	var in_cells: Array = []                  # tracked so _refresh can colour each by have/need
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
		in_cells.append({"count": cell.count, "panel": cell.panel, "id": int(ing[0]), "need": int(ing[1])})

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

	var btn := UITheme.make_button("Craft", "primary", Vector2(110, SWATCH))
	btn.pressed.connect(_craft.bind(idx))
	row.add_child(btn)

	_recipe_rows.append({"btn": btn, "idx": idx, "row": row, "inputs": in_cells})
	return row

## True if the inventory holds every input of a recipe.
func _can_afford(r: Dictionary) -> bool:
	if player == null or player.inventory == null:
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
	if player == null or player.inventory == null:
		return
	# Auto-dismiss a stale "Need X" message once the player has gathered the missing items
	# (the row turns green) — _refresh fires on every inventory change.
	if _toast and _toast.text.begins_with("Need "):
		_toast.text = ""
	var any_mat := false
	for i in range(_mat_slots.size()):
		var s = player.inventory.slots[i]
		var ui = _mat_slots[i]
		if s.count > 0:
			any_mat = true
			var tex: Texture2D = ItemIcons.icon(s.id)
			ui.icon.texture = tex
			ui.swatch.color = Color(0, 0, 0, 0) if tex != null else VoxelTypes.color_of(s.id)
			ui.count.text = str(s.count) if s.count > 1 else ""
			ui.panel.tooltip_text = "%s  ×%d" % [VoxelTypes.name_of(s.id), s.count]
		else:
			ui.icon.texture = null
			ui.swatch.color = Color(0, 0, 0, 0)
			ui.count.text = ""
			ui.panel.tooltip_text = "Empty"
	if _mat_empty:
		_mat_empty.visible = not any_mat
	for rr in _recipe_rows:
		var r: Dictionary = RECIPES[rr.idx]
		var kind := String(r.get("kind", "item"))
		var owned := false
		if kind == "tool":
			owned = player.has_method("owns_tool") and player.owns_tool(String(r.get("tool", "")))
		elif kind == "armor":
			owned = (int(player.armor_tier) if "armor_tier" in player else 0) >= int(r.get("armor", 0))
		var afford: bool = _can_afford(r)
		# Dim the WHOLE row when you can't afford it, so you can scan for "what can I make now"
		# at a glance. Owned recipes stay bright with a muted "Owned" button.
		var craftable: bool = afford and not owned
		rr.row.modulate = Color(1, 1, 1, 1) if (craftable or owned) else Color(1, 1, 1, 0.4)
		rr.btn.disabled = owned or not afford
		rr.btn.text = "Owned" if owned else "Craft"
		rr.btn.tooltip_text = "%s → %d %s" % [_inputs_label(r), int(r.get("out_n", 1)), _out_name(r)]
		# Colour each ingredient green (you have enough) or red (missing some) so it's obvious at a
		# glance what a recipe still needs, and spell it out in the tooltip.
		for inp in rr.get("inputs", []):
			var have: int = player.inventory.total(int(inp.id))
			inp.count.modulate = Color(0.6, 1.0, 0.6) if have >= int(inp.need) else Color(1.0, 0.5, 0.45)
			inp.panel.tooltip_text = "%s — have %d, need %d" % [VoxelTypes.name_of(int(inp.id)), have, int(inp.need)]

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
			player.give_or_drop(int(r.get("out_id", 0)), int(r.get("out_n", 1)))
			_toast.text = "Crafted %d %s" % [int(r.get("out_n", 1)), _out_name(r)]
			if player.has_signal("item_crafted"):
				player.emit_signal("item_crafted", int(r.get("out_id", 0)))
			# Teach the new right-click verbs once (center toast — the panel's own _toast is local).
			var oid := int(r.get("out_id", 0))
			if oid == VoxelTypes.RESONATOR and not _taught_resonator:
				_taught_resonator = true
				if player.hud and player.hud.has_method("show_toast"):
					player.hud.show_toast("Resonator ready — hold it and right-click to echo-sound ore through rock.", Color(0.55, 0.85, 0.95))
			elif oid == VoxelTypes.MONOLITH and not _taught_monolith:
				_taught_monolith = true
				if player.hud and player.hud.has_method("show_toast"):
					player.hud.show_toast("Monolith ready — place it, then right-click it to read its Annals.", Color(0.82, 0.86, 1.0))
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

func is_open() -> bool:
	return open

func toggle() -> void:
	if open:
		close()
		return
	var c = get_tree().get_first_node_in_group("chest_ui")
	if c and c.has_method("is_open") and c.is_open():
		return                                  # don't open over an open chest
	var an = get_tree().get_first_node_in_group("chronicle")
	if an and an.has_method("is_open") and an.is_open():
		return                                  # nor over the Monolith's Annals dialog
	open_for("hand")

## Open the screen in a context: "hand" (C key — basics anywhere), "table" (Crafting
## Table, adds Tools/Armor) or "furnace" (adds Smelt). Stations call this on interact.
func open_for(ctx: String) -> void:
	get_tree().call_group("chest_ui", "close")   # never stack with an open chest (symmetric with chest opening)
	_context = ctx
	open = true
	_panel.visible = true
	if _recipe_scroll:   # re-fit in case the window was resized while the panel was closed
		_recipe_scroll.custom_minimum_size.y = _recipe_scroll_cap()
	_play(_snd_open)
	_toast.text = ""
	_set_title()
	_apply_context()
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _set_title() -> void:
	if _title:
		_title.text = String(CONTEXT_TITLE.get(_context, "CRAFTING"))

## Show only the recipe categories the current context allows.
func _apply_context() -> void:
	var allowed: Array = CONTEXT_CATS.get(_context, ["Crafting"])
	for cat in _cat_sections:
		var vis: bool = cat in allowed
		_cat_sections[cat].header.visible = vis
		for r in _cat_sections[cat].rows:
			r.visible = vis
	# Hand-crafting only shows basics; nudge the player toward a Crafting Table for tools/armor.
	if _gate_hint:
		_gate_hint.text = "Tools & armor are crafted at a Crafting Table — craft one (4 Planks), place it, then right-click it." if _context == "hand" else ""
		_gate_hint.visible = _context == "hand"

## Called by the pause menu / death so the overlays never stack.
func close() -> void:
	if not open:
		return
	_play(_snd_click)              # dismiss feedback, symmetric with the open sound (chest UI does this)
	open = false
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
