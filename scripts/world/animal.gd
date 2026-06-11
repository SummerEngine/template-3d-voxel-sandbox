class_name Animal
extends CharacterBody3D

## Simple, cheap wandering creature (low-poly box body + head).
## Picks a random direction, walks for a few seconds, idles, repeats. Gravity keeps
## it on the floor; if it wanders off the edge into the void it respawns on the floor.

const SPEED := 2.0

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _dir := Vector3.ZERO
var _timer := 0.0
var _pending_color := Color(0.95, 0.92, 0.86)
var _rng := RandomNumberGenerator.new()

func set_color(c: Color) -> void:
	_pending_color = c

func _ready() -> void:
	_rng.randomize()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _pending_color

	# Body
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.8, 1.2)
	col.shape = box
	col.position = Vector3(0, 0.4, 0)
	add_child(col)

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.8, 1.2)
	body.mesh = bm
	body.material_override = mat
	body.position = Vector3(0, 0.4, 0)
	add_child(body)

	# Head
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.5, 0.5, 0.5)
	head.mesh = hm
	head.material_override = mat
	head.position = Vector3(0, 0.65, 0.7)
	add_child(head)

	_pick_dir()

func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_pick_dir()

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	velocity.x = _dir.x * SPEED
	velocity.z = _dir.z * SPEED

	if _dir.length() > 0.1:
		var target := global_position + Vector3(_dir.x, 0.0, _dir.z)
		look_at(target, Vector3.UP)

	move_and_slide()

	if global_position.y < -5.0:
		global_position = Vector3(_rng.randf_range(-6, 6), 2.0, _rng.randf_range(-6, 6))
		velocity = Vector3.ZERO

func _pick_dir() -> void:
	_timer = _rng.randf_range(1.5, 4.0)
	if _rng.randf() < 0.3:
		_dir = Vector3.ZERO        # idle
	else:
		var a := _rng.randf_range(0.0, TAU)
		_dir = Vector3(cos(a), 0.0, sin(a))
