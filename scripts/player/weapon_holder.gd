class_name WeaponHolder
extends Node3D

## Equips a melee weapon into the rigged character's right hand via a
## BoneAttachment3D on the "RightHand" bone, and cycles through the weapon set.
## Weapon data (name + stats) comes from WeaponRegistry; the swing itself is the
## character's Attack/Mine animation clip, driven by the player.
## Tweak GRIP_* if a weapon sits wrong in the hand.

const HAND_BONE := "RightHand"
const GRIP_POSITION := Vector3(0.0, 0.05, 0.0)
const GRIP_ROTATION_DEG := Vector3(0.0, 0.0, 0.0)
const GRIP_SCALE := 0.5

var weapons: Array = []
var _attach: BoneAttachment3D
var _model: Node3D
var _current := -1

func setup(skeleton: Skeleton3D, registry: Array) -> void:
	weapons = registry
	if skeleton == null:
		push_warning("WeaponHolder: no Skeleton3D found on character")
		return
	_attach = BoneAttachment3D.new()
	_attach.bone_name = HAND_BONE
	skeleton.add_child(_attach)
	if not weapons.is_empty():
		equip(0)

func equip(index: int) -> void:
	if weapons.is_empty() or _attach == null:
		return
	index = clampi(index, 0, weapons.size() - 1)
	_current = index
	if _model and is_instance_valid(_model):
		_model.queue_free()
		_model = null
	var path: String = weapons[index].get("path", "")
	if path == "" or not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	_model = packed.instantiate() as Node3D
	if _model == null:
		return
	_model.position = GRIP_POSITION
	_model.rotation_degrees = GRIP_ROTATION_DEG
	_model.scale = Vector3.ONE * GRIP_SCALE
	_attach.add_child(_model)

func next() -> void:
	if not weapons.is_empty():
		equip((_current + 1) % weapons.size())

func prev() -> void:
	if not weapons.is_empty():
		equip((_current - 1 + weapons.size()) % weapons.size())

func current() -> Dictionary:
	if _current >= 0 and _current < weapons.size():
		return weapons[_current]
	return {}
