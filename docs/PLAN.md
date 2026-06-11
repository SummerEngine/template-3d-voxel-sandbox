# Voxel Sandbox Template — Project Plan

Phased plan to take the template from "runnable prototype" to "polished, documented
foundation other developers build on." Each phase lists **tasks** and **done-when** criteria.
Tick items as they land. See `DESIGN.md` for the design rationale behind each system.

---

## Phase 0 — Foundation & Pipeline ✅ (current)
Prove the repo, structure, docs, and deploy pipeline before building features.

- [x] GDScript-only project (removed `[dotnet]` config)
- [x] Project folder structure (`assets/`, `scripts/`, `scenes/`, `docs/`)
- [x] Design documentation (`docs/DESIGN.md`)
- [x] This project plan (`docs/PLAN.md`)
- [x] Template `README.md` + asset conventions (`assets/README.md`)
- [ ] **Commit + push `main` and `developer` to GitHub** (needs GitHub auth — see "Deploy" below)

**Done when:** both branches exist on the team's GitHub remote and a teammate can clone.

---

## Phase 1 — Movement Controller
Production-quality first-person controller (replaces the prototype `player.gd`).

- [ ] Move controller into `scripts/player/player_controller.gd` + `scenes/player.tscn`
- [ ] Walk/run (sprint), mouse look (clamped), jump with gravity
- [ ] Creative fly toggle (up/down), clean ground/air state
- [ ] Coyote time + jump buffering for good feel
- [ ] Input map bindings (not hardcoded keycodes) via `summer_input_map_bind`

**Done when:** you can walk, sprint, jump, and fly smoothly; bindings are remappable.

---

## Phase 2 — Voxel World System
Data-driven, scalable world (evolves the prototype `voxel_world.gd`).

- [ ] `scripts/core/block_registry.gd` — block types (id, name, material/texture, flags)
- [ ] `scripts/world/voxel_world.gd` — chunk-based storage + meshing (replace node-per-block)
- [ ] Procedural terrain generation hook (flat → heightmap noise)
- [ ] Efficient collision (per-chunk collision shapes)

**Done when:** a multi-chunk world generates and runs at smooth framerate.

---

## Phase 3 — Interaction & Inventory
- [ ] Raycast place/break wired to the block registry
- [ ] Hotbar UI (`scripts/ui/`) showing selectable block types
- [ ] Block selection (number keys + scroll)
- [ ] Place validation (don't place inside the player)

**Done when:** you can build/break with multiple block types via the hotbar.

---

## Phase 4 — Assets & Texturing
- [ ] Block texture atlas in `assets/textures/` (via Summer MCP `summer_generate_image` or manual)
- [ ] Materials in `assets/materials/` referenced by the block registry
- [ ] Replace flat colors with textured blocks
- [ ] Optional: ambient SFX (place/break/step) in `assets/audio/`

**Done when:** blocks are textured and the registry maps types → atlas regions.

---

## Phase 5 — Game Feel & Polish
- [ ] Block place/break feedback (particles, sound, subtle screen feedback)
- [ ] Sky/lighting pass (time-of-day optional)
- [ ] Performance pass (`summer_get_diagnostics`) — target stable 60 FPS

**Done when:** interactions feel responsive and the scene is visually clean.

---

## Phase 6 — Template Packaging
Make it genuinely reusable by others.

- [ ] End-user README: how to clone, open, play, and extend
- [ ] Inline "EXTEND HERE" comments at each extension point
- [ ] Example: add a custom block type, documented step-by-step
- [ ] Tag a `v1.0` template release

**Done when:** a new developer can clone, read the README, and ship a change in <30 min.

---

## Deploy (gates Phase 0 completion)

The remote currently points at Summer's **read-only template**, and GitHub auth isn't set up
yet. To deploy for the team:

1. Authenticate GitHub CLI (token method is simplest):
   - Create a token at https://github.com/settings/tokens (scope: `repo`)
   - `gh auth login --with-token`  → paste token → Enter
2. Create the team repo and push both branches:
   ```
   gh repo create <org-or-user>/template-3d-voxel-sandbox --private --source . --remote origin --push
   git push -u origin developer
   ```

**Branching model:** `main` = stable/reviewed; `developer` = integration branch teammates
branch off of. Feature work → PR into `developer` → periodic PR `developer → main`.
