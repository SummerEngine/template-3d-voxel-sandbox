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
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.10, 0.11, 0.14, 0.97)
	box.set_border_width_all(3)
	box.border_color = Color(0.55, 0.58, 0.66, 0.9)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(22)
	frame.add_theme_stylebox_override("panel", box)
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
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.pressed.connect(close)
	vb.add_child(close_btn)
	var hint := Label.new()
	hint.text = "Click a stack to move it between chest and inventory"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(hint)

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
		ct.position = Vector2(SLOT - 20, SLOT - 20)
		ct.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(ct)
		var idx := i
		btn.pressed.connect(func() -> void: _on_slot(which, idx))
		g.add_child(btn)
		store.append({"swatch": sw, "icon": ic, "count": ct})
	return gc

func open_chest(cell: Vector3i) -> void:
	if world == null:
		return
	get_tree().call_group("crafting_ui", "close")
	_chest = world.chest_at(cell)
	open = true
	_panel.visible = true
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
		return
	var left: int = dst.add(s.id, s.count)
	var moved: int = s.count - left
	s.count -= moved
	if s.count <= 0:
		s.id = VoxelTypes.AIR
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
			ui_slots[i].count.text = str(data[i].count)
		else:
			ui_slots[i].icon.texture = null
			ui_slots[i].swatch.color = Color(0, 0, 0, 0)
			ui_slots[i].count.text = ""

func _play() -> void:
	if _snd and _snd.stream:
		_snd.pitch_scale = randf_range(0.97, 1.03)
		_snd.play()
