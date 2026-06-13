class_name UITheme

## Shared look for the menu + pause screens: a wood-framed panel and chunky coloured
## buttons (blue primary / gold / teal normal / red danger), so both screens match.

const FONT_SIZE := 22

static func panel_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.28, 0.20, 0.13, 0.96)
	s.border_color = Color(0.15, 0.10, 0.05)
	s.set_border_width_all(5)
	s.set_corner_radius_all(8)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	return s

static func _palette(kind: String) -> Array:
	match kind:
		"primary": return [Color(0.20, 0.58, 0.86), Color(0.60, 0.86, 1.0)]
		"gold":    return [Color(0.80, 0.61, 0.27), Color(0.97, 0.84, 0.47)]
		"danger":  return [Color(0.67, 0.26, 0.22), Color(0.92, 0.46, 0.40)]
		_:         return [Color(0.22, 0.46, 0.53), Color(0.47, 0.74, 0.82)]   # teal normal

static func _btn_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(3)
	s.set_corner_radius_all(6)
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	s.content_margin_left = 16
	s.content_margin_right = 16
	return s

static func make_button(text: String, kind: String = "normal", min_size := Vector2(320, 0)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.88, 0.88, 0.88))
	b.add_theme_constant_override("outline_size", 5)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	var p := _palette(kind)
	var bg: Color = p[0]
	var border: Color = p[1]
	b.add_theme_stylebox_override("normal", _btn_box(bg, border))
	b.add_theme_stylebox_override("hover", _btn_box(bg.lightened(0.13), border))
	b.add_theme_stylebox_override("pressed", _btn_box(bg.darkened(0.15), border))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b
