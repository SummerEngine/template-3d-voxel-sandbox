extends Control

## Main menu over the mockup art. The six options are real buttons stacked to
## evenly fill the panel area (so they line up with the baked-in buttons), fully
## clickable. Single-player template -> Multiplayer just shows a note.

const BG_PATH := "res://assets/textures/menu_background.png"
const TEX_W := 1024.0
const TEX_H := 1024.0
# Button-stack region inside the 1024x1024 mockup (x, y, w, h fractions).
const STACK := Rect2(0.335, 0.383, 0.318, 0.366)
const OPTION_IDS := ["single", "multi", "create", "load", "settings", "exit"]

var _bg: TextureRect
var _vbox: VBoxContainer
var _toast: Label
var _have_bg := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var lb := ColorRect.new()
	lb.color = Color(0.07, 0.09, 0.13)
	lb.set_anchors_preset(Control.PRESET_FULL_RECT)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lb)

	var tex: Texture2D = load(BG_PATH) if ResourceLoader.exists(BG_PATH) else null
	_have_bg = tex != null
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _have_bg:
		_bg.texture = tex
		_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	add_child(_bg)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 4)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vbox)
	for id in OPTION_IDS:
		var btn := Button.new()
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		if _have_bg:
			btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			var hov := StyleBoxFlat.new()
			hov.bg_color = Color(1, 1, 1, 0.16)
			btn.add_theme_stylebox_override("hover", hov)
			var prs := StyleBoxFlat.new()
			prs.bg_color = Color(1, 1, 1, 0.30)
			btn.add_theme_stylebox_override("pressed", prs)
		else:
			btn.text = _label_for(id)
		btn.pressed.connect(_on_option.bind(id))
		_vbox.add_child(btn)

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.position = Vector2(0, -64)
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.modulate = Color(1, 1, 0.85)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	add_child(_toast)

	get_viewport().size_changed.connect(_layout)
	_layout()

func _label_for(id: String) -> String:
	match id:
		"single": return "Single Player"
		"multi": return "Multi Player"
		"create": return "Create New World"
		"load": return "Load World"
		"settings": return "Settings"
		"exit": return "Exit"
	return id

func _layout() -> void:
	var vp := get_viewport_rect().size
	var fit: float = minf(vp.x / TEX_W, vp.y / TEX_H)
	var disp := Vector2(TEX_W, TEX_H) * fit
	var origin := (vp - disp) * 0.5
	if _have_bg:
		_vbox.position = origin + Vector2(STACK.position.x, STACK.position.y) * disp
		_vbox.size = Vector2(STACK.size.x, STACK.size.y) * disp
	else:
		_vbox.position = Vector2(vp.x * 0.5 - 150.0, vp.y * 0.3)
		_vbox.size = Vector2(300, 360)

func _on_option(id: String) -> void:
	match id:
		"single", "create":
			get_tree().paused = false
			get_tree().change_scene_to_file("res://main.tscn")
		"load":
			_show_toast("No saved worlds yet")
		"settings":
			_show_toast("Settings - coming soon")
		"multi":
			_show_toast("Multiplayer isn't available - single-player template")
		"exit":
			get_tree().quit()

func _show_toast(msg: String) -> void:
	_toast.text = msg
	_toast.visible = true
	get_tree().create_timer(2.5).timeout.connect(_hide_toast)

func _hide_toast() -> void:
	if is_instance_valid(_toast):
		_toast.visible = false
