extends Node

## Ensures Music / Ambient / SFX audio buses exist (created at runtime, routed to
## Master) and briefly ducks Music + Ambient on impacts so SFX punches through.
## Added to the scene by main.gd / main_menu.gd and called via the "ducker" group:
##   get_tree().call_group("ducker", "duck", 0.5, 0.45)

const BUSES := ["Music", "Ambient", "SFX"]
const WEIGHTS := {"Music": 0.9, "Ambient": 0.7}   # SFX is never ducked

var _initial: Dictionary = {}
var _tween: Tween
var _lowpass_idx := -1      # index of the underwater low-pass effect on the Master bus
var _underwater := false

func _ready() -> void:
	add_to_group("ducker")
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	for b in WEIGHTS.keys():
		var idx := AudioServer.get_bus_index(b)
		if idx != -1:
			_initial[b] = AudioServer.get_bus_volume_db(idx)
	_setup_underwater()

## A low-pass filter on Master, bypassed until the player's head goes underwater — then
## everything (music, ambient, SFX) muffles, the classic submerged sound. Toggled via the
## "ducker" group: get_tree().call_group("ducker", "set_underwater", true/false).
func _setup_underwater() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master == -1:
		return
	# The Master bus persists across scene changes, so reuse a low-pass a previous scene's
	# ducker already added instead of stacking a fresh effect on every scene load.
	for i in range(AudioServer.get_bus_effect_count(master)):
		if AudioServer.get_bus_effect(master, i) is AudioEffectLowPassFilter:
			_lowpass_idx = i
			AudioServer.set_bus_effect_enabled(master, i, false)
			return
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 600.0
	lp.resonance = 0.4
	AudioServer.add_bus_effect(master, lp)
	_lowpass_idx = AudioServer.get_bus_effect_count(master) - 1
	AudioServer.set_bus_effect_enabled(master, _lowpass_idx, false)

## Set a bus's resting volume from the settings menu. For ducked buses (Music/Ambient) this
## also updates the stored baseline so a later impact-duck restores to the new level, not the old.
func set_base_volume(bus: String, db: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, db)
	if _initial.has(bus):
		_initial[bus] = db

func set_underwater(on: bool) -> void:
	if _lowpass_idx == -1 or on == _underwater:
		return
	_underwater = on
	var master := AudioServer.get_bus_index("Master")
	if master != -1:
		AudioServer.set_bus_effect_enabled(master, _lowpass_idx, on)

## amount 0..1 (0.5 noticeable, 1.0 near-silence), dur = total duck+restore seconds.
func duck(amount: float, dur: float = 0.45) -> void:
	if _initial.is_empty():
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	var attack := dur * 0.15
	var release := dur * 0.85
	for b in _initial.keys():
		var idx := AudioServer.get_bus_index(b)
		if idx == -1:
			continue
		var base: float = _initial[b]
		var target := base + (-24.0 * amount * float(WEIGHTS[b]))
		_tween.tween_method(_set_db.bind(idx), base, target, attack).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_set_db.bind(idx), target, base, release).set_delay(attack).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _set_db(db: float, idx: int) -> void:
	AudioServer.set_bus_volume_db(idx, db)
