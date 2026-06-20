extends CanvasLayer

## Pause overlay. Owns the Esc key: toggles the game's pause state and this menu.
## Runs while the tree is paused (PROCESS_MODE_ALWAYS) so its buttons stay responsive.

const InputActions := preload("res://scripts/core/input_actions.gd")

var panel: Control
var paused := false
var world
var player
var day_night
var weather
var _toast: Label
var _snd_click: AudioStreamPlayer
var _settings_panel: Control
var _capturing_action := ""        # while non-empty, the next key press rebinds this action
var _rebind_btns := {}             # action -> Button (its label shows the current key)

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

	var settings := UITheme.make_button("SETTINGS", "normal", Vector2(300, 0))
	settings.pressed.connect(_play_click)
	settings.pressed.connect(_open_settings)
	vb.add_child(settings)

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

	_build_settings()

## In-game settings overlay (same sliders as the main menu) that applies LIVE to the running
## player + world, then persists, so volume / look-speed / view distance can be tuned mid-game.
func _build_settings() -> void:
	GameSettings.load_cfg()
	_settings_panel = Control.new()
	add_child(_settings_panel)
	_settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_panel.add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_settings_panel.add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UITheme.panel_box())
	center.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	box.add_child(vb)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var pct := func(v): return "%d%%" % roundi(v * 100.0)
	var dec := func(v): return "%.2fx" % v
	var whole := func(v): return "%d" % int(v)
	vb.add_child(UITheme.setting_row("Master", 0.0, 1.0, 0.05, GameSettings.master, pct, _on_master))
	vb.add_child(UITheme.setting_row("Music", 0.0, 1.0, 0.05, GameSettings.music, pct, _on_music))
	vb.add_child(UITheme.setting_row("Sound FX", 0.0, 1.0, 0.05, GameSettings.sfx, pct, _on_sfx))
	vb.add_child(UITheme.setting_row("Look speed", 0.3, 2.5, 0.05, GameSettings.sensitivity, dec, _on_sens))
	vb.add_child(UITheme.setting_row("View distance", 2, 8, 1, GameSettings.render_radius, whole, _on_render))

	var ctl := Label.new()
	ctl.text = "Controls  (click a key, then press the new one)"
	ctl.add_theme_font_size_override("font_size", 20)
	ctl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	vb.add_child(ctl)
	_rebind_btns = {}
	for action in InputActions.ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var lbl := Label.new()
		lbl.text = InputActions.LABELS.get(action, action)
		lbl.custom_minimum_size = Vector2(150, 0)
		lbl.add_theme_font_size_override("font_size", UITheme.FONT_SIZE)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		row.add_child(lbl)
		var keybtn := UITheme.make_button(InputActions.key_label(InputActions.keycode_for(action)), "normal", Vector2(180, 0))
		keybtn.pressed.connect(_begin_capture.bind(action, keybtn))
		row.add_child(keybtn)
		_rebind_btns[action] = keybtn
		vb.add_child(row)
	var reset := UITheme.make_button("RESET CONTROLS", "danger", Vector2(320, 0))
	reset.pressed.connect(_play_click)
	reset.pressed.connect(_reset_controls)
	vb.add_child(reset)

	var back := UITheme.make_button("BACK", "primary", Vector2(320, 0))
	back.pressed.connect(_play_click)
	back.pressed.connect(_close_settings)
	vb.add_child(back)

func _begin_capture(action: String, btn: Button) -> void:
	_play_click()
	_capturing_action = action
	btn.text = "Press a key…"

func _reset_controls() -> void:
	InputActions.reset()
	_refresh_rebind_labels()

func _refresh_rebind_labels() -> void:
	for action in _rebind_btns:
		var b: Button = _rebind_btns[action]
		if is_instance_valid(b):
			b.text = InputActions.key_label(InputActions.keycode_for(action))

# Settings handlers — apply live to the running game, then persist.
func _on_master(v: float) -> void:
	GameSettings.master = v; GameSettings.apply_audio(get_tree()); GameSettings.save_cfg()

func _on_music(v: float) -> void:
	GameSettings.music = v; GameSettings.apply_audio(get_tree()); GameSettings.save_cfg()

func _on_sfx(v: float) -> void:
	GameSettings.sfx = v; GameSettings.apply_audio(get_tree()); GameSettings.save_cfg()

func _on_sens(v: float) -> void:
	GameSettings.sensitivity = v
	if player and player.has_method("set_sensitivity"):
		player.set_sensitivity(v)
	GameSettings.save_cfg()

func _on_render(v: float) -> void:
	GameSettings.render_radius = int(v)
	if world and world.has_method("set_render_radius"):
		world.set_render_radius(int(v))
	GameSettings.save_cfg()

func _open_settings() -> void:
	if _settings_panel:
		_settings_panel.visible = true

func _close_settings() -> void:
	_capturing_action = ""                        # drop any pending rebind capture
	if _settings_panel:
		_settings_panel.visible = false

func _settings_open() -> bool:
	return _settings_panel != null and _settings_panel.visible

func _save() -> void:
	if world and player:
		var ok: bool = WorldSave.save(world, player, day_night, weather)
		_toast.text = "World saved" if ok else "Save failed"
	else:
		_toast.text = "Nothing to save"

func _unhandled_input(event: InputEvent) -> void:
	# Rebind capture: the next key press becomes the binding (Esc cancels without binding).
	if _capturing_action != "" and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode != KEY_ESCAPE:
			InputActions.rebind(_capturing_action, event.physical_keycode)
		_capturing_action = ""
		_refresh_rebind_labels()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _settings_open():
			_close_settings()                    # first Esc backs out of the settings overlay
		elif paused:
			_resume()
		elif player and player.has_method("is_dead") and player.is_dead():
			pass                                     # dead: the death screen + R own the input, don't pause over it
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
	if not v and _settings_panel:
		_settings_panel.visible = false          # closing the pause menu also closes settings
