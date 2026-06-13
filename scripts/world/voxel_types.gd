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
const MAX_BLOCK := 16

# --- item ids (non-placeable) ---
const ITEM_BASE := 100
const APPLE := 100

## Atlas is a 4x4 grid (see assets/textures/blocks/atlas.png). Tile index = row*4 + col.
static func atlas_index(t: int) -> int:
	match t:
		GRASS:       return 0
		DIRT:        return 1
		STONE:       return 2
		COBBLESTONE: return 3
		SAND:        return 4
		WOOD:        return 5
		PLANKS:      return 6
		LEAVES:      return 7
		COAL_ORE:    return 8
		IRON_ORE:    return 9
		GOLD_ORE:    return 10
		DIAMOND_ORE: return 11
		GLASS:       return 12
		WATER:       return 13
		LAVA:        return 14
		BEDROCK:     return 15
		_:           return 2

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
		GRASS, DIRT, SAND: return 0.5
		WATER, LAVA: return 0.3
		WOOD, PLANKS: return 1.1
		STONE, COBBLESTONE: return 1.6
		COAL_ORE:    return 2.0
		IRON_ORE, GOLD_ORE: return 2.6
		DIAMOND_ORE: return 3.2
		BEDROCK:     return -1.0
		_:           return 1.0

## What you collect when this block breaks (AIR = nothing).
static func drop_of(t: int) -> int:
	match t:
		GRASS:       return DIRT          # grass crumbles to dirt
		STONE:       return COBBLESTONE   # stone yields cobblestone
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
		APPLE:       return "Apple"
		_:           return "?"

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
		APPLE:       return Color(0.85, 0.18, 0.18)
		_:           return Color(1, 0, 1)
