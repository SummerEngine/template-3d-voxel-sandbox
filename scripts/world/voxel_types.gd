class_name VoxelTypes

## Central block + item registry. Every block has an atlas tile, a display name,
## an approximate solid colour (used for drops / particles / hotbar swatches),
## a hardness (seconds to mine at mining_power 1.0; negative = unbreakable) and a
## drop (the block id you collect when you break it). Items (id >= ITEM_BASE) are
## not placeable — e.g. APPLE, which you eat.

# --- block ids ---
const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const LAVA := 4
const COBBLESTONE := 5
const SAND := 6
const WOOD := 7
const PLANKS := 8
const LEAVES := 9
const COAL_ORE := 10
const IRON_ORE := 11
const GOLD_ORE := 12
const DIAMOND_ORE := 13
const GLASS := 14
const WATER := 15
const BEDROCK := 16
# --- added blocks (8x8 atlas, cols 4-7) ---
const CRAFTING_TABLE := 17
const FURNACE := 18
const CHEST := 19
const BRICKS := 20
const STONE_BRICKS := 21
const POLISHED_STONE := 22
const FARMLAND := 23
const WHITE_BLOCK := 24
const RED_BLOCK := 25
const BLUE_BLOCK := 26
const GREEN_BLOCK := 27
const SNOW := 28
const MAX_BLOCK := 28

# --- item ids (non-placeable: crafting materials, food, gems) ---
const ITEM_BASE := 100
const APPLE := 100
const STICK := 101
const COAL := 102
const IRON_INGOT := 103
const GOLD_INGOT := 104
const DIAMOND := 105
const RAW_MEAT := 106
const COOKED_MEAT := 107

# Extra atlas tiles that aren't a block's main face: item icons (28-35) and the log
# ring-top (36). Tile index = row*8 + col in the 8x8 atlas.
const TILE_WOOD_TOP := 36

## Atlas is an 8x8 grid (see assets/textures/blocks/atlas.png). Tile index = row*8 + col.
## The original 16 blocks keep their cols 0-3 positions; added blocks live in cols 4-7.
static func atlas_index(t: int) -> int:
	match t:
		GRASS:          return 0
		DIRT:           return 1
		STONE:          return 2
		COBBLESTONE:    return 3
		CRAFTING_TABLE: return 4
		FURNACE:        return 5
		CHEST:          return 6
		BRICKS:         return 7
		SAND:           return 8
		WOOD:           return 9
		PLANKS:         return 10
		LEAVES:         return 11
		STONE_BRICKS:   return 12
		POLISHED_STONE: return 13
		FARMLAND:       return 14
		WHITE_BLOCK:    return 15
		COAL_ORE:       return 16
		IRON_ORE:       return 17
		GOLD_ORE:       return 18
		DIAMOND_ORE:    return 19
		RED_BLOCK:      return 20
		BLUE_BLOCK:     return 21
		GREEN_BLOCK:    return 22
		SNOW:           return 37
		GLASS:          return 24
		WATER:          return 25
		LAVA:           return 26
		BEDROCK:        return 27
		_:              return 2

## Atlas tile for a specific FACE of a block. `d` is the face axis (1 = Y / top &
## bottom), `back` is the negative-facing side. Most blocks use one tile on every face;
## logs are the exception — bark on the sides, growth rings on the top & bottom caps.
static func face_atlas_index(t: int, d: int, _back: bool) -> int:
	if t == WOOD and d == 1:
		return TILE_WOOD_TOP
	return atlas_index(t)

## Atlas tile used to draw this id as a flat icon in the UI (hotbar / inventory /
## crafting). Blocks show their main face tile; items have dedicated icon tiles.
static func tile_index(id: int) -> int:
	match id:
		STICK:       return 28
		COAL:        return 29
		IRON_INGOT:  return 30
		GOLD_INGOT:  return 31
		DIAMOND:     return 32
		APPLE:       return 33
		RAW_MEAT:    return 34
		COOKED_MEAT: return 35
		_:           return atlas_index(id)

static func is_solid(t: int) -> bool:
	return t != AIR

static func is_placeable(id: int) -> bool:
	return id >= GRASS and id <= MAX_BLOCK

static func is_item(id: int) -> bool:
	return id >= ITEM_BASE

## Seconds to break at mining_power 1.0. Negative = unbreakable.
static func hardness(t: int) -> float:
	match t:
		LEAVES:      return 0.2
		GLASS:       return 0.15
		SNOW:        return 0.25
		GRASS, DIRT, SAND: return 0.5
		WATER, LAVA: return 0.3
		WOOD, PLANKS, CRAFTING_TABLE, CHEST: return 1.1
		FARMLAND: return 0.5
		STONE, COBBLESTONE, FURNACE, BRICKS, STONE_BRICKS, POLISHED_STONE: return 1.6
		COAL_ORE:    return 2.0
		IRON_ORE, GOLD_ORE: return 2.6
		DIAMOND_ORE: return 3.2
		BEDROCK:     return -1.0
		_:           return 1.0

## Minimum pickaxe tier needed to HARVEST a block (0 = bare hands, 1 = wood,
## 2 = stone, 3 = iron). Mining a block above your tier still breaks it but drops
## nothing (the Minecraft rule). Most blocks are tier 0.
static func mine_tier(t: int) -> int:
	match t:
		STONE, COBBLESTONE, COAL_ORE: return 1
		IRON_ORE:                     return 2
		GOLD_ORE, DIAMOND_ORE:        return 3
		_:                            return 0

## What you collect when this block breaks (AIR = nothing). Ores now yield resources:
## coal/diamond drop their item; iron/gold drop the ore block to be smelted into ingots.
static func drop_of(t: int) -> int:
	match t:
		GRASS:       return DIRT          # grass crumbles to dirt
		STONE:       return COBBLESTONE   # stone yields cobblestone
		COAL_ORE:    return COAL          # coal item (smelting fuel)
		DIAMOND_ORE: return DIAMOND       # diamond gem (no smelting needed)
		FARMLAND:    return DIRT          # tilled soil reverts to dirt when broken
		WATER, LAVA, BEDROCK: return AIR  # fluids / bedrock drop nothing
		_:           return t

static func name_of(id: int) -> String:
	match id:
		AIR:         return "Empty"
		GRASS:       return "Grass"
		DIRT:        return "Dirt"
		STONE:       return "Stone"
		LAVA:        return "Lava"
		COBBLESTONE: return "Cobblestone"
		SAND:        return "Sand"
		WOOD:        return "Wood"
		PLANKS:      return "Planks"
		LEAVES:      return "Leaves"
		COAL_ORE:    return "Coal Ore"
		IRON_ORE:    return "Iron Ore"
		GOLD_ORE:    return "Gold Ore"
		DIAMOND_ORE: return "Diamond Ore"
		GLASS:       return "Glass"
		WATER:       return "Water"
		BEDROCK:     return "Bedrock"
		CRAFTING_TABLE: return "Crafting Table"
		FURNACE:        return "Furnace"
		CHEST:          return "Chest"
		BRICKS:         return "Bricks"
		STONE_BRICKS:   return "Stone Bricks"
		POLISHED_STONE: return "Polished Stone"
		FARMLAND:       return "Farmland"
		WHITE_BLOCK:    return "White Block"
		RED_BLOCK:      return "Red Block"
		BLUE_BLOCK:     return "Blue Block"
		GREEN_BLOCK:    return "Green Block"
		SNOW:           return "Snow"
		APPLE:       return "Apple"
		STICK:       return "Stick"
		COAL:        return "Coal"
		IRON_INGOT:  return "Iron Ingot"
		GOLD_INGOT:  return "Gold Ingot"
		DIAMOND:     return "Diamond"
		RAW_MEAT:    return "Raw Meat"
		COOKED_MEAT: return "Cooked Steak"
		_:           return "?"

## Hunger restored when this item is eaten (0 = not food). Cooking roughly triples the
## value of raw meat — the incentive to build a furnace.
static func food_value(id: int) -> int:
	match id:
		APPLE:       return 3
		RAW_MEAT:    return 2
		COOKED_MEAT: return 6
		_:           return 0

## Approximate solid colour for drops, break particles and hotbar swatches.
static func color_of(id: int) -> Color:
	match id:
		GRASS:       return Color(0.36, 0.66, 0.30)
		DIRT:        return Color(0.48, 0.34, 0.21)
		STONE:       return Color(0.53, 0.53, 0.56)
		LAVA:        return Color(0.95, 0.40, 0.12)
		COBBLESTONE: return Color(0.42, 0.42, 0.45)
		SAND:        return Color(0.86, 0.78, 0.55)
		WOOD:        return Color(0.45, 0.31, 0.18)
		PLANKS:      return Color(0.67, 0.50, 0.29)
		LEAVES:      return Color(0.24, 0.46, 0.20)
		COAL_ORE:    return Color(0.24, 0.24, 0.26)
		IRON_ORE:    return Color(0.74, 0.62, 0.52)
		GOLD_ORE:    return Color(0.86, 0.72, 0.27)
		DIAMOND_ORE: return Color(0.40, 0.78, 0.82)
		GLASS:       return Color(0.74, 0.86, 0.92)
		WATER:       return Color(0.24, 0.42, 0.80)
		BEDROCK:     return Color(0.20, 0.20, 0.22)
		CRAFTING_TABLE: return Color(0.66, 0.48, 0.31)
		FURNACE:        return Color(0.52, 0.52, 0.55)
		CHEST:          return Color(0.54, 0.35, 0.18)
		BRICKS:         return Color(0.62, 0.29, 0.24)
		STONE_BRICKS:   return Color(0.50, 0.50, 0.52)
		POLISHED_STONE: return Color(0.61, 0.61, 0.63)
		FARMLAND:       return Color(0.29, 0.20, 0.12)
		WHITE_BLOCK:    return Color(0.90, 0.90, 0.88)
		RED_BLOCK:      return Color(0.75, 0.23, 0.19)
		BLUE_BLOCK:     return Color(0.21, 0.32, 0.75)
		GREEN_BLOCK:    return Color(0.25, 0.63, 0.27)
		SNOW:           return Color(0.93, 0.95, 0.98)
		APPLE:       return Color(0.85, 0.18, 0.18)
		STICK:       return Color(0.55, 0.40, 0.22)
		COAL:        return Color(0.14, 0.14, 0.16)
		IRON_INGOT:  return Color(0.82, 0.80, 0.78)
		GOLD_INGOT:  return Color(0.92, 0.78, 0.30)
		DIAMOND:     return Color(0.45, 0.85, 0.88)
		RAW_MEAT:    return Color(0.78, 0.34, 0.38)
		COOKED_MEAT: return Color(0.48, 0.26, 0.15)
		_:           return Color(1, 0, 1)
