# Assets

All game assets, organised by type. Everything here is either AI-generated through
Summer Engine Studio (royalty-free, free commercial-use licence) or a project mock-up.
No third-party copyrighted assets are bundled.

Each `.glb` / `.png` / `.mp3` has a sibling `.import` (and sometimes `.uid`) file that
Godot uses to track the imported resource — keep them together when moving a file.

```
assets/
├── audio/
│   ├── ambient/
│   │   └── wind.mp3              # looping outdoor wind bed  → "Ambient" bus
│   ├── music/
│   │   └── theme.mp3             # looping background theme  → "Music" bus
│   └── sfx/                      # one-shots → "SFX" bus (never ducked)
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
│   ├── block_atlas.gdshader      # samples one tile of the 4x4 atlas per voxel face
│   └── chroma_key.gdshader       # knocks out the menu logo's solid background
├── models/                       # every model lives in a category sub-folder
│   ├── animals/                  # cow / pig / sheep (passive) + textures
│   ├── characters/               # player_rigged (animated), player, player_animated + textures
│   ├── mobs/                     # zombie (hostile, night) + texture
│   ├── props/                    # gold_ore + textures
│   ├── tools/                    # 7 tool models (axe, hammer, hoe, scythe, shovel, sword, war axe)
│   └── weapons/                  # 27 melee weapons (see scripts/player/weapon_registry.gd)
└── textures/
    ├── blocks/
    │   └── atlas.png             # 4x4 voxel texture atlas (tile order below)
    └── menu/
        ├── background.png        # main-menu backdrop (covers the whole screen)
        └── logo.png              # "VOXEL CREATIONS" logo (chroma-keyed in main_menu.gd)
```

Note: GLB models ship with extracted `*_Image_0.jpg` / `*_normal.png` / `*_texture_*.png`
files — the model's baked colour and normal maps. They are referenced by the GLB's
materials by `uid://`, so they must stay beside their `.glb`.

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
| Summer Engine Studio — ElevenLabs SFX/music | `audio/**` | Free, commercial use |
| Summer Engine Studio — image generation | `textures/**` | Free, commercial use |
| Summer Engine Studio — 3D generation | `models/**` | Free, commercial use |
| Project shaders / mock-ups | `materials/**` | Project-owned |
