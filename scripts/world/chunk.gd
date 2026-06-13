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

# Per-build voxel cache: every block (incl. a 1-voxel border, edits and trees) is
# computed ONCE here, then the greedy mesher reads this flat array instead of
# re-evaluating terrain noise ~6x per voxel.
var _cache: PackedInt32Array = PackedInt32Array()
var _ground_cache: PackedInt32Array = PackedInt32Array()   # pure terrain, computed once
var _ground_top := -1
var _ox := 0
var _oz := 0
var _top := 0
var _sx := CW + 2                # cache stride in x (border on both sides)
var _sz := CD + 2                # cache stride in z
var _collision_faces := PackedVector3Array()   # solid faces only (water excluded)

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
	# Mesh up to the tallest terrain (+8 for tree canopies) but NEVER below sea level,
	# or ocean/lake water above the floor goes unmeshed -> empty pits you fall into.
	var top: int = mini(maxi(max_y + manager.TREE_H + 1, manager.SEA_LEVEL + 1), manager.WORLD_H)

	_fill_cache(ox, oz, top)
	var arrays := _greedy(top)

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
	var mat: Material
	const SHADER_PATH := "res://assets/materials/block_atlas.gdshader"
	const ATLAS_PATH  := "res://assets/textures/blocks/atlas.png"
	if ResourceLoader.exists(SHADER_PATH) and ResourceLoader.exists(ATLAS_PATH):
		var sm := ShaderMaterial.new()
		sm.shader = load(SHADER_PATH)
		sm.set_shader_parameter("atlas", load(ATLAS_PATH))
		mat = sm
	else:
		var fb := StandardMaterial3D.new()
		fb.vertex_color_use_as_albedo = true
		fb.roughness = 1.0
		fb.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat = fb
	am.surface_set_material(0, mat)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = am
	add_child(_mesh_instance)

	if _collision_faces.size() >= 3:
		_body = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(_collision_faces)
		shape.backface_collision = true   # faces use mixed winding; collide from both sides
		cs.shape = shape
		_body.add_child(cs)
		add_child(_body)

## Compute the whole chunk (plus a 1-voxel border) once: ground terrain from the
## generator, player edits from overrides, and tree blocks layered on top — the
## last computed per-chunk by scanning only nearby tree origins, not per-voxel.
func _fill_cache(ox: int, oz: int, top: int) -> void:
	_ox = ox
	_oz = oz
	_top = top
	# Terrain is static, so the expensive noise/tree pass runs once and is reused;
	# rebuilds (block edits, neighbour updates) just copy it and re-apply overrides.
	if _ground_top != top or _ground_cache.size() != (top + 1) * _sz * _sx:
		_compute_ground(ox, oz, top)
		_ground_top = top
	_cache = _ground_cache.duplicate()

	# Overlay player edits (loop the overrides, not the volume — usually a small set).
	for key in manager.overrides.keys():
		var lx: int = key.x - ox
		var ly: int = key.y
		var lz: int = key.z - oz
		if ly >= 0 and ly <= top and lx >= -1 and lx <= CW and lz >= -1 and lz <= CD:
			_cache[(ly * _sz + (lz + 1)) * _sx + (lx + 1)] = manager.overrides[key]

## The expensive part: pure terrain + trees (no edits), cached for the chunk's lifetime.
func _compute_ground(ox: int, oz: int, top: int) -> void:
	_ground_cache = PackedInt32Array()
	_ground_cache.resize((top + 1) * _sz * _sx)

	# Surfaces for the chunk + border, packed (avoids a Vector2i + dict lookup per voxel).
	var surf := PackedInt32Array()
	surf.resize(_sz * _sx)
	for lz in range(-1, CD + 1):
		for lx in range(-1, CW + 1):
			surf[(lz + 1) * _sx + (lx + 1)] = _col_height[Vector2i(ox + lx, oz + lz)]

	# Tree blocks for every tree whose canopy can reach this chunk (origins within 2).
	var tree_blocks: Dictionary = {}
	var maxr: int = manager.TREE_R
	for tcz in range(oz - 1 - maxr, oz + CD + 1 + maxr):
		for tcx in range(ox - 1 - maxr, ox + CW + 1 + maxr):
			if not manager.is_tree(tcx, tcz):
				continue
			var sc: int = manager.surface_height(tcx, tcz)
			if sc <= manager.SEA_LEVEL + 1 or sc >= manager.MOUNTAIN_ROCK:
				continue
			var tall: bool = manager.is_jungle(tcx, tcz)
			var rr: int = maxr if tall else 2
			var hh: int = manager.TREE_H if tall else 6
			for ry in range(1, hh + 1):
				for rx in range(-rr, rr + 1):
					for rz in range(-rr, rr + 1):
						var tv: int = manager.tree_voxel(rx, ry, rz, tall)
						if tv != VoxelTypes.AIR:
							tree_blocks[Vector3i(tcx + rx, sc + ry, tcz + rz)] = tv
	var has_trees := not tree_blocks.is_empty()

	for ly in range(0, top + 1):
		var ybase := ly * _sz
		for lz in range(-1, CD + 1):
			var wz := oz + lz
			var rowbase := (ybase + (lz + 1)) * _sx
			var sbase := (lz + 1) * _sx
			for lx in range(-1, CW + 1):
				var s := surf[sbase + (lx + 1)]
				var b: int = manager.ground_block(ox + lx, ly, wz, s)
				if has_trees and b == VoxelTypes.AIR and ly > s and ly <= s + manager.TREE_H:
					var tk := Vector3i(ox + lx, ly, wz)
					if tree_blocks.has(tk):
						b = tree_blocks[tk]
				_ground_cache[rowbase + (lx + 1)] = b

func _block(wx: int, wy: int, wz: int) -> int:
	var lx := wx - _ox
	var lz := wz - _oz
	if wy >= 0 and wy <= _top and lx >= -1 and lx <= CW and lz >= -1 and lz <= CD:
		return _cache[(wy * _sz + (lz + 1)) * _sx + (lx + 1)]
	# Rare out-of-cache border sample.
	var key := Vector3i(wx, wy, wz)
	if manager.overrides.has(key):
		return manager.overrides[key]
	return manager.generate_block(wx, wy, wz)

func _greedy(top: int) -> Array:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	_collision_faces = PackedVector3Array()

	var dims := [CW, top, CD]

	for d in range(3):
		var u := (d + 1) % 3
		var v := (d + 2) % 3
		var du: int = dims[u]
		var dv: int = dims[v]
		var x := [0, 0, 0]
		var q := [0, 0, 0]
		q[d] = 1
		var mask := PackedInt32Array()
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
					# Inlined cache reads (local coords == x[] since the chunk origin cancels).
					var ay: int = x[1]
					var a := 0
					if ay >= 0:
						a = _cache[(ay * _sz + (x[2] + 1)) * _sx + (x[0] + 1)]
					var by: int = ay + q[1]
					var b: int = _cache[(by * _sz + (x[2] + q[2] + 1)) * _sx + (x[0] + q[0] + 1)]
					var sa := a != 0
					var sb := b != 0
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
						_quad(positions, normals, colors, uvs, indices, x, duv, dvv, d, c < 0, absi(c))
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
	arr[Mesh.ARRAY_VERTEX]   = positions
	arr[Mesh.ARRAY_NORMAL]   = normals
	arr[Mesh.ARRAY_COLOR]    = colors
	arr[Mesh.ARRAY_TEX_UV]   = uvs
	arr[Mesh.ARRAY_INDEX]    = indices
	return arr

func _quad(positions: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		uvs: PackedVector2Array, indices: PackedInt32Array,
		x: Array, duv: Array, dvv: Array, d: int, back: bool, btype: int) -> void:
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
	# Tile origin within the 4x4 atlas, packed into COLOR.rg for the block shader.
	var ai := VoxelTypes.atlas_index(btype)
	var col := Color(float(ai & 3) * 0.25, float(ai >> 2) * 0.25, 0.0, 1.0)
	# UV extents for tiling within the atlas slot
	var w := float(absi(duv[0]) + absi(duv[1]) + absi(duv[2]))
	var h := float(absi(dvv[0]) + absi(dvv[1]) + absi(dvv[2]))
	var base := positions.size()
	positions.push_back(p0)
	positions.push_back(p1)
	positions.push_back(p2)
	positions.push_back(p3)
	for k in range(4):
		normals.push_back(nrm)
		colors.push_back(col)
	uvs.push_back(Vector2(0.0, 0.0))
	uvs.push_back(Vector2(w,   0.0))
	uvs.push_back(Vector2(w,   h))
	uvs.push_back(Vector2(0.0, h))
	if back:
		indices.push_back(base + 0); indices.push_back(base + 2); indices.push_back(base + 1)
		indices.push_back(base + 0); indices.push_back(base + 3); indices.push_back(base + 2)
	else:
		indices.push_back(base + 0); indices.push_back(base + 1); indices.push_back(base + 2)
		indices.push_back(base + 0); indices.push_back(base + 2); indices.push_back(base + 3)
	# Water is rendered but NOT collidable, so the player can swim into it.
	if btype != VoxelTypes.WATER:
		_collision_faces.push_back(p0); _collision_faces.push_back(p1); _collision_faces.push_back(p2)
		_collision_faces.push_back(p0); _collision_faces.push_back(p2); _collision_faces.push_back(p3)
