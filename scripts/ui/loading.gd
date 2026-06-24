extends Control

## Loading screen shown between the menu and the gameplay scene. It warms Godot's resource cache
## by load()-ing every heavy asset (models, textures, audio, animations) up front, so entities no
## longer hitch as they stream/spawn in. Shows a progress bar + rotating tips for at least
## MIN_TIME seconds (paced so the bar fills smoothly), then enters the world.

const NEXT_SCENE := "res://main.tscn"
const BG_PATH := "res://assets/textures/menu/background.png"
const MIN_TIME := 4.0                       # keep the screen up at least this long (perceived load)
const BAR_W := 480.0
const HEAVY_EXT := [".glb", ".mp3", ".ogg"]   # models + audio (the cold loads that hitch on spawn);
                                              # textures are pulled in by the GLBs that use them
const TIPS := [
	"Double-tap Space to toggle creative flight.",
	"Mine grass for seeds — till soil with a hoe and grow wheat.",
	"Cook raw meat in a furnace for far more hunger than eating it raw.",
	"Build a shelter before nightfall — zombies roam at night.",
	"Q / E switch your weapon; 1-9 (or scroll) pick a hotbar slot.",
	"Press C to craft, M for the map, J for your goals, F3 for stats.",
	"Higher-tier tools break tougher blocks and free rarer ores.",
]

var _paths: PackedStringArray = PackedStringArray()
var _index := 0
var _elapsed := 0.0
var _tip_t := 0.0
var _tip_i := 0
var _done := false
var _next: PackedScene
var _bar_fill: ColorRect
var _pct: Label
var _tip: Label
var _sub: Label                             # sub-text; swapped to "Ready…" once load finishes

func _ready() -> void:
	var win := get_window()
	if win:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_gather("res://assets")

func _build_ui() -> void:
	var fill := ColorRect.new()
	fill.color = Color(0.06, 0.08, 0.12)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)
	if ResourceLoader.exists(BG_PATH):
		var bg := TextureRect.new()
		bg.texture = load(BG_PATH)
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vb)

	var title := Label.new()
	title.text = "VOXEL CREATIONS"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "Loading your world…"
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(sub)
	_sub = sub

	var bar := Control.new()
	bar.custom_minimum_size = Vector2(BAR_W, 18)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(bar)
	var track := ColorRect.new()
	track.color = Color(0, 0, 0, 0.5)
	track.size = Vector2(BAR_W, 18)
	bar.add_child(track)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(0.45, 0.80, 0.46)
	_bar_fill.size = Vector2(0, 18)
	bar.add_child(_bar_fill)

	_pct = Label.new()
	_pct.text = "0%"
	_pct.add_theme_font_size_override("font_size", 16)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pct.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(_pct)

	_tip = Label.new()
	_tip.text = TIPS[0]
	_tip.add_theme_font_size_override("font_size", 18)
	_tip.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.85))
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(_tip)

## Recursively collect every heavy asset path under `dir_path`.
func _gather(dir_path: String) -> void:
	var da := DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if da.current_is_dir():
			if not n.begins_with("."):
				_gather(dir_path.path_join(n))
		else:
			var low := n.to_lower()
			for ext in HEAVY_EXT:
				if low.ends_with(ext):
					_paths.append(dir_path.path_join(n))
					break
		n = da.get_next()
	da.list_dir_end()

func _process(delta: float) -> void:
	_elapsed += delta
	_tip_t += delta
	if _tip_t >= 2.4:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		if _tip:
			_tip.text = TIPS[_tip_i]

	var total := _paths.size()
	if _index < total:
		# Load within a per-frame time budget so the screen keeps rendering (bar + tips animate)
		# instead of freezing while big models load synchronously.
		var deadline := Time.get_ticks_msec() + 10
		while _index < total and Time.get_ticks_msec() < deadline:
			var p := _paths[_index]
			if ResourceLoader.exists(p):
				ResourceLoader.load(p)         # warms the cache; later spawns hit it instantly
			_index += 1
	elif _next == null:
		_next = load(NEXT_SCENE)               # warm the gameplay scene itself, last
		if _next == null and _elapsed >= MIN_TIME:
			# Pre-load failed (broken/missing scene) — don't hang on the loading screen forever.
			# Fall straight to the scene change, which surfaces any real error instead of freezing.
			_done = true
			get_tree().change_scene_to_file(NEXT_SCENE)
			return

	var frac: float = float(_index) / float(maxi(1, total))
	if _bar_fill:
		_bar_fill.size.x = BAR_W * clampf(frac, 0.0, 1.0)
	if _pct:
		_pct.text = "%d%%" % roundi(frac * 100.0)
	# Assets done but still holding for MIN_TIME — tell the player it's ready instead of "Loading…".
	if _index >= total and _sub and _sub.text != "Ready — entering world…":
		_sub.text = "Ready — entering world…"

	if not _done and _index >= total and _next != null and _elapsed >= MIN_TIME:
		_done = true
		get_tree().change_scene_to_packed(_next)
