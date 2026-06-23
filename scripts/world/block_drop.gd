class_name BlockDrop
extends Node3D

## A dropped item: a small bobbing, spinning cube that falls onto terrain, then
## magnetises to a nearby player and is collected into their inventory.

const GRAVITY := 14.0
const MAGNET_RADIUS := 2.8
const PICKUP_RADIUS := 1.4
const MAGNET_SPEED := 6.0
const ItemIcons := preload("res://scripts/ui/item_icons.gd")

const DESPAWN_AFTER := 300.0      # uncollected drops vanish after 5 min (Minecraft rule) — no infinite buildup

var block_id := VoxelTypes.AIR
var manager                       # ChunkManager
var player                        # Player
var _vy := 0.0
var _age := 0.0
var _last_probe_cell := Vector3i(2147483647, 0, 0)   # last cell probed for "resting" — re-probe only on change
var _resting := false
var _mesh: MeshInstance3D

# Every drop is the same 0.3 cube, and a given block id always looks the same — so the mesh
# is shared by all drops and the per-id material is built once and cached. Mining a vein used
# to allocate a fresh BoxMesh + StandardMaterial3D per dropped cube; now it allocates nothing.
static var _shared_mesh: BoxMesh
static var _mat_cache: Dictionary = {}   # block_id -> StandardMaterial3D

static func _drop_mesh() -> BoxMesh:
	if _shared_mesh == null:
		_shared_mesh = BoxMesh.new()
		_shared_mesh.size = Vector3(0.3, 0.3, 0.3)
	return _shared_mesh

static func _drop_material(id: int) -> StandardMaterial3D:
	if _mat_cache.has(id):
		return _mat_cache[id]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = VoxelTypes.color_of(id)
	mat.roughness = 0.9
	# Blocks show their real atlas texture on the little cube; items keep the flat colour
	# (their icons are transparent cut-outs that wouldn't read on a solid cube).
	if id <= VoxelTypes.MAX_BLOCK:
		var tex: Texture2D = ItemIcons.tile_texture(id)   # a single cropped tile, not the whole atlas
		if tex != null:
			mat.albedo_texture = tex
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.albedo_color = Color.WHITE
	_mat_cache[id] = mat
	return mat

func setup(id: int, mgr, plr) -> void:
	block_id = id
	manager = mgr
	player = plr

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _drop_mesh()
	_mesh.material_override = _drop_material(block_id)
	add_child(_mesh)

func _physics_process(delta: float) -> void:
	_age += delta
	if _age > DESPAWN_AFTER:               # uncollected too long (e.g. inventory full) — clean up
		queue_free()
		return
	_mesh.rotate_y(delta * 2.2)
	_mesh.position.y = 0.05 + sin(_age * 3.0) * 0.06

	# Fall until the block directly below is solid. get_block routes through noise for natural ground,
	# so only re-probe when the drop moves to a new cell — a settled drop then never re-samples.
	if manager:
		var cell := Vector3i(floori(global_position.x), floori(global_position.y - 0.35), floori(global_position.z))
		if cell != _last_probe_cell:
			_last_probe_cell = cell
			_resting = VoxelTypes.is_solid(manager.get_block(cell.x, cell.y, cell.z))
	if _resting:
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
			var taken := 1
			if player.has_method("collect_item"):
				taken = player.collect_item(block_id, 1)
			if taken > 0:
				if player.has_method("_emit_burst"):
					player._emit_burst(global_position, Color(0.95, 0.82, 0.35), 6, 0.35, 70.0, 0.6, 1.6, 3.0)   # warm pickup poof
				queue_free()        # only despawn if it actually fit; else wait on the ground
