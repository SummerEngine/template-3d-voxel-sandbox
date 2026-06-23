extends Node

## Feature #3 — Hauntfields.
## Wherever a mob falls or you die, the ground keeps a grave (world.graves: cell -> kill_count,
## persisted). Later nights bias the hostile spawn ring toward your bloodiest battlefields, and
## on a Blood Moon part of the horde claws up out of your densest killing ground.
## Graves decay slowly so abandoned fields go quiet; the registry is pruned to bound the save.
##
## Reuses: player.mob_died_at / player.died_at signals, surface_height, the main spawn ring
## (main calls bias_spawn + blood_moon_targets), a pooled dirt-burst for the claw-up.

const NEAR := 42.0            # graves within this range steer the night
const NEAR2 := NEAR * NEAR
const MAX_GRAVES := 400       # prune cap (keep the bloodiest)
const DECAL_POOL := 48
const DECAY_EVERY := 60.0

var world: ChunkManager
var player: Player
var _decals: Array = []
var _decal_i := 0
var _decay_t := DECAY_EVERY
var _rng := RandomNumberGenerator.new()
var _announced := false

func setup(w, p) -> void:
	world = w
	player = p
	if player:
		if player.has_signal("mob_died_at"):
			player.mob_died_at.connect(_on_death)
		if player.has_signal("died_at"):
			player.died_at.connect(_on_death)

func _ready() -> void:
	_rng.randomize()
	for _i in range(DECAL_POOL):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.05, 0.04, 1.05)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.05, 0.02, 0.02, 0.0)
		mi.material_override = m
		mi.visible = false
		add_child(mi)
		_decals.append(mi)

func _on_death(pos: Vector3) -> void:
	var cell := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
	var inc := 1
	# A player death scars the ground harder than a mob's.
	if player and pos.distance_to(player.global_position) < 2.5 and player.has_method("is_dead") and player.is_dead():
		inc = 3
	world.graves[cell] = int(world.graves.get(cell, 0)) + inc
	_mark(cell)
	if not _announced and world.graves.size() >= 6:
		_announced = true
		if player and player.hud and player.hud.has_method("show_toast"):
			player.hud.show_toast("The ground remembers...", Color(0.7, 0.55, 0.55))

func _mark(cell: Vector3i) -> void:
	var gy := world.surface_height(cell.x, cell.z)
	var d: MeshInstance3D = _decals[_decal_i]
	_decal_i = (_decal_i + 1) % DECAL_POOL
	d.global_position = Vector3(float(cell.x) + 0.5, float(gy) + 1.06, float(cell.z) + 0.5)
	d.visible = true
	if d.material_override:
		# A readable dried-blood scorch (was near-black + floating, almost invisible at night).
		var w: float = clampf(float(int(world.graves.get(cell, 1))) / 5.0, 0.0, 1.0)
		d.material_override.albedo_color = Color(0.16 + 0.1 * w, 0.03, 0.02, 0.78)

## Bias one siege spawn toward a nearby battlefield. Returns {ang, rad}; falls back to the
## passed-in defaults when there's no blood nearby to draw on.
func bias_spawn(player_pos: Vector3, def_ang: float, def_rad: float) -> Dictionary:
	if world.graves.is_empty() or _rng.randf() > 0.6:
		return {"ang": def_ang, "rad": def_rad}
	var picks: Array = []
	var weights := 0
	for cell in world.graves.keys():
		var c := Vector3(cell) + Vector3(0.5, 0, 0.5)
		if Vector2(c.x - player_pos.x, c.z - player_pos.z).length_squared() <= NEAR2:
			var w: int = int(world.graves[cell])
			if w >= 2:
				picks.append([cell, w])
				weights += w
	if picks.is_empty():
		return {"ang": def_ang, "rad": def_rad}
	var roll := _rng.randi_range(1, weights)
	var acc := 0
	var chosen = picks[0][0]
	for pr in picks:
		acc += int(pr[1])
		if roll <= acc:
			chosen = pr[0]
			break
	var dx := (float(chosen.x) + 0.5) - player_pos.x
	var dz := (float(chosen.z) + 0.5) - player_pos.z
	var ang := atan2(dz, dx) + _rng.randf_range(-0.5, 0.5)
	return {"ang": ang, "rad": def_rad}

## On a Blood Moon: pick up to n dense grave cells near the player for the horde to erupt from.
func blood_moon_targets(n: int) -> Array:
	var out: Array = []
	if player == null or world.graves.is_empty():
		return out
	var pp := player.global_position
	var ranked: Array = []
	for cell in world.graves.keys():
		var c := Vector3(cell) + Vector3(0.5, 0, 0.5)
		if Vector2(c.x - pp.x, c.z - pp.z).length_squared() <= NEAR2 and int(world.graves[cell]) >= 3:
			ranked.append(cell)
	ranked.sort_custom(func(a, b): return int(world.graves[a]) > int(world.graves[b]))
	for i in range(mini(n, ranked.size())):
		var cell: Vector3i = ranked[i]
		var gy := world.surface_height(cell.x, cell.z)
		out.append(Vector3(float(cell.x) + 0.5, float(gy) + 2.0, float(cell.z) + 0.5))
	return out

## A short dirt-burst where a zombie claws its way up out of marked soil.
func clawup_vfx(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.32, 0.22, 0.14)
	bm.material = m
	p.mesh = bm
	p.amount = 22
	p.one_shot = true
	p.lifetime = 0.8
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -9.0, 0)
	p.global_position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)

func _process(delta: float) -> void:
	_decay_t -= delta
	if _decay_t > 0.0:
		return
	_decay_t = DECAY_EVERY
	# Slow decay so abandoned battlefields go quiet; prune to bound the save.
	var dead: Array = []
	for cell in world.graves.keys():
		var v: int = int(world.graves[cell]) - 1
		if v <= 0:
			dead.append(cell)
		else:
			world.graves[cell] = v
	for cell in dead:
		world.graves.erase(cell)
	if world.graves.size() > MAX_GRAVES:
		var keys: Array = world.graves.keys()
		keys.sort_custom(func(a, b): return int(world.graves[a]) < int(world.graves[b]))
		for i in range(world.graves.size() - MAX_GRAVES):
			world.graves.erase(keys[i])
