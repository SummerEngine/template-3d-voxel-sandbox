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
var _hint: Label
var _hotbar: HBoxContainer
var _slots: Array = []          # each: {panel, swatch, count}
var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _dmg_flash: ColorRect
var _death_dim: ColorRect
var _death_title: Label
var _death_sub: Label
var _respawn_btn: Button
var _snd_click: AudioStreamPlayer
var _fps: Label
var _fps_accum := 0.0
var _toast: Label
var _toast_tw: Tween

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
	get_viewport().size_changed.connect(_layout)
	_layout()

func _process(delta: float) -> void:
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_fps.visible = not _fps.visible

func _build_styles() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0, 0, 0, 0.35)
	_style_normal.set_border_width_all(2)
	_style_normal.border_color = Color(0.7, 0.7, 0.7, 0.5)
	_style_selected = StyleBoxFlat.new()
	_style_selected.bg_color = Color(0, 0, 0, 0.45)
	_style_selected.set_border_width_all(3)
	_style_selected.border_color = Color(1, 1, 1, 0.95)

func _build() -> void:
	# Full-screen red damage flash (behind the HUD widgets, over the 3D world).
	_dmg_flash = ColorRect.new()
	_dmg_flash.color = Color(0.85, 0.0, 0.0, 1.0)
	_dmg_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmg_flash.modulate = Color(1, 1, 1, 0.0)
	add_child(_dmg_flash)

	_cross = Label.new()
	_cross.text = "+"
	_cross.add_theme_font_size_override("font_size", 22)
	add_child(_cross)

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
	add_child(_hearts)

	_hunger = Label.new()
	_hunger.add_theme_font_size_override("font_size", 24)
	_hunger.position = Vector2(16, 44)
	_hunger.modulate = Color(0.95, 0.65, 0.25)
	add_child(_hunger)

	_tool = Label.new()
	_tool.position = Vector2(16, 78)
	_tool.modulate = Color(0.85, 0.92, 1.0)
	add_child(_tool)

	_armor = Label.new()
	_armor.position = Vector2(16, 102)
	_armor.modulate = Color(0.65, 0.85, 1.0)
	add_child(_armor)

	_block_name = Label.new()
	_block_name.add_theme_font_size_override("font_size", 18)
	_block_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_block_name)

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
		panel.add_child(count)
		var key := Label.new()
		key.text = str(i + 1)
		key.add_theme_font_size_override("font_size", 11)
		key.position = Vector2(4, 2)
		key.modulate = Color(1, 1, 1, 0.5)
		panel.add_child(key)
		_hotbar.add_child(panel)
		_slots.append({"panel": panel, "swatch": swatch, "icon": icon, "count": count})

	_hint = Label.new()
	_hint.text = "WASD move  Ctrl sprint  Space jump (x2 fly)  1-9/scroll hotbar  Q/E weapon  LMB mine/attack  RMB place  G eat  C craft  M map  J goals  F5 view  F3 stats  Esc pause"
	_hint.modulate = Color(1, 1, 1, 0.65)
	add_child(_hint)

	_build_death_screen()

	# Transient centre-screen toast (tool-too-weak, advancements, etc.).
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate = Color(1, 1, 1, 0)
	add_child(_toast)

	# F3 debug overlay: live FPS + draw stats, top-right, hidden by default.
	_fps = Label.new()
	_fps.add_theme_font_size_override("font_size", 16)
	_fps.modulate = Color(0.7, 1.0, 0.7)
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps.visible = false
	add_child(_fps)

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
	_death_title.visible = false
	add_child(_death_title)

	_death_sub = Label.new()
	_death_sub.text = "Press R or click Respawn"
	_death_sub.add_theme_font_size_override("font_size", 20)
	_death_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_sub.modulate = Color(0.95, 0.9, 0.9, 0.85)
	_death_sub.visible = false
	add_child(_death_sub)

	_respawn_btn = Button.new()
	_respawn_btn.text = "Respawn"
	_respawn_btn.add_theme_font_size_override("font_size", 24)
	_respawn_btn.custom_minimum_size = Vector2(220, 56)
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
	_cross.position = Vector2(vp.x * 0.5 - 6, vp.y * 0.5 - 16)
	_mine_bg.position = Vector2(vp.x * 0.5 - 32, vp.y * 0.5 + 16)
	_mine_fill.position = _mine_bg.position
	var total_w := Inventory.HOTBAR * SLOT + (Inventory.HOTBAR - 1) * SLOT_PAD
	_hotbar.position = Vector2(vp.x * 0.5 - total_w * 0.5, vp.y - SLOT - 16)
	_block_name.position = Vector2(vp.x * 0.5 - 100, vp.y - SLOT - 44)
	_block_name.size = Vector2(200, 20)
	_hint.position = Vector2(16, vp.y - 26)
	if _fps:
		_fps.size = Vector2(240, 40)
		_fps.position = Vector2(vp.x - 256, 12)
	if _toast:
		_toast.size = Vector2(vp.x, 28)
		_toast.position = Vector2(0, vp.y * 0.5 - 70)

	if _death_dim:
		_death_dim.position = Vector2.ZERO
		_death_dim.size = vp
		_death_title.size = Vector2(vp.x, 80)
		_death_title.position = Vector2(0, vp.y * 0.5 - 130)
		_death_sub.size = Vector2(vp.x, 30)
		_death_sub.position = Vector2(0, vp.y * 0.5 - 40)
		_respawn_btn.position = Vector2(vp.x * 0.5 - 110, vp.y * 0.5 + 10)

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

## Brief red screen flash when the player takes damage.
func flash_damage() -> void:
	if _dmg_flash == null:
		return
	_dmg_flash.modulate.a = 0.45
	var tw := create_tween()
	tw.tween_property(_dmg_flash, "modulate:a", 0.0, 0.4)

func set_health(h: int, max_h: int) -> void:
	if _hearts == null: return
	var s := ""
	for i in range(max_h):
		s += "♥" if i < h else "♡"
	_hearts.text = s

func set_hunger(h: int, max_h: int) -> void:
	if _hunger == null: return
	var s := ""
	for i in range(max_h):
		s += "◆" if i < h else "◇"
	_hunger.text = s

func set_mine_progress(p: float) -> void:
	var active := p > 0.0 and p < 1.0
	_mine_bg.visible = active
	_mine_fill.visible = active
	if active:
		_mine_fill.size.x = 64.0 * clampf(p, 0.0, 1.0)

func set_tool(tool_name: String) -> void:
	if _tool:
		_tool.text = "Tool: %s  (Q/E)" % tool_name

func set_armor(armor_name: String) -> void:
	if _armor:
		_armor.text = ("Armor: %s" % armor_name) if armor_name != "" else ""

func update_hotbar(slots: Array, selected: int) -> void:
	for i in range(_slots.size()):
		var s = slots[i]
		var ui = _slots[i]
		if s.count > 0:
			var tex: Texture2D = ItemIcons.icon(s.id)
			ui.icon.texture = tex
			ui.swatch.color = Color(0, 0, 0, 0) if tex != null else VoxelTypes.color_of(s.id)
			ui.count.text = str(s.count)
		else:
			ui.icon.texture = null
			ui.swatch.color = Color(0, 0, 0, 0)
			ui.count.text = ""
		ui.panel.add_theme_stylebox_override("panel", _style_selected if i == selected else _style_normal)
	var sel_id: int = slots[selected].id if selected >= 0 and selected < slots.size() else VoxelTypes.AIR
	if _block_name:
		_block_name.text = VoxelTypes.name_of(sel_id) if sel_id != VoxelTypes.AIR else ""
