extends Control

## Title screen. Startup scene of the project. Play -> loads the game; Quit -> exits.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 16)
	center.add_child(vb)

	var title := Label.new()
	title.text = "VOXEL SANDBOX"
	title.add_theme_font_size_override("font_size", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A Minecraft-style template for Summer Engine"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(subtitle)

	vb.add_child(_spacer(24))

	var play := _btn("Play")
	play.pressed.connect(_on_play)
	vb.add_child(play)

	var quit := _btn("Quit")
	quit.pressed.connect(_on_quit)
	vb.add_child(quit)

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 50)
	b.add_theme_font_size_override("font_size", 24)
	return b

func _on_play() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main.tscn")

func _on_quit() -> void:
	get_tree().quit()
