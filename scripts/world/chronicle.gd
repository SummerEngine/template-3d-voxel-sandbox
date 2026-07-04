extends CanvasLayer

## Feature #4 — The Chronicle Stone.
## Place a Monolith and the world auto-engraves the deeds you actually do (first diamond, kill
## milestones, blood moons survived, nights endured) onto the BOUND monolith — the last one you
## placed or used. Engravings carry the day number + season. Every few lines the obelisk grows a
## Polished-Stone block taller, so a well-travelled save sprouts a tall monument. Right-click it
## to read its Annals.
##
## Reuses: world.monoliths (cell -> Array[String], persisted), block_placed_at signal, the
## player milestone signals, set_block self-stacking, UITheme.dialog_box.

const STACK_EVERY := 5        # grow the obelisk one block per this many engravings
const MAX_STACK := 6
const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]

var world
var player
var day_night
var weather

var _bound: Vector3i = Vector3i(2147483647, 0, 0)
var _has_bound := false
var _day := 1
var _kills := 0
var _first_diamond := false
var _panel: Control
var _list: VBoxContainer
var _open := false

func setup(w, p, dn, wx) -> void:
	world = w
	player = p
	day_night = dn
	weather = wx
	if day_night and day_night.has_signal("phase_changed"):
		day_night.phase_changed.connect(_on_phase)
	if player:
		if player.has_signal("block_placed_at"):
			player.block_placed_at.connect(_on_placed)
		if player.has_signal("block_harvested"):
			player.block_harvested.connect(_on_harvested)
		if player.has_signal("mob_died_at"):
			player.mob_died_at.connect(_on_kill)
		if player.has_signal("night_survived"):
			player.night_survived.connect(_on_night)

func _ready() -> void:
	layer = 7
	add_to_group("chronicle")
	_build_panel()
	# Re-bind to the most-recent already-placed monolith on a loaded save, so the Annals work
	# immediately after Load (the player won't have re-placed it).
	if world and not world.monoliths.is_empty():
		for cell in world.monoliths.keys():
			_bound = cell
			_has_bound = true

# ---------- deed hooks ----------
func _on_phase(is_night: bool) -> void:
	if not is_night:
		_day += 1                               # a new day dawns

func _on_placed(cell: Vector3i, id: int) -> void:
	if id == VoxelTypes.MONOLITH:
		_bound = cell
		_has_bound = true
		if not world.monoliths.has(cell):
			world.monoliths[cell] = []
		_engrave("Raised a monolith to mark this ground.")

func _on_harvested(id: int) -> void:
	if id == VoxelTypes.DIAMOND_ORE and not _first_diamond:
		_first_diamond = true
		_engrave("Struck the first diamond from the deep stone.")

func _on_kill(_pos: Vector3) -> void:
	_kills += 1
	if _kills == 1:
		_engrave("Felled the first of the night's dead.")
	elif _kills == 25:
		_engrave("Twenty-five foes laid low.")
	elif _kills == 100:
		_engrave("A hundred slain — the dead know this name.", true)

func _on_night() -> void:
	# Read the LATCHED blood flag, not the live one: main.gd clears day_night.blood_moon at dawn
	# BEFORE emitting night_survived (which drives this), so the live flag is always false here.
	# last_blood captures the night that was actually survived (set in main.gd before the clear).
	if day_night and day_night.last_blood:
		_engrave("Endured a blood-rimmed moon.", true)
	elif _day <= 2 and _has_bound and world.monoliths.has(_bound) and world.monoliths[_bound].size() <= 1:
		_engrave("Survived the first night.")   # gated on a fresh stone so a loaded save can't re-fire it

# ---------- engraving ----------
func _engrave(text: String, milestone: bool = false) -> void:
	if not _has_bound or world == null or not world.monoliths.has(_bound):
		return
	var season := ""
	if weather:
		season = SEASONS[clampi(int(weather.season), 0, 3)]
	var line := "Day %d · %s — %s" % [_day, season, text] if season != "" else "Day %d — %s" % [_day, text]
	var lines: Array = world.monoliths[_bound]
	if not lines.is_empty() and String(lines[lines.size() - 1]) == line:
		return                                   # de-dupe identical back-to-back deeds
	lines.append(line)
	world.monoliths[_bound] = lines
	_grow_if_due(lines.size())
	if player and player.hud and player.hud.has_method("show_toast"):
		# Surface WHAT was recorded, and let milestone deeds land brighter than routine ones.
		var tint := Color(1.0, 0.86, 0.55) if milestone else Color(0.74, 0.78, 0.9)
		player.hud.show_toast("Engraved: " + text, tint)
	if _open:
		_refresh()

func _grow_if_due(count: int) -> void:
	@warning_ignore("integer_division")
	var want: int = mini(count / STACK_EVERY, MAX_STACK)
	for k in range(1, want + 1):
		var c := _bound + Vector3i(0, k, 0)
		# Only grow into NATURAL air — never into player-edited space (a carved room, a gap in a
		# build). Guarding just for AIR would let the column punch through a player's interior.
		if world.get_block(c.x, c.y, c.z) == VoxelTypes.AIR and not world.overrides.has(c):
			world.set_block(c.x, c.y, c.z, VoxelTypes.POLISHED_STONE)
			# The monument physically rose — make the growth felt at the pillar, not silent.
			if player and player.hud and player.hud.has_method("show_toast"):
				player.hud.show_toast("The monolith rises.", Color(0.8, 0.85, 1.0))
			if player and player.has_method("_emit_burst"):
				player._emit_burst(Vector3(c) + Vector3(0.5, 0.5, 0.5), Color(0.72, 0.74, 0.8), 10, 0.7, 30.0, 0.5, 1.4, 2.0)

# ---------- Annals UI ----------
func _build_panel() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.dialog_box())
	center.add_child(frame)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(520, 0)
	frame.add_child(vb)
	var title := Label.new()
	title.text = "ANNALS OF THE MONOLITH"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	vb.add_child(_list)
	var close_btn := UITheme.make_button("Close", "normal", Vector2(150, 40))
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close_annals)
	vb.add_child(close_btn)
	_panel.visible = false

func open_annals(cell: Vector3i) -> void:
	if world and world.monoliths.has(cell):
		_bound = cell
		_has_bound = true
	_refresh()
	_open = true
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_annals() -> void:
	if not _open:
		return
	_open = false
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_open() -> bool:
	return _open

func _refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var lines: Array = []
	if _has_bound and world and world.monoliths.has(_bound):
		lines = world.monoliths[_bound]
	if lines.is_empty():
		var empty := Label.new()
		empty.text = "The stone is bare. Your deeds will write themselves here."
		empty.modulate = Color(1, 1, 1, 0.6)
		_list.add_child(empty)
		return
	var start: int = maxi(0, lines.size() - 14)
	for i in range(start, lines.size()):
		var row := Label.new()
		row.text = "• " + String(lines[i])
		row.add_theme_font_size_override("font_size", 16)
		_list.add_child(row)
