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

## A consistent dark panel for the in-game content screens (crafting, chest, advancements), so
## they read as one dialog system instead of three slightly-different boxes. Defined once here.
static func dialog_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.11, 0.14, 0.97)
	s.border_color = Color(0.55, 0.58, 0.66, 0.9)
	s.set_border_width_all(3)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(22)
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

static func _slot_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(2)
	s.border_color = border
	s.set_corner_radius_all(3)
	return s

## Style a clickable Button as a dark inventory slot (matching the hotbar + crafting swatches), so
## the chest grid stops rendering as default grey buttons inside the dark dialog.
static func style_slot_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _slot_box(Color(0, 0, 0, 0.4), Color(0.6, 0.6, 0.65, 0.6)))
	b.add_theme_stylebox_override("hover", _slot_box(Color(0, 0, 0, 0.5), Color(0.9, 0.92, 1.0, 0.9)))
	b.add_theme_stylebox_override("pressed", _slot_box(Color(0, 0, 0, 0.55), Color(0.9, 0.92, 1.0, 0.95)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE

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
	# A muted disabled look so "Owned"/unaffordable buttons read as intentional, not unstyled.
	b.add_theme_stylebox_override("disabled", _btn_box(bg.darkened(0.45), border.darkened(0.4)))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

## A labelled settings row: "Name [====slider====] value". `fmt` formats the value label
## from the slider value; `on_change` is called with the new value as the user drags. Used by
## both the main-menu and pause settings panels so they look and behave identically.
static func setting_row(label_text: String, minv: float, maxv: float, step: float,
		value: float, fmt: Callable, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name := Label.new()
	name.text = label_text
	name.custom_minimum_size = Vector2(150, 0)
	name.add_theme_font_size_override("font_size", FONT_SIZE)
	name.add_theme_color_override("font_color", Color(1, 1, 1))
	row.add_child(name)
	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(220, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var val := Label.new()
	val.custom_minimum_size = Vector2(64, 0)
	val.text = fmt.call(value)
	val.add_theme_font_size_override("font_size", FONT_SIZE)
	val.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	slider.value_changed.connect(func(v):
		val.text = fmt.call(v)
		on_change.call(v))
	return row
