extends CanvasLayer

## A top-down minimap so the player can locate themselves. Samples the world's biome around
## the player into a small image (colour-coded by biome), centred on the player, north-up,
## with a yellow arrow showing facing. Press M to expand it to a wider world view.

const RES := 48                 # image resolution (pixels per side) — kept low; biome_at is costly
const STEP_MINI := 3            # world blocks per pixel in the corner map (coverage = RES*STEP)
const STEP_FULL := 9            # wider coverage when expanded
const UPDATE := 0.8             # seconds between resamples
const COLORS := {
	"water":    Color(0.20, 0.42, 0.75),
	"desert":   Color(0.86, 0.78, 0.52),
	"snow":     Color(0.93, 0.95, 0.98),
	"mountain": Color(0.55, 0.55, 0.58),
	"jungle":   Color(0.15, 0.40, 0.17),
	"forest":   Color(0.24, 0.52, 0.26),
	"meadow":   Color(0.46, 0.72, 0.40),
}

var world
var player
var _img: Image
var _tex: ImageTexture
var _rect: TextureRect
var _border: Panel
var _arrow: Label
var _t := 0.0
var _full := false
var _last_cx := 999999          # last sampled centre — skip redraw while standing still
var _last_cz := 999999

func setup(w, p) -> void:
	world = w
	player = p

func _ready() -> void:
	layer = 2
	_img = Image.create(RES, RES, false, Image.FORMAT_RGB8)
	_tex = ImageTexture.create_from_image(_img)

	_border = Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.35)
	st.set_border_width_all(3)
	st.border_color = Color(0.85, 0.78, 0.55, 0.9)
	st.set_corner_radius_all(4)
	_border.add_theme_stylebox_override("panel", st)
	add_child(_border)

	_rect = TextureRect.new()
	_rect.texture = _tex
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_border.add_child(_rect)

	_arrow = Label.new()
	_arrow.text = "^"
	_arrow.add_theme_font_size_override("font_size", 20)
	_arrow.add_theme_color_override("font_color", Color(1.0, 0.95, 0.25))
	_arrow.add_theme_constant_override("outline_size", 4)
	_arrow.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_arrow)

	_layout()
	_redraw()

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := minf(vp.x, vp.y) * 0.6 if _full else 170.0
	var pos := (vp - Vector2(s, s)) * 0.5 if _full else Vector2(vp.x - s - 16.0, 16.0)
	_border.position = pos
	_border.size = Vector2(s, s)
	_rect.position = Vector2(4, 4)
	_rect.size = Vector2(s - 8, s - 8)
	_arrow.size = Vector2(22, 24)
	_arrow.pivot_offset = Vector2(11, 12)
	_arrow.position = pos + Vector2(s, s) * 0.5 - Vector2(11, 12)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_full = not _full
		_layout()
		_redraw()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if world == null or player == null or not is_instance_valid(player):
		return
	# Spin the facing arrow every frame (north-up map, arrow points where the camera looks).
	var cam = player.get("camera")
	if cam and is_instance_valid(cam):
		var fwd: Vector3 = -cam.global_transform.basis.z
		_arrow.rotation = atan2(fwd.x, -fwd.z)
	_t -= delta
	if _t <= 0.0:
		_t = UPDATE
		var cx := int(player.global_position.x)
		var cz := int(player.global_position.z)
		var step := STEP_FULL if _full else STEP_MINI
		if absi(cx - _last_cx) >= step or absi(cz - _last_cz) >= step:
			_last_cx = cx
			_last_cz = cz
			_redraw()

func _redraw() -> void:
	if world == null or not world.has_method("biome_at"):
		return
	var step := STEP_FULL if _full else STEP_MINI
	var px := int(player.global_position.x)
	var pz := int(player.global_position.z)
	var mid := int(RES / 2.0)
	for y in range(RES):
		var wz := pz + (y - mid) * step
		for x in range(RES):
			var wx := px + (x - mid) * step
			var b: String = world.biome_at(wx, wz)
			_img.set_pixel(x, y, COLORS.get(b, Color(0.5, 0.5, 0.5)))
	_tex.update(_img)
