extends CanvasLayer

## In-game HUD: crosshair, mine-progress bar, health hearts, hunger, held-tool label,
## a 9-slot hotbar (block swatch + count, selected slot highlighted) and a controls
## hint. The player pushes state in via the set_*/update_hotbar methods.

const SLOT := 50
const SLOT_PAD := 6

var _cross: Label
var _mine_bg: ColorRect
var _mine_fill: ColorRect
var _hearts: Label
var _hunger: Label
var _tool: Label
var _block_name: Label
var _hint: Label
var _hotbar: HBoxContainer
var _slots: Array = []          # each: {panel, swatch, count}
var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _dmg_flash: ColorRect

func _ready() -> void:
	layer = 5
	_build_styles()
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _build_styles() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0, 0, 0, 0.35)
	_style_normal.set_border_width_all(2)
	_style_normal.border_color = Color(0.7, 0.7, 0.7, 0.5)
	_style_selected = StyleBoxFlat.new()
	_style_selected.bg_color = Color(0, 0, 0, 0.45)
	_style_selected.set_border_width_all(3)
	_style_selected.border_color = Color(1, 1, 1, 0.95)

func _build() -> void:
	# Full-screen red damage flash (behind the HUD widgets, over the 3D world).
	_dmg_flash = ColorRect.new()
	_dmg_flash.color = Color(0.85, 0.0, 0.0, 1.0)
	_dmg_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmg_flash.modulate = Color(1, 1, 1, 0.0)
	add_child(_dmg_flash)

	_cross = Label.new()
	_cross.text = "+"
	_cross.add_theme_font_size_override("font_size", 22)
	add_child(_cross)

	_mine_bg = ColorRect.new()
	_mine_bg.color = Color(0, 0, 0, 0.6)
	_mine_bg.size = Vector2(64, 7)
	_mine_bg.visible = false
	add_child(_mine_bg)
	_mine_fill = ColorRect.new()
	_mine_fill.color = Color(0.9, 0.9, 0.95, 0.95)
	_mine_fill.size = Vector2(0, 7)
	_mine_fill.visible = false
	add_child(_mine_fill)

	_hearts = Label.new()
	_hearts.add_theme_font_size_override("font_size", 24)
	_hearts.position = Vector2(16, 12)
	_hearts.modulate = Color(1.0, 0.27, 0.32)
	add_child(_hearts)

	_hunger = Label.new()
	_hunger.add_theme_font_size_override("font_size", 24)
	_hunger.position = Vector2(16, 44)
	_hunger.modulate = Color(0.95, 0.65, 0.25)
	add_child(_hunger)

	_tool = Label.new()
	_tool.position = Vector2(16, 78)
	_tool.modulate = Color(0.85, 0.92, 1.0)
	add_child(_tool)

	_block_name = Label.new()
	_block_name.add_theme_font_size_override("font_size", 18)
	_block_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_block_name)

	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", SLOT_PAD)
	add_child(_hotbar)
	for i in range(Inventory.SIZE):
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(SLOT, SLOT)
		panel.add_theme_stylebox_override("panel", _style_normal)
		var swatch := ColorRect.new()
		swatch.size = Vector2(SLOT - 14, SLOT - 14)
		swatch.position = Vector2(7, 7)
		swatch.color = Color(0, 0, 0, 0)
		panel.add_child(swatch)
		var count := Label.new()
		count.add_theme_font_size_override("font_size", 14)
		count.position = Vector2(SLOT - 20, SLOT - 22)
		panel.add_child(count)
		var key := Label.new()
		key.text = str(i + 1)
		key.add_theme_font_size_override("font_size", 11)
		key.position = Vector2(4, 2)
		key.modulate = Color(1, 1, 1, 0.5)
		panel.add_child(key)
		_hotbar.add_child(panel)
		_slots.append({"panel": panel, "swatch": swatch, "count": count})

	_hint = Label.new()
	_hint.text = "WASD move  Ctrl sprint  Space jump (x2 fly)  1-9/scroll hotbar  Q/E weapon  LMB mine/attack  RMB place  G eat  C craft  F5 view  Esc pause"
	_hint.modulate = Color(1, 1, 1, 0.65)
	add_child(_hint)

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	if _dmg_flash:
		_dmg_flash.position = Vector2.ZERO
		_dmg_flash.size = vp
	_cross.position = Vector2(vp.x * 0.5 - 6, vp.y * 0.5 - 16)
	_mine_bg.position = Vector2(vp.x * 0.5 - 32, vp.y * 0.5 + 16)
	_mine_fill.position = _mine_bg.position
	var total_w := Inventory.SIZE * SLOT + (Inventory.SIZE - 1) * SLOT_PAD
	_hotbar.position = Vector2(vp.x * 0.5 - total_w * 0.5, vp.y - SLOT - 16)
	_block_name.position = Vector2(vp.x * 0.5 - 100, vp.y - SLOT - 44)
	_block_name.size = Vector2(200, 20)
	_hint.position = Vector2(16, vp.y - 26)

## Brief red screen flash when the player takes damage.
func flash_damage() -> void:
	if _dmg_flash == null:
		return
	_dmg_flash.modulate.a = 0.45
	var tw := create_tween()
	tw.tween_property(_dmg_flash, "modulate:a", 0.0, 0.4)

func set_health(h: int, max_h: int) -> void:
	if _hearts == null: return
	var s := ""
	for i in range(max_h):
		s += "♥" if i < h else "♡"
	_hearts.text = s

func set_hunger(h: int, max_h: int) -> void:
	if _hunger == null: return
	var s := ""
	for i in range(max_h):
		s += "◆" if i < h else "◇"
	_hunger.text = s

func set_mine_progress(p: float) -> void:
	var active := p > 0.0 and p < 1.0
	_mine_bg.visible = active
	_mine_fill.visible = active
	if active:
		_mine_fill.size.x = 64.0 * clampf(p, 0.0, 1.0)

func set_tool(tool_name: String) -> void:
	if _tool:
		_tool.text = "Tool: %s  (Q/E)" % tool_name

func update_hotbar(slots: Array, selected: int) -> void:
	for i in range(_slots.size()):
		var s = slots[i]
		var ui = _slots[i]
		if s.count > 0:
			ui.swatch.color = VoxelTypes.color_of(s.id)
			ui.count.text = str(s.count)
		else:
			ui.swatch.color = Color(0, 0, 0, 0)
			ui.count.text = ""
		ui.panel.add_theme_stylebox_override("panel", _style_selected if i == selected else _style_normal)
	var sel_id: int = slots[selected].id if selected >= 0 and selected < slots.size() else VoxelTypes.AIR
	if _block_name:
		_block_name.text = VoxelTypes.name_of(sel_id) if sel_id != VoxelTypes.AIR else ""
