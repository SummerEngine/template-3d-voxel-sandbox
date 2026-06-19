# 3D Voxel Sandbox — Summer Engine Template

A **Minecraft-style voxel survival sandbox** for [Summer Engine](https://www.summerengine.com)
(Godot 4.6, GDScript). Clone it, press Play, and you have a complete, optimized voxel game to
explore — and a clean, documented foundation to build your own on top of.

> This is a **template**: a full, working sandbox you can ship as-is or reshape into your own game.

## What's in it

**World & exploration**
- Streamed voxel terrain with biomes — meadow, forest, jungle, desert, snow, mountains, oceans & rivers
- Day/night cycle, dynamic weather + seasons (rain, snow, sandstorms, thunder, tsunamis)
- Discoverable structures with loot — ruined towers, guarded crypts, treasure caches
- Ambient life — fireflies at night, drifting pollen by day, shooting stars

**Survival & combat**
- Mining & building, crafting, furnace smelting, chests
- Tool & armor tier progression (wood → stone → iron → diamond)
- Hunger & health survival loop
- Night sieges of zombies (normal / fast runner / brute), blood moons, cave lurkers, daylight burning

**Living world**
- Biome fauna — birds, fish, reptiles, farm animals — each with positional sounds, animation & VFX

**Polish**
- 27-slot inventory + crafting UI, hotbar, minimap, advancements, settings + rebindable keys, save/load
- Full audio: per-material footsteps/blocks, mob, weather, UI & wildlife SFX + music
- Optimized: greedy meshing, off-thread chunk builds, shared materials, pooled VFX — locked ~60 FPS

## Quick start

1. Open the project in **Summer Engine**.
2. Press **Play** (F5) and choose **Single Player**.
3. Survive, mine, build, and explore.

### Controls

| Input | Action |
|---|---|
| **WASD** | Move |
| **Ctrl** | Sprint |
| **Space** | Jump · double-tap to toggle creative fly |
| **Mouse** | Look |
| **1–9 / Scroll** | Select hotbar slot |
| **Left click** | Mine / attack |
| **Right click** | Place block |
| **Q / E** | Switch weapon |
| **G** | Eat |
| **C** | Crafting |
| **M** | Map |
| **J** | Advancements |
| **F5** | Toggle first / third person |
| **F3** | Debug stats |
| **Esc** | Pause / release mouse |

## Tech

- **Engine:** Summer Engine / Godot 4.6 · Forward+ · **GDScript** · Jolt Physics

## Project layout

```
assets/    textures/ models/ materials/ audio/        — art & sound (see assets/README.md)
docs/      DESIGN.md — design reference · PLAN.md — roadmap
scenes/    main_menu.tscn — entry scene
scripts/   core/ player/ world/ entities/ ui/         — GDScript by responsibility
main.tscn  gameplay scene (loaded from the menu)
```

## Documentation

- **[docs/DESIGN.md](docs/DESIGN.md)** — how the template is designed (systems, conventions, extension points).
- **[docs/PLAN.md](docs/PLAN.md)** — the phased build roadmap.

## Contributing (team workflow)

- `main` — stable, reviewed.
- `developer` — integration branch; branch your features off this.
- Open a PR into `developer`; we periodically merge `developer → main`.

## License

Template intended for reuse — see repository for license terms.
