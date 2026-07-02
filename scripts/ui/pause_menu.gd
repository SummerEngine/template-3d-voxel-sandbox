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
var _settings_scroll: ScrollContainer   # holds the sliders+rebinds; height-capped so BACK stays reachable
var _capturing_action := ""        # while non-empty, the next key press rebinds this action
var _rebind_btns := {}             # action -> Button (its label shows the current key)
var _resume_btn: Button            # focused on open so the pause menu is keyboard/controller navigable

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

	# make_button clears focus; re-enable it here (scoped to the pause buttons only) so Tab/arrows
	# navigate and Enter activates — keyboard/controller players can operate the menu. The focus
	# stylebox is empty, so this adds NO visual change.
	var resume := UITheme.make_button("RESUME", "primary", Vector2(300, 0))
	resume.focus_mode = Control.FOCUS_ALL
	resume.pressed.connect(_play_click)
	resume.pressed.connect(_resume)
	vb.add_child(resume)
	_resume_btn = resume

	var save := UITheme.make_button("SAVE WORLD", "gold", Vector2(300, 0))
	save.focus_mode = Control.FOCUS_ALL
	save.pressed.connect(_play_click)
	save.pressed.connect(_save)
	vb.add_child(save)

	var settings := UITheme.make_button("SETTINGS", "normal", Vector2(300, 0))
	settings.focus_mode = Control.FOCUS_ALL
	settings.pressed.connect(_play_click)
	settings.pressed.connect(_open_settings)
	vb.add_child(settings)

	var menu := UITheme.make_button("MAIN MENU", "normal", Vector2(300, 0))
	menu.focus_mode = Control.FOCUS_ALL
	menu.pressed.connect(_play_click)
	menu.pressed.connect(_to_menu)
	vb.add_child(menu)

	var quit := UITheme.make_button("QUIT", "danger", Vector2(300, 0))
	quit.focus_mode = Control.FOCUS_ALL
	quit.pressed.connect(_play_click)
	quit.pressed.connect(_quit)
	vb.add_child(quit)

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate = Color(0.8, 1.0, 0.8)
	vb.add_child(_toast)

	var ver := Label.new()
	ver.text = UITheme.VERSION
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.add_theme_font_size_override("font_size", 13)
	ver.modulate = Color(1, 1, 1, 0.45)
	vb.add_child(ver)

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

	# Sliders + key rebinds go in a height-capped ScrollContainer so the panel never overflows a
	# short window; RESET / BACK stay pinned below (direct vb children) so they're always reachable.
	_settings_scroll = ScrollContainer.new()
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_scroll.custom_minimum_size = Vector2(480, _settings_scroll_cap())
	vb.add_child(_settings_scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_scroll.add_child(list)

	var pct := func(v): return "%d%%" % roundi(v * 100.0)
	var dec := func(v): return "%.2fx" % v
	var whole := func(v): return "%d" % int(v)
	var deg := func(v): return "%d°" % int(v)
	list.add_child(UITheme.setting_row("Master", 0.0, 1.0, 0.05, GameSettings.master, pct, _on_master))
	list.add_child(UITheme.setting_row("Music", 0.0, 1.0, 0.05, GameSettings.music, pct, _on_music))
	list.add_child(UITheme.setting_row("Sound FX", 0.0, 1.0, 0.05, GameSettings.sfx, pct, _on_sfx))
	list.add_child(UITheme.setting_row("Look speed", 0.3, 2.5, 0.05, GameSettings.sensitivity, dec, _on_sens))
	list.add_child(UITheme.setting_row("Field of view", 60, 110, 1, GameSettings.fov, deg, _on_fov))
	list.add_child(UITheme.setting_row("View distance", 2, 8, 1, GameSettings.render_radius, whole, _on_render))

	# Fullscreen (persisted; applied live — the standard first thing anyone opens Settings for).
	var fs_cb := CheckButton.new()
	fs_cb.text = "Fullscreen"
	fs_cb.button_pressed = GameSettings.fullscreen
	fs_cb.add_theme_color_override("font_color", Color(1, 1, 1))
	fs_cb.toggled.connect(func(v: bool) -> void:
		GameSettings.fullscreen = v
		GameSettings.apply_window()
		GameSettings.save_cfg()
		_play_click())
	list.add_child(fs_cb)

	# "Eerie events" — the world-unease systems (mirages, blind-spot edits). Ships on; can be silenced.
	var unease_cb := CheckButton.new()
	unease_cb.text = "Eerie events"
	unease_cb.button_pressed = GameSettings.world_unease
	unease_cb.tooltip_text = "The world sometimes plays tricks on you — mirages in storms, things shifting when unseen."
	unease_cb.add_theme_color_override("font_color", Color(1, 1, 1))
	unease_cb.toggled.connect(func(v: bool) -> void:
		GameSettings.world_unease = v
		GameSettings.save_cfg()
		_play_click())
	list.add_child(unease_cb)

	var ctl := Label.new()
	ctl.text = "Controls  (click a key, then press the new one — Esc cancels)"
	ctl.add_theme_font_size_override("font_size", 20)
	ctl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	list.add_child(ctl)
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
		list.add_child(row)

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
	btn.text = "Press a key…  (Esc cancels)"
	get_viewport().gui_release_focus()   # focused controls would eat arrows/Enter before _unhandled_input sees them

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

func _on_fov(v: float) -> void:
	GameSettings.fov = v
	if player and player.has_method("set_fov"):
		player.set_fov(v)
	GameSettings.save_cfg()

func _on_render(v: float) -> void:
	GameSettings.render_radius = int(v)
	if world and world.has_method("set_render_radius"):
		world.set_render_radius(int(v))
	GameSettings.save_cfg()

## Cap the scrollable settings list to the current viewport so the panel (title + scroll + pinned
## RESET/BACK) always fits, even on a short window.
func _settings_scroll_cap() -> float:
	return clampf(get_viewport().get_visible_rect().size.y - 240.0, 180.0, 460.0)

func _open_settings() -> void:
	if _settings_panel:
		if _settings_scroll:
			_settings_scroll.custom_minimum_size.y = _settings_scroll_cap()   # re-fit if the window resized
		_settings_panel.visible = true
		get_viewport().gui_release_focus()   # don't let arrows/Enter drive the pause column hidden under this overlay

func _close_settings() -> void:
	_capturing_action = ""                        # drop any pending rebind capture
	if _settings_panel:
		_settings_panel.visible = false
	if paused and _resume_btn:
		_resume_btn.grab_focus()                  # restore keyboard nav on the main column

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
			var cu = get_tree().get_first_node_in_group("crafting_ui")
			var c = get_tree().get_first_node_in_group("chest_ui")
			var an = get_tree().get_first_node_in_group("chronicle")
			if cu and cu.has_method("is_open") and cu.is_open():
				cu.close()                           # first Esc closes crafting (was falling through to pause)
			elif c and c.has_method("is_open") and c.is_open():
				c.close()                            # first Esc closes an open chest
			elif an and an.has_method("is_open") and an.is_open():
				an.close_annals()                    # first Esc closes the Monolith's Annals dialog
			else:
				_pause()
		get_viewport().set_input_as_handled()

func _pause() -> void:
	get_tree().call_group("crafting_ui", "close")   # never stack with crafting
	get_tree().call_group("chest_ui", "close")
	get_tree().call_group("chronicle", "close_annals")   # nor with the Annals dialog
	paused = true
	get_tree().paused = true
	if _toast:
		_toast.text = ""        # clear any stale "World saved" so it doesn't linger across pauses
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
	if v and _resume_btn:
		_resume_btn.grab_focus()                 # land focus on RESUME so keys work without a mouse
	if not v and _settings_panel:
		_settings_panel.visible = false          # closing the pause menu also closes settings
