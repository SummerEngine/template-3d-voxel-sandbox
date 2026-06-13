# Assets

All game assets, organised by type. Everything here is either AI-generated through
Summer Engine Studio (royalty-free, free commercial-use licence) or a project mock-up.
No third-party copyrighted assets are bundled.

```
assets/
├── audio/
│   ├── ambient/
│   │   └── wind.mp3              # looping outdoor wind bed (main.gd ambient player)
│   └── sfx/
│       ├── blocks/
│       │   ├── break_soft.mp3    # break grass / dirt / sand / wood / leaves
│       │   ├── break_hard.mp3    # break stone / cobble / ore / lava
│       │   └── place.mp3         # place a block
│       ├── items/
│       │   └── pickup.mp3        # collect a dropped item
│       ├── mobs/
│       │   └── monster_hurt.mp3  # hit a hostile mob
│       └── player/
│           ├── step_grass.mp3    # footstep on soft ground
│           ├── step_stone.mp3    # footstep on stone
│           ├── swing.mp3         # weapon / mining swing
│           ├── hurt.mp3          # player takes damage
│           └── eat.mp3           # eat an apple
├── materials/
│   └── block_atlas.gdshader      # samples one tile of the 4x4 atlas per face
├── models/
│   ├── characters/               # player_rigged.glb (animated player) + player.glb
│   ├── weapons/                  # 27 melee weapons (see weapon_registry.gd)
│   ├── tools/                    # legacy tool models
│   └── props/                    # gold_ore.glb
└── textures/
    ├── blocks/
    │   └── atlas.png             # 4x4 voxel texture atlas (tile order below)
    ├── menu_background.png        # main-menu mock-up
    └── reference/                # concept art only — NOT loaded at runtime
```

## Block atlas tile order

`atlas.png` is a 4×4 grid (tile index = `row * 4 + col`). `VoxelTypes.atlas_index()`
maps each block id to its tile, and `block_atlas.gdshader` samples it. To re-skin a
block, repaint its tile in place — no code changes needed.

| col→ | 0 | 1 | 2 | 3 |
|------|---|---|---|---|
| **row 0** | grass | dirt | stone | cobblestone |
| **row 1** | sand | wood | planks | leaves |
| **row 2** | coal ore | iron ore | gold ore | diamond ore |
| **row 3** | glass | water | lava | bedrock |

## Licensing

| Source | Files | Licence |
|--------|-------|---------|
| Summer Engine Studio — ElevenLabs SFX | `audio/**` | Free, commercial use |
| Summer Engine Studio — image generation | `textures/blocks/atlas.png` | Free, commercial use |
| Project mock-up / concept | `textures/menu_background.png`, `textures/reference/**` | Project-owned |
| Imported 3D models | `models/**` | Free, commercial use |
