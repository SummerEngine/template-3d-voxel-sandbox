# Assets

All art and sound for the template lives here, organized by type. Both **generated** assets
(via the Summer MCP/CLI) and **hand-made** assets (created in the studio and imported) go in
the matching subfolder.

## Folders

| Folder | What goes here | Formats |
|---|---|---|
| `textures/` | Block face textures, UI sprites, the block **atlas** | `.png` |
| `models/` | 3D props/characters (non-voxel meshes) | `.glb`, `.gltf` |
| `materials/` | Reusable Godot material resources | `.tres`, `.material` |
| `audio/` | SFX (place/break/step) and music | `.ogg`, `.wav` |

## Naming conventions

- Block textures: `block_<name>_<face>.png` (e.g. `block_grass_top.png`, `block_dirt_side.png`).
- Atlas: `blocks_atlas.png` + a matching mapping in the block registry.
- Materials: `mat_<thing>.tres` (e.g. `mat_grass.tres`).
- Audio: `sfx_<action>.ogg` (e.g. `sfx_block_break.ogg`), `music_<name>.ogg`.

## Creating assets

**Via Summer MCP / CLI (preferred):**
- Images/textures → `summer_generate_image`
- 3D models → `summer_generate_3d`
- Audio → `summer_generate_audio`
- Import existing files/URLs → `summer_import_asset` / `summer_import_from_url`

**Manually:** create or import in the Summer studio, then save the file into the correct
subfolder above so it's tracked in git.

> Keep this folder tidy — the block registry and scenes reference assets **by path**, so a
> consistent layout and naming scheme keeps everything wired up as the project grows.
