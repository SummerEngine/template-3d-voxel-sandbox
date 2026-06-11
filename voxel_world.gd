class_name VoxelWorld
extends Node3D

## Voxel world: a dictionary of unit blocks keyed by integer grid cell.
## Optimized for low-end hardware: all blocks share ONE BoxMesh and ONE BoxShape3D,
## and materials are cached per colour (so 256 floor blocks use ~1 material, not 256).

const BLOCK_SIZE := 1.0

var blocks: Dictionary = {}            # Vector3i -> StaticBody3D
var _materials: Dictionary = {}        # Color  -> StandardMaterial3D (shared)
var _box_mesh: BoxMesh
var _box_shape: BoxShape3D

func _ready() -> void:
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	_box_shape = BoxShape3D.new()
	_box_shape.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	_generate_floor(16)

func _generate_floor(size: int) -> void:
	var half := int(size / 2.0)
	for x in range(-half, half):
		for z in range(-half, half):
			add_block(Vector3i(x, 0, z), Color(0.30, 0.58, 0.27))

func _get_material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		_materials[color] = m
	return _materials[color]

func has_block(cell: Vector3i) -> bool:
	return blocks.has(cell)

func add_block(cell: Vector3i, color: Color) -> void:
	if blocks.has(cell):
		return
	var body := StaticBody3D.new()
	body.position = Vector3(cell) * BLOCK_SIZE
	body.set_meta("cell", cell)

	var mesh := MeshInstance3D.new()
	mesh.mesh = _box_mesh                       # shared mesh
	mesh.material_override = _get_material(color)  # shared per-colour material
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	col.shape = _box_shape                      # shared shape
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
