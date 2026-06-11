# 3D Voxel Sandbox — Summer Engine Template

A Minecraft-style **3D voxel sandbox template** for [Summer Engine](https://www.summerengine.com)
(Godot 4.6, GDScript). Clone it, press Play, and build your own voxel game on top of a clean,
documented foundation.

> ⚠️ This is a **template**, not a finished game. It gives you movement, a voxel world, and
> build/break interaction — you bring the gameplay.

## Quick start

1. Open the project in **Summer Engine**.
2. Press **Play** (F5).
3. You spawn above a voxel floor under an open sky.

### Controls

| Input | Action |
|---|---|
| **WASD** | Move |
| **Mouse** | Look |
| **Space** | Jump (or fly up) |
| **F** | Toggle creative fly |
| **1–5** | Select block color/type |
| **Left click** | Break block |
| **Right click** | Place block |
| **Esc** | Release mouse |

## Tech

- **Engine:** Summer Engine / Godot 4.6 · Forward+ · **GDScript** · Jolt Physics

## Project layout

```
assets/    textures/ models/ materials/ audio/   — art & sound (see assets/README.md)
docs/      DESIGN.md — design reference · PLAN.md — roadmap
scenes/    .tscn scenes
scripts/   core/ player/ world/ ui/              — GDScript by responsibility
main.tscn  entry scene
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
