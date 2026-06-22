extends Node

## Seasons + a continuous, evolving climate. Instead of flipping between fixed weather
## states, four scalars drift smoothly over time (each driven by slow noise, biased by the
## season and the player's biome):
##   _cloud  — sky cloud coverage (clear blue <-> grey overcast)
##   _wet    — humidity / precipitation potential
##   _temp   — temperature (decides rain vs snow)
##   _wind   — wind strength (particle drift, wind audio, sandstorm trigger)
## The visible weather (clear / partly cloudy / overcast / rain / thunderstorm / snow) is
## DERIVED from these every frame, so days drift naturally — a bright clear morning can
## cloud over into an overcast afternoon and break into rain or snow. Deserts get sandstorms
## (dry + windy). Drives the sky's cloud layer, sun
## dimming, fog, screen tint, particles and audio beds. Runs after DayNight.

enum Season { SPRING, SUMMER, AUTUMN, WINTER }
const SEASON_NAMES := ["Spring", "Summer", "Autumn", "Winter"]
const SEASON_LENGTH := 240.0           # seconds per season
const SEASON_SAT := [1.05, 1.12, 0.96, 0.70]            # saturation grade per season
const SEASON_CLOUD := [0.05, -0.06, 0.10, 0.18]         # cloud bias per season
const SEASON_WET := [0.06, -0.02, 0.10, 0.12]           # humidity bias per season
const SEASON_TEMP := [0.52, 0.84, 0.44, 0.18]           # temperature baseline (<0.34 = snow)

enum Weather { CLEAR, RAIN, STORM, SANDSTORM, SNOW }
const BASE_FOG := 0.02         # clear-air baseline fog; lower = the horizon reads farther out

var player
var world
var hud
var day_night
var _env: Environment
var _sun: DirectionalLight3D
var _sky: ShaderMaterial

# season + climate
var season := Season.SUMMER
var _season_t := 0.0
var _clock := 0.0
var _cloud := 0.2
var _wet := 0.2
var _temp := 0.6
var _wind := 0.3
var _cloud_drift := 0.0
var _noise := FastNoiseLite.new()

# derived weather
var weather := Weather.CLEAR
var _intensity := 0.0                   # precipitation / sandstorm strength (0..1)
var _sheltered := false                 # true when the player has blocks overhead (cave / roof)
var _desert := false                    # cached: is the player over desert (throttled noise query)
var _clim_t := 0.0                       # throttle: recompute biome/shelter a few times a second

# visuals
var _tint: CanvasLayer
var _season_rect: ColorRect
var _weather_rect: ColorRect
var _flash_rect: ColorRect
var _label: Label
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _sand: GPUParticles3D
var _thunder_t := 0.0

# audio (one looping bed, fade-swapped on change; plus thunder one-shots)
var _bed: AudioStreamPlayer
var _bed_path_cur := ""
var _bed_db := -40.0
var _bed_target_db := -40.0
var _snd_thunder: AudioStreamPlayer

func setup(p, w, env: Environment, sun: DirectionalLight3D, sky: ShaderMaterial, h, dn) -> void:
	player = p
	world = w
	_env = env
	_sun = sun
	_sky = sky
	hud = h
	day_night = dn
	process_priority = 20
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 0.01
	_noise.seed = randi()
	_build_overlay()
	_build_particles()
	_build_audio()

## Persisted across save/load so a winter snow day doesn't reload as a summer clear sky.
## The climate scalars re-derive from noise; only the season clock needs restoring.
func save_state() -> Dictionary:
	return {"season": int(season), "season_t": _season_t}

func load_state(d: Dictionary) -> void:
	season = (clampi(int(d.get("season", season)), 0, 3)) as Season
	_season_t = float(d.get("season_t", _season_t))

# --- build ---------------------------------------------------------------------------
func _build_overlay() -> void:
	_tint = CanvasLayer.new()
	_tint.layer = -1
	add_child(_tint)
	_season_rect = _full_rect(Color(0, 0, 0, 0))
	_tint.add_child(_season_rect)
	_weather_rect = _full_rect(Color(0, 0, 0, 0))
	_tint.add_child(_weather_rect)
	_flash_rect = _full_rect(Color(1, 1, 1, 0))
	_tint.add_child(_flash_rect)

	var ui := CanvasLayer.new()
	ui.layer = 3
	add_child(ui)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_constant_override("outline_size", 5)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.position = Vector2(-300, 196)            # sits just below the top-right minimap
	_label.size = Vector2(284, 24)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(_label)

func _full_rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _unshaded(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	return m

func _build_particles() -> void:
	_rain = _make_particles(380, 0.55, Vector3(0, -1, 0), 2.0, 18.0, 26.0,
			Vector3(0, -34, 0), Vector3(0.03, 0.55, 0.03), Color(0.72, 0.80, 0.95, 0.65))
	_snow = _make_particles(240, 3.4, Vector3(0, -1, 0), 35.0, 1.2, 2.6,
			Vector3(0, -2.2, 0), Vector3(0.10, 0.10, 0.10), Color(1, 1, 1, 0.9))
	_sand = _make_particles(520, 1.1, Vector3(1, 0.05, 0), 24.0, 16.0, 30.0,
			Vector3(0, -1.5, 0), Vector3(0.14, 0.14, 0.14), Color(0.86, 0.70, 0.42, 0.7))
	for p in [_rain, _snow, _sand]:
		p.emitting = false
		add_child(p)

## Weather precipitation runs on GPUParticles3D: the game is CPU-bound with GPU headroom, so
## simulating these hundreds of particles on the GPU (not the main thread) is free performance.
## local_coords = true preserves the original look: the field stays centred on the player (the
## node is re-positioned each frame in _update_particles). CPUParticles3D defaulted this to
## true; GPUParticles3D defaults it to false, so we must set it explicitly to avoid a change.
func _make_particles(count: int, life: float, dir: Vector3, spread: float,
		vmin: float, vmax: float, grav: Vector3, msize: Vector3, col: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = life
	p.local_coords = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(17, 1.0, 17)
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = grav
	p.process_material = pm
	var bm := BoxMesh.new()
	bm.size = msize
	p.draw_pass_1 = bm
	p.material_override = _unshaded(col)
	return p

func _build_audio() -> void:
	_bed = AudioStreamPlayer.new()
	_bed.volume_db = -40.0
	if AudioServer.get_bus_index("Ambient") != -1:
		_bed.bus = "Ambient"
	add_child(_bed)
	_snd_thunder = _oneshot("res://assets/audio/weather/thunder.mp3", -3.0, "SFX")

func _oneshot(path: String, db: float, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.volume_db = db
	if AudioServer.get_bus_index(bus) != -1:
		p.bus = bus
	add_child(p)
	return p

# --- per-frame -----------------------------------------------------------------------
func _process(delta: float) -> void:
	if player == null or world == null or not is_instance_valid(player):
		return

	_season_t += delta
	if _season_t >= SEASON_LENGTH:
		_season_t -= SEASON_LENGTH
		season = ((season + 1) % 4) as Season
		if hud and hud.has_method("show_toast"):
			hud.show_toast("%s has arrived" % SEASON_NAMES[season], Color(0.8, 0.9, 1.0))

	_advance_climate(delta)

	# The expensive world queries (biome_at -> surface_height, and the overhead block scan)
	# don't need to run every frame — weather and cover change slowly. Recompute a few times
	# a second and cache; this is the single biggest per-frame CPU saving.
	_clim_t -= delta
	if _clim_t <= 0.0:
		_clim_t = 0.3
		_derive_weather()
		_sheltered = _check_sheltered()
		_desert = world.has_method("_is_desert") and world._is_desert(int(player.global_position.x), int(player.global_position.z))

	_apply_visuals(delta)
	_update_particles()
	if weather == Weather.STORM and _intensity > 0.4:
		_update_lightning(delta)
	_update_audio(delta)
	_apply_label()

func _n01(v: float) -> float:
	return clampf(v * 0.5 + 0.5, 0.0, 1.0)

## Drift the four climate scalars toward noise-driven targets (smooth, gradual).
func _advance_climate(delta: float) -> void:
	_clock += delta
	var desert: bool = _desert        # cached + refreshed in the throttled climate block (was a per-frame noise query)

	var nc := _n01(_noise.get_noise_1d(_clock * 2.0))
	var nw := _n01(_noise.get_noise_1d(_clock * 2.0 + 4000.0))
	var nv := _n01(_noise.get_noise_1d(_clock * 2.5 + 9000.0))

	var s: int = season
	var cloud_t: float = clampf(nc + SEASON_CLOUD[s] + (-0.10 if desert else 0.0), 0.0, 1.0)
	var wet_t: float = clampf(nw + SEASON_WET[s] + (-0.45 if desert else 0.0), 0.0, 1.0)
	var temp_t: float = clampf(SEASON_TEMP[s] + (nc - 0.5) * 0.15 + (0.25 if desert else 0.0), 0.0, 1.0)
	var wind_t: float = clampf(nv + (0.12 if desert else 0.0), 0.0, 1.0)

	_cloud = move_toward(_cloud, cloud_t, delta * 0.08)
	_wet = move_toward(_wet, wet_t, delta * 0.06)
	_temp = move_toward(_temp, temp_t, delta * 0.05)
	_wind = move_toward(_wind, wind_t, delta * 0.15)
	_cloud_drift += delta * (0.004 + _wind * 0.02)

## Map the climate scalars to a discrete weather + intensity for particles/overlay/audio.
func _derive_weather() -> void:
	var px := int(player.global_position.x)
	var pz := int(player.global_position.z)
	var biome := "meadow"
	if world.has_method("biome_at"):
		biome = world.biome_at(px, pz)
	var precip := clampf((_wet - 0.5) / 0.5, 0.0, 1.0) * clampf((_cloud - 0.45) / 0.55, 0.0, 1.0)

	if biome == "desert":
		# Hot and dry: only sandstorms or clear skies here — never rain or snow.
		if _wind > 0.55 and _wet < 0.5:
			weather = Weather.SANDSTORM
			_intensity = clampf((_wind - 0.55) / 0.45, 0.3, 1.0)
		else:
			weather = Weather.CLEAR
			_intensity = 0.0
		return
	if precip > 0.06:
		# Snow only where it's actually cold: snow / mountain biomes, or temperate land in winter.
		var cold: bool = biome == "snow" or biome == "mountain" or (season == Season.WINTER and biome != "jungle")
		if cold:
			weather = Weather.SNOW
			_intensity = precip
		elif precip > 0.62:
			weather = Weather.STORM
			_intensity = precip
		else:
			weather = Weather.RAIN
			_intensity = precip
	else:
		weather = Weather.CLEAR
		_intensity = 0.0

# --- visuals -------------------------------------------------------------------------
func _apply_visuals(_delta: float) -> void:
	_env.adjustment_enabled = true
	_env.adjustment_saturation = lerpf(SEASON_SAT[season], 0.85, _cloud * 0.5)

	# Sky clouds (always reflect coverage, independent of rain).
	if _sky:
		_sky.set_shader_parameter("cloud_cover", _cloud)
		_sky.set_shader_parameter("cloud_time", _cloud_drift)

	var k := _intensity
	var fog := BASE_FOG + _cloud * 0.012
	var wcol := Color(0, 0, 0, 0)
	var dim := lerpf(1.0, 0.62, _cloud)            # cloudy days are dimmer
	match weather:
		Weather.RAIN:
			fog += 0.05 * k
			wcol = Color(0.22, 0.27, 0.36, 0.20 * k)
			dim *= lerpf(1.0, 0.78, k)
		Weather.STORM:
			fog += 0.06 * k
			wcol = Color(0.12, 0.14, 0.20, 0.34 * k)
			dim *= lerpf(1.0, 0.55, k)
		Weather.SANDSTORM:
			fog = lerpf(BASE_FOG, 0.165, k)
			wcol = Color(0.86, 0.60, 0.32, 0.46 * k)
			dim = lerpf(1.0, 0.70, k)
			_env.fog_light_color = Color(0.86, 0.62, 0.34)
		Weather.SNOW:
			fog += 0.045 * k
			wcol = Color(0.82, 0.86, 0.95, 0.20 * k)
			dim *= lerpf(1.0, 0.86, k)
		_:
			# clear: a faint grey wash only when genuinely overcast
			wcol = Color(0.55, 0.57, 0.62, clampf((_cloud - 0.55) * 0.5, 0.0, 0.16))
	_env.fog_density = fog
	if _sheltered:
		wcol.a *= 0.3                                   # weather barely shows through a roof
	# Season tint sits under the weather tint (very subtle).
	_season_rect.color = Color(0.7, 0.85, 1.0, 0.05) if season == Season.WINTER else \
			(Color(0.95, 0.55, 0.25, 0.07) if season == Season.AUTUMN else Color(0, 0, 0, 0))
	_weather_rect.color = wcol
	_sun.light_energy *= dim
	_env.ambient_light_energy *= lerpf(1.0, 0.78, _cloud)

func _update_particles() -> void:
	var base: Vector3 = player.global_position
	_rain.global_position = base + Vector3(0, 13, 0)
	_snow.global_position = base + Vector3(0, 13, 0)
	_sand.global_position = base + Vector3(0, 4, 0)
	# No falling precipitation when the player is under cover (cave, roof) — it shouldn't
	# rain or snow down through the ceiling while you're digging or indoors.
	var open := not _sheltered
	_rain.emitting = open and (weather == Weather.RAIN or weather == Weather.STORM)
	_snow.emitting = open and weather == Weather.SNOW
	_sand.emitting = open and weather == Weather.SANDSTORM
	if _sand.emitting:
		(_sand.process_material as ParticleProcessMaterial).direction = Vector3(1, 0.05, 0.3).normalized()

## True when there are solid blocks just above the player's head (cave / building roof),
## so precipitation and its screen tint are suppressed indoors.
func _check_sheltered() -> bool:
	if world == null:
		return false
	var px := floori(player.global_position.x)
	var py := floori(player.global_position.y)
	var pz := floori(player.global_position.z)
	for dy in range(2, 10):
		var b: int = world.get_block(px, py + dy, pz)
		if b != VoxelTypes.AIR and b != VoxelTypes.WATER and b != VoxelTypes.LEAVES:
			return true
	return false

func _update_lightning(delta: float) -> void:
	_thunder_t -= delta
	if _thunder_t <= 0.0:
		_thunder_t = randf_range(6.0, 14.0)
		_flash_rect.color = Color(1, 1, 1, 0.55)
		var tw := create_tween()
		tw.tween_property(_flash_rect, "color:a", 0.0, 0.5)
		if _snd_thunder and _snd_thunder.stream:
			var tw_t := create_tween()           # thunder lags the flash — that gap reads as distance
			tw_t.tween_interval(randf_range(0.4, 1.8))
			tw_t.tween_callback(_snd_thunder.play)

var _label_cache := ""
func _apply_label() -> void:
	if not _label:
		return
	var t := "%s  ·  %s" % [SEASON_NAMES[season], _condition_text()]
	if t != _label_cache:                        # runs every frame; only touch the Label when it changes
		_label_cache = t
		_label.text = t

func _condition_text() -> String:
	match weather:
		Weather.SANDSTORM: return "Sandstorm"
		Weather.SNOW:      return "Snow" if _intensity > 0.45 else "Light Snow"
		Weather.STORM:     return "Thunderstorm"
		Weather.RAIN:      return "Rain" if _intensity > 0.45 else "Light Rain"
		_:
			if _cloud < 0.25:
				return "Clear"
			elif _cloud < 0.50:
				return "Partly Cloudy"
			elif _cloud < 0.72:
				return "Cloudy"
			return "Overcast"

# --- audio ---------------------------------------------------------------------------
## Which looping ambience suits the current sky, and how loud it should be.
func _desired_bed_path() -> String:
	match weather:
		Weather.SANDSTORM: return "res://assets/audio/weather/sandstorm.mp3"
		Weather.RAIN, Weather.STORM: return "res://assets/audio/weather/rain.mp3"
		Weather.SNOW: return "res://assets/audio/weather/wind_gust.mp3"
		_:
			# clear: birds on calm clear days, gusty wind once it clouds over
			return "res://assets/audio/weather/wind_gust.mp3" if _cloud >= 0.42 \
					else "res://assets/audio/weather/clear.mp3"

func _desired_bed_db() -> float:
	match weather:
		Weather.SANDSTORM: return lerpf(-20.0, -7.0, _intensity)
		Weather.RAIN, Weather.STORM: return lerpf(-22.0, -9.0, _intensity)
		Weather.SNOW: return lerpf(-30.0, -16.0, clampf(_wind, 0.0, 1.0))
		_:
			if _cloud >= 0.42:
				return lerpf(-30.0, -12.0, clampf((_cloud - 0.42) / 0.58 + _wind * 0.4, 0.0, 1.0))
			return lerpf(-30.0, -14.0, clampf(1.0 - _cloud * 2.2, 0.0, 1.0))

func _update_audio(delta: float) -> void:
	var path := _desired_bed_path()
	if path != _bed_path_cur:
		_bed_target_db = -42.0                      # fade the old bed out, then swap
		if _bed_db <= -38.0:
			_bed_path_cur = path
			if path == "" or not ResourceLoader.exists(path):
				_bed.stop()
			else:
				var st := load(path) as AudioStreamMP3
				if st:
					st.loop = true
				_bed.stream = st
				_bed.play()
	else:
		_bed_target_db = _desired_bed_db()
	_bed_db = lerpf(_bed_db, _bed_target_db, 1.0 - exp(-delta * 3.0))
	_bed.volume_db = _bed_db
