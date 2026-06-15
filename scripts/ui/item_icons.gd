## Shared source of flat UI icons for blocks and items. Slices the block atlas (the
## same PNG the world uses) into per-tile AtlasTextures so the hotbar, inventory, chest
## and crafting screens show real textures instead of flat colour swatches.
##
## The atlas is loaded once from the raw PNG on disk (matching Chunk._atlas_texture) so
## edits apply without an editor reimport, and each tile's AtlasTexture is cached.

const ATLAS_PATH := "res://assets/textures/blocks/atlas.png"
const TILES := 8                       # 8x8 grid

static var _atlas: Texture2D
static var _cache: Dictionary = {}     # tile index -> AtlasTexture (for 2D UI)
static var _tiles: Dictionary = {}     # tile index -> standalone ImageTexture (for 3D meshes)

static func _atlas_texture() -> Texture2D:
	if _atlas != null:
		return _atlas
	var disk := ProjectSettings.globalize_path(ATLAS_PATH)
	if FileAccess.file_exists(disk):
		var img := Image.load_from_file(disk)
		if img != null:
			_atlas = ImageTexture.create_from_image(img)
	if _atlas == null and ResourceLoader.exists(ATLAS_PATH):
		_atlas = load(ATLAS_PATH)
	return _atlas

## AtlasTexture for an item/block id (null only if the atlas can't load yet — callers
## fall back to a flat colour swatch).
static func icon(id: int) -> Texture2D:
	var ti := VoxelTypes.tile_index(id)
	if _cache.has(ti):
		return _cache[ti]
	var atlas := _atlas_texture()
	if atlas == null:
		return null
	var px := floori(float(atlas.get_width()) / float(TILES))
	var t := AtlasTexture.new()
	t.atlas = atlas
	t.region = Rect2(float((ti % TILES) * px), float(floori(float(ti) / float(TILES)) * px), float(px), float(px))
	_cache[ti] = t
	return t

## A STANDALONE texture of just this id's tile, cropped out of the atlas. Use this for 3D
## materials (dropped-item cubes): an AtlasTexture as a 3D albedo samples the whole atlas
## (its region remap only applies in 2D), so a dropped block would show every tile at once.
static func tile_texture(id: int) -> Texture2D:
	var ti := VoxelTypes.tile_index(id)
	if _tiles.has(ti):
		return _tiles[ti]
	var atlas := _atlas_texture()
	if atlas == null or not (atlas is ImageTexture):
		return null
	var img := (atlas as ImageTexture).get_image()
	if img == null:
		return null
	var px := floori(float(atlas.get_width()) / float(TILES))
	var rect := Rect2i((ti % TILES) * px, int(floori(float(ti) / float(TILES))) * px, px, px)
	var crop := img.get_region(rect)
	var t := ImageTexture.create_from_image(crop)
	_tiles[ti] = t
	return t
