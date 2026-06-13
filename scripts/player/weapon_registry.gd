class_name WeaponRegistry

## All player weapons/tools with gameplay stats. Designed + balance-reviewed.
## damage = melee damage, attack_speed = swings/sec, mining_power = block-break
## multiplier vs bare hand (1.0). Models live in assets/models/weapons/.

const DIR := "res://assets/models/weapons/"

const WEAPONS := [
	{"name": "Pickaxe",          "file": "pickaxe",          "category": "pickaxe", "damage": 3,  "attack_speed": 1.4, "mining_power": 3.0, "desc": "The miner's mainstay; tears through stone and ore far faster than any blade."},
	{"name": "Chisel",           "file": "chisel",           "category": "chisel",  "damage": 3,  "attack_speed": 2.6, "mining_power": 2.0, "desc": "A fine carving chisel that chips stone fast but barely scratches foes."},
	{"name": "Heavy Chisel",     "file": "chisel_heavy",     "category": "chisel",  "damage": 4,  "attack_speed": 2.2, "mining_power": 2.3, "desc": "A thick-shanked chisel that bites deeper into rock and bone alike."},
	{"name": "Iron Sword",       "file": "sword_iron",       "category": "sword",   "damage": 7,  "attack_speed": 1.5, "mining_power": 1.1, "desc": "A dependable iron blade with a clean balance of speed and bite."},
	{"name": "Scimitar",         "file": "scimitar",         "category": "sword",   "damage": 8,  "attack_speed": 1.5, "mining_power": 1.1, "desc": "A sweeping curved blade built for swift, slashing strikes."},
	{"name": "Short Scimitar",   "file": "scimitar_short",   "category": "sword",   "damage": 6,  "attack_speed": 1.8, "mining_power": 1.0, "desc": "A compact curved sword that trades reach for blinding speed."},
	{"name": "Cutlass",          "file": "cutlass",          "category": "sword",   "damage": 7,  "attack_speed": 1.6, "mining_power": 1.1, "desc": "A curved single-edged sailor's blade, quick to draw and quicker to slash."},
	{"name": "Broadsword",       "file": "sword_wide",       "category": "sword",   "damage": 9,  "attack_speed": 1.3, "mining_power": 1.2, "desc": "A heavy wide-bladed sword that lands crushing, decisive cuts."},
	{"name": "Wide Blade",       "file": "blade_wide",       "category": "sword",   "damage": 8,  "attack_speed": 1.4, "mining_power": 1.2, "desc": "A heavy slab of a blade favoring raw chopping power over finesse."},
	{"name": "Cleaver Shortblade","file": "blade_wide_small","category": "sword",   "damage": 6,  "attack_speed": 1.7, "mining_power": 1.1, "desc": "A stubby wide blade with surprising bite in close quarters."},
	{"name": "Short Dagger",     "file": "dagger_short",     "category": "dagger",  "damage": 3,  "attack_speed": 2.7, "mining_power": 1.0, "desc": "A nimble little blade made for lightning-quick stabs up close."},
	{"name": "Round Dagger",     "file": "dagger_round",     "category": "dagger",  "damage": 4,  "attack_speed": 2.5, "mining_power": 1.0, "desc": "A rounded-tip dagger that favors fast flurries over heavy hits."},
	{"name": "Bent Dagger",      "file": "dagger_bent",      "category": "dagger",  "damage": 4,  "attack_speed": 2.4, "mining_power": 1.0, "desc": "A crooked-bladed dagger that hooks and tears on the draw."},
	{"name": "Wide Dirk",        "file": "dagger_wide_small","category": "dagger",  "damage": 5,  "attack_speed": 2.1, "mining_power": 1.0, "desc": "A broad little dagger that carves wider wounds than its size suggests."},
	{"name": "Wavy Stiletto",    "file": "stiletto_wavy",    "category": "dagger",  "damage": 4,  "attack_speed": 2.5, "mining_power": 1.0, "desc": "A serpentine needle blade that slips between armor with every thrust."},
	{"name": "Round Stiletto",   "file": "stiletto_round",   "category": "dagger",  "damage": 4,  "attack_speed": 2.6, "mining_power": 1.0, "desc": "A smooth round-shaft stiletto made for quick, repeated jabs."},
	{"name": "Sickle",           "file": "sickle",           "category": "sickle",  "damage": 6,  "attack_speed": 1.7, "mining_power": 1.1, "desc": "A hooked harvesting blade that reaps crops and careless enemies alike."},
	{"name": "Broadaxe",         "file": "axe_broad",        "category": "axe",     "damage": 10, "attack_speed": 1.2, "mining_power": 1.6, "desc": "A wide-bitted axe that fells trees and foes in heavy, biting arcs."},
	{"name": "War Axe",          "file": "axe_war",          "category": "axe",     "damage": 11, "attack_speed": 1.1, "mining_power": 1.6, "desc": "A battle-forged axe balanced for splitting helms on the field."},
	{"name": "Bardiche",         "file": "bardiche",         "category": "polearm", "damage": 11, "attack_speed": 1.1, "mining_power": 1.4, "desc": "A long-hafted axe-polearm that sweeps enemies at the end of its reach."},
	{"name": "Spiked Mace",      "file": "mace",             "category": "mace",    "damage": 11, "attack_speed": 1.1, "mining_power": 1.3, "desc": "A brutal spiked head that punches straight through plate and skull."},
	{"name": "Round Mace",       "file": "mace_round",       "category": "mace",    "damage": 10, "attack_speed": 1.2, "mining_power": 1.3, "desc": "A smooth bludgeoning head that delivers reliable, bone-jarring blows."},
	{"name": "Wooden Mallet",    "file": "mallet",           "category": "hammer",  "damage": 8,  "attack_speed": 1.3, "mining_power": 1.3, "desc": "A simple wooden mallet that thumps with honest, blunt force."},
	{"name": "Iron Warmaul",     "file": "maul_iron_1",      "category": "maul",    "damage": 12, "attack_speed": 1.0, "mining_power": 1.3, "desc": "A forged iron maul balanced just enough to swing without losing its punch."},
	{"name": "Iron Maul",        "file": "maul_iron_2",      "category": "maul",    "damage": 13, "attack_speed": 1.0, "mining_power": 1.3, "desc": "A solid iron maul that turns slow swings into devastating impacts."},
	{"name": "Sledgehammer",     "file": "sledgehammer",     "category": "maul",    "damage": 15, "attack_speed": 0.8, "mining_power": 1.3, "desc": "A two-handed wrecker that flattens anything its slow swing connects with."},
	{"name": "Heavy Maul",       "file": "maul_heavy",       "category": "maul",    "damage": 17, "attack_speed": 0.7, "mining_power": 1.3, "desc": "A monstrous slab of a maul that pulps anything caught by its ponderous arc."},
	{"name": "Bare Hands",       "file": "",                 "category": "fist",    "damage": 1,  "attack_speed": 2.0, "mining_power": 1.0, "desc": "No weapon — weak, slow to mine, but always ready."},
]

static func list() -> Array:
	var out: Array = []
	for w in WEAPONS:
		var d: Dictionary = w.duplicate()
		d["path"] = DIR + String(w.file) + ".glb"
		out.append(d)
	return out
