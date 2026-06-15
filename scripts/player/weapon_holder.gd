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
const GRIP_SCALE := 0.5         # fallback when a model has no measurable bounds
const GRIP_LENGTH := 0.7        # target longest-dimension size of a held weapon

const CHOP := ["axe", "maul", "hammer", "mace", "pickaxe", "chisel"]
const THRUST := ["polearm"]

var weapons: Array = []
var _attach: BoneAttachment3D
var _model: Node3D
var _current := -1
var _tween: Tween
var _rest_pos := Vector3.ZERO   # fitted grip position (bone-scale aware)
var _inv_scale := 1.0           # 1 / bone scale, to convert world offsets to local
var _world_visible := true      # the in-world (third-person) weapon; hidden in first person

## Show/hide the third-person weapon held in the character's hand. First person hides it
## so ONLY the first-person viewmodel weapon is seen (no duplicate floating weapon).
func set_world_visible(v: bool) -> void:
	_world_visible = v
	if _model and is_instance_valid(_model):
		_model.visible = v

func setup(skeleton: Skeleton3D, registry: Array) -> void:
	weapons = registry
	if skeleton == null:
		push_warning("WeaponHolder: no Skeleton3D found on character")
		return
	_attach = BoneAttachment3D.new()
	skeleton.add_child(_attach)                     # add first so bone_name resolves
	var bone := _find_hand_bone(skeleton)
	if bone != "":
		_attach.bone_name = bone
	if not weapons.is_empty():
		equip(0)

func _bone_names(skel: Skeleton3D) -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(skel.get_bone_count()):
		out.append(skel.get_bone_name(i))
	return out

## Find the right-hand bone across common rig naming conventions (RightHand,
## hand_r, mixamorig:RightHand, hand.R, etc.), falling back to any hand/wrist bone.
func _find_hand_bone(skel: Skeleton3D) -> String:
	var names := _bone_names(skel)
	for n in names:
		var l := String(n).to_lower().replace(" ", "").replace(":", "").replace("_", "").replace(".", "")
		if l.contains("righthand") or l.contains("handright") or l.ends_with("handr"):
			return n
	for n in names:
		var l := String(n).to_lower()
		if l.contains("hand") and (l.contains("right") or l.contains("_r") or l.contains(".r") or l.ends_with("r")):
			return n
	for n in names:
		if String(n).to_lower().contains("hand"):
			return n
	for n in names:
		var l := String(n).to_lower()
		if (l.contains("wrist") or l.contains("forearm") or l.contains("lowerarm")) and (l.contains("right") or l.ends_with("r")):
			return n
	return HAND_BONE

func equip(index: int) -> void:
	if weapons.is_empty() or _attach == null:
		return
	index = clampi(index, 0, weapons.size() - 1)
	_current = index
	if _tween and _tween.is_valid():
		_tween.kill()
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
	_model.rotation_degrees = GRIP_ROTATION_DEG
	_attach.add_child(_model)
	_fit_weapon(_model)
	_model.visible = _world_visible          # keep hidden in first person (viewmodel shows instead)

## Scale a weapon to a hand-appropriate length regardless of its model's intrinsic
## size, and centre it on the grip so it's always visible in the hand.
func _fit_weapon(model: Node3D) -> void:
	# The hand bone carries the rig's import scale (e.g. 0.01 for a cm rig); divide
	# it out so the weapon is GRIP_LENGTH in WORLD units, not bone-local units.
	var as_scale := _attach.global_transform.basis.get_scale()
	var asf := (as_scale.x + as_scale.y + as_scale.z) / 3.0
	if asf <= 0.0001:
		asf = 1.0
	_inv_scale = 1.0 / asf
	var box := _merged_local_aabb(model)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest > 0.0001:
		var s := GRIP_LENGTH / (longest * asf)
		model.scale = Vector3(s, s, s)
		_rest_pos = GRIP_POSITION * _inv_scale - box.get_center() * s
	else:
		model.scale = Vector3.ONE * (GRIP_SCALE * _inv_scale)
		_rest_pos = GRIP_POSITION * _inv_scale
	model.position = _rest_pos

func _merged_local_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var has := false
	var stack: Array = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		for ch in node.get_children():
			stack.push_back(ch)
		if node is VisualInstance3D:
			var a: AABB = (node as VisualInstance3D).get_aabb()
			a = (root.global_transform.affine_inverse() * node.global_transform) * a
			if has:
				result = result.merge(a)
			else:
				result = a
				has = true
	return result

## Add a weapon/tool to the owned set; equip it only if asked (crafted = equip,
## advancement reward = keep your current weapon).
func add_weapon(w: Dictionary, do_equip := true) -> void:
	weapons.append(w)
	if do_equip:
		equip(weapons.size() - 1)

## Halt any in-progress swing tween (e.g. on death, so the weapon doesn't keep moving).
func stop_swing() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

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

## Procedural attack motion on the held weapon, shaped by its category:
## chop = overhead arc, thrust = forward stab, slash = horizontal sweep.
func swing(category: String, dur: float) -> void:
	if _model == null or not is_instance_valid(_model):
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	var t := maxf(dur, 0.18)
	_tween = create_tween()
	if THRUST.has(category):
		_model.rotation_degrees = GRIP_ROTATION_DEG + Vector3(-8, 0, 0)
		_model.position = _rest_pos
		var lunge := _rest_pos + Vector3(0, 0, -0.35 * _inv_scale)
		_tween.tween_property(_model, "position", lunge, t * 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_model, "position", _rest_pos, t * 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		return
	var windup: Vector3
	var follow: Vector3
	if CHOP.has(category):
		windup = GRIP_ROTATION_DEG + Vector3(-120, 0, 0)   # raise overhead
		follow = GRIP_ROTATION_DEG + Vector3(55, 0, 0)     # chop down
	else:
		windup = GRIP_ROTATION_DEG + Vector3(-15, -85, -25)  # slash wind-up
		follow = GRIP_ROTATION_DEG + Vector3(15, 85, 25)     # sweep through
	_model.rotation_degrees = windup
	_tween.tween_property(_model, "rotation_degrees", follow, t * 0.42) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_model, "rotation_degrees", GRIP_ROTATION_DEG, t * 0.58) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
