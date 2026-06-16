extends RefCounted
## Loads the 3D tree + palm GLBs once and exposes, for each, its Mesh (with materials baked
## onto the surfaces) plus a "base transform" that maps the raw mesh verts to a normalized
## space: base-centred on the origin, exactly 1 unit tall, upright. Per-chunk MultiMesh code
## then just multiplies by a world placement (position + Y-rotation + height scale). One Mesh
## is shared by every instance in every chunk, so a whole forest is a handful of draw calls.

const TREE_PATH := "res://assets/models/world/tree_u.glb"   # user-provided stylized tree
const PALM_PATH := "res://assets/models/world/palm_u.glb"   # user-provided palm

static var _tree_loaded := false
static var _palm_loaded := false
static var _tree: Array = []     # [Mesh, Transform3D] or [] if unavailable
static var _palm: Array = []

## [Mesh, base_xf] for the broadleaf tree, or [] if the model is missing.
static func tree() -> Array:
	if not _tree_loaded:
		_tree = _load_model(TREE_PATH)
		_tree_loaded = true
	return _tree

## [Mesh, base_xf] for the palm, or [] if the model is missing.
static func palm() -> Array:
	if not _palm_loaded:
		_palm = _load_model(PALM_PATH)
		_palm_loaded = true
	return _palm

static func _load_model(path: String) -> Array:
	if not ResourceLoader.exists(path):
		return []
	var packed := load(path) as PackedScene
	if packed == null:
		return []
	var root := packed.instantiate()
	if root == null:
		return []
	var mis := root.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		root.free()
		return []
	var mi := mis[0] as MeshInstance3D
	var mesh: Mesh = mi.mesh
	if mesh == null:
		root.free()
		return []
	# Bake any node-level surface overrides onto the mesh so the shared Mesh carries its colours.
	for si in range(mesh.get_surface_count()):
		var ov := mi.get_surface_override_material(si)
		if ov != null:
			mesh.surface_set_material(si, ov)

	# Transform from the mesh's local space up to the instantiated root (GLBs often nest the
	# mesh under a "convert" node with a Y-up conversion baked into the transform).
	var m_xform := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != root:
		if n is Node3D:
			m_xform = (n as Node3D).transform * m_xform
		n = n.get_parent()
	if root is Node3D:
		m_xform = (root as Node3D).transform * m_xform

	var aabb_root: AABB = m_xform * mesh.get_aabb()
	root.free()
	if aabb_root.size.y <= 0.0001:
		return [mesh, Transform3D.IDENTITY]

	var s := 1.0 / aabb_root.size.y                       # normalize height to 1 unit
	var base := Vector3(
		aabb_root.position.x + aabb_root.size.x * 0.5,    # x centre
		aabb_root.position.y,                             # y bottom (feet)
		aabb_root.position.z + aabb_root.size.z * 0.5)    # z centre
	var sb := Basis(Vector3(s, 0, 0), Vector3(0, s, 0), Vector3(0, 0, s))
	# norm(P) = s * (m_xform * P - base)  ->  basis = s*m_xform.basis, origin = s*(m_xform.origin - base)
	var base_xf := Transform3D(sb * m_xform.basis, sb * (m_xform.origin - base))
	return [mesh, base_xf]
