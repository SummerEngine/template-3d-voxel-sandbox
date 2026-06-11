class_name VoxelWorld
extends Node3D

## Simple voxel world: a dictionary of unit blocks keyed by integer grid cell.
## Each block is a StaticBody3D (BoxMesh + BoxShape3D) so the player can stand on,
## raycast, break and place blocks.

const BLOCK_SIZE := 1.0

var blocks: Dictionary = {}  # Vector3i -> StaticBody3D

func _ready() -> void:
	_generate_floor(16)

func _generate_floor(size: int) -> void:
	var half := int(size / 2.0)
	for x in range(-half, half):
		for z in range(-half, half):
			add_block(Vector3i(x, 0, z), Color(0.30, 0.58, 0.27))

func has_block(cell: Vector3i) -> bool:
	return blocks.has(cell)

func add_block(cell: Vector3i, color: Color) -> void:
	if blocks.has(cell):
		return
	var body := StaticBody3D.new()
	body.position = Vector3(cell) * BLOCK_SIZE
	body.set_meta("cell", cell)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	col.shape = shape
	body.add_child(col)

	add_child(body)
	blocks[cell] = body

func remove_block(cell: Vector3i) -> void:
	if not blocks.has(cell):
		return
	var body: Node = blocks[cell]
	if is_instance_valid(body):
		body.queue_free()
	blocks.erase(cell)
