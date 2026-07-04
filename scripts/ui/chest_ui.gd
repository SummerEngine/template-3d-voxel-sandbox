extends CanvasLayer

## Opened by right-clicking a placed Chest. Shows the chest's storage slots and the
## player's inventory; click a stack to move it between them. Storage is an Inventory
## kept on the ChunkManager per cell (persisted in the save).

const SLOT := 46
const ItemIcons := preload("res://scripts/ui/item_icons.gd")

var player
var world
var _chest                       # Inventory of the currently-open chest
var _panel: Control
var _chest_slots: Array = []     # {swatch, count}
var _inv_slots: Array = []
var _snd: AudioStreamPlayer
var _snd_open: AudioStreamPlayer   # open whoosh (crafting's ui/open.mp3) — open ≠ slot-click
var _toast: Label                # status line for blocked/partial stack moves
var open := false

func _ready() -> void:
	layer = 8
	add_to_group("chest_ui")
	_build()
	_snd = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/sfx/ui/click.mp3"):
		_snd.stream = load("res://assets/audio/sfx/ui/click.mp3")
	_snd.volume_db = -8.0
	if AudioServer.get_bus_index("SFX") != -1:
		_snd.bus = "SFX"
	add_child(_snd)
	_snd_open = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/sfx/ui/open.mp3"):
		_snd_open.stream = load("res://assets/audio/sfx/ui/open.mp3")
	_snd_open.volume_db = -10.0
	if AudioServer.get_bus_index("SFX") != -1:
		_snd_open.bus = "SFX"
	add_child(_snd_open)
	_panel.visible = false

func is_open() -> bool:
	return open

func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.dialog_box())   # shared in-game dialog look
	center.add_child(frame)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	frame.add_child(vb)

	var title := Label.new()
	title.text = "CHEST"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	vb.add_child(_grid(_chest_slots, "chest"))
	var lbl := Label.new()
	lbl.text = "Your Inventory"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.modulate = Color(0.75, 0.82, 0.95)
	vb.add_child(lbl)
	vb.add_child(_grid(_inv_slots, "inv"))
	# Bulk-transfer + Close row: emptying/looting a chest was up to 27 clicks each way.
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	var deposit_btn := UITheme.make_button("Deposit All", "normal", Vector2(140, 40))
	deposit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	deposit_btn.pressed.connect(_deposit_all)
	btn_row.add_child(deposit_btn)
	var take_btn := UITheme.make_button("Take All", "normal", Vector2(140, 40))
	take_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	take_btn.pressed.connect(_take_all)
	btn_row.add_child(take_btn)
	var close_btn := UITheme.make_button("Close", "normal", Vector2(140, 40))
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close)
	btn_row.add_child(close_btn)
	vb.add_child(btn_row)
	var hint := Label.new()
	hint.text = "Click a stack to move it between chest and inventory"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(hint)
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate = Color(1.0, 1.0, 0.8)
	vb.add_child(_toast)

func _grid(store: Array, which: String) -> Control:
	var gc := HBoxContainer.new()
	gc.alignment = BoxContainer.ALIGNMENT_CENTER
	var g := GridContainer.new()
	g.columns = 9
	g.add_theme_constant_override("h_separation", 5)
	g.add_theme_constant_override("v_separation", 5)
	gc.add_child(g)
	for i in range(Inventory.SIZE):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(SLOT, SLOT)
		UITheme.style_slot_button(btn)   # dark slot look (was default grey)
		var sw := ColorRect.new()
		sw.size = Vector2(SLOT - 14, SLOT - 14)
		sw.position = Vector2(7, 7)
		sw.color = Color(0, 0, 0, 0)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(sw)
		var ic := TextureRect.new()
		ic.size = Vector2(SLOT - 14, SLOT - 14)
		ic.position = Vector2(7, 7)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(ic)
		var ct := Label.new()
		ct.add_theme_font_size_override("font_size", 12)
		ct.add_theme_constant_override("outline_size", 3)   # legible over bright swatches/icons
		ct.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		ct.position = Vector2(SLOT - 20, SLOT - 20)
		ct.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(ct)
		var idx := i
		btn.pressed.connect(func() -> void: _on_slot(which, idx))
		g.add_child(btn)
		store.append({"btn": btn, "swatch": sw, "icon": ic, "count": ct})
	return gc

func open_chest(cell: Vector3i) -> void:
	if world == null:
		return
	get_tree().call_group("crafting_ui", "close")
	_chest = world.chest_at(cell)
	open = true
	_panel.visible = true
	if _toast: _toast.text = ""
	if _snd_open and _snd_open.stream:   # open = whoosh, close/slot-moves = click (matches crafting)
		_snd_open.pitch_scale = randf_range(0.97, 1.03)
		_snd_open.play()
	else:
		_play()
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	if not open:
		return
	open = false
	_panel.visible = false
	_play()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Move a whole stack from one side to the other.
func _on_slot(which: String, i: int) -> void:
	if _chest == null or player == null:
		return
	var src: Array = player.inventory.slots if which == "inv" else _chest.slots
	var dst = _chest if which == "inv" else player.inventory
	var s = src[i]
	if s.count <= 0:
		if _toast: _toast.text = ""   # dismiss a stale "That side is full" on an empty-slot click
		return
	var left: int = dst.add(s.id, s.count)
	var moved: int = s.count - left
	s.count -= moved
	if s.count <= 0:
		s.id = VoxelTypes.AIR
	if _toast:                       # explain a blocked/partial move (the click otherwise looks dead)
		_toast.text = "That side is full" if moved == 0 else ("Moved %d (rest didn't fit)" % moved if left > 0 else "")
	_play()
	if player.has_method("on_inventory_changed"):
		player.on_inventory_changed()
	_refresh()

## Move every stack from the player's inventory into the chest.
func _deposit_all() -> void:
	if _chest == null or player == null:
		return
	_bulk_move(player.inventory.slots, _chest, "Deposited")

## Move every stack from the chest into the player's inventory.
func _take_all() -> void:
	if _chest == null or player == null:
		return
	_bulk_move(_chest.slots, player.inventory, "Took")

## Shared bulk mover: for each non-empty slot in src, add as much as fits into dst,
## clearing emptied source slots. src/dst are distinct Inventory arrays so iterating
## src while add() mutates dst is safe. Same per-slot data path as _on_slot.
func _bulk_move(src: Array, dst, verb: String) -> void:
	var total := 0
	for s in src:
		if s.count <= 0:
			continue
		var left: int = dst.add(s.id, s.count)
		var moved: int = s.count - left
		s.count -= moved
		total += moved
		if s.count <= 0:
			s.id = VoxelTypes.AIR
	if _toast:
		_toast.text = ("%s %d" % [verb, total]) if total > 0 else "Nothing fit — that side is full"
	_play()
	if player.has_method("on_inventory_changed"):
		player.on_inventory_changed()
	_refresh()

func _refresh() -> void:
	_fill(_chest_slots, _chest.slots if _chest else [])
	_fill(_inv_slots, player.inventory.slots if player else [])

func _fill(ui_slots: Array, data: Array) -> void:
	for i in range(ui_slots.size()):
		if i < data.size() and data[i].count > 0:
			var tex: Texture2D = ItemIcons.icon(data[i].id)
			ui_slots[i].icon.texture = tex
			ui_slots[i].swatch.color = Color(0, 0, 0, 0) if tex != null else VoxelTypes.color_of(data[i].id)
			ui_slots[i].count.text = str(data[i].count) if data[i].count > 1 else ""
			ui_slots[i].btn.tooltip_text = "%s  ×%d" % [VoxelTypes.name_of(data[i].id), data[i].count]
		else:
			ui_slots[i].icon.texture = null
			ui_slots[i].swatch.color = Color(0, 0, 0, 0)
			ui_slots[i].count.text = ""
			ui_slots[i].btn.tooltip_text = "Empty"

func _play() -> void:
	if _snd and _snd.stream:
		_snd.pitch_scale = randf_range(0.97, 1.03)
		_snd.play()
