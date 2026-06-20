class_name Crop
extends Node3D

## A single farmed crop growing on farmland. The model is built from voxel boxes (no imported
## asset, so there's no copyright surface), advances through growth stages over real time, sways
## gently in the breeze, and sparkles gold when it ripens. The FarmManager plants, ticks and
## harvests these; harvesting reads is_mature().
##
## Rendering is batched Minecraft-style: every crop at a given stage shares ONE cached merged
## mesh and ONE shared material, so a whole field renders in a handful of draw calls instead of
## ~6-12 per plant. Growth/sway is per-instance (the node transform), which the GPU instances.

const GROW_TIME := 20.0          # seconds per growth stage
const STAGES := 3                # 0 = sprout, 1 = tall green, 2 = ripe golden (mature)

const STAGE_H := [0.18, 0.46, 0.78]   # crop height by stage
const OFFS := [
	Vector2(0.0, 0.0), Vector2(0.12, 0.06), Vector2(-0.10, 0.09),
	Vector2(0.07, -0.12), Vector2(-0.08, -0.07), Vector2(0.13, -0.09)]

# One material + one mesh-per-stage shared by EVERY crop in the world, built lazily once. Sharing
# the mesh resource lets the renderer batch the whole field; per-crop sway is just a node rotation.
static var _crop_mat: StandardMaterial3D
static var _stage_mesh: Array = [null, null, null]

const SWAY_DIST_SQ := 26.0 * 26.0   # only animate sway for crops the player is near enough to see move

var stage := 0                   # set by the FarmManager before add_child; _ready builds it
var grow_t := 0.0
var player                       # set by the FarmManager — used to skip sway on distant fields
var _model: MeshInstance3D
var _phase := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_phase = _rng.randf() * TAU
	_build()

func is_mature() -> bool:
	return stage >= STAGES - 1

func _process(delta: float) -> void:
	if stage < STAGES - 1:
		grow_t += delta
		if grow_t >= GROW_TIME:
			grow_t = 0.0
			stage += 1
			_build()
			if is_mature():
				_ripen_sparkle()
	# Gentle breeze sway (per-instance node transform; mesh stays shared). Skipped for crops far
	# from the player — a distant field doesn't need per-frame transforms it can't be seen moving.
	if _model and is_instance_valid(_model) and player and is_instance_valid(player) \
			and global_position.distance_squared_to(player.global_position) < SWAY_DIST_SQ:
		_phase += delta * 1.6
		_model.rotation.z = sin(_phase) * 0.06
		_model.rotation.x = cos(_phase * 0.8) * 0.04

## Swap the single MeshInstance to this stage's shared, cached merged mesh.
func _build() -> void:
	if _model and is_instance_valid(_model):
		_model.queue_free()
	_model = MeshInstance3D.new()
	_model.mesh = _stage_mesh_for(clampi(stage, 0, STAGES - 1))
	_model.material_override = _shared_material()
	add_child(_model)

# --- shared, cached resources -----------------------------------------------------------
static func _shared_material() -> StandardMaterial3D:
	if _crop_mat == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true     # per-vertex stalk/grain colour
		m.roughness = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_crop_mat = m
	return _crop_mat

static func _stage_mesh_for(stage_i: int) -> Mesh:
	if _stage_mesh[stage_i] == null:
		_stage_mesh[stage_i] = _build_stage_mesh(stage_i)
	return _stage_mesh[stage_i]

## Build one merged mesh for a stage: a cluster of stalks (green while growing, golden when ripe)
## topped with grain heads once mature. Deterministic, so every crop at this stage shares it.
static func _build_stage_mesh(stage_i: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ripe := stage_i >= STAGES - 1
	var base: Color = Color(0.86, 0.72, 0.26) if ripe else Color(0.32, 0.62, 0.22)
	var h: float = STAGE_H[stage_i]
	var blades := 4 if stage_i == 0 else 6
	for i in range(blades):
		var o: Vector2 = OFFS[i % OFFS.size()]
		_add_box(st, Vector3(o.x, h * 0.5, o.y), Vector3(0.05, h, 0.05), base.darkened(float(i) * 0.03))
	if ripe:
		for i in range(blades):
			var o2: Vector2 = OFFS[i % OFFS.size()]
			_add_box(st, Vector3(o2.x, h + 0.04, o2.y), Vector3(0.085, 0.14, 0.085), Color(0.95, 0.82, 0.32))
	return st.commit()

## Append one axis-aligned box (6 faces) into the SurfaceTool with flat normals + a vertex colour.
## Material is cull-disabled, so winding doesn't matter for visibility.
static func _add_box(st: SurfaceTool, c: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z),
		c + Vector3(h.x, -h.y, h.z),   c + Vector3(-h.x, -h.y, h.z),
		c + Vector3(-h.x, h.y, -h.z),  c + Vector3(h.x, h.y, -h.z),
		c + Vector3(h.x, h.y, h.z),    c + Vector3(-h.x, h.y, h.z)]
	var faces := [
		[0, 1, 2, 3, Vector3(0, -1, 0)],   # bottom
		[4, 7, 6, 5, Vector3(0, 1, 0)],    # top
		[0, 4, 5, 1, Vector3(0, 0, -1)],   # -Z
		[3, 2, 6, 7, Vector3(0, 0, 1)],    # +Z
		[0, 3, 7, 4, Vector3(-1, 0, 0)],   # -X
		[1, 5, 6, 2, Vector3(1, 0, 0)]]    # +X
	for f in faces:
		var n: Vector3 = f[4]
		_tri(st, p[f[0]], p[f[1]], p[f[2]], n, color)
		_tri(st, p[f[0]], p[f[2]], p[f[3]], n, color)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color) -> void:
	st.set_color(color); st.set_normal(n); st.add_vertex(a)
	st.set_color(color); st.set_normal(n); st.add_vertex(b)
	st.set_color(color); st.set_normal(n); st.add_vertex(c)

## A short gold sparkle burst when the crop ripens, so a ready field reads at a glance.
func _ripen_sparkle() -> void:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 0.05)
	p.mesh = bm
	p.amount = 16
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = true
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.5
	p.gravity = Vector3(0.0, -1.8, 0.0)
	p.color = Color(1.0, 0.86, 0.35)
	p.position = Vector3(0.0, 0.7, 0.0)
	add_child(p)
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)
