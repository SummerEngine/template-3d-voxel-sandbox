extends Node

## Ensures Music / Ambient / SFX audio buses exist (created at runtime, routed to
## Master) and briefly ducks Music + Ambient on impacts so SFX punches through.
## Added to the scene by main.gd / main_menu.gd and called via the "ducker" group:
##   get_tree().call_group("ducker", "duck", 0.5, 0.45)

const BUSES := ["Music", "Ambient", "SFX"]
const WEIGHTS := {"Music": 0.9, "Ambient": 0.7}   # SFX is never ducked

var _initial: Dictionary = {}
var _tween: Tween

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
