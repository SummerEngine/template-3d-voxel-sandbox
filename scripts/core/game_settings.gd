class_name GameSettings

## Persistent player settings (volume, mouse sensitivity, view distance), saved to
## user://settings.cfg and applied to the live game. Static so any scene can read/apply
## them; load_cfg() runs once on first access. The main menu applies audio (the buses
## persist across scenes); main.gd also applies the gameplay settings once the player +
## world exist. The settings panels (main menu + pause) write these and call save_cfg().

const PATH := "user://settings.cfg"

# Audio is stored as linear 0..1 (slider-friendly); converted to dB on apply.
static var master := 1.0
static var music := 1.0
static var sfx := 1.0
static var sensitivity := 1.0      # multiplier on the player's base mouse sensitivity
static var render_radius := 3      # chunks streamed around the player (2..8)
static var keybinds := {}          # action name -> physical keycode (overrides; see InputActions)
static var _loaded := false

static func load_cfg() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	master = float(cf.get_value("audio", "master", master))
	music = float(cf.get_value("audio", "music", music))
	sfx = float(cf.get_value("audio", "sfx", sfx))
	sensitivity = float(cf.get_value("input", "sensitivity", sensitivity))
	render_radius = int(cf.get_value("world", "render_radius", render_radius))
	var kb = cf.get_value("input", "keybinds", {})
	if kb is Dictionary:
		keybinds = kb

static func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master)
	cf.set_value("audio", "music", music)
	cf.set_value("audio", "sfx", sfx)
	cf.set_value("input", "sensitivity", sensitivity)
	cf.set_value("world", "render_radius", render_radius)
	cf.set_value("input", "keybinds", keybinds)
	cf.save(PATH)

static func _db(linear: float) -> float:
	return linear_to_db(clampf(linear, 0.0001, 1.0))

## Master + SFX go straight to their buses; Music routes through the audio ducker so its
## ducking baseline updates too (otherwise an impact-duck would restore the wrong level).
static func apply_audio(tree: SceneTree) -> void:
	load_cfg()
	_set_bus("Master", master)
	_set_bus("SFX", sfx)
	if tree:
		tree.call_group("ducker", "set_base_volume", "Music", _db(music))

static func _set_bus(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, _db(linear))

## Gameplay settings need the live nodes, so main.gd calls this after they're built.
static func apply_gameplay(player, world) -> void:
	load_cfg()
	if player and player.has_method("set_sensitivity"):
		player.set_sensitivity(sensitivity)
	if world and world.has_method("set_render_radius"):
		world.set_render_radius(render_radius)
