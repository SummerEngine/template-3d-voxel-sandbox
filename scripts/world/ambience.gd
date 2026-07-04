extends Node3D

## "Living world" ambience that follows the player: fireflies drift around at night, soft
## pollen/dust motes float by day, and the odd shooting star streaks the night sky. All cheap
## CPU particles parented here. The mote emitters use world-space particles (so motes linger
## where they were emitted as you move) and a wide emission box scatters them all around the
## player; only one set emits at a time, swapped by DayNight, the other fades over its lifetime.

var player                              # Player
var day_night                           # DayNight
var _has_atmo := false                  # cached: does the player expose atmosphere_blocked() (invariant)

const AREA := 18.0                      # motes scatter within this radius of the player
const NIGHT_BED := "res://assets/audio/ambient/night.wav"   # looping crickets/owls bed
const MUSIC_DAY := "res://assets/audio/music/day_explore.mp3"     # peaceful day exploration loop
const MUSIC_NIGHT := "res://assets/audio/music/night_tension.mp3" # tense night loop
var _fireflies: CPUParticles3D
var _pollen: CPUParticles3D
var _night_bed: AudioStreamPlayer       # crossfaded in at night, out by day
var _music_day: AudioStreamPlayer       # day/night gameplay music on the Music bus, crossfaded by time of day
var _music_night: AudioStreamPlayer
var _star_t := 20.0
var _rng := RandomNumberGenerator.new()

func setup(p, dn) -> void:
	player = p
	day_night = dn
	_has_atmo = p != null and p.has_method("atmosphere_blocked")

func _ready() -> void:
	_rng.randomize()
	_fireflies = _make_motes(true)
	_pollen = _make_motes(false)
	add_child(_fireflies)
	add_child(_pollen)
	_star_t = _rng.randf_range(14.0, 32.0)
	# Looping night ambience (crickets/owls), faded in only at night via _process.
	_night_bed = AudioStreamPlayer.new()
	if ResourceLoader.exists(NIGHT_BED):
		var s = load(NIGHT_BED)
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_night_bed.stream = s
	_night_bed.volume_db = -80.0
	if AudioServer.get_bus_index("Ambient") != -1:
		_night_bed.bus = "Ambient"
	add_child(_night_bed)
	if _night_bed.stream:
		_night_bed.play()
	# Day/night gameplay music — two looping tracks on the Music bus, crossfaded by time of day.
	_music_day = _make_music(MUSIC_DAY)
	_music_night = _make_music(MUSIC_NIGHT)

## A looping music track on the Music bus, started silent (crossfaded in by _process).
func _make_music(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		var s = load(path)
		if s is AudioStreamMP3:
			s.loop = true
		p.stream = s
	p.volume_db = -80.0
	if AudioServer.get_bus_index("Music") != -1:
		p.bus = "Music"
	add_child(p)
	if p.stream:
		p.play()
	return p

## One drifting-mote emitter. firefly=true: glowing yellow-green, hovering; false: soft pale
## pollen that sinks and drifts on a breeze. A 0->1->0 alpha ramp makes each mote twinkle in
## and out instead of popping.
func _make_motes(firefly: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.09, 0.09) if firefly else Vector3(0.05, 0.05, 0.05)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	if firefly:
		mat.albedo_color = Color(0.95, 1.0, 0.5, 1.0)
		mat.emission = Color(0.85, 1.0, 0.35)
		mat.emission_energy_multiplier = 3.0
	else:
		mat.albedo_color = Color(1.0, 1.0, 0.95, 0.5)
		mat.emission = Color(1.0, 1.0, 0.9)
		mat.emission_energy_multiplier = 0.25
	bm.material = mat
	p.mesh = bm
	p.amount = 46 if firefly else 40
	p.lifetime = 4.5 if firefly else 7.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(AREA, 4.0 if firefly else 6.0, AREA)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO if firefly else Vector3(0.2, -0.25, 0.0)
	p.initial_velocity_min = 0.15 if firefly else 0.1
	p.initial_velocity_max = 0.6 if firefly else 0.35
	p.damping_min = 0.2
	p.damping_max = 0.7
	var g := Gradient.new()
	var c: Color = mat.albedo_color
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([
		Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, c.a), Color(c.r, c.g, c.b, 0.0)])
	p.color_ramp = g
	p.emitting = false
	return p

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or day_night == null:
		return
	var night: bool = day_night.is_night()
	# Suppress motes when the player is underground/under cover or submerged (no sunbeam pollen in
	# a cave, no dry dust underwater) — the player computes this on a throttle.
	var blocked: bool = _has_atmo and player.atmosphere_blocked()
	var fire_on: bool = night and not blocked
	var pollen_on: bool = (not night) and not blocked
	var pos: Vector3 = player.global_position
	# Only reposition an emitter that is actually emitting (its origin is refreshed on the exact
	# frame it turns on) — no wasted transform writes on the idle/off emitter.
	if fire_on:
		_fireflies.global_position = pos + Vector3(0.0, 2.5, 0.0)
	if pollen_on:
		_pollen.global_position = pos + Vector3(0.0, 3.0, 0.0)
	_fireflies.emitting = fire_on
	_pollen.emitting = pollen_on
	# Crossfade the night ambience bed (audible only at night, and not while underground/submerged).
	# Skip the write once the fade has settled so we don't marshal a no-op volume write every frame.
	if _night_bed and _night_bed.stream:
		var want := -15.0 if fire_on else -80.0
		if not is_equal_approx(_night_bed.volume_db, want):
			_night_bed.volume_db = move_toward(_night_bed.volume_db, want, delta * 30.0)
	# Crossfade the gameplay music: peaceful by day, tense by night (plays underground too — music,
	# unlike the ambience bed, isn't gated on cover).
	if _music_day and _music_day.stream:
		var want_day := -80.0 if night else -16.0
		if not is_equal_approx(_music_day.volume_db, want_day):
			_music_day.volume_db = move_toward(_music_day.volume_db, want_day, delta * 8.0)
	if _music_night and _music_night.stream:
		var want_night := -13.0 if night else -80.0
		if not is_equal_approx(_music_night.volume_db, want_night):
			_music_night.volume_db = move_toward(_music_night.volume_db, want_night, delta * 8.0)
	if night:
		_star_t -= delta
		if _star_t <= 0.0:
			_star_t = _rng.randf_range(16.0, 40.0)
			_spawn_shooting_star(pos)

## A bright emissive streak high above the player, tweened across the sky and fading out.
func _spawn_shooting_star(near: Vector3) -> void:
	var star := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.16, 0.9)   # long on -Z (look_at forward) so the streak aligns to its path
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.95, 0.8)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = mat
	star.mesh = bm
	add_child(star)
	var a := _rng.randf_range(0.0, TAU)
	var start := near + Vector3(cos(a) * 45.0, 40.0, sin(a) * 45.0)
	var travel := Vector3(-cos(a) * 65.0, -22.0, -sin(a) * 65.0)
	star.global_position = start
	if travel.length() > 0.01:
		star.look_at(start + travel, Vector3.UP)   # orient the streak along its travel direction
	var tw := create_tween()
	tw.tween_property(star, "global_position", start + travel, 1.3).set_trans(Tween.TRANS_LINEAR)
	tw.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.9).set_delay(0.4)
	tw.tween_callback(star.queue_free)
