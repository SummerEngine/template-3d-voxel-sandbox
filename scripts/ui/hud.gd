extends CanvasLayer

## In-game HUD: crosshair, hearts (health), selected-block label, and a controls hint.
## The player calls set_health() and set_block() to update it.

var hearts_label: Label
var block_label: Label
var tool_label: Label

func _ready() -> void:
	layer = 5
	_build()

func _build() -> void:
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-6, -16)
	add_child(cross)

	hearts_label = Label.new()
	hearts_label.add_theme_font_size_override("font_size", 26)
	hearts_label.position = Vector2(16, 12)
	hearts_label.modulate = Color(1.0, 0.27, 0.32)
	add_child(hearts_label)

	block_label = Label.new()
	block_label.position = Vector2(16, 52)
	add_child(block_label)

	tool_label = Label.new()
	tool_label.position = Vector2(16, 76)
	tool_label.modulate = Color(0.85, 0.92, 1.0)
	add_child(tool_label)

	var hint := Label.new()
	hint.text = "WASD move   Ctrl sprint   Space jump (x2 = fly)   1-4 block   Scroll / Q-E weapon   Hold LMB mine   RMB place   Esc pause"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(16, -30)
	hint.modulate = Color(1, 1, 1, 0.7)
	add_child(hint)

func set_health(h: int, max_h: int) -> void:
	if hearts_label == null:
		return
	var s := ""
	for i in range(max_h):
		s += "♥" if i < h else "♡"   # ♥ filled / ♡ empty
	hearts_label.text = s

func set_block(block_name: String, idx: int, total: int) -> void:
	if block_label:
		block_label.text = "Block: %s  (%d/%d)" % [block_name, idx, total]

func set_tool(tool_name: String) -> void:
	if tool_label:
		tool_label.text = "Tool: %s  (Q/E)" % tool_name
