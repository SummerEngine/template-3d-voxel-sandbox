class_name ToolHolder
extends Node3D

## First-person held tool/weapon. Attached under the camera; shows the equipped
## model as a viewmodel, cycles through the tool set, and swings on use.
## Tweak HOLD_* below if a model sits wrong in the hand.

const TOOLS := [
	{ "name": "Sword",      "path": "res://assets/models/tools/sword.glb" },
	{ "name": "War Axe",    "path": "res://assets/models/tools/war_axe.glb" },
	{ "name": "Battle Axe", "path": "res://assets/models/tools/double_bit_axe.glb" },
	{ "name": "Hammer",     "path": "res://assets/models/tools/hammer.glb" },
	{ "name": "Hoe",        "path": "res://assets/models/tools/hoe.glb" },
	{ "name": "Scythe",     "path": "res://assets/models/tools/scythe.glb" },
	{ "name": "Shovel",     "path": "res://assets/models/tools/shovel.glb" },
]

# Viewmodel placement in front of the camera (tweak to taste).
const HOLD_POSITION := Vector3(0.34, -0.32, -0.62)
const HOLD_SCALE := 0.22
const HOLD_ROT_DEG := Vector3(0.0, 120.0, 0.0)

var _current := -1
var _model: Node3D

func _ready() -> void:
	equip(0)

func equip(index: int) -> void:
	index = clampi(index, 0, TOOLS.size() - 1)
	_current = index
	if _model and is_instance_valid(_model):
		_model.queue_free()
		_model = null
	var path: String = TOOLS[index].path
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	_model = packed.instantiate() as Node3D
	if _model == null:
		return
	_model.position = HOLD_POSITION
	_model.scale = Vector3.ONE * HOLD_SCALE
	_model.rotation_degrees = HOLD_ROT_DEG
	add_child(_model)

func next() -> void:
	equip((_current + 1) % TOOLS.size())

func prev() -> void:
	equip((_current - 1 + TOOLS.size()) % TOOLS.size())

func current_name() -> String:
	return TOOLS[_current].name if _current >= 0 else ""

func swing() -> void:
	if _model == null or not is_instance_valid(_model):
		return
	var t := create_tween()
	t.tween_property(_model, "rotation_degrees", HOLD_ROT_DEG + Vector3(-45.0, 0.0, 10.0), 0.06)
	t.tween_property(_model, "rotation_degrees", HOLD_ROT_DEG, 0.14)
