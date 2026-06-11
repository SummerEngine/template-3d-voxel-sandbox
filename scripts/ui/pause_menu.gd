extends CanvasLayer

## Pause overlay. Owns the Esc key: toggles the game's pause state and this menu.
## Runs while the tree is paused (PROCESS_MODE_ALWAYS) so its buttons stay responsive.

var panel: Control
var paused := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build()
	_show(false)

func _build() -> void:
	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	center.add_child(vb)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var resume := _btn("Resume")
	resume.pressed.connect(_resume)
	vb.add_child(resume)

	var menu := _btn("Main Menu")
	menu.pressed.connect(_to_menu)
	vb.add_child(menu)

	var quit := _btn("Quit")
	quit.pressed.connect(_quit)
	vb.add_child(quit)

func _btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 46)
	b.add_theme_font_size_override("font_size", 20)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if paused:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()

func _pause() -> void:
	paused = true
	get_tree().paused = true
	_show(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _resume() -> void:
	paused = false
	get_tree().paused = false
	_show(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _quit() -> void:
	get_tree().quit()

func _show(v: bool) -> void:
	if panel:
		panel.visible = v
