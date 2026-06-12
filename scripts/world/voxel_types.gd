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
		GRASS: return Color(0.30, 0.58, 0.27)
		DIRT:  return Color(0.45, 0.32, 0.20)
		STONE: return Color(0.46, 0.46, 0.49)
		LAVA:  return Color(0.90, 0.32, 0.10)
		_:     return Color(1, 0, 1)
