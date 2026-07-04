extends CanvasLayer

## In-game HUD: crosshair, mine-progress bar, health hearts, hunger, held-tool label,
## a 9-slot hotbar (block swatch + count, selected slot highlighted), a controls
## hint and a death/respawn screen. The player pushes state in via the
## set_*/update_hotbar methods and listens for respawn_requested.

signal respawn_requested

const ItemIcons := preload("res://scripts/ui/item_icons.gd")
const SLOT := 50
const SLOT_PAD := 6

var _cross: Label
var _mine_bg: ColorRect
var _mine_fill: ColorRect
var _hearts: Label
var _hunger: Label
var _tool: Label
var _armor: Label
var _block_name: Label
var _target_name: Label           # what you're AIMING at (name + "needs a better pickaxe" when too weak)
var _controls: PanelContainer
var _controls_hint: PanelContainer   # tiny "H — Controls" chip shown when the controls panel is hidden
var _hotbar: HBoxContainer
var _slots: Array = []          # each: {panel, swatch, count}
var _prev_counts: Array = []    # last-seen count per slot, to pulse a slot when it gains an item
var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _dmg_flash: ColorRect
var _dir_flash: Array = []       # 4 screen-edge strips (L/R/top/bottom) lit toward an attacker
var _vignette: TextureRect       # sustained red edge-vignette that pulses when health is low
var _low_active := false
var _low_intensity := 0.0
var _low_phase := 0.0
var _death_dim: ColorRect
var _death_title: Label
var _death_sub: Label
var _respawn_btn: Button
var _snd_click: AudioStreamPlayer
var _fps: Label
var _fps_accum := 0.0
var _toast: Label
var _toast_tw: Tween
var _hitmark: Label              # brief red "x" when an attack lands on a mob
var _prev_sel := -1              # last hotbar selection, to pulse + tick on change
var _snd_tick: AudioStreamPlayer # dedicated soft tick for hotbar scrolling
var _hb: AudioStreamPlayer       # low-health heartbeat, synced to the vignette breathe
var _hb_next := 0.0              # next _low_phase at which to thump (one beat per breathe cycle)
var _blood_vig: TextureRect      # pulsing red edge-vignette during a blood moon
var _blood_on := false
var _blood_phase := 0.0
var _time_label: Label           # persistent "Day N" / "Night N" readout
var _time_plain := ""            # undecorated "Day N"/"Night N" (death screen uses this, not the "· BLOOD MOON" label text)
var _objective: Label            # persistent "current goal" line (fed by advancements.next_goal)

func _ready() -> void:
	layer = 5
	_build_styles()
	_build()
	_snd_click = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/sfx/ui/click.mp3"):
		_snd_click.stream = load("res://assets/audio/sfx/ui/click.mp3")
	_snd_click.volume_db = -8.0
	if AudioServer.get_bus_index("SFX") != -1:
		_snd_click.bus = "SFX"
	add_child(_snd_click)
	_snd_tick = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/sfx/ui/click.mp3"):
		_snd_tick.stream = load("res://assets/audio/sfx/ui/click.mp3")
	_snd_tick.volume_db = -16.0
	_snd_tick.pitch_scale = 1.5
	if AudioServer.get_bus_index("SFX") != -1:
		_snd_tick.bus = "SFX"
	add_child(_snd_tick)
	_hb = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/sfx/player/heartbeat.wav"):
		_hb.stream = load("res://assets/audio/sfx/player/heartbeat.wav")
	_hb.volume_db = -10.0
	if AudioServer.get_bus_index("SFX") != -1:
		_hb.bus = "SFX"
	add_child(_hb)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _process(delta: float) -> void:
	_update_vignette(delta)
	if _fps == null or not _fps.visible:
		return
	_fps_accum += delta
	if _fps_accum >= 0.25:          # refresh 4x/sec so the number is readable
		_fps_accum = 0.0
		var fps := Engine.get_frames_per_second()
		var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		_fps.text = "FPS %d\n%d draws\n%.1fM tris" % [fps, draws, float(prims) / 1_000_000.0]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_fps.visible = not _fps.visible
		elif event.keycode == KEY_H:
			_toggle_controls()
			get_viewport().set_input_as_handled()

## Hide / show the controls guide. When hidden, a small "H — Controls" chip stays so the binding
## is always discoverable.
func _toggle_controls() -> void:
	if _controls == null:
		return
	_controls.visible = not _controls.visible
	if _controls_hint:
		_controls_hint.visible = not _controls.visible
	_center_controls()

## On a fresh world, fade the full controls panel out after a grace period (leaving the "H — Controls"
## chip), so first-timers get the guide but it doesn't clutter the screen forever. H still toggles it.
func auto_retire_controls() -> void:
	if _controls == null:
		return
	get_tree().create_timer(25.0).timeout.connect(_retire_controls)   # outlive the welcome toasts + mouse-settling window

func _retire_controls() -> void:
	if _controls == null or not _controls.visible:
		return                                    # already hidden (player pressed H) — leave it
	# Don't vanish mid-read while a menu is open (mouse freed) — wait and try again shortly.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		get_tree().create_timer(5.0).timeout.connect(_retire_controls)
		return
	var tw := create_tween()
	tw.tween_property(_controls, "modulate:a", 0.0, 1.2)
	tw.tween_callback(func() -> void:
		_controls.visible = false
		_controls.modulate.a = 1.0
		if _controls_hint:
			_controls_hint.visible = true
		_center_controls())

func _build_styles() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0, 0, 0, 0.35)
	_style_normal.set_border_width_all(2)
	_style_normal.border_color = Color(0.7, 0.7, 0.7, 0.5)
	_style_selected = StyleBoxFlat.new()
	_style_selected.bg_color = Color(0, 0, 0, 0.5)
	_style_selected.set_border_width_all(3)
	_style_selected.border_color = Color(1.0, 0.85, 0.42, 1.0)   # gold accent (matches the controls keys)
	_style_selected.shadow_color = Color(1.0, 0.82, 0.35, 0.55)  # soft glow so the active slot pops
	_style_selected.shadow_size = 5

## A black outline behind a label so HUD text stays legible over bright sky, snow or lava
## (the world behind the HUD is any colour). Returns the label for inline use.
func _outline(l: Label, size: int = 4) -> Label:
	l.add_theme_constant_override("outline_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return l

func _build() -> void:
	# Full-screen red damage flash (behind the HUD widgets, over the 3D world).
	_dmg_flash = ColorRect.new()
	_dmg_flash.color = Color(0.85, 0.0, 0.0, 1.0)
	_dmg_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmg_flash.modulate = Color(1, 1, 1, 0.0)
	add_child(_dmg_flash)

	# Directional damage strips: 4 gradient edges (left/right/top/bottom) lit toward the attacker.
	# Alpha-0 by default; indicate_damage_from() flashes the edge(s) facing the hit source.
	var efrom := [Vector2(0, 0.5), Vector2(1, 0.5), Vector2(0.5, 0), Vector2(0.5, 1)]
	var eto := [Vector2(1, 0.5), Vector2(0, 0.5), Vector2(0.5, 1), Vector2(0.5, 0)]
	for i in range(4):
		var eg := Gradient.new()
		eg.set_color(0, Color(0.8, 0.02, 0.02, 0.9))
		eg.set_color(1, Color(0.8, 0.02, 0.02, 0.0))
		var et := GradientTexture2D.new()
		et.gradient = eg
		et.fill_from = efrom[i]
		et.fill_to = eto[i]
		var er := TextureRect.new()
		er.texture = et
		er.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		er.stretch_mode = TextureRect.STRETCH_SCALE
		er.mouse_filter = Control.MOUSE_FILTER_IGNORE
		er.modulate = Color(1, 1, 1, 0.0)
		add_child(er)
		_dir_flash.append(er)

	# Low-health vignette: a radial gradient that's clear in the centre and dark red at the
	# edges, faded out by default and pulsed in (via _process) only when health is critical.
	_vignette = TextureRect.new()
	var grad := Gradient.new()
	grad.set_offset(0, 0.42)
	grad.set_color(0, Color(0.55, 0.0, 0.0, 0.0))   # centre: clear
	grad.set_offset(1, 1.0)
	grad.set_color(1, Color(0.45, 0.0, 0.0, 1.0))   # edges: red
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(0.5, 1.0)
	gtex.width = 256
	gtex.height = 256
	_vignette.texture = gtex
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate = Color(1, 1, 1, 0.0)
	add_child(_vignette)

	# Blood-moon vignette: a deep-red edge pulse that breathes through siege nights (composes on
	# top of the low-health vignette). Driven by set_blood_moon() + _update_vignette().
	_blood_vig = TextureRect.new()
	var bgrad := Gradient.new()
	bgrad.set_offset(0, 0.30)
	bgrad.set_color(0, Color(0.5, 0.0, 0.0, 0.0))
	bgrad.set_offset(1, 1.0)
	bgrad.set_color(1, Color(0.42, 0.0, 0.02, 1.0))
	var btex := GradientTexture2D.new()
	btex.gradient = bgrad
	btex.fill = GradientTexture2D.FILL_RADIAL
	btex.fill_from = Vector2(0.5, 0.5)
	btex.fill_to = Vector2(0.5, 1.0)
	btex.width = 256
	btex.height = 256
	_blood_vig.texture = btex
	_blood_vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_blood_vig.stretch_mode = TextureRect.STRETCH_SCALE
	_blood_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blood_vig.modulate = Color(1, 1, 1, 0.0)
	add_child(_blood_vig)

	_cross = Label.new()
	_cross.text = "+"
	_cross.add_theme_font_size_override("font_size", 22)
	_cross.modulate = Color(1, 1, 1, 0.55)        # dim until something is in reach (set_crosshair_state)
	_outline(_cross, 3)
	add_child(_cross)

	# Hit-marker: a brief red "x" over the crosshair when an attack connects with a mob.
	_hitmark = Label.new()
	_hitmark.text = "✕"
	_hitmark.add_theme_font_size_override("font_size", 26)
	_hitmark.modulate = Color(1, 1, 1, 0)
	_hitmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline(_hitmark, 3)
	add_child(_hitmark)

	_mine_bg = ColorRect.new()
	_mine_bg.color = Color(0, 0, 0, 0.6)
	_mine_bg.size = Vector2(64, 7)
	_mine_bg.visible = false
	add_child(_mine_bg)
	_mine_fill = ColorRect.new()
	_mine_fill.color = Color(0.9, 0.9, 0.95, 0.95)
	_mine_fill.size = Vector2(0, 7)
	_mine_fill.visible = false
	add_child(_mine_fill)

	_hearts = Label.new()
	_hearts.add_theme_font_size_override("font_size", 24)
	_hearts.position = Vector2(16, 12)
	_hearts.modulate = Color(1.0, 0.27, 0.32)
	_outline(_hearts)
	add_child(_hearts)

	_hunger = Label.new()
	_hunger.add_theme_font_size_override("font_size", 24)
	_hunger.position = Vector2(16, 44)
	_hunger.modulate = Color(0.95, 0.65, 0.25)
	_outline(_hunger)
	add_child(_hunger)

	_tool = Label.new()
	_tool.position = Vector2(16, 78)
	_tool.modulate = Color(0.85, 0.92, 1.0)
	_outline(_tool)
	add_child(_tool)

	_armor = Label.new()
	_armor.position = Vector2(16, 102)
	_armor.modulate = Color(0.65, 0.85, 1.0)
	_outline(_armor)
	add_child(_armor)

	# Persistent day/night readout (the fading toast alone wasn't enough to track the night number,
	# which drives escalating difficulty + the every-5th-night blood moon).
	_time_label = Label.new()
	_time_label.position = Vector2(16, 126)
	_time_label.add_theme_font_size_override("font_size", 16)
	_time_label.modulate = Color(0.95, 0.95, 0.82)
	_outline(_time_label)
	add_child(_time_label)

	# Persistent objective line so a lost player always has a "what next" prompt (the two welcome
	# toasts fade in ~5s). Auto-advances through the advancement chain via set_objective().
	_objective = Label.new()
	_objective.position = Vector2(16, 146)
	_objective.add_theme_font_size_override("font_size", 14)
	_objective.modulate = Color(0.82, 0.9, 1.0)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size = Vector2(300, 0)
	_outline(_objective)
	add_child(_objective)

	_block_name = Label.new()
	_block_name.add_theme_font_size_override("font_size", 18)
	_block_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(_block_name)
	add_child(_block_name)

	# "What am I aiming at" readout, just above the crosshair. Shows the targeted block's name and,
	# when your pickaxe is too weak to harvest it, why (turns red). Fed from the player's per-frame
	# look path, change-gated so it only updates when the aimed block changes.
	_target_name = Label.new()
	_target_name.add_theme_font_size_override("font_size", 15)
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_name.visible = false
	_outline(_target_name)
	add_child(_target_name)

	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", SLOT_PAD)
	add_child(_hotbar)
	for i in range(Inventory.HOTBAR):
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(SLOT, SLOT)
		panel.add_theme_stylebox_override("panel", _style_normal)
		var swatch := ColorRect.new()
		swatch.size = Vector2(SLOT - 14, SLOT - 14)
		swatch.position = Vector2(7, 7)
		swatch.color = Color(0, 0, 0, 0)
		panel.add_child(swatch)
		var icon := TextureRect.new()                      # real texture, drawn over the swatch
		icon.size = Vector2(SLOT - 14, SLOT - 14)
		icon.position = Vector2(7, 7)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		panel.add_child(icon)
		var count := Label.new()
		count.add_theme_font_size_override("font_size", 14)
		count.position = Vector2(SLOT - 20, SLOT - 22)
		_outline(count, 3)
		panel.add_child(count)
		var key := Label.new()
		key.text = str(i + 1)
		key.add_theme_font_size_override("font_size", 11)
		key.position = Vector2(4, 2)
		key.modulate = Color(1, 1, 1, 0.8)        # brighter so the 1-9 hint reads over bright terrain
		_outline(key, 3)
		panel.add_child(key)
		_hotbar.add_child(panel)
		_slots.append({"panel": panel, "swatch": swatch, "icon": icon, "count": count})

	_build_controls()

	_build_death_screen()

	# Transient centre-screen toast (tool-too-weak, advancements, etc.).
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate = Color(1, 1, 1, 0)
	_outline(_toast)
	add_child(_toast)

	# F3 debug overlay: live FPS + draw stats, top-right, hidden by default.
	_fps = Label.new()
	_fps.add_theme_font_size_override("font_size", 16)
	_fps.modulate = Color(0.7, 1.0, 0.7)
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT   # left column, below Day/Night — was drawn over the minimap
	_fps.visible = false
	_outline(_fps, 3)
	add_child(_fps)

## Controls reference at the top — one row per control, each as "control → action" with plain,
## beginner-friendly labels ("Left click", not "LMB"). Two key→action columns keep it compact.
func _build_controls() -> void:
	const CONTROLS := [
		["WASD", "Move"],
		["Ctrl", "Sprint"],
		["Space", "Jump  (double-tap to fly)"],
		["Scroll / 1-9", "Select hotbar"],
		["Q / E", "Switch weapon"],
		["Left click", "Mine / attack"],
		["Right click", "Place / use"],
		["G", "Eat"],
		["C", "Crafting"],
		["M", "Map"],
		["J", "Goals"],
		["F5", "First / third person"],
		["F3", "Stats"],
		["H", "Hide controls"],
		["Esc", "Pause"],
	]
	_controls = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.34)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(8)
	_controls.add_theme_stylebox_override("panel", box)
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_controls)
	var grid := GridContainer.new()
	grid.columns = 4                                     # key, action, key, action — two columns of pairs
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls.add_child(grid)
	var half := int(ceil(CONTROLS.size() / 2.0))
	for i in range(half):
		_ctrl_row(grid, CONTROLS[i])
		var j := i + half
		if j < CONTROLS.size():
			_ctrl_row(grid, CONTROLS[j])
		else:
			grid.add_child(_ctrl_cell("", true))
			grid.add_child(_ctrl_cell("", false))
	_controls.resized.connect(_center_controls)

	# Minimised indicator: a small "H — Controls" chip shown in the controls panel's spot when the
	# panel is hidden, so you always know how to bring the guide back.
	_controls_hint = PanelContainer.new()
	var hbox := StyleBoxFlat.new()
	hbox.bg_color = Color(0, 0, 0, 0.34)
	hbox.set_corner_radius_all(6)
	hbox.set_content_margin_all(6)
	_controls_hint.add_theme_stylebox_override("panel", hbox)
	_controls_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls_hint.add_child(hb)
	var kl := Label.new()
	kl.text = "H"
	kl.add_theme_font_size_override("font_size", 14)
	kl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
	kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline(kl, 3)
	hb.add_child(kl)
	var al := Label.new()
	al.text = "Controls"
	al.add_theme_font_size_override("font_size", 14)
	al.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	al.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline(al, 3)
	hb.add_child(al)
	_controls_hint.visible = false
	add_child(_controls_hint)
	_controls_hint.resized.connect(_center_controls)

func _ctrl_row(grid: GridContainer, pair: Array) -> void:
	grid.add_child(_ctrl_cell(String(pair[0]), true))    # the control (key) — accent colour
	grid.add_child(_ctrl_cell(String(pair[1]), false))   # the action — white

func _ctrl_cell(text: String, is_key: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42) if is_key else Color(0.95, 0.97, 1.0))
	l.custom_minimum_size = Vector2(96.0 if is_key else 132.0, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Keep the controls panel centred across the top, clear of the corner stats + minimap.
func _center_controls() -> void:
	var vp := get_viewport().get_visible_rect().size
	if _controls:
		_controls.position = Vector2((vp.x - _controls.size.x) * 0.5, 8)
	if _controls_hint:
		_controls_hint.position = Vector2((vp.x - _controls_hint.size.x) * 0.5, 8)

## A dark-red full-screen overlay with "You Died" and a Respawn button. Hidden until
## the player calls show_death(); the button (or the R key) emits respawn_requested.
func _build_death_screen() -> void:
	_death_dim = ColorRect.new()
	_death_dim.color = Color(0.22, 0.0, 0.02, 0.78)
	_death_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow clicks behind it
	_death_dim.visible = false
	add_child(_death_dim)

	_death_title = Label.new()
	_death_title.text = "YOU DIED"
	_death_title.add_theme_font_size_override("font_size", 64)
	_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_title.modulate = Color(0.88, 0.16, 0.18)
	_outline(_death_title, 6)
	_death_title.visible = false
	add_child(_death_title)

	_death_sub = Label.new()
	_death_sub.text = "Press R or click Respawn"
	_death_sub.add_theme_font_size_override("font_size", 20)
	_death_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_sub.modulate = Color(0.95, 0.9, 0.9, 0.85)
	_death_sub.visible = false
	add_child(_death_sub)

	_respawn_btn = UITheme.make_button("Respawn", "primary", Vector2(220, 56))
	_respawn_btn.focus_mode = Control.FOCUS_ALL   # make_button clears focus; we want R/Enter on it
	_respawn_btn.visible = false
	_respawn_btn.pressed.connect(func() -> void:
		if _snd_click and _snd_click.stream:
			_snd_click.play()
		respawn_requested.emit())
	add_child(_respawn_btn)

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	if _dmg_flash:
		_dmg_flash.position = Vector2.ZERO
		_dmg_flash.size = vp
	if _dir_flash.size() == 4:
		_dir_flash[0].position = Vector2.ZERO;             _dir_flash[0].size = Vector2(vp.x * 0.12, vp.y)
		_dir_flash[1].position = Vector2(vp.x * 0.88, 0);  _dir_flash[1].size = Vector2(vp.x * 0.12, vp.y)
		_dir_flash[2].position = Vector2.ZERO;             _dir_flash[2].size = Vector2(vp.x, vp.y * 0.14)
		_dir_flash[3].position = Vector2(0, vp.y * 0.86);  _dir_flash[3].size = Vector2(vp.x, vp.y * 0.14)
	if _vignette:
		_vignette.position = Vector2.ZERO
		_vignette.size = vp
	if _blood_vig:
		_blood_vig.position = Vector2.ZERO
		_blood_vig.size = vp
	_cross.position = Vector2(vp.x * 0.5 - 6, vp.y * 0.5 - 16)
	if _hitmark:
		_hitmark.position = Vector2(vp.x * 0.5 - 9, vp.y * 0.5 - 18)
	_mine_bg.position = Vector2(vp.x * 0.5 - 32, vp.y * 0.5 + 16)
	_mine_fill.position = _mine_bg.position
	var total_w := Inventory.HOTBAR * SLOT + (Inventory.HOTBAR - 1) * SLOT_PAD
	_hotbar.position = Vector2(vp.x * 0.5 - total_w * 0.5, vp.y - SLOT - 16)
	_block_name.position = Vector2(vp.x * 0.5 - 100, vp.y - SLOT - 44)
	_block_name.size = Vector2(200, 20)
	if _target_name:
		_target_name.size = Vector2(360, 20)
		_target_name.position = Vector2(vp.x * 0.5 - 180, vp.y * 0.5 + 42)   # just under the crosshair + mine bar
	_center_controls()
	if _fps:
		_fps.size = Vector2(240, 60)
		_fps.position = Vector2(16, 180)   # left column under Day/Night + objective — clear of the top-right minimap
	if _toast:
		_toast.size = Vector2(vp.x, 28)
		_toast.position = Vector2(0, vp.y * 0.5 - 70)

	if _death_dim:
		_death_dim.position = Vector2.ZERO
		_death_dim.size = vp
		_death_title.size = Vector2(vp.x, 80)
		_death_title.position = Vector2(0, vp.y * 0.5 - 130)
		_death_sub.size = Vector2(vp.x, 56)                 # two lines (run stat + respawn hint)
		_death_sub.position = Vector2(0, vp.y * 0.5 - 52)
		_respawn_btn.position = Vector2(vp.x * 0.5 - 110, vp.y * 0.5 + 10)

## Persistent "current goal" line, fed by advancements as goals complete. Empty text hides it.
func set_objective(text: String) -> void:
	if _objective == null:
		return
	_objective.text = ("Goal: " + text) if text != "" else ""
	_objective.visible = text != ""

## A brief fading message in the centre of the screen.
func show_toast(text: String, color: Color = Color(1, 0.9, 0.7)) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.modulate = Color(color.r, color.g, color.b, 1.0)
	if _toast_tw and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_interval(1.1)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.6)

func flash_tool_weak(id: int) -> void:
	show_toast("Need a stronger pickaxe to mine %s" % VoxelTypes.name_of(id), Color(1, 0.55, 0.4))

func show_death() -> void:
	if _death_dim == null:
		return
	# Scoreboard moment: headline how far the run got, from the live Day/Night readout.
	if _time_plain != "":
		_death_sub.text = "You made it to %s\nPress R or click Respawn" % _time_plain
	for n in [_death_dim, _death_title, _death_sub, _respawn_btn]:
		n.visible = true
	_death_dim.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_death_dim, "modulate:a", 1.0, 0.6)
	_respawn_btn.grab_focus()

func hide_death() -> void:
	if _death_dim == null:
		return
	for n in [_death_dim, _death_title, _death_sub, _respawn_btn]:
		n.visible = false

## Crosshair reach feedback: 0 = nothing in reach (dim), 1 = a reachable block, 2 = a mob (red).
func set_crosshair_state(s: int) -> void:
	if _cross == null:
		return
	match s:
		2: _cross.modulate = Color(1.0, 0.45, 0.4, 1.0)
		1: _cross.modulate = Color(1, 1, 1, 1.0)
		_: _cross.modulate = Color(1, 1, 1, 0.5)

## A brief "✕" that POPS over the crosshair when an attack lands; bigger/brighter on a heavy/lethal blow.
func hit_marker(heavy := false) -> void:
	if _hitmark == null:
		return
	_hitmark.pivot_offset = _hitmark.size * 0.5   # centre the scale pivot so the pop stays on the crosshair
	var peak := 1.7 if heavy else 1.35
	var dur := 0.30 if heavy else 0.22
	_hitmark.modulate = Color(1.0, 0.85, 0.8, 1.0) if heavy else Color(1.0, 0.35, 0.3, 1.0)
	_hitmark.scale = Vector2(peak, peak)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_hitmark, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_hitmark, "modulate:a", 0.0, dur)

## Turn the breathing blood-moon vignette on/off (driven by main on the night phase change).
func set_blood_moon(on: bool) -> void:
	_blood_on = on
	if not on and _blood_vig:
		_blood_phase = 0.0

## Persistent day/night readout under the vitals.
func set_time_state(is_night: bool, n: int, blood: bool) -> void:
	if _time_label == null:
		return
	if blood:
		_time_label.text = "Night %d  ·  BLOOD MOON" % n
		_time_label.modulate = Color(1.0, 0.4, 0.35)
		_time_plain = "Night %d" % n
	elif is_night:
		_time_label.text = "Night %d" % n
		_time_label.modulate = Color(0.72, 0.8, 1.0)
		_time_plain = "Night %d" % n
	else:
		_time_label.text = "Day %d" % maxi(1, n)
		_time_label.modulate = Color(0.95, 0.95, 0.82)
		_time_plain = "Day %d" % maxi(1, n)

## Brief red screen flash when the player takes damage. `intensity` (0..1) scales the wash so a
## big hit reads harder; defaults to 0.45 so existing no-arg callers (e.g. the void plunge) are unchanged.
func flash_damage(intensity := 0.45) -> void:
	if _dmg_flash == null:
		return
	_dmg_flash.modulate.a = clampf(intensity, 0.0, 1.0)
	var tw := create_tween()
	tw.tween_property(_dmg_flash, "modulate:a", 0.0, 0.4)

## Light the screen edge(s) facing the attacker. local_dir is view-space (x=right, y=forward).
## Front hits deliberately don't light an edge — you can already see the attacker;
## only flanks and rear get the extra tell.
func indicate_damage_from(local_dir: Vector2) -> void:
	if _dir_flash.size() != 4:
		return
	var strengths := [maxf(-local_dir.x, 0.0), maxf(local_dir.x, 0.0), 0.0, maxf(-local_dir.y, 0.0)]
	for i in range(4):
		var s: float = strengths[i]
		if s < 0.35:
			continue
		var e: Control = _dir_flash[i]
		e.modulate.a = maxf(e.modulate.a, 0.85 * s)
		var tw2 := create_tween()
		tw2.tween_property(e, "modulate:a", 0.0, 0.6)

## Pulse the low-health vignette in (and out) every frame. Lives outside the FPS-overlay gate
## so it runs whether or not F3 is up.
func _update_vignette(delta: float) -> void:
	if _vignette == null:
		return
	var target := 0.0
	if _low_active:
		_low_phase += delta * 3.2
		target = _low_intensity * (0.45 + 0.55 * absf(sin(_low_phase)))   # breathe between dim and full
		# Heartbeat thump once per breathe cycle (~1s), deepening as health falls — an AUDIBLE danger
		# cue for players watching the world, not the hearts. Latched on _low_phase so it can't spam.
		if _hb and _hb.stream and _low_phase >= _hb_next:
			_hb_next = _low_phase + PI
			_hb.volume_db = lerpf(-13.0, -4.0, clampf(_low_intensity / 0.6, 0.0, 1.0))
			_hb.play()
	else:
		_hb_next = 0.0                                   # re-arm: next low-health episode thumps right away
	_vignette.modulate.a = move_toward(_vignette.modulate.a, target, delta * 2.2)
	# Blood-moon edge pulse (composes over the low-health one).
	if _blood_vig:
		var bt := 0.0
		if _blood_on:
			_blood_phase += delta * 1.2
			bt = 0.16 + 0.12 * absf(sin(_blood_phase))
		_blood_vig.modulate.a = move_toward(_blood_vig.modulate.a, bt, delta * 1.0)

func set_health(h: int, max_h: int) -> void:
	if _hearts == null: return
	var s := ""
	for i in range(max_h):
		s += "♥" if i < h else "♡"
	_hearts.text = s + "  %d/%d" % [h, max_h]   # exact count for quick/low-vision reads (glyphs kept)
	# Critical-health warning: vignette kicks in at the bottom third of health and deepens as it
	# drops. Off entirely at 0 (the death screen takes over from there).
	var frac := float(h) / float(maxi(1, max_h))
	_low_active = h > 0 and frac <= 0.34
	_low_intensity = clampf((0.34 - frac) / 0.34, 0.0, 1.0) * 0.6

func set_hunger(h: int, max_h: int) -> void:
	if _hunger == null: return
	var s := ""
	for i in range(max_h):
		s += "◆" if i < h else "◇"
	_hunger.text = s + "  %d/%d" % [h, max_h]

func set_mine_progress(p: float) -> void:
	var active := p > 0.0 and p < 1.0
	_mine_bg.visible = active
	_mine_fill.visible = active
	if active:
		_mine_fill.size.x = 64.0 * clampf(p, 0.0, 1.0)

## The block currently under the crosshair: its name, and — when your pickaxe is too weak to harvest
## it — why (red + a "needs a better pickaxe" tail). Empty name hides it. Fed from the player's
## per-frame look path, change-gated there so this only updates when the aimed block changes.
func set_target_name(txt: String, weak: bool = false) -> void:
	if _target_name == null:
		return
	if txt == "":
		_target_name.visible = false
		return
	_target_name.text = (txt + "  —  needs a better pickaxe") if weak else txt
	_target_name.modulate = Color(1.0, 0.55, 0.45) if weak else Color(0.92, 0.92, 0.98)
	_target_name.visible = true

func set_tool(tool_name: String) -> void:
	if _tool:
		_tool.text = "Tool: %s  (Q/E)" % tool_name

func set_armor(armor_name: String) -> void:
	if _armor:
		_armor.text = ("Armor: %s" % armor_name) if armor_name != "" else ""

func update_hotbar(slots: Array, selected: int) -> void:
	var first := _prev_counts.is_empty()        # don't pulse every starting slot on the first fill
	if first:
		_prev_counts.resize(_slots.size())
		_prev_counts.fill(0)
	for i in range(_slots.size()):
		var s = slots[i]
		var ui = _slots[i]
		if s.count > 0:
			var tex: Texture2D = ItemIcons.icon(s.id)
			ui.icon.texture = tex
			ui.swatch.color = Color(0, 0, 0, 0) if tex != null else VoxelTypes.color_of(s.id)
			ui.count.text = str(s.count) if s.count > 1 else ""   # a stack of 1 needs no number
		else:
			ui.icon.texture = null
			ui.swatch.color = Color(0, 0, 0, 0)
			ui.count.text = ""
		ui.panel.add_theme_stylebox_override("panel", _style_selected if i == selected else _style_normal)
		if not first and s.count > _prev_counts[i]:   # gained an item here — quick pickup pulse
			_pulse_slot(ui.panel)
		_prev_counts[i] = s.count
	var sel_id: int = slots[selected].id if selected >= 0 and selected < slots.size() else VoxelTypes.AIR
	if _block_name:
		_block_name.text = VoxelTypes.name_of(sel_id) if sel_id != VoxelTypes.AIR else ""
	# Selection-change feedback: pulse the newly-selected slot + a soft tick (skip the first fill).
	if _prev_sel != -1 and selected != _prev_sel and selected >= 0 and selected < _slots.size():
		_pulse_slot(_slots[selected].panel)
		if _snd_tick and _snd_tick.stream:
			_snd_tick.play()
	_prev_sel = selected

## Soft UI tick for actions that change the held item without touching the hotbar `selected` index
## (e.g. Q/E weapon switch), so they match the hotbar's own select click. Reuses the _snd_tick voice.
func tick_select() -> void:
	if _snd_tick and _snd_tick.stream:
		_snd_tick.play()

## A brief warm brighten of a hotbar slot when its stack grows — the "+1" pickup pop. Modulate
## only (not scale) so it never shifts the HBox layout.
func _pulse_slot(panel: Panel) -> void:
	if panel == null:
		return
	panel.modulate = Color(1.7, 1.7, 1.3)
	var tw := create_tween()
	tw.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.28)

## Quick warm flash of the hunger bar when the player eats (eating feedback).
func flash_hunger() -> void:
	if _hunger == null:
		return
	_hunger.modulate = Color(1.6, 1.2, 0.5)
	var tw := create_tween()
	tw.tween_property(_hunger, "modulate", Color(0.95, 0.65, 0.25), 0.45)

## Quick green pulse of the hearts when a heart regenerates (healing feedback). Returns to the
## hearts' resting RED tint (not white), since the hearts label is modulated red.
func flash_heal() -> void:
	if _hearts == null:
		return
	_hearts.modulate = Color(0.5, 1.7, 0.7)
	var tw := create_tween()
	tw.tween_property(_hearts, "modulate", Color(1.0, 0.27, 0.32), 0.45)
