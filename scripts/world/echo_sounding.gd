extends Node

## Feature #5 — Echo-Sounding.
## Right-click the Resonator and it pings the rock around you: ore veins glow as ghost cubes
## THROUGH solid stone, lava pulses red. The signal attenuates with distance AND with how much
## solid rock sits between you and it (a cheap raymarch "muffle"), so deep diamond reads faint —
## "tunnel toward the strongest signal" becomes a real deduction, not a wallhack.
##
## Reuses: world.get_block (which falls back to the PURE generate_block for unmeshed cells, so it
## reads rock you've never seen), a MultiMesh of unshaded translucent cubes (the foliage pattern),
## color_of for vein colours. Capped radius + cooldown so the R^3 sample never becomes a map reveal.

const RADIUS := 11
const MAX_GHOSTS := 240
const FADE := 6.0
const COOLDOWN := 2.2

var world: ChunkManager
var player: Player
var _cd := 0.0
var _explained := false          # frame the deduction loop on the first successful ping
var _snd: AudioStreamPlayer

func setup(w, p) -> void:
	world = w
	player = p
	if player and player.has_signal("resonator_ping"):
		player.resonator_ping.connect(_ping)

func _ready() -> void:
	_snd = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/sfx/ui/click.mp3"):
		_snd.stream = load("res://assets/audio/sfx/ui/click.mp3")
	_snd.volume_db = -3.0
	_snd.pitch_scale = 0.6
	if AudioServer.get_bus_index("SFX") != -1:
		_snd.bus = "SFX"
	add_child(_snd)

func _process(delta: float) -> void:
	if _cd > 0.0:
		_cd -= delta

func _is_signal_block(id: int) -> bool:
	return id == VoxelTypes.COAL_ORE or id == VoxelTypes.IRON_ORE \
		or id == VoxelTypes.GOLD_ORE or id == VoxelTypes.DIAMOND_ORE or id == VoxelTypes.LAVA

func _ping() -> void:
	if _cd > 0.0 or world == null or player == null:
		return
	_cd = COOLDOWN
	if _snd and _snd.stream:
		_snd.play()
	var eye := player.global_position + Vector3(0, 1.5, 0)
	if player.camera and is_instance_valid(player.camera):
		eye = player.camera.global_position
	var ox := int(player.global_position.x)
	var oy := int(player.global_position.y)
	var oz := int(player.global_position.z)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.9, 0.9)
	mm.mesh = bm
	var xforms: Array = []
	var colors: Array = []
	var r2 := RADIUS * RADIUS
	var budget := 6200                                # hard backstop on per-ping read work
	var best_a := 0.0                                 # strongest (non-lava) signal, for the readout
	var best_id := -1
	var best_cell := Vector3.ZERO
	# Column-outer / y-inner: surface_height is sampled ONCE per (x,z) and reused down the column
	# (was recomputed per cell via get_block). Override-aware read keeps results identical to get_block.
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			if dx * dx + dz * dz > r2:
				continue
			var wx := ox + dx
			var wz := oz + dz
			var s := world.surface_height(wx, wz)
			for dy in range(-RADIUS, RADIUS + 1):
				if dx * dx + dy * dy + dz * dz > r2:
					continue
				var wy := oy + dy
				if wy < 1:
					continue
				budget -= 1
				if budget <= 0:
					break
				var cell := Vector3i(wx, wy, wz)
				var id: int = world.overrides[cell] if world.overrides.has(cell) else world.generate_block(wx, wy, wz, s)
				if not _is_signal_block(id):
					continue
				var c := Vector3(float(wx) + 0.5, float(wy) + 0.5, float(wz) + 0.5)
				var dist := eye.distance_to(c)
				if dist < 0.5:
					continue
				var dterm := 1.0 - clampf(dist / float(RADIUS + 1), 0.0, 1.0)
				if dterm < 0.06:
					continue                          # distance alone culls it — skip the raymarch entirely
				var muffle := _solid_between(eye, c)
				var a := dterm * (1.0 / (1.0 + muffle * 0.45))
				if a < 0.06:
					continue
				if id != VoxelTypes.LAVA and a > best_a:
					best_a = a
					best_id = id
					best_cell = c
				var col := VoxelTypes.color_of(id)
				if id == VoxelTypes.LAVA:
					col = Color(1.0, 0.3, 0.1)
				xforms.append(Transform3D(Basis(), c))
				colors.append(Color(col.r, col.g, col.b, clampf(a, 0.0, 0.9)))
				if xforms.size() >= MAX_GHOSTS:
					break
			if xforms.size() >= MAX_GHOSTS or budget <= 0:
				break
		if xforms.size() >= MAX_GHOSTS or budget <= 0:
			break

	if xforms.is_empty():
		if player.hud and player.hud.has_method("show_toast"):
			player.hud.show_toast("The resonance fades into dead rock.", Color(0.6, 0.7, 0.75))
		return
	mm.instance_count = xforms.size()
	var intro_shown := false
	if not _explained and player.hud and player.hud.has_method("show_toast"):
		_explained = true
		intro_shown = true
		player.hud.show_toast("Echo-sounding: %d signals — brighter = closer, red = lava." % xforms.size(), Color(0.55, 0.85, 0.95))
	# Surface the strongest read (type + rough bearing) so the deduction loop is legible.
	if best_id != -1 and player.hud and player.hud.has_method("show_toast"):
		if intro_shown:
			get_tree().create_timer(1.4).timeout.connect(_signal_readout.bind(best_id, best_cell, best_a))
		else:
			_signal_readout(best_id, best_cell, best_a)
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.no_depth_test = true                       # the whole point: read veins THROUGH rock
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	# Pulse-fade over a few seconds, then free.
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, FADE).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(mmi.queue_free)

## Coarse voxel raymarch: how many solid cells lie between the eye and a target (the "muffle").
func _solid_between(from: Vector3, to: Vector3) -> int:
	var d := to - from
	var dist := d.length()
	if dist < 1.0:
		return 0
	var steps := int(dist)
	var step := d / float(steps)
	var solid := 0
	var p := from
	for _i in range(steps):
		p += step
		var b := world.get_block(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)))
		if b != VoxelTypes.AIR and b != VoxelTypes.WATER and not _is_signal_block(b):
			solid += 1
	return solid

## Announce the strongest (non-lava) signal: its type, strength, and rough compass bearing.
func _signal_readout(best_id: int, best_cell: Vector3, best_a: float) -> void:
	if best_id == -1 or player == null or not is_instance_valid(player):
		return
	if not (player.hud and player.hud.has_method("show_toast")):
		return
	var dvec := best_cell - player.global_position
	var ang := atan2(dvec.x, -dvec.z)             # Godot: -Z is forward/north
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var compass: String = dirs[int(round(ang / (PI / 4.0))) & 7]
	var strength := "faint"
	if best_a >= 0.6:
		strength = "strong"
	elif best_a >= 0.3:
		strength = "clear"
	player.hud.show_toast("Strongest: %s, %s — to the %s." % [VoxelTypes.name_of(best_id), strength, compass], VoxelTypes.color_of(best_id))
