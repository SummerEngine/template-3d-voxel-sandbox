extends Control

## Themed main menu: a voxel-landscape background, the chroma-keyed VOXEL CREATIONS
## logo, a wood-framed panel of chunky buttons, a player profile chip, a settings
## gear and a version label. Single-player template -> Multiplayer shows a note.

const BG_PATH := "res://assets/textures/menu/background.png"
const LOGO_PATH := "res://assets/textures/menu/logo.png"
const CHROMA_PATH := "res://assets/materials/chroma_key.gdshader"
const VERSION := "v1.2.3"
const PROFILE_NAME := "BlockyBuilder"

const OPTIONS := [
	{"id": "single", "text": "SINGLE PLAYER", "kind": "primary"},
	{"id": "multi", "text": "MULTI PLAYER", "kind": "gold"},
	{"id": "create", "text": "CREATE NEW WORLD", "kind": "normal"},
	{"id": "load", "text": "LOAD WORLD", "kind": "normal"},
	{"id": "settings", "text": "SETTINGS", "kind": "normal"},
	{"id": "exit", "text": "EXIT", "kind": "danger"},
]

var _toast: Label
var _settings: Control
var _col: VBoxContainer
var _fill: ColorRect
var _bg: TextureRect
var _scrim: ColorRect

func _ready() -> void:
	# Make the UI fill the whole window at runtime (no letterbox / gray gap),
	# regardless of cached project settings, so the menu is truly centered + full.
	var win := get_window()
	if win:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(preload("res://scripts/core/audio_ducker.gd").new())   # creates audio buses
	_build()
	get_viewport().size_changed.connect(_layout_menu)
	_layout_menu()

## Centre the menu column on the real viewport (same proven approach as the HUD).
func _layout_menu() -> void:
	var vp := get_viewport_rect().size
	for r in [_fill, _bg, _scrim]:
		if r:
			r.position = Vector2.ZERO
			r.size = vp
	if _col:
		_col.position = ((vp - _col.size) * 0.5).floor()

func _build() -> void:
	# Background (fallback to a dark fill if the image is missing).
	# Background layers — sized to the real viewport in _layout_menu so they always
	# cover the whole screen (anchors alone don't, since the root isn't full-size).
	_fill = ColorRect.new()
	_fill.color = Color(0.07, 0.09, 0.13)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)
	if ResourceLoader.exists(BG_PATH):
		_bg = TextureRect.new()
		_bg.texture = load(BG_PATH)
		_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg)
	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.18)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)

	# Centered column: logo + subtitle + panel of buttons.
	# Full-width column: each child is centered horizontally on screen (SHRINK_CENTER),
	# and the whole group is centered vertically (alignment CENTER). This avoids the
	# column inheriting the logo's width and shifting the buttons off-centre.
	_col = VBoxContainer.new()
	add_child(_col)
	_col.add_theme_constant_override("separation", 10)
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.resized.connect(_layout_menu)   # re-center whenever its content size changes

	if ResourceLoader.exists(LOGO_PATH):
		var logo := TextureRect.new()
		logo.texture = load(LOGO_PATH)
		logo.custom_minimum_size = Vector2(540, 200)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if ResourceLoader.exists(CHROMA_PATH):
			var mat := ShaderMaterial.new()
			mat.shader = load(CHROMA_PATH)
			logo.material = mat
		_col.add_child(logo)
	else:
		var title := Label.new()
		title.text = "VOXEL CREATIONS"
		title.add_theme_font_size_override("font_size", 56)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_col.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "BUILD YOUR WORLD"
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_constant_override("outline_size", 6)
	subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	subtitle.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_col.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	_col.add_child(spacer)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_col.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	for opt in OPTIONS:
		var btn := UITheme.make_button(opt.text, opt.kind, Vector2(340, 0))
		btn.pressed.connect(_on_option.bind(opt.id))
		vb.add_child(btn)

	_build_profile_chip()
	_build_gear()
	_build_version()
	_build_music()
	_build_settings()

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.position = Vector2(0, -70)
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_constant_override("outline_size", 5)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_toast.modulate = Color(1, 1, 0.85)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	add_child(_toast)

func _build_profile_chip() -> void:
	var chip := PanelContainer.new()
	chip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	chip.position = Vector2(16, 16)
	chip.add_theme_stylebox_override("panel", UITheme.panel_box())
	add_child(chip)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	chip.add_child(hb)
	var avatar := ColorRect.new()
	avatar.color = Color(0.55, 0.75, 0.95)
	avatar.custom_minimum_size = Vector2(26, 26)
	hb.add_child(avatar)
	var name_lbl := Label.new()
	name_lbl.text = PROFILE_NAME
	name_lbl.add_theme_font_size_override("font_size", 18)
	hb.add_child(name_lbl)
	var coin := ColorRect.new()
	coin.color = Color(0.95, 0.80, 0.25)
	coin.custom_minimum_size = Vector2(20, 20)
	hb.add_child(coin)

func _build_gear() -> void:
	var gear := UITheme.make_button("⚙", "normal", Vector2(48, 48))
	gear.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gear.position = Vector2(-64, 16)
	gear.pressed.connect(_on_option.bind("settings"))
	add_child(gear)

func _build_music() -> void:
	const MUSIC := "res://assets/audio/music/theme.mp3"
	if not ResourceLoader.exists(MUSIC):
		return
	var stream := load(MUSIC) as AudioStreamMP3
	if stream:
		stream.loop = true
	var music := AudioStreamPlayer.new()
	music.stream = stream
	music.volume_db = -12.0
	music.autoplay = true
	if AudioServer.get_bus_index("Music") != -1:
		music.bus = "Music"
	add_child(music)

func _build_settings() -> void:
	_settings = Control.new()
	add_child(_settings)
	_settings.set_anchors_preset(Control.PRESET_FULL_RECT)   # anchor AFTER add for proper size
	_settings.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings.add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_settings.add_child(center)
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
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var vol_lbl := Label.new()
	vol_lbl.text = "Master Volume"
	vb.add_child(vol_lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	slider.custom_minimum_size = Vector2(320, 0)
	slider.value_changed.connect(_on_volume)
	vb.add_child(slider)
	var back := UITheme.make_button("BACK", "primary", Vector2(320, 0))
	back.pressed.connect(_close_settings)
	vb.add_child(back)

func _on_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))

func _close_settings() -> void:
	if _settings:
		_settings.visible = false

func _build_version() -> void:
	var v := Label.new()
	v.text = VERSION
	v.add_theme_font_size_override("font_size", 16)
	v.add_theme_constant_override("outline_size", 4)
	v.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	v.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	v.position = Vector2(-70, -28)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)

func _on_option(id: String) -> void:
	match id:
		"single", "create":
			GameState.load_on_start = false
			get_tree().paused = false
			get_tree().change_scene_to_file("res://main.tscn")
		"load":
			if WorldSave.has_save():
				GameState.load_on_start = true
				get_tree().paused = false
				get_tree().change_scene_to_file("res://main.tscn")
			else:
				_show_toast("No saved worlds yet")
		"settings":
			if _settings:
				_settings.visible = true
		"multi":
			_show_toast("Multiplayer isn't available — single-player template")
		"exit":
			get_tree().quit()

func _show_toast(msg: String) -> void:
	_toast.text = msg
	_toast.visible = true
	get_tree().create_timer(2.5).timeout.connect(_hide_toast)

func _hide_toast() -> void:
	if is_instance_valid(_toast):
		_toast.visible = false
