# Voxel Sandbox — Design & Architecture

> How this game is actually built. Read before changing a system; keep it current.
> (This replaces the old prototype-era design doc — there is no node-per-block world anymore.)

## 1. What it is
A Minecraft-style 3D voxel **survival sandbox** on Summer Engine (Godot 4.6, GDScript only,
Forward+ / D3D12, Jolt physics). Build & break a streamed voxel world, gather/craft/smelt up
a tool tier, survive escalating night sieges, explore biomes with weather and fauna.

**Convention:** 1 block = 1 world unit (metre). The player is 1.8 m tall (eye 1.5 m); all
object sizes proportion against that — see the `world-scale-reference` notes.

## 2. World (`scripts/world/`)
- **`ChunkManager`** streams 16×16×256 chunks around the player (radius = `render_radius`,
  default 3, settings-adjustable). Terrain is a **pure function** of world coords (layered
  FastNoiseLite + integer hashes) plus a `overrides` dict of player edits, so any voxel is
  sample-able even if unloaded. Owns biome/height/tree queries and chest storage.
- **`Chunk`** builds one chunk on a worker thread: a per-build voxel cache (computed once,
  reused across edits), **greedy meshing** (merged faces, culled hidden faces) into an
  opaque surface + a translucent water surface, plus a trimesh collider, applied on the main
  thread (budgeted per frame). All chunks **share** one solid + one water material.
- **`VoxelTypes`** — the single block/item registry: ids, atlas tile, colour, hardness, drop,
  mine-tier, food value, flags. Add a block here + give it an atlas tile (8×8 grid). 29 blocks
  (id 0–28), 8 items (id ≥ 100).
- **Trees** are 3D models placed per-chunk via MultiMesh (a 2-block minable stump is the only
  tree voxel). **`weather.gd`** drives continuous climate → precipitation (GPU particles),
  sandstorms, tsunamis. **`world_save.gd`** persists overrides/chests/player/time/weather.

## 3. Player (`scripts/player/`)
First-person `CharacterBody3D`. Walk/run/jump/fly/swim, auto-step, mouse look (`mouse_sens`,
settings-scaled). Raycast targeting (reach 6). Left = mine (tier-gated, crack overlay,
particles), right = place (validated). Mining/combat swing both the third-person rig
(AnimationPlayer clips) and the first-person viewmodel (procedural bob/sway/swing + a
placement push). Inventory (27 + hotbar), hunger, armor, death/respawn. `weapon_holder` /
`tool_holder` equip models to the hand bone; `WeaponRegistry` holds stats.

## 4. Entities (`scripts/entities/`)
- **`hostile_mob`** — night zombies (player GLB + procedural shamble, chase/attack/leap, hit
  flash, death topple). **`creature` + `fauna`** — biome-spawned animals with ground/air/water
  procedural locomotion or baked clips, culled by distance. (`animal.gd` is legacy/unused.)

## 5. UI, core, audio (`scripts/ui`, `scripts/core`)
HUD, minimap, crafting/chest screens, main + pause menus, **settings** (`GameSettings` →
`user://settings.cfg`). `main.gd` wires the scene; `advancements.gd` tracks goals;
`audio_ducker.gd` creates Music/Ambient/SFX buses, ducks on impact, owns the underwater
low-pass and the settings volume hooks. SFX play through a pooled voice set; mob audio is
positional.

## 6. Conventions
- GDScript only; typed vars; `snake_case` members, `PascalCase` `class_name`; tabs.
- One responsibility per script; prefer composition. Gameplay constants as `const` at the top.
- Reference scripts via `preload("res://…")` where `class_name` registration order could bite.
- New `class_name` scripts may need a filesystem rescan before refs resolve in the editor.

## 7. Extension points
| Want to… | Change… |
|---|---|
| Add a block/item | `VoxelTypes` (one entry) + an atlas tile |
| Change terrain/biomes | the noise + `biome_at`/`surface_height` in `ChunkManager` |
| Retune movement/look | the `const` block atop `player.gd` |
| Add a creature | a `CREATURES` entry in `fauna.gd` + a model |
| Restyle UI | `scripts/ui/` + `UITheme` |
| Add a setting | `GameSettings` + a `UITheme.setting_row` in the two settings panels |
