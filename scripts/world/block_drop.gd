class_name BlockDrop
extends Node3D

## A dropped item: a small bobbing, spinning cube that falls onto terrain, then
## magnetises to a nearby player and is collected into their inventory.

const GRAVITY := 14.0
const MAGNET_RADIUS := 2.8
const PICKUP_RADIUS := 1.4
const MAGNET_SPEED := 6.0

var block_id := VoxelTypes.AIR
var manager                       # ChunkManager
var player                        # Player
var _vy := 0.0
var _age := 0.0
var _mesh: MeshInstance3D

func setup(id: int, mgr, plr) -> void:
	block_id = id
	manager = mgr
	player = plr

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.3, 0.3)
	_mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = VoxelTypes.color_of(block_id)
	mat.roughness = 0.9
	_mesh.material_override = mat
	add_child(_mesh)

func _physics_process(delta: float) -> void:
	_age += delta
	_mesh.rotate_y(delta * 2.2)
	_mesh.position.y = 0.05 + sin(_age * 3.0) * 0.06

	# Fall until the block directly below is solid.
	var resting := false
	if manager:
		var below: int = manager.get_block(floori(global_position.x), floori(global_position.y - 0.35), floori(global_position.z))
		resting = VoxelTypes.is_solid(below)
	if resting:
		_vy = 0.0
	else:
		_vy -= GRAVITY * delta
		global_position.y += _vy * delta

	if global_position.y < -40.0:
		queue_free()
		return

	if player and is_instance_valid(player):
		var to: Vector3 = player.global_position + Vector3(0, 0.8, 0) - global_position
		var d := to.length()
		if d < MAGNET_RADIUS and _age > 0.35:
			global_position += to.normalized() * minf(d, MAGNET_SPEED * delta)
		if d < PICKUP_RADIUS and _age > 0.3:
			if player.has_method("collect_item"):
				player.collect_item(block_id, 1)
			queue_free()
