extends Control

## Main menu. Uses the mockup art (assets/textures/menu_background.png) as the
## background and overlays transparent, clickable buttons exactly on the six
## baked-in options, with hover highlights. Single-player template, so Multiplayer
## shows a note instead of doing nothing.

const BG_PATH := "res://assets/textures/menu_background.png"
const TEX_W := 1024.0   # mockup is square 1024x1024
const TEX_H := 1024.0

# Each option's rect inside the 1024x1024 mockup, as fractions (x, y, w, h).
# Tweak these if the highlights don't sit perfectly over the baked buttons.
const OPTIONS := [
	{ "id": "single",   "rect": [0.335, 0.385, 0.315, 0.052] },
	{ "id": "multi",    "rect": [0.335, 0.448, 0.315, 0.052] },
	{ "id": "create",   "rect": [0.335, 0.511, 0.315, 0.052] },
	{ "id": "load",     "rect": [0.335, 0.574, 0.315, 0.052] },
	{ "id": "settings", "rect": [0.335, 0.637, 0.315, 0.052] },
	{ "id": "exit",     "rect": [0.335, 0.700, 0.315, 0.052] },
]

var _bg: TextureRect
var _buttons: Array = []        # [{button, highlight, rect}]
var _toast: Label
var _have_bg := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var tex: Texture2D = load(BG_PATH) if ResourceLoader.exists(BG_PATH) else null
	_have_bg = tex != null

	# letterbox backing so the bars beside the square mockup aren't bare
	var letterbox := ColorRect.new()
	letterbox.color = Color(0.07, 0.09, 0.13)
	letterbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(letterbox)

	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	if _have_bg:
		_bg.texture = tex
		_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT   # show the whole mockup
	else:
		var fallback := ColorRect.new()
		fallback.color = Color(0.55, 0.45, 0.30)
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(fallback)
	add_child(_bg)

	for opt in OPTIONS:
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		# transparent over the baked art (the art already shows the label)
		var empty := StyleBoxEmpty.new()
		btn.add_theme_stylebox_override("normal", empty)
		btn.add_theme_stylebox_override("hover", empty)
		btn.add_theme_stylebox_override("pressed", empty)
		# fallback visible label when there is no background art
		if not _have_bg:
			btn.text = _label_for(opt.id)
		var hi := ColorRect.new()
		hi.color = Color(1, 1, 1, 0.16)
		hi.visible = false
		hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hi.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.add_child(hi)
		btn.mouse_entered.connect(func(): hi.visible = true)
		btn.mouse_exited.connect(func(): hi.visible = false)
		btn.pressed.connect(_on_option.bind(opt.id))
		add_child(btn)
		_buttons.append({ "button": btn, "rect": opt.rect })

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.position = Vector2(0, -70)
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.modulate = Color(1, 1, 0.85)
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
	# Match STRETCH_KEEP_ASPECT_COVERED mapping so buttons sit on the baked art.
	var fit_scale: float = minf(vp.x / TEX_W, vp.y / TEX_H)   # whole image visible (KEEP_ASPECT)
	var disp := Vector2(TEX_W, TEX_H) * fit_scale
	var origin := (vp - disp) * 0.5
	for entry in _buttons:
		var r: Array = entry.rect
		var btn: Button = entry.button
		if _have_bg:
			btn.position = origin + Vector2(r[0], r[1]) * disp
			btn.size = Vector2(r[2], r[3]) * disp
		else:
			# simple centered stack fallback
			btn.size = Vector2(280, 48)
			btn.position = Vector2((vp.x - 280) * 0.5, vp.y * 0.32 + _buttons.find(entry) * 58)

func _on_option(id: String) -> void:
	match id:
		"single", "create":
			get_tree().paused = false
			get_tree().change_scene_to_file("res://main.tscn")
		"load":
			_show_toast("No saved worlds yet")
		"settings":
			_show_toast("Settings — coming soon")
		"multi":
			_show_toast("Multiplayer isn't available — this is a single-player template")
		"exit":
			get_tree().quit()

func _show_toast(msg: String) -> void:
	_toast.text = msg
	_toast.visible = true
	get_tree().create_timer(2.5).timeout.connect(_hide_toast)

func _hide_toast() -> void:
	if is_instance_valid(_toast):
		_toast.visible = false
