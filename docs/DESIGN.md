# Voxel Sandbox Template — Design Documentation

> The single source of truth for how this template is designed and built.
> Read this before adding or changing systems. Keep it updated as the template evolves.

## 1. Vision

A clean, well-documented **Minecraft-style 3D voxel sandbox template** for Summer Engine
(Godot 4.6, GDScript). It is **not a finished game** — it is a foundation other developers
clone and build their own voxel games on top of. Priorities, in order:

1. **Readable** — every system is small, commented, and easy to find.
2. **Extensible** — adding a block type, changing world generation, or swapping the
   controller should each be a localized, obvious change.
3. **Runnable from the first clone** — open in Summer Engine, press Play, walk around.

## 2. Core Pillars

| Pillar | What it means |
|---|---|
| **Build & break** | Place and remove blocks anywhere with instant feedback. |
| **Free movement** | First-person walk/run/jump on the ground; toggle creative fly. |
| **Data-driven blocks** | Block types defined in one registry, not hardcoded across the code. |
| **Asset-ready** | A clear pipeline + folder layout for textures, models, audio. |

## 3. Tech Baseline

- **Engine:** Summer Engine (Godot 4.6), Forward+ renderer, D3D12 on Windows.
- **Language:** **GDScript only** (no C#/.NET — the `[dotnet]` config has been removed).
- **Physics:** Jolt Physics (3D).
- **Coordinate convention:** 1 block = 1 world unit. Block at grid cell `(x,y,z)` is centered
  at `Vector3(x,y,z)`; its top face is at `y + 0.5`.

## 4. Systems

### 4.1 Player Controller (`scripts/player/`)
First-person `CharacterBody3D`.
- **Walk/Run:** WASD relative to facing; optional sprint.
- **Look:** mouse-captured pitch (clamped ±85°) + yaw.
- **Jump/Gravity:** uses `ProjectSettings` default gravity; jump only when on floor.
- **Creative fly:** `F` toggles; Space/Shift for up/down; gravity disabled while flying.
- **Targeting:** forward `RayCast3D` (reach ~6 units) identifies the block under the crosshair.

### 4.2 Voxel World (`scripts/world/`)
Authoritative store of placed blocks.
- Blocks live in a `Dictionary` keyed by `Vector3i` cell → block instance/metadata.
- Each block is a `StaticBody3D` (BoxMesh + BoxShape3D) carrying its `cell` in metadata, so a
  raycast hit maps straight back to a grid cell.
- `add_block(cell, type)`, `remove_block(cell)`, `has_block(cell)`.
- Initial floor is generated procedurally (flat grid) — the hook where real terrain generation
  plugs in later (see PLAN Phase 2).
- **Scaling note:** the starter uses one node per block (simple, readable). The documented
  upgrade path is **chunked meshing** for large worlds — see PLAN Phase 2.

### 4.3 Block Registry (`scripts/core/`) — *planned*
A single resource/script that defines every block type: id, display name, color/material,
texture references, and flags (solid, breakable). Place/break and the hotbar read from here so
new blocks require **one** edit.

### 4.4 Interaction
- **Left click** → break the targeted block.
- **Right click** → place the selected block on the face the ray hit (cell + hit normal).
- **1–5** → select active block type (drives the hotbar).

### 4.5 UI (`scripts/ui/`)
- Crosshair, a hotbar showing the selectable block types, and an on-screen controls hint.
- Built with Control nodes under a `CanvasLayer`.

## 5. Asset Pipeline

Assets are produced two ways and **both land in `assets/`** (see `assets/README.md`):
1. **Generated** via the Summer MCP / CLI (`summer_generate_image`, `summer_generate_3d`,
   `summer_generate_audio`, `summer_import_*`).
2. **Hand-made** in the Summer studio and imported manually when generation isn't a good fit.

Voxel textures use a **texture atlas** (one image, many block faces) referenced by the block
registry, to keep draw calls and materials low.

## 6. Project Structure

```
assets/        textures/ models/ materials/ audio/   — all art & sound, organized by type
docs/          DESIGN.md (this file) + PLAN.md
scenes/        .tscn scenes (main, player, ui, …)
scripts/       core/ player/ world/ ui/              — GDScript by responsibility
main.tscn      entry scene (set as project main scene)
project.godot  Godot project config (GDScript, Jolt, Forward+)
```

> **Prototype note:** the first runnable prototype (`main.gd`, `player.gd`, `voxel_world.gd`)
> currently lives at the project root. PLAN Phase 1–2 relocates these into `scripts/` and
> `scenes/` and converts them into the data-driven systems described above.

## 7. Conventions

- **GDScript style:** typed variables, `snake_case` members, `PascalCase` for `class_name`.
  Tabs for indentation (Godot default).
- **One responsibility per script.** Prefer composition (child nodes) over giant scripts.
- **No magic numbers** — gameplay constants go at the top of their script as `const`.
- **Reference scripts by `preload("res://…")`** when global `class_name` registration order
  could bite (see the `main.gd` fix); otherwise `class_name` is fine.

## 8. For Template Users (extension points)

| Want to… | Change… |
|---|---|
| Add a block type | the **block registry** (one entry: id, color/texture, flags) |
| Change the world shape | `VoxelWorld` generation hook (Phase 2 terrain generator) |
| Retune movement | the `const` block at the top of the player controller |
| Restyle the HUD | the UI scripts/scenes under `scripts/ui/` + `scenes/` |
| Add assets | drop files into the matching `assets/` subfolder (see its README) |
