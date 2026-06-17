# Voxel Sandbox — Project Plan

Status of the game and the forward roadmap. This file used to describe a node-per-block
prototype; the project has long since grown into a full voxel survival-sandbox. This reflects
what's actually in the code today (2026-06) and what's worth doing next. See `DESIGN.md` for
how the systems are built.

---

## Built (shipped in the codebase)

- **World:** threaded chunk streaming (`ChunkManager` + `Chunk`), greedy meshing, per-chunk
  voxel cache, shared chunk materials, layered-noise terrain with biomes (meadow / forest /
  jungle / desert / snow / mountain / water), caves, ores, rivers & oases.
- **Blocks/items:** 29 blocks + 8 items in one registry (`VoxelTypes`), 8×8 texture atlas,
  per-face tiles, drops, 27-slot inventory + hotbar, crafting table / furnace / chests.
- **Player:** first-person controller (walk/run/jump/fly/swim), auto-step, mining with tier
  gates, place validation, camera feel (FOV/bob/shake), first-person viewmodel + animations.
- **Progression:** tiered tools/weapons, smelting, armor, advancements (J), escalating night
  sieges, hunger (lethal), day/night cycle.
- **Enemies & fauna:** night zombies (chase/attack/leap, death topple) + 16 biome creatures
  with procedural/clip locomotion.
- **Weather/seasons:** continuous climate → clear/cloudy/rain/snow, desert sandstorm, coast
  tsunami, GPU precipitation, audio beds.
- **Polish:** fog, water shader, crack overlay, particles (GPU weather/ambient, pooled
  bursts), pooled SFX voices, underwater muffle, music + ambient, minimap, death screen.
- **Meta:** save/load, main menu, pause menu, **settings (volume / look-speed / view
  distance, persisted)**.

---

## Roadmap (next, roughly in priority order)

### A. Verify & document (do first)
- [ ] **Run the game and verify** the recent optimization/SFX/VFX/animation/settings passes
      (the engine has been offline; none are runtime-checked yet).
- [x] Bring `DESIGN.md` / `PLAN.md` in line with the real game.

### B. Fixes
- [ ] **Remappable controls** — input is currently hardcoded (`KEY_*` in `player.gd`).
      Migrate to InputMap actions, add a rebind UI to the settings panel.
- [ ] **Farming loop** — `FARMLAND` (and a hoe model) exist but there are no seeds/crops/
      growth. Either wire a real till→plant→grow→harvest loop or remove the stub block.
- [ ] **Animal SFX** — `fauna.gd` creatures are silent; add per-species idle/hurt sounds.
- [ ] **Player third-person model height** — `MODEL_SCALE = 1.0` (not AABB-fit); verify the
      body matches the 1.8 m capsule when seen in third person.

### C. Gameplay additions (each wants new assets + runtime iteration)
- [ ] **Combat variety** — a ranged enemy (skeleton) + a player bow/arrow projectile.
- [ ] **Placeable light** — torches (block + light) so caves/bases aren't lit only by the
      player's follow-lamp.
- [ ] **Structures** — villages / ruins / dungeons with loot, keyed to the biome system.
- [ ] **Beds & sleep** — skip/secure the night and set spawn.

---

## Branching & deploy
`main` = stable/reviewed; `developer` = integration branch. Feature work → PR into
`developer` → periodic PR `developer → main`. Origin is the team GitHub remote.
