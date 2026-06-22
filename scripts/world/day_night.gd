class_name DayNight
extends Node

## Drives a day/night cycle: rotates the sun, fades its energy/colour, recolours the
## sky (with a dawn/dusk glow) and the ambient light. Emits phase_changed(is_night)
## on transitions so the world can spawn or clear night-time mobs.

signal phase_changed(is_night: bool)

const DAY_LENGTH := 480.0       # seconds for a full cycle (longer days = more prep time)
const NIGHT_CUTOFF := 0.20      # daylight below this counts as night — a real, lasting siege window

const DAY_SUN := Color(1.0, 0.97, 0.90)
const NIGHT_SUN := Color(0.55, 0.62, 0.85)
const DAY_TOP := Color(0.30, 0.52, 0.86)
const NIGHT_TOP := Color(0.02, 0.03, 0.08)
const DAY_HORIZON := Color(0.78, 0.86, 0.95)
const NIGHT_HORIZON := Color(0.05, 0.06, 0.12)
const DUSK_GLOW := Color(0.95, 0.45, 0.20)

const BLOOD_SUN := Color(0.95, 0.18, 0.12)
const BLOOD_TOP := Color(0.16, 0.02, 0.03)
const BLOOD_HORIZON := Color(0.50, 0.08, 0.06)

var time_of_day := 0.30         # 0..1 (0.25 = noon, 0.75 = midnight)
var blood_moon := false         # set by main.gd on siege nights — washes the night sky red
var _sun: DirectionalLight3D
var _env: Environment
var _sky: ShaderMaterial
var _was_night := false

func setup(sun: DirectionalLight3D, env: Environment, sky: ShaderMaterial) -> void:
	_sun = sun
	_env = env
	_sky = sky
	_apply()

func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / DAY_LENGTH, 1.0)
	_apply()

func _apply() -> void:
	if _sun == null:
		return
	var elev := sin(time_of_day * TAU)                 # +1 noon, -1 midnight
	var daylight: float = clampf(elev * 1.1 + 0.15, 0.0, 1.0)
	# Blood-moon wash: strongest deep at night, none by day, so dawn still breaks normally.
	var blood: float = (clampf(1.0 - daylight, 0.0, 1.0) * 0.85) if blood_moon else 0.0

	# Arc the sun east -> overhead -> west across the day (not a fixed bearing), so shadows rake
	# through the day and the visible sun/moon disc sweeps the sky. elev (= the direction's height)
	# still drives all the energy/colour math below; only the bearing is animated here. The 0.3 lean
	# keeps the noon pass slightly off dead-overhead (and avoids a degenerate look-at up-vector).
	var sun_ang := time_of_day * TAU
	var sun_dir := Vector3(cos(sun_ang), sin(sun_ang), 0.30).normalized()   # direction TO the sun
	_sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)
	_sun.light_energy = maxf(lerpf(0.04, 1.45, daylight), 0.32 * blood)   # eerie red moonlight
	_sun.light_color = NIGHT_SUN.lerp(DAY_SUN, daylight).lerp(BLOOD_SUN, blood)
	_sun.shadow_enabled = daylight > 0.1

	if _env:
		_env.ambient_light_energy = lerpf(0.18, 1.0, daylight) + 0.2 * blood

	if _sky:
		var glow: float = clampf(1.0 - absf(elev) * 3.0, 0.0, 1.0)   # peaks at dawn/dusk
		var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, daylight).lerp(DUSK_GLOW, glow * 0.6).lerp(BLOOD_HORIZON, blood)
		_sky.set_shader_parameter("top_color", NIGHT_TOP.lerp(DAY_TOP, daylight).lerp(BLOOD_TOP, blood))
		_sky.set_shader_parameter("horizon_color", horizon)
		_sky.set_shader_parameter("star_amount", clampf(1.0 - daylight * 2.0, 0.0, 1.0))
		if _env:
			_env.fog_light_color = horizon   # fog blends into the current sky horizon

	var night := daylight < NIGHT_CUTOFF
	if night != _was_night:
		_was_night = night
		phase_changed.emit(night)

func is_night() -> bool:
	return _was_night
