class_name Chunk
extends Node3D

## One 16x16x256 chunk. Builds a single greedy-meshed surface (merged same-type
## faces, hidden faces culled) plus a trimesh collider. Samples the manager for
## neighbour blocks so chunk borders are seamless.

const CW := 16
const CD := 16

var manager                      # ChunkManager
var coord: Vector2i
var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _col_height: Dictionary = {} # Vector2i(wx,wz) -> surface height (cached per build)

func _ready() -> void:
	build()

func build() -> void:
	var ox := coord.x * CW
	var oz := coord.y * CD

	# Precompute surface heights for this chunk's columns (+1 border ring) and the
	# tallest point we need to mesh up to (covers terrain and any tall edits).
	_col_height.clear()
	var max_y := 0
	for lz in range(-1, CD + 1):
		for lx in range(-1, CW + 1):
			var s: int = manager.surface_height(ox + lx, oz + lz)
			_col_height[Vector2i(ox + lx, oz + lz)] = s
			if s > max_y:
				max_y = s
	for key in manager.overrides.keys():
		if manager.chunk_x(key.x) == coord.x and manager.chunk_z(key.z) == coord.y:
			if key.y > max_y:
				max_y = key.y
	var top: int = mini(max_y + 2, manager.WORLD_H)

	var arrays := _greedy(ox, oz, top)

	if _mesh_instance and is_instance_valid(_mesh_instance):
		_mesh_instance.queue_free()
		_mesh_instance = null
	if _body and is_instance_valid(_body):
		_body.queue_free()
		_body = null
	if arrays.is_empty():
		return

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # explicit normals -> safe both-sided
	am.surface_set_material(0, mat)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = am
	add_child(_mesh_instance)

	_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = am.create_trimesh_shape()
	_body.add_child(cs)
	add_child(_body)

func _block(wx: int, wy: int, wz: int) -> int:
	var ov: Dictionary = manager.overrides
	var key := Vector3i(wx, wy, wz)
	if ov.has(key):
		return ov[key]
	var col := Vector2i(wx, wz)
	var s: int = _col_height[col] if _col_height.has(col) else manager.surface_height(wx, wz)
	return manager.block_from_surface(wy, s)

func _greedy(ox: int, oz: int, top: int) -> Array:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var dims := [CW, top, CD]

	for d in range(3):
		var u := (d + 1) % 3
		var v := (d + 2) % 3
		var du: int = dims[u]
		var dv: int = dims[v]
		var x := [0, 0, 0]
		var q := [0, 0, 0]
		q[d] = 1
		var mask: Array = []
		mask.resize(du * dv)

		x[d] = -1
		while x[d] < dims[d]:
			# Build the mask for the boundary plane between slice x[d] and x[d]+1.
			var s_lo: int = x[d]
			var a_in: bool = s_lo >= 0 and s_lo < int(dims[d])
			var b_in: bool = (s_lo + 1) >= 0 and (s_lo + 1) < int(dims[d])
			var n := 0
			x[v] = 0
			while x[v] < dv:
				x[u] = 0
				while x[u] < du:
					var a := _block(ox + x[0], x[1], oz + x[2])
					var bx: int = int(x[0]) + int(q[0])
					var by: int = int(x[1]) + int(q[1])
					var bz: int = int(x[2]) + int(q[2])
					var b := _block(ox + bx, by, oz + bz)
					var sa := VoxelTypes.is_solid(a)
					var sb := VoxelTypes.is_solid(b)
					if sa and not sb and a_in:
						mask[n] = a            # front face of a (+d)
					elif sb and not sa and b_in:
						mask[n] = -b           # face of b (-d)
					else:
						mask[n] = 0
					n += 1
					x[u] += 1
				x[v] += 1

			x[d] += 1   # plane coordinate is now x[d]

			# Emit merged quads from the mask.
			n = 0
			var j := 0
			while j < dv:
				var i := 0
				while i < du:
					var c: int = mask[n]
					if c != 0:
						var w := 1
						while i + w < du and mask[n + w] == c:
							w += 1
						var h := 1
						var stop := false
						while j + h < dv:
							var k := 0
							while k < w:
								if mask[n + k + h * du] != c:
									stop = true
									break
								k += 1
							if stop:
								break
							h += 1
						x[u] = i
						x[v] = j
						var duv := [0, 0, 0]
						duv[u] = w
						var dvv := [0, 0, 0]
						dvv[v] = h
						_quad(positions, normals, colors, indices, x, duv, dvv, d, c < 0, absi(c))
						var l := 0
						while l < h:
							var k2 := 0
							while k2 < w:
								mask[n + k2 + l * du] = 0
								k2 += 1
							l += 1
						i += w
						n += w
					else:
						i += 1
						n += 1
				j += 1

	if positions.is_empty():
		return []
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = positions
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	return arr

func _quad(positions: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		indices: PackedInt32Array, x: Array, duv: Array, dvv: Array, d: int, back: bool, btype: int) -> void:
	var p0 := Vector3(x[0], x[1], x[2])
	var p1 := Vector3(x[0] + duv[0], x[1] + duv[1], x[2] + duv[2])
	var p2 := Vector3(x[0] + duv[0] + dvv[0], x[1] + duv[1] + dvv[1], x[2] + duv[2] + dvv[2])
	var p3 := Vector3(x[0] + dvv[0], x[1] + dvv[1], x[2] + dvv[2])
	var sgn := -1.0 if back else 1.0
	var nrm := Vector3.ZERO
	if d == 0:
		nrm = Vector3(sgn, 0.0, 0.0)
	elif d == 1:
		nrm = Vector3(0.0, sgn, 0.0)
	else:
		nrm = Vector3(0.0, 0.0, sgn)
	var col := VoxelTypes.color_of(btype)
	var base := positions.size()
	positions.push_back(p0)
	positions.push_back(p1)
	positions.push_back(p2)
	positions.push_back(p3)
	for k in range(4):
		normals.push_back(nrm)
		colors.push_back(col)
	if back:
		indices.push_back(base + 0); indices.push_back(base + 2); indices.push_back(base + 1)
		indices.push_back(base + 0); indices.push_back(base + 3); indices.push_back(base + 2)
	else:
		indices.push_back(base + 0); indices.push_back(base + 1); indices.push_back(base + 2)
		indices.push_back(base + 0); indices.push_back(base + 2); indices.push_back(base + 3)
