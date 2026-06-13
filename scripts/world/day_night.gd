class_name DayNight
extends Node

## Drives a day/night cycle: rotates the sun, fades its energy/colour, recolours the
## sky (with a dawn/dusk glow) and the ambient light. Emits phase_changed(is_night)
## on transitions so the world can spawn or clear night-time mobs.

signal phase_changed(is_night: bool)

const DAY_LENGTH := 300.0       # seconds for a full cycle
const NIGHT_CUTOFF := 0.12      # daylight below this counts as night

const DAY_SUN := Color(1.0, 0.97, 0.90)
const NIGHT_SUN := Color(0.55, 0.62, 0.85)
const DAY_TOP := Color(0.30, 0.52, 0.86)
const NIGHT_TOP := Color(0.02, 0.03, 0.08)
const DAY_HORIZON := Color(0.78, 0.86, 0.95)
const NIGHT_HORIZON := Color(0.05, 0.06, 0.12)
const DUSK_GLOW := Color(0.95, 0.45, 0.20)

var time_of_day := 0.30         # 0..1 (0.25 = noon, 0.75 = midnight)
var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _was_night := false

func setup(sun: DirectionalLight3D, env: Environment, sky: ProceduralSkyMaterial) -> void:
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

	_sun.rotation = Vector3(-asin(clampf(elev, -1.0, 1.0)), deg_to_rad(-45.0), 0.0)
	_sun.light_energy = lerpf(0.04, 1.45, daylight)
	_sun.light_color = NIGHT_SUN.lerp(DAY_SUN, daylight)
	_sun.shadow_enabled = daylight > 0.1

	if _env:
		_env.ambient_light_energy = lerpf(0.18, 1.0, daylight)

	if _sky:
		var glow: float = clampf(1.0 - absf(elev) * 3.0, 0.0, 1.0)   # peaks at dawn/dusk
		var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, daylight).lerp(DUSK_GLOW, glow * 0.6)
		_sky.sky_top_color = NIGHT_TOP.lerp(DAY_TOP, daylight)
		_sky.sky_horizon_color = horizon
		_sky.ground_horizon_color = horizon

	var night := daylight < NIGHT_CUTOFF
	if night != _was_night:
		_was_night = night
		phase_changed.emit(night)

func is_night() -> bool:
	return _was_night
