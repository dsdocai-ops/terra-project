# terra-project

Game-development project built in **Godot**. Repo: https://github.com/dsdocai-ops/terra-project (default branch `main`).

> The repo is at an early stage (only `README.md` so far). When you add the Godot project, update the "Project layout" and "Engine" sections below so they stay accurate.

## How this project is developed

This project is **co-developed by two people, sharing work through GitHub**. Several agents (Claude Code sessions, on either developer's machine) may also be working on it. Treat every session as one contributor among several, and assume the other side has changed things since you last looked.

### Git workflow

- **Pull before you start, and before you push**: `git pull --rebase origin main`. Check `git status` and `git log` first so you know what changed.
- **Never work directly on `main`** for anything non-trivial. Use a short-lived branch (`feature/<topic>`, `fix/<topic>`) and merge via pull request.
- Keep commits small and focused, with clear messages describing the *why*.
- **Never force-push** to `main` or to a branch someone else may be using. Never rewrite shared history.
- Don't commit or push unless the developer asks you to.
- If a merge or rebase conflicts, stop and resolve it carefully. Don't discard the other side's work to make it go away. When in doubt, ask.

### Avoiding collisions (Godot-specific)

Godot's text-based scene/resource files merge poorly when two people edit the same one:

- **`.tscn`, `.tres` and `project.godot` are the main conflict risks.** Avoid editing the same scene as the other developer at the same time; coordinate on who owns which scene.
- Prefer **small, composable scenes** and put logic in **scripts** (`.gd`) rather than piling everything into one big scene.
- Don't reformat or mass-rename files/nodes unrelated to your task. It creates noisy diffs and conflicts.
- Moving or renaming files should be done **inside the Godot editor** (so references and `.uid`/import data stay valid), and committed as its own change.
- Commit the `.uid` files and `.import` files Godot generates; do **not** commit the `.godot/` cache folder (make sure `.gitignore` covers it).
- Large binary assets (art, audio, models) bloat the repo. Flag it before adding big files; consider Git LFS.

### Working as an agent

- Read this file and `README.md` first, then look at the existing code and scene structure before changing anything. Match the existing conventions rather than introducing new ones.
- Make the smallest change that does the job. Don't refactor or restructure across the project unprompted, since the other developer may be mid-edit in the same area.
- Say what you changed and what you didn't verify. If you couldn't run the game or tests, say so.
- Record decisions that affect both developers (new folder structure, naming rules, addons added, Godot version bumps) in this file or in a `docs/` note, so the next session, human or agent, doesn't have to guess.

## Engine

- Godot (version not yet pinned; **record the exact version here once chosen** and make sure both developers use the same one, since mixing versions rewrites project files).
- Language: GDScript unless the team decides otherwise.

## Conventions (defaults until the team decides otherwise)

- GDScript style per the official Godot style guide: `snake_case` for files, functions and variables; `PascalCase` for classes and node names; `UPPER_SNAKE_CASE` for constants.
- One script per scene where practical, named to match the scene (`player.tscn` / `player.gd`).
- No secrets, API keys or personal paths committed to the repo.

## Project layout

_To be filled in as the project grows._ Suggested starting structure:

```
scenes/    # .tscn scenes
scripts/   # .gd scripts not tied 1:1 to a scene
assets/    # art, audio, fonts
docs/      # design notes and decisions
```

Map:

- `scenes/main.tscn` uses `scripts/terrain.gd` (node `Terrain`), which builds the level procedurally at startup, seeded so it's identical every run: a 1.6 km heightmap valley (with `HeightMapShape3D` collision) ringed by rocky mountains, a dirt trail, wind-swept grass (MultiMesh chunks, `shaders/grass.gdshader`), pine forests and mossy boulders (`shaders/rock.gdshader`), ground coloured by `shaders/terrain.gdshader`. The spawn (origin) is a flat clearing at y = 0. The environment (sky, haze, sun) is in `main.tscn`; the sky is `shaders/toon_sky.gdshader` (a sky shader: flat gradient, hard sun disc with a halo that follows the Sun light, and drifting cartoon cumulus clouds: each a flat base with round puffs on it, shaded white with a scalloped lavender shadow along the underside and an even-width blue ink rim, set in far / mid / high rings around the sky (the far ring hazed toward the horizon); coverage, size, wind speed and colours are uniforms). Its radiance pass skips clouds and sun so ambient light stays steady.
- `scripts/city.gd` and `shaders/building.gdshader` (the old neon city) are no longer used by any scene.
- **Art style: toon / cel-shaded.** World shaders include `shaders/toon_light.gdshaderinc` (a `light()` that bands diffuse light into shadow / mid / lit, no specular). Objects get ink outlines from `shaders/outline.gdshader` used as a material `next_pass` (inverted hull; see its `push_mode` for flat-shaded meshes). The mech's imported materials are switched to toon diffuse/specular with an outline at runtime in `vela_model.gd`. The environment uses linear tonemapping so flat colours stay saturated. New world art should follow this: flat saturated colours, `toon_light` lighting, outlines on props (not on ground or grass).
- **Effects are cel-shaded too.** Build particles and glowing shots with `scripts/toon_fx.gd` (use via `preload`): particles are hard-edged shapes (blob, four-point sparkle, diamond, ring) in flat colour with an ink rim (`shaders/toon_particle.gdshader`), whose colour ramps switch in steps and which shrink away instead of fading (alpha in the ramp is the size); energy balls use `shaders/toon_energy.gdshader` (white core / glow / rim bands) with an ink outline. Avoid soft additive glow sprites, which clash with the toon look. Used by the thrusters, `energy_ball.gd` (one ball that grows out of the barrel, with a sparkle trail; impact: star flash, shock ring, sparkles, smoke puffs) and the muzzle sparkles in `vela_model.gd`. A shot shows as a single ball: there is no separate muzzle-flash ball.
- Save text files as UTF-8 **without** BOM: Godot's scene parser rejects a BOM at the start of `.tscn` files (Windows PowerShell 5.1 `Set-Content -Encoding utf8` adds one).

Models built in Blender:

- `art_src/` holds Blender sources (`.blend` plus the Python build script that generates each model). It has a `.gdignore` so Godot doesn't try to import `.blend` files.
- `assets/models/` holds the exported `.glb` files that the game actually uses.
- `art_src/vela_07/build_vela_07.py` regenerates the Vela-07 mech (see its docstring for the command). Edit the script and re-run it rather than hand-editing the exported files. The model is in a T-pose and faces -Y in Blender (glTF/Godot +Z). It is **assembled from parts like a real robot**: every moving piece is its own object (`<Bone>_Part`, 36 in total) with its origin on its joint, parented to that bone, and the joints are modelled on the pivots (the head is a knight helm: rounded dome, beaked faceplate with a glowing eye slit and vents; ball joints at shoulders/hips/wrists/ankles, hinges at elbows/knees/knuckles/toes whose axis matches the bend, a waist bearing, neck column and back-plate hinge; upper arms and thighs fork around the elbow/knee hinges; shoulder caps sit above the arms so the cannon can swing forward). When changing it, keep new pieces on the right bone and clear of neighbouring parts' swing. It imports as a `Skeleton3D` (38 bones) with each part a `MeshInstance3D` on a `BoneAttachment3D`. Bone names follow Godot's `SkeletonProfileHumanoid` (no UpperChest, eyes, jaw, thumb metacarpals or right-hand fingers), so humanoid animations can be retargeted onto it via the import settings. Extra bones: `Root`, `Backpack`, `RightMuzzle`.
- **Vela-08** is a blue / orange sibling built by the same script with `palette=vela_08` (same frame, rig, bones and clips; orange plates, cobalt armour, a white helm face with an orange eye slit, orange core glows, cyan accents, "08" on the pauldrons). It is saved as `art_src/vela_08/vela_08.blend` and exported to `assets/models/vela_08.glb`. **Vela-08 is the player; Vela-07 is the enemy** (`scripts/enemy.gd`, a `CharacterBody3D` that builds its body from `vela_model.gd` with `model_scene = VELA_07` and flashes its armour via `hit_flash()` when hit).
- **Enemy AI** (`scripts/enemy.gd`, a state machine): PATROL (wander around home) -> CHASE (sees the player within `SIGHT_RANGE` with line of sight, or gets shot) -> ATTACK (inside `ATTACK_RANGE`: circle-strafes, keeps `KEEP_AWAY` distance, raises the cannon then fires red-orange energy balls with partial lead and spread) -> RETURN (lost the player for `LOSE_TIME`, player dead, or past `LEASH` from home) -> PATROL. Enemy shots do `SHOT_DAMAGE` and never hurt other enemies (`energy_ball.gd` takes per-shot `damage` / `glow_color` / `rim_color` and skips same-side hits). Tuning constants are at the top of `enemy.gd`.
- **Death:** `vela_model.gd` `explode()` plays the death for both sides: a quick flash of the armour, then `scripts/mech_explosion.gd` (a toon fireball turning to smoke) and every part flies off as a `RigidBody3D` (collides with the world only, shrinks away after ~2.6 s); `reassemble()` rebuilds the mech. Enemies explode at 0 health and reassemble at their spawn spot after `RESPAWN_TIME`. The player has `health`, `take_hit(damage, point)` and `die()`; it explodes at 0 health (camera shake, "DESTROYED" banner, no control or shooting) and respawns at its start point after 3.5 s. Enemy shots damage the player (health bar bottom left, red screen-edge flash on a hit); **K** self-destructs for testing. Paint schemes live in `PALETTES` in the build script; add one there for further variants. Orange glows use a low emission strength because stronger values clip to yellow under the linear tonemap.
- The build script also authors the looping clips `Idle`, `Run`, `Fly`, `Hover`, `Cruise` (exported in the `.glb`). `Hover` plays in hover mode (H key: hold altitude, WASD moves mid-air, Space/Ctrl climb/sink, see `player.gd`), while stabilising (Shift), or when barely moving in the air; `Fly` otherwise. `Backpack` is never keyed: `scripts/vela_model.gd` flares it in code.
- The right hand is an **arm cannon** (no right finger bones; a `RightMuzzle` bone marks the muzzle, +Y along the barrel). `scripts/weapon.gd` fires `scripts/energy_ball.gd` projectiles (left mouse) toward the crosshair; while aiming (right mouse) or shooting, `scripts/arm_aim.gd` (a `SkeletonModifier3D` on the skeleton) swings the arm to point at the target on top of the playing clip, with recoil and muzzle sparkles driven from `vela_model.gd`. Aiming is smoothed: `player.gd` keeps one eased aim-down-sights blend (`ads`, 0..1) that drives camera distance, zoom, look sensitivity and the reticle size; the arm raise eases and follows a smoothed aim point, and the reticle kicks on each shot and fades/tints rather than snapping (see the smoothing constants in `weapon.gd`) (`aim_arm`, `fire_recoil`, `muzzle_transform`).
- In game, the player's `Model` node uses `scripts/vela_model.gd`, which instances the `.glb` set in its `model_scene` (default Vela-08), picks the clip from the player state (`update_motion`), flares the back plates (`update_wings`) and drives thruster flames attached to the foot and back-plate bones (`set_thrust`). Each flame is a `scripts/thruster.gd` node: a hard-banded jet cone (`shaders/thruster_flame.gdshader`) plus CPU particles (flame blobs, sparkles, cloud-puff smoke), chosen to work on the Compatibility renderer. `scripts/mech_model.gd` (the old primitive mech) is no longer used by any scene.
