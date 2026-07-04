extends Node

## Feature #1 — Heat-Shimmer Mirages & False Oases.
## In a sandstorm or a snow whiteout a shape resolves out of the haze ahead of you — a tower, an
## oasis, or a still figure — and dissolves as you approach. A rare, seeded few are REAL: they
## commit an actual little ruin + loot where the lie stood, announced by one detuned note.
##
## Reuses: weather state (poll — Weather has no signals), surface_height, set_block, chest_at,
## the player camera for facing. One live imposter at a time, long cooldown — cheap and safe.

const W_SANDSTORM := 3        # Weather.SANDSTORM (enum int; weather.gd has no public getter)
const W_SNOW := 4             # Weather.SNOW
const FOG_DIST := 26.0        # how far out the imposter forms (near the fog edge)
const DISSOLVE_DIST := 12.0   # fakes melt once you get this close
const COMMIT_DIST := 15.0     # reals commit (stamp the structure) at this range
const LIFETIME := 34.0        # gone after this even if you never approach
const COOLDOWN := 28.0        # min seconds between mirages
const COMMIT_PCT := 8         # ~8% of mirages turn out to be real

var world: ChunkManager
var player: Player
var day_night
var weather

var _imp: Node3D
var _mat: StandardMaterial3D
var _t := 0.0
var _life := 0.0
var _cd := 10.0
var _check := 0.0
var _real := false
var _committed := false
var _committed_once := false
var _snd: AudioStreamPlayer

func setup(w, p, dn, wx) -> void:
	world = w
	player = p
	day_night = dn
	weather = wx

func _ready() -> void:
	_snd = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/weather/wind_gust.mp3"):
		_snd.stream = load("res://assets/audio/weather/wind_gust.mp3")
	_snd.volume_db = -4.0
	_snd.pitch_scale = 0.38                       # detuned, dreamlike
	if AudioServer.get_bus_index("Ambient") != -1:
		_snd.bus = "Ambient"
	add_child(_snd)

func _process(delta: float) -> void:
	if player == null or world == null:
		return
	if _imp and is_instance_valid(_imp):
		_update_imposter(delta)
		return
	if not GameSettings.world_unease:
		return                                    # the "Eerie events" toggle silences new phantoms
	_cd -= delta
	if _cd > 0.0:
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	if _hazy():
		_spawn_imposter()

func _hazy() -> bool:
	if weather == null:
		return false
	if int(weather.weather) == W_SANDSTORM:
		return true
	if int(weather.weather) == W_SNOW and float(weather._intensity) > 0.45:
		return true
	return false

func _hash(x: int, z: int) -> int:
	var h: int = (x * 73856093) ^ (z * 19349663)
	return absi(h)

func _spawn_imposter() -> void:
	var cam = player.camera if player.camera else null
	var fwd := Vector3(0, 0, -1)
	if cam and is_instance_valid(cam):
		fwd = -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var side := randf_range(-6.0, 6.0)
	var base := player.global_position + fwd * FOG_DIST + Vector3(-fwd.z, 0, fwd.x) * side
	var gx := floori(base.x)
	var gz := floori(base.z)
	var sy := world.surface_height(gx, gz)
	if sy <= world.SEA_LEVEL - 1:
		_cd = 6.0
		return                                    # don't conjure a tower in the open sea
	var h := _hash(gx >> 2, gz >> 2)
	_real = (h % 100) < COMMIT_PCT
	_committed = false
	_t = 0.0
	_life = 0.0
	var kind := h % 3                             # 0 tower, 1 oasis, 2 figure

	_imp = Node3D.new()
	add_child(_imp)
	_imp.global_position = Vector3(float(gx) + 0.5, float(sy) + 1.0, float(gz) + 0.5)

	var snow := int(weather.weather) == W_SNOW
	var tint := Color(0.93, 0.95, 0.99) if snow else Color(0.88, 0.80, 0.62)
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.0)
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	match kind:
		1:                                        # false oasis: a still water disc + a lone palm
			_add_box(Vector3(7, 0.12, 7), Vector3(0, 0.06, 0), Color(0.35, 0.55, 0.8))
			_add_box(Vector3(0.5, 4.0, 0.5), Vector3(1.6, 2.0, 1.0), Color(0.4, 0.3, 0.18))
			_add_box(Vector3(2.4, 0.6, 2.4), Vector3(1.6, 4.2, 1.0), Color(0.25, 0.5, 0.25))
		2:                                        # a still figure, watching
			_add_box(Vector3(0.85, 2.4, 0.55), Vector3(0, 1.2, 0), Color(0.06, 0.07, 0.09))
		_:                                        # a tower out of the murk
			_add_box(Vector3(3.0, 10.0, 3.0), Vector3(0, 5.0, 0), Color(0.4, 0.4, 0.45))
			_add_box(Vector3(3.6, 1.0, 3.6), Vector3(0, 10.2, 0), Color(0.34, 0.34, 0.4))

func _add_box(sz: Vector3, off: Vector3, base_col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	# Each piece shares the haze material but keeps its own albedo via an override copy so the
	# whole silhouette fades together (alpha driven on the shared _mat each frame).
	var m: StandardMaterial3D = _mat.duplicate()
	m.albedo_color = Color(base_col.r, base_col.g, base_col.b, 0.0)
	mi.material_override = m
	mi.position = off
	mi.set_meta("base_rgb", base_col)
	_imp.add_child(mi)

func _update_imposter(delta: float) -> void:
	_t += delta
	_life += delta
	var d := player.global_position.distance_to(_imp.global_position)
	if _life > LIFETIME or not _hazy():
		_dispel()
		return
	if _real and d < COMMIT_DIST and not _committed:
		_commit()
		return
	if not _real and d < DISSOLVE_DIST:
		_dispel()
		return
	# Orient to face the player on the horizontal only when not essentially on its column
	# (a near-zero horizontal forward makes look_at error / NaN — e.g. flying directly overhead).
	var hdx := player.global_position.x - _imp.global_position.x
	var hdz := player.global_position.z - _imp.global_position.z
	if hdx * hdx + hdz * hdz > 0.04:
		var look := player.global_position
		look.y = _imp.global_position.y
		_imp.look_at(look, Vector3.UP)
	var a := clampf((d - DISSOLVE_DIST) / (FOG_DIST - DISSOLVE_DIST), 0.0, 1.0) * 0.8
	_imp.scale.y = 1.0 + sin(_t * 7.0) * 0.05     # vertical heat-warp shimmer
	for c in _imp.get_children():
		if c is MeshInstance3D and c.material_override:
			var rgb: Color = c.get_meta("base_rgb", Color.WHITE)
			c.material_override.albedo_color = Color(rgb.r, rgb.g, rgb.b, a)

## A real mirage commits: a little stone-brick obelisk + a loot chest stamp into the world exactly
## where the lie stood. The eerie note + toast teach that the audio tell means "this one is real".
func _commit() -> void:
	var ix := floori(_imp.global_position.x)
	var iz := floori(_imp.global_position.z)
	var iy := world.surface_height(ix, iz)
	var cc := Vector3i(ix + 1, iy + 1, iz)
	# Never stamp over the player's work: if any obelisk/chest cell is a player edit, or the chest
	# spot is occupied / already a chest, abandon — the "real" mirage simply melts like a fake
	# instead of bulldozing a build or hijacking existing storage.
	for hgt in range(4):
		if world.overrides.has(Vector3i(ix, iy + 1 + hgt, iz)):
			_dispel()
			return
	if world.overrides.has(Vector3i(ix, iy + 5, iz)) or world.overrides.has(cc):
		_dispel()
		return
	if world.get_block(cc.x, cc.y, cc.z) != VoxelTypes.AIR or world.chests.has(cc):
		_dispel()
		return
	_committed = true
	for hgt in range(4):
		world.set_block(ix, iy + 1 + hgt, iz, VoxelTypes.STONE_BRICKS)
	world.set_block(ix, iy + 5, iz, VoxelTypes.POLISHED_STONE)
	world.set_block(cc.x, cc.y, cc.z, VoxelTypes.CHEST)
	var inv = world.chest_at(cc)
	inv.add(VoxelTypes.DIAMOND, 1)
	inv.add(VoxelTypes.GOLD_INGOT, 2)
	inv.add(VoxelTypes.COOKED_MEAT, 3)
	_eerie()
	if player and player.hud and player.hud.has_method("show_toast"):
		if not _committed_once:
			_committed_once = true
			player.hud.show_toast("A Waking Dream — not every mirage lies.", Color(0.78, 0.9, 1.0))
		else:
			player.hud.show_toast("The dream held true — a cache remains.", Color(0.78, 0.9, 1.0))
	# Gold shimmer rising out of the haze so the loot's arrival is unmistakable.
	if player and is_instance_valid(player) and player.has_method("_emit_burst"):
		player._emit_burst(Vector3(cc.x + 0.5, cc.y + 0.5, cc.z + 0.5), Color(1.0, 0.85, 0.4), 24, 1.1, 0.4, 0.6, 1.6, 1.2)
	_free_imp()
	_cd = COOLDOWN * 1.5

func _eerie() -> void:
	if _snd and _snd.stream:
		_snd.play()

func _dispel() -> void:
	_free_imp()
	_cd = COOLDOWN

func _free_imp() -> void:
	if _imp and is_instance_valid(_imp):
		_imp.queue_free()
	_imp = null
	_mat = null
	_life = 0.0
	_committed = false
