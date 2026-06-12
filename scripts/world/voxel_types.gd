class_name VoxelTypes

## Block type ids and their placeholder colours (until textures are provided).

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const LAVA := 4

static func is_solid(t: int) -> bool:
	return t != AIR

static func color_of(t: int) -> Color:
	match t:
		GRASS: return Color(0.36, 0.66, 0.30)
		DIRT:  return Color(0.48, 0.34, 0.21)
		STONE: return Color(0.53, 0.53, 0.56)
		LAVA:  return Color(0.95, 0.40, 0.12)
		_:     return Color(1, 0, 1)
