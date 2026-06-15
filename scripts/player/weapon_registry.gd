class_name WeaponRegistry

## All player weapons/tools with gameplay stats. Designed + balance-reviewed.
## damage = melee damage, attack_speed = swings/sec, mining_power = block-break
## multiplier vs bare hand (1.0). Models live in assets/models/weapons/.

const DIR := "res://assets/models/weapons/"

const WEAPONS := [
	{"name": "Wooden Pickaxe",   "file": "pickaxe",          "category": "pickaxe", "damage": 2,  "attack_speed": 1.4, "mining_power": 2.0, "tier": 1, "desc": "A crude wooden pick — mines stone and coal, but ore tougher than iron shrugs it off."},
	{"name": "Stone Pickaxe",    "file": "pickaxe",          "category": "pickaxe", "damage": 3,  "attack_speed": 1.4, "mining_power": 3.0, "tier": 2, "desc": "A sturdier stone pick that bites into iron ore as well as stone."},
	{"name": "Iron Pickaxe",     "file": "pickaxe",          "category": "pickaxe", "damage": 4,  "attack_speed": 1.5, "mining_power": 4.5, "tier": 3, "desc": "A forged iron pick — fast on stone and the only thing that frees gold and diamond."},
	{"name": "Diamond Pickaxe",  "file": "pickaxe",          "category": "pickaxe", "damage": 5,  "attack_speed": 1.6, "mining_power": 6.0, "tier": 4, "desc": "The ultimate pick — tears through any block in the world at blinding speed."},
	{"name": "Gold Pickaxe",     "file": "pickaxe",          "category": "pickaxe", "damage": 3,  "attack_speed": 1.9, "mining_power": 7.5, "tier": 2, "desc": "A gleaming gold pick — blisteringly fast on stone, coal and iron, but too soft to free gold or diamond."},
	{"name": "Chisel",           "file": "chisel",           "category": "chisel",  "damage": 3,  "attack_speed": 2.6, "mining_power": 2.0, "desc": "A fine carving chisel that chips stone fast but barely scratches foes."},
	{"name": "Heavy Chisel",     "file": "chisel_heavy",     "category": "chisel",  "damage": 4,  "attack_speed": 2.2, "mining_power": 2.3, "desc": "A thick-shanked chisel that bites deeper into rock and bone alike."},
	{"name": "Wooden Sword",     "file": "sword_iron",       "category": "sword",   "damage": 3,  "attack_speed": 1.6, "mining_power": 1.0, "desc": "A whittled wooden blade — better than fists, barely."},
	{"name": "Stone Sword",      "file": "sword_iron",       "category": "sword",   "damage": 5,  "attack_speed": 1.6, "mining_power": 1.1, "desc": "A chipped stone edge that hits noticeably harder than wood."},
	{"name": "Iron Sword",       "file": "sword_iron",       "category": "sword",   "damage": 7,  "attack_speed": 1.5, "mining_power": 1.1, "desc": "A dependable iron blade with a clean balance of speed and bite."},
	{"name": "Diamond Sword",    "file": "sword_iron",       "category": "sword",   "damage": 10, "attack_speed": 1.6, "mining_power": 1.2, "desc": "A flawless diamond edge — the deadliest blade you can forge."},
	{"name": "Gold Sword",       "file": "sword_iron",       "category": "sword",   "damage": 8,  "attack_speed": 2.1, "mining_power": 1.1, "desc": "A gilded blade — lightning-fast and sharp, prized as much for its gleam as its bite."},
	{"name": "Scimitar",         "file": "scimitar",         "category": "sword",   "damage": 8,  "attack_speed": 1.5, "mining_power": 1.1, "desc": "A sweeping curved blade built for swift, slashing strikes."},
	{"name": "Shamshir",         "file": "scimitar_short",   "category": "sword",   "damage": 6,  "attack_speed": 1.8, "mining_power": 1.0, "desc": "A compact deeply-curved Persian sabre that trades reach for blinding speed."},
	{"name": "Cutlass",          "file": "cutlass",          "category": "sword",   "damage": 7,  "attack_speed": 1.6, "mining_power": 1.1, "desc": "A curved single-edged sailor's blade, quick to draw and quicker to slash."},
	{"name": "Broadsword",       "file": "sword_wide",       "category": "sword",   "damage": 9,  "attack_speed": 1.3, "mining_power": 1.2, "desc": "A heavy wide-bladed sword that lands crushing, decisive cuts."},
	{"name": "Falchion",         "file": "blade_wide",       "category": "sword",   "damage": 8,  "attack_speed": 1.4, "mining_power": 1.2, "desc": "A heavy single-edged falchion favoring raw chopping power over finesse."},
	{"name": "Messer",           "file": "blade_wide_small", "category": "sword",   "damage": 6,  "attack_speed": 1.7, "mining_power": 1.1, "desc": "A stout German messer with surprising bite in close quarters."},
	{"name": "Short Dagger",     "file": "dagger_short",     "category": "dagger",  "damage": 3,  "attack_speed": 2.7, "mining_power": 1.0, "desc": "A nimble little blade made for lightning-quick stabs up close."},
	{"name": "Rondel Dagger",    "file": "dagger_round",     "category": "dagger",  "damage": 4,  "attack_speed": 2.5, "mining_power": 1.0, "desc": "A round-guarded rondel that favors fast flurries over heavy hits."},
	{"name": "Karambit",         "file": "dagger_bent",      "category": "dagger",  "damage": 4,  "attack_speed": 2.4, "mining_power": 1.0, "desc": "A curved hooked karambit that hooks and tears on the draw."},
	{"name": "Baselard",         "file": "dagger_wide_small","category": "dagger",  "damage": 5,  "attack_speed": 2.1, "mining_power": 1.0, "desc": "A broad-bladed baselard that carves wider wounds than its size suggests."},
	{"name": "Kris",             "file": "stiletto_wavy",    "category": "dagger",  "damage": 4,  "attack_speed": 2.5, "mining_power": 1.0, "desc": "A serpentine wavy-bladed kris that slips between armor with every thrust."},
	{"name": "Round Stiletto",   "file": "stiletto_round",   "category": "dagger",  "damage": 4,  "attack_speed": 2.6, "mining_power": 1.0, "desc": "A smooth round-shaft stiletto made for quick, repeated jabs."},
	{"name": "Sickle",           "file": "sickle",           "category": "sickle",  "damage": 6,  "attack_speed": 1.7, "mining_power": 1.1, "desc": "A hooked harvesting blade that reaps crops and careless enemies alike."},
	{"name": "Broadaxe",         "file": "battleaxe",        "category": "axe",     "damage": 10, "attack_speed": 1.2, "mining_power": 1.6, "desc": "A wide-bitted axe that fells trees and foes in heavy, biting arcs."},
	{"name": "War Axe",          "file": "battleaxe",          "category": "axe",     "damage": 11, "attack_speed": 1.1, "mining_power": 1.6, "desc": "A battle-forged axe balanced for splitting helms on the field."},
	{"name": "Bardiche",         "file": "battleaxe",         "category": "polearm", "damage": 11, "attack_speed": 1.1, "mining_power": 1.4, "desc": "A long-hafted axe-polearm that sweeps enemies at the end of its reach."},
	{"name": "Spiked Mace",      "file": "warmaul",             "category": "mace",    "damage": 11, "attack_speed": 1.1, "mining_power": 1.3, "desc": "A brutal spiked head that punches straight through plate and skull."},
	{"name": "Flanged Mace",     "file": "warmaul",       "category": "mace",    "damage": 10, "attack_speed": 1.2, "mining_power": 1.3, "desc": "A flanged steel head that delivers reliable, bone-jarring blows."},
	{"name": "Wooden Mallet",    "file": "warmaul",           "category": "hammer",  "damage": 8,  "attack_speed": 1.3, "mining_power": 1.3, "desc": "A simple wooden mallet that thumps with honest, blunt force."},
	{"name": "Warhammer",        "file": "warmaul",      "category": "maul",    "damage": 12, "attack_speed": 1.0, "mining_power": 1.3, "desc": "A forged warhammer balanced just enough to swing without losing its punch."},
	{"name": "Great Maul",       "file": "warmaul",      "category": "maul",    "damage": 13, "attack_speed": 1.0, "mining_power": 1.3, "desc": "A solid great maul that turns slow swings into devastating impacts."},
	{"name": "Sledgehammer",     "file": "warmaul",     "category": "maul",    "damage": 15, "attack_speed": 0.8, "mining_power": 1.3, "desc": "A two-handed wrecker that flattens anything its slow swing connects with."},
	{"name": "Heavy Maul",       "file": "warmaul",       "category": "maul",    "damage": 17, "attack_speed": 0.7, "mining_power": 1.3, "desc": "A monstrous slab of a maul that pulps anything caught by its ponderous arc."},
	{"name": "Bare Hands",       "file": "",                 "category": "fist",    "damage": 1,  "attack_speed": 2.0, "mining_power": 1.0, "desc": "No weapon — weak, slow to mine, but always ready."},
]

static func list() -> Array:
	var out: Array = []
	for w in WEAPONS:
		out.append(_with_path(w))
	return out

static func _with_path(w: Dictionary) -> Dictionary:
	var d: Dictionary = w.duplicate()
	d["path"] = DIR + String(w.file) + ".glb"
	return d

## Look up a single weapon/tool by its display name (with the model path resolved).
static func by_name(n: String) -> Dictionary:
	for w in WEAPONS:
		if String(w.name) == n:
			return _with_path(w)
	return {}
