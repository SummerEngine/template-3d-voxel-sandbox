extends CanvasLayer

## Pause overlay. Owns the Esc key: toggles the game's pause state and this menu.
## Runs while the tree is paused (PROCESS_MODE_ALWAYS) so its buttons stay responsive.

var panel: Control
var paused := false
var world
var player
var day_night
var weather
var _toast: Label
var _snd_click: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build()
	_snd_click = AudioStreamPlayer.new()
	_snd_click.process_mode = Node.PROCESS_MODE_ALWAYS   # must sound while the tree is paused
	if ResourceLoader.exists("res://assets/audio/sfx/ui/click.mp3"):
		_snd_click.stream = load("res://assets/audio/sfx/ui/click.mp3")
	_snd_click.volume_db = -8.0
	if AudioServer.get_bus_index("SFX") != -1:
		_snd_click.bus = "SFX"
	add_child(_snd_click)
	_show(false)

func _play_click() -> void:
	if _snd_click and _snd_click.stream:
		_snd_click.play()

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

	# Wood-framed panel (matches the main menu).
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UITheme.panel_box())
	center.add_child(box)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)

	var title := Label.new()
	title.text = "GAME PAUSED"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var resume := UITheme.make_button("RESUME", "primary", Vector2(300, 0))
	resume.pressed.connect(_play_click)
	resume.pressed.connect(_resume)
	vb.add_child(resume)

	var save := UITheme.make_button("SAVE WORLD", "gold", Vector2(300, 0))
	save.pressed.connect(_play_click)
	save.pressed.connect(_save)
	vb.add_child(save)

	var menu := UITheme.make_button("MAIN MENU", "normal", Vector2(300, 0))
	menu.pressed.connect(_play_click)
	menu.pressed.connect(_to_menu)
	vb.add_child(menu)

	var quit := UITheme.make_button("QUIT", "danger", Vector2(300, 0))
	quit.pressed.connect(_play_click)
	quit.pressed.connect(_quit)
	vb.add_child(quit)

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate = Color(0.8, 1.0, 0.8)
	vb.add_child(_toast)

func _save() -> void:
	if world and player:
		var ok: bool = WorldSave.save(world, player, day_night, weather)
		_toast.text = "World saved" if ok else "Save failed"
	else:
		_toast.text = "Nothing to save"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if paused:
			_resume()
		else:
			var c = get_tree().get_first_node_in_group("chest_ui")
			if c and c.has_method("is_open") and c.is_open():
				c.close()                            # first Esc closes an open chest
			else:
				_pause()
		get_viewport().set_input_as_handled()

func _pause() -> void:
	get_tree().call_group("crafting_ui", "close")   # never stack with crafting
	get_tree().call_group("chest_ui", "close")
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
