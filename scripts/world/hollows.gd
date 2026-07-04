extends Node

## Feature #6 — The Hunger of Hollows.
## Every block of air you carve UNDERGROUND raises that region's "hollow" pressure. Over-mine and
## the hollow grows hungry, in staggered stages: (1) nearby torches gutter and dim — an
## atmospheric warning; (2) lurkers stir more often; (3) a telegraphed ceiling collapse (creak +
## dust, then a block drops and hurts if you're under it). Filling the space back LOWERS the
## pressure; fully calming a hungry hollow pays out once — "the dark forgives you."
##
## Reuses: player.block_broken_at / block_placed_at, surface_height, the torch dict + lights,
## set_block, player.hurt, a HostileMob lurker (day_night unset, so it never burns).

const REGION := 8             # cells per region edge
const T1 := 12                # torches gutter
const T2 := 22                # lurkers stir
const T3 := 34                # collapse risk
const TICK := 2.5
const COLLAPSE_CD := 26.0
const MAX_CALMED := 512      # cap the persisted calmed-region dict (like MAX_GRAVES) so long saves stay flat
const LURKER_CAP := 2

var world: ChunkManager
var player: Player
var _t := TICK
var _collapse_cd := 10.0
var _lurkers: Array = []
var _hungry := {}             # region keys that have reached T2 (await calming for the reward)
var _warned := {}             # region key -> highest stage announced
var _rng := RandomNumberGenerator.new()
var _creak: AudioStreamPlayer

func setup(w, p) -> void:
	world = w
	player = p
	if player:
		if player.has_signal("block_broken_at"):
			player.block_broken_at.connect(_on_broken)
		if player.has_signal("block_placed_at"):
			player.block_placed_at.connect(_on_placed)

func _ready() -> void:
	_rng.randomize()
	_creak = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/weather/wind_gust.mp3"):
		_creak.stream = load("res://assets/audio/weather/wind_gust.mp3")
	_creak.volume_db = -2.0
	_creak.pitch_scale = 0.5
	if AudioServer.get_bus_index("SFX") != -1:
		_creak.bus = "SFX"
	add_child(_creak)

func _key(wx: int, wy: int, wz: int) -> String:
	return "%d,%d,%d" % [floori(float(wx) / REGION), floori(float(wy) / REGION), floori(float(wz) / REGION)]

func _underground(wx: int, wy: int, wz: int) -> bool:
	return wy < world.surface_height(wx, wz) - 2

func _on_broken(cell: Vector3i, _id: int) -> void:
	if not _underground(cell.x, cell.y, cell.z):
		return
	var k := _key(cell.x, cell.y, cell.z)
	world.hollow_scores[k] = int(world.hollow_scores.get(k, 0)) + 1

func _on_placed(cell: Vector3i, _id: int) -> void:
	if not _underground(cell.x, cell.y, cell.z):
		return
	var k := _key(cell.x, cell.y, cell.z)
	var v: int = int(world.hollow_scores.get(k, 0)) - 1
	if v <= 0:
		world.hollow_scores.erase(k)
		if _hungry.has(k):
			_hungry.erase(k)
			_warned.erase(k)
			# Pay the calm-the-hollow reward only ONCE per region (persisted) — no dig/refill farm.
			if not world.hollow_calmed.has(k):
				world.hollow_calmed[k] = true
				# Bound this persisted dict so a marathon over-mined save doesn't grow it forever (serialized
				# in full every save). Evict oldest-inserted; a re-calmed evictee re-pays 1 iron once — fine.
				if world.hollow_calmed.size() > MAX_CALMED:
					var _ck: Array = world.hollow_calmed.keys()
					for _i in range(world.hollow_calmed.size() - MAX_CALMED):
						world.hollow_calmed.erase(_ck[_i])
				if player and player.hud and player.hud.has_method("show_toast"):
					player.hud.show_toast("The dark forgives you.", Color(0.7, 0.95, 0.8))
				if player and player.has_method("give_or_drop"):
					player.give_or_drop(VoxelTypes.IRON_INGOT, 1)
	else:
		world.hollow_scores[k] = v

func _process(delta: float) -> void:
	for i in range(_lurkers.size() - 1, -1, -1):
		var m = _lurkers[i]
		if not is_instance_valid(m):
			_lurkers.remove_at(i)
		elif player and m.global_position.distance_squared_to(player.global_position) > 784.0:   # 28² — avoid per-frame sqrt
			m.queue_free()
			_lurkers.remove_at(i)
	if _collapse_cd > 0.0:
		_collapse_cd -= delta
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	if player == null or world == null:
		return
	var px := int(player.global_position.x)
	var py := int(player.global_position.y)
	var pz := int(player.global_position.z)
	if not _underground(px, py, pz):
		return
	var k := _key(px, py, pz)
	var score: int = int(world.hollow_scores.get(k, 0))
	if score >= T2:
		_hungry[k] = true
	var stage := 0
	if score >= T3: stage = 3
	elif score >= T2: stage = 2
	elif score >= T1: stage = 1
	if stage > int(_warned.get(k, 0)):
		_warned[k] = stage
		_announce(stage)
	if stage >= 1 and _rng.randf() < 0.6:
		_gutter_torch()
	if stage >= 2 and _lurkers.size() < LURKER_CAP and _rng.randf() < 0.5:
		_spawn_lurker(px, py, pz)
	if stage >= 3 and _collapse_cd <= 0.0 and _rng.randf() < 0.5:
		_collapse(px, py, pz)

func _announce(stage: int) -> void:
	if player == null or player.hud == null or not player.hud.has_method("show_toast"):
		return
	match stage:
		1: player.hud.show_toast("A cold draft moves through the hollow.", Color(0.7, 0.78, 0.85))
		2: player.hud.show_toast("Something stirs in the carved-out dark.", Color(0.8, 0.7, 0.6))
		3: player.hud.show_toast("The hollow groans — the ceiling is unsound.", Color(0.95, 0.6, 0.5))

func _gutter_torch() -> void:
	for cell in world.torches.keys():
		var p := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
		if player.global_position.distance_to(p) > 11.0:
			continue
		var prop = world.torches[cell]
		if not is_instance_valid(prop):
			continue
		for ch in prop.get_children():
			if ch is OmniLight3D:
				var base: float = ch.light_energy
				if base <= 0.9:
					continue                      # already guttering — pick another
				var tw := create_tween()
				tw.tween_property(ch, "light_energy", 0.5, 0.6)
				tw.tween_interval(1.6)
				tw.tween_property(ch, "light_energy", base, 1.2)
				return

func _spawn_lurker(px: int, py: int, pz: int) -> void:
	for _try in range(10):
		var ox := _rng.randi_range(-10, 10)
		var oz := _rng.randi_range(-10, 10)
		if absi(ox) < 4 and absi(oz) < 4:
			continue
		var cx := px + ox
		var cz := pz + oz
		var cy := py
		if world.get_block(cx, cy, cz) == VoxelTypes.AIR \
				and world.get_block(cx, cy + 1, cz) == VoxelTypes.AIR \
				and VoxelTypes.is_solid(world.get_block(cx, cy - 1, cz)):
			var mob := preload("res://scripts/entities/hostile_mob.gd").new()
			mob.player = player
			mob.world = world
			mob.health = 10
			mob.damage = 3
			mob.position = Vector3(float(cx) + 0.5, float(cy), float(cz) + 0.5)
			add_child(mob)
			_lurkers.append(mob)
			return

func _collapse(px: int, py: int, pz: int) -> void:
	# Find the first solid ceiling block above the player's head.
	var cy := -1
	for h in range(2, 7):
		if world.overrides.has(Vector3i(px, py + h, pz)):
			continue                              # never collapse a player-placed/edited block
		var b := world.get_block(px, py + h, pz)
		if VoxelTypes.is_solid(b) and b != VoxelTypes.BEDROCK:
			cy = py + h
			break
	if cy < 0:
		return
	_collapse_cd = COLLAPSE_CD
	if _creak and _creak.stream:
		_creak.play()
	var pos := Vector3(float(px) + 0.5, float(cy) + 0.5, float(pz) + 0.5)
	_dust(pos, Color(0.5, 0.45, 0.4), 10)
	if player.has_method("add_trauma"):
		player.add_trauma(0.3)
	# Telegraph, then the block lets go.
	var cell := Vector3i(px, cy, pz)
	get_tree().create_timer(1.3).timeout.connect(_drop_ceiling.bind(cell))

func _drop_ceiling(cell: Vector3i) -> void:
	if world.get_block(cell.x, cell.y, cell.z) == VoxelTypes.AIR:
		return                                    # already mined away in the meantime
	if world.overrides.has(cell):
		return                                    # player built/altered this during the telegraph — leave it
	world.set_block(cell.x, cell.y, cell.z, VoxelTypes.AIR)
	var pos := Vector3(cell) + Vector3(0.5, 0.0, 0.5)
	_dust(pos, Color(0.45, 0.4, 0.36), 26)
	if player and player.has_method("add_trauma"):
		player.add_trauma(0.5)
	# Hurt the player if they're roughly beneath the fall.
	if player:
		var d := Vector2(player.global_position.x - pos.x, player.global_position.z - pos.z).length()
		if d < 1.6 and player.global_position.y < float(cell.y) and player.has_method("hurt"):
			player.hurt(4)
	# A region that collapses has "digested" some pressure.
	var k := _key(cell.x, cell.y, cell.z)
	world.hollow_scores[k] = maxi(0, int(world.hollow_scores.get(k, 0)) - 6)

func _dust(pos: Vector3, col: Color, amount: int) -> void:
	# Reuse the player's pooled burst (tuned scale-taper + alpha fade) instead of allocating a fresh
	# CPUParticles3D + BoxMesh + StandardMaterial3D + timer node per collapse/telegraph.
	if player and player.has_method("_emit_burst"):
		player._emit_burst(pos, col, amount, 1.0, 35.0, 1.0, 3.0, 6.0, Vector3.DOWN)
