extends CanvasLayer

## Toggled with C. A small data-driven crafting panel: each recipe consumes inputs
## from the player's inventory and yields an output. Add rows to RECIPES to extend.
## Doesn't pause the game; it just frees the mouse so the buttons are clickable.

const RECIPES := [
	{"in_id": VoxelTypes.WOOD,   "in_n": 1, "out_id": VoxelTypes.PLANKS, "out_n": 4},
	{"in_id": VoxelTypes.SAND,   "in_n": 1, "out_id": VoxelTypes.GLASS,  "out_n": 1},
	{"in_id": VoxelTypes.PLANKS, "in_n": 4, "out_id": VoxelTypes.WOOD,   "out_n": 1},
]

var player
var _panel: Control
var _toast: Label
var open := false

func _ready() -> void:
	layer = 8
	add_to_group("crafting_ui")
	_build()
	_panel.visible = false

func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow clicks so they don't reach the game
	_panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	center.add_child(vb)

	var title := Label.new()
	title.text = "CRAFTING"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	for i in range(RECIPES.size()):
		var r: Dictionary = RECIPES[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var lbl := Label.new()
		lbl.text = "%d %s   →   %d %s" % [r.in_n, VoxelTypes.name_of(r.in_id), r.out_n, VoxelTypes.name_of(r.out_id)]
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.custom_minimum_size = Vector2(320, 0)
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Craft"
		btn.custom_minimum_size = Vector2(120, 40)
		btn.pressed.connect(_craft.bind(i))
		row.add_child(btn)
		vb.add_child(row)

	var hint := Label.new()
	hint.text = "Press C to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(hint)

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate = Color(1, 1, 0.8)
	vb.add_child(_toast)

func _craft(idx: int) -> void:
	if player == null:
		return
	var r: Dictionary = RECIPES[idx]
	if player.inventory.consume(r.in_id, r.in_n):
		player.inventory.add(r.out_id, r.out_n)
		_toast.text = "Crafted %d %s" % [r.out_n, VoxelTypes.name_of(r.out_id)]
		if player.has_method("on_inventory_changed"):
			player.on_inventory_changed()
		if player.has_method("play_craft_sound"):
			player.play_craft_sound()
	else:
		_toast.text = "Need %d %s" % [r.in_n, VoxelTypes.name_of(r.in_id)]

func _unhandled_input(event: InputEvent) -> void:
	# Ignore C while the game is paused so crafting can't open over the pause menu.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		if not get_tree().paused:
			toggle()
			get_viewport().set_input_as_handled()

func toggle() -> void:
	open = not open
	_panel.visible = open
	if open:
		_toast.text = ""
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Called by the pause menu so the two overlays never stack.
func close() -> void:
	if open:
		open = false
		_panel.visible = false
