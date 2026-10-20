# Sinkhole task list

Lanes: **A** = Dev A (Pit lane), **B** = Dev B (Systems lane), **AB** = both. Module ids from `specs/CAPABILITY_MAP.md`. Branch name: `feat/<module-id>-<task-id-lowercase>-<short-desc>`.

Every week carries `[art-audio]` tasks: Claude Code generates or sources every asset (SPEC-art-audio), the lane owner reviews the sheet in `docs/asset-review/`. Week 1 is fully detailed. Weeks 2 to 12 are listed with brief acceptance and are expanded into the week 1 format at the start of each week.

---

## Week 1: Foundation + networking

**Done when:** Isometric TileSet, Y-sort, player movement, camera. 2 players can connect and see each other move (host + client).

### Dev B

## Task W1-B1: Project settings and folder tree

**Module:** `foundation`
**Description:** Set every `project.godot` value from the SPEC-foundation settings table (960x540, canvas_items, keep, integer, gl_compatibility both methods, nearest filter, 2D pixel snap both, 6-color fallback palette, etc.).

**Acceptance criteria:**
- [x] `project.godot` matches the SPEC-foundation table line for line (one recorded deviation: `inferred_declaration` Ignore, not Warn; `run/main_scene` is set in W1-B6 when the scene exists; physics layer names added)
- [x] Every folder under `scenes/`, `scripts/`, `data/`, `assets/`, `tests/` from SPEC-project exists (`.gdkeep` in empty ones)
- [x] Headless import produces zero warnings and zero errors

**Verification:**
- [x] `godot --headless --path . --import` exits 0 with no warnings; `tests/unit/test_project_settings.gd` asserts every table value, the features, the layer names, and the folder tree
- [ ] Manual: editor opens, viewport 960x540, test window 1920x1080 shows integer-scaled crisp pixels on a placeholder sprite (Dev A, when running the game)

**Dependencies:** None
**Files likely touched:** `project.godot`, `*/.gdkeep`
**Estimated scope:** S

**Ask from Dev A (W1-A7 follow-up):** add 2D physics layer names so scenes read clearly: `layer_names/2d_physics/layer_1 = "world"`, `layer_2 = "player"`, `layer_3 = "enemy"`, `layer_4 = "hitbox_player"`, `layer_5 = "hitbox_enemy"`, `layer_6 = "interactable"`. `player.tscn` already uses layer 2 / mask 1 so players pass through each other and collide with walls only.

## Task W1-B2: Input Map

**Module:** `foundation`
**Description:** Add every action from the SPEC-foundation Input Map table with its keyboard/mouse binding and a controller binding. Movement is four actions; no deadzone tuning yet.

**Acceptance criteria:**
- [x] All 24 action names exist exactly as spelled in SPEC-foundation (written by `tools/configure_input_map.gd`, the canonical list)
- [x] Each gameplay action has one keyboard/mouse and one controller event; `weapon_1`, `weapon_2`, `debug_console` are keyboard-only by design. Controller deviation recorded in the spec: ability_2 RB, ability_3 R3, ultimate L3 (no chords; A stays on interact)
- [x] `debug_console` bound to backtick

**Verification:**
- [x] `tests/unit/test_input_map.gd`: every name exists, binding classes per action, specific keys/buttons/axes from the table, no joypad button bound twice, and synthetic key and stick events drive the actions through `Input`
- [ ] Manual: Input Map panel shows controller icons next to each (Dev A, in the editor)

**Dependencies:** W1-B1
**Files likely touched:** `project.godot`, `tests/unit/test_input_map.gd`
**Estimated scope:** S

## Task W1-B3: Autoload stubs and ContentData base

**Module:** `foundation`
**Description:** Create the 7 autoload scripts in SPEC-foundation order (`Events`, `TimeManager`, `GameState`, `SaveManager`, `StoryManager`, `AudioManager`, `NetworkManager`) with the public API defined by the module specification.

**Acceptance criteria:**
- [x] All 7 autoloads registered in the specified order and reachable by name from a test
- [x] Each stub exposes every signal, constant, and method named in its spec's "Interfaces provided" block, fully typed (base classes with `TODO(module)` markers where the real class does not exist yet; `StoryManager` flags and lore are a working in-memory set)
- [x] `ContentData` loads and a test `.tres` extending it round-trips

**Verification:**
- [x] `tests/unit/test_autoloads.gd`: order, every spec method and signal, the full Events signal set with no public methods, constants, ContentData round trip
- [x] Import exits 0 with `untyped_declaration` as Error

**Dependencies:** W1-B1
**Files likely touched:** `scripts/autoload/*.gd` (7), `scripts/data/content_data.gd`, `project.godot`, `tests/unit/test_autoloads.gd`
**Estimated scope:** M

## Task W1-B4: GUT and test skeleton

**Module:** `foundation`
**Description:** Vendor the latest GUT 9.x release compatible with 4.7 into `addons/gut/`, enable the plugin, add `tests/unit/`, `tests/integration/`, `tests/helpers/`, write `test_scenes_load.gd` and other smoke tests.

**Acceptance criteria:**
- [x] `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` exits 0 (GUT 9.7.1 vendored, plugin enabled)
- [x] A deliberately failing test makes it exit 1 (verified, then removed)
- [x] `test_scenes_load` and `test_data_loads` pass on the current tree

**Verification:**
- [x] Ran the command twice: green with exit 0, and exit 1 with a throwaway failing test
- [x] SPEC-foundation open question for GUT version resolved (9.7.1)

**Dependencies:** W1-B1
**Files likely touched:** `addons/gut/**`, `project.godot`, `tests/integration/test_scenes_load.gd`, `tests/integration/test_data_loads.gd`, `specs/SPEC-foundation.md`
**Estimated scope:** M

## Task W1-B5: CI workflow

**Module:** `foundation`
**Description:** `.github/workflows/ci.yml` on `pull_request` and `push` to `main`: check out, install Godot 4.7.2 headless, run import and GUT, fail on non-zero exit.

**Acceptance criteria:**
- [ ] A PR shows a CI status check that passes on the current tree (verified by the `feat/surface-week1` PR run; workflow written 2026-10-18)
- [ ] A PR with a failing test shows red (exit code 1 on failure verified locally in W1-B4; observe on a PR)
- [ ] Runtime under 5 minutes

**Verification:**
- [ ] Observe the PR check; a throwaway failing-test PR is optional once the first run is green
- [x] SPEC-foundation open question for the setup action resolved: direct download of the official `godotengine/godot-builds` 4.7.2 Linux release, no third-party action

**Dependencies:** W1-B4
**Files likely touched:** `.github/workflows/ci.yml`, `specs/SPEC-foundation.md`
**Estimated scope:** S

## Task W1-B6: Main scene and launch args

**Module:** `foundation`
**Description:** `scenes/main/main.tscn` + `main.gd` as the project main scene. Parses `OS.get_cmdline_user_args()` for `--host`, `--join=<ip>`, `--seed=<int>`; sets `GameState.world` after loading.

**Acceptance criteria:**
- [x] `godot --path . -- --host` reaches the world scene with no menu (`LaunchArgs` + `Main.apply_options`)
- [x] `godot --path . -- --join=127.0.0.1` attempts a join with no menu (`--join=ip:port` also accepted)
- [x] No args shows the placeholder menu with Play Solo, Host, Join + IP field; failures put the menu back with a status line

**Verification:**
- [x] `tests/unit/test_launch_args.gd` (11) and `tests/unit/test_main_scene.gd` (7); `application/run/main_scene` asserted in `test_project_settings`
- [ ] Manual: launch each variant (covered by the headless two-instance smoke in W1-B10 and Dev A's walkabout)

**Dependencies:** W1-B1, W1-B3 (NetworkManager stub), W1-A3 (world scene path; can use a placeholder until A3 lands)
**Files likely touched:** `scenes/main/main.tscn`, `scenes/main/main.gd`, `project.godot` (main_scene), `tests/unit/test_launch_args.gd`
**Estimated scope:** S

## Task W1-B7: NetworkManager host, join, peer tracking

**Module:** `networking`
**Description:** Replace the stub with the real `NetworkManager`: `host(port)`, `join(ip, port)`, `start_solo()`, `disconnect_all()`, `is_host`, `local_peer_id`, `peer_ids`, `players`, `player_connected`, and lifecycle hooks.

**Acceptance criteria:**
- [x] Two instances on one machine connect; host logs `player_joined(peer_id)`; client logs connection (headless smoke green)
- [x] Closing the client fires `player_left` on host; closing the host fires `host_disconnected` on client (both observed in the smoke logs)
- [x] `start_solo()` sets `is_host` true with `peer_ids == [1]`; host() and join() refuse while a session is active; malformed addresses are rejected before ENet

**Verification:**
- [x] `tests/unit/test_network_manager.gd` (12): multiplier table, inactive state, solo, host, refusals, disconnect reset, address validation, pending client
- [ ] Two-instance connect/disconnect via the headless smoke (W1-B10)

**Dependencies:** W1-B3, W1-B6
**Files likely touched:** `scripts/autoload/network_manager.gd`, `tests/unit/test_network_manager.gd`
**Estimated scope:** M

## Task W1-B8: Player spawning through MultiplayerSpawner

**Module:** `networking`
**Description:** `MultiplayerSpawner` under `World/Players` with the player scene registered. On `player_joined` (and for the host itself at world load), the host calls `spawn()` with a `PlayerSpawnInfo` payload.

**Acceptance criteria:**
- [x] Host and one client each see two `Player` nodes under `World/Players` with distinct `peer_id` (headless smoke green)
- [x] Late joiner sees existing players; existing players see the late joiner (the client joins 2 s after the host spawned itself and receives Player1; smoke green)
- [x] Leaving removes the node on all peers (host logs the peer leaving and drops to 1 player; smoke green)

**Verification:**
- [x] `tests/unit/test_player_spawner.gd` (12): `PlayerSpawnInfo` round trip and wire types, spawner under World targeting Players, spawn sets name / peer_id / position / authorities / input visibility, registry, despawn, replace-on-respawn, auto-spawn from `player_joined`, despawn from `player_left`, non-overlapping default positions
- [ ] Two-instance: spawn, late join, leave (headless smoke in W1-B10)

**Dependencies:** W1-B7, W1-A4
**Files likely touched:** `scenes/main/world.tscn` (Players spawner node; coordinate with Dev A, owner), `scripts/network/player_spawn_info.gd`, `scripts/autoload/network_manager.gd`, `tests/unit/test_spawn_info.gd`
**Estimated scope:** M

## Task W1-B9: InputSync and StateSync configuration

**Module:** `networking` (PR into Dev A's `player.tscn`, Dev A reviews)
**Description:** Configure the two `MultiplayerSynchronizer` nodes Dev A placed in `player.tscn` (W1-A4). `InputSync`: authority = owning peer, replicates `move_input: Vector2`, `aim_position: Vector2`; `StateSync`: position, facing, animation and health.

**Acceptance criteria:**
- [x] Client input moves the client's player on the host (headless smoke: InputSync check passes)
- [x] Host position updates appear on the client for both players (headless smoke: StateSync check passes; remote copies interpolate, the local player reconciles)
- [ ] A third instance joining sees both others moving (manual, `tools/run_two.ps1 -Clients 2`)

**Verification:**
- [x] `tests/unit/test_player_sync.gd` (12): replication configs, publish, roles, reconcile, interpolate, anim replay; `tools/smoke_two.sh` green
- [x] `player.gd` doc comment contains "Sync:"

**Dependencies:** W1-B8, W1-A4, W1-A6
**Files likely touched:** `scenes/player/player.tscn`, `scenes/player/player.gd`, `scripts/autoload/network_manager.gd`
**Estimated scope:** S

## Task W1-B10: Two-instance launcher

**Module:** `debug-tools` (pulled forward from week 2 because week 1 smoke needs it)
**Description:** `tools/run_two.ps1` and `tools/run_two.sh` launching `--host` and `--join=127.0.0.1` with windows positioned side by side, optional count for more clients. Configure Godot's debug options as required.

**Acceptance criteria:**
- [x] Running the script opens two windows that connect (`tools/run_two.ps1`, `tools/run_two.sh`; the connect / spawn / move path is proven headless by `tools/smoke_two.sh`, 15 checks green)
- [ ] F5 in the editor with multi-instance enabled does the same (per-machine setting in `.godot/`, documented in SPEC-project commands; Dev A sets it once)

**Verification:**
- [ ] Manual run of the windowed launcher (Dev A); headless smoke green 2026-10-18

**Dependencies:** W1-B6, W1-B7
**Files likely touched:** `tools/run_two.ps1`, `tools/run_two.sh`, `specs/SPEC-project.md`
**Estimated scope:** XS

### Dev A

## Task W1-A1: Iso helper

**Module:** `foundation`
**Description:** `scripts/iso.gd` static class `Iso` with `to_screen(tile: Vector2i) -> Vector2`, `to_tile(screen: Vector2) -> Vector2i`, `input_to_world(dir: Vector2) -> Vector2` for 64x32 diamond coordinates.

**Acceptance criteria:**
- [x] `to_tile(to_screen(t)) == t` for every tile in a 64x64 grid including negatives
- [x] `input_to_world` of the 8 unit directions all have equal length and point along the expected screen directions
- [x] Fully typed, doc comment

**Verification:**
- [x] `tests/unit/test_iso.gd` passes (10 tests, cross-checked against a real TileMapLayer)

**Dependencies:** None
**Files likely touched:** `scripts/iso.gd`, `tests/unit/test_iso.gd`
**Estimated scope:** S

## Task W1-A2: Placeholder isometric TileSet and placeholder generator

**Modules:** `foundation`, `art-audio`
**Description:** `assets/tilesets/placeholder_iso.tres`: TileSet, Isometric shape, Diamond Down layout, 64x32, atlas with floor, wall, pit tiles in flat colors, physics layer on walls, custom data for walkable state.

**Acceptance criteria:**
- [x] TileSet has the three tiles, walls collide, `walkable` is true on floor and false on wall/pit
- [x] Generator runs headless from the CLI (not an EditorScript, so CI can regenerate) and writes PNGs with correct sizes
- [x] Imported textures are lossless with mipmaps off; nearest filtering is the project default set in W1-B1

**Verification:**
- [x] `tests/unit/test_tileset.gd`: tile count, custom data values, physics layer present
- [ ] Manual: 20x20 diamond renders crisp at 1920x1080 (after W1-B1 lands the nearest filter setting)

**Dependencies:** W1-B1 (folders)
**Files likely touched:** `assets/tilesets/placeholder_iso.tres`, `assets/tilesets/placeholder/*.png`, `tools/make_placeholders.gd`, `assets/.import presets`, `tests/unit/test_tileset.gd`
**Estimated scope:** M

## Task W1-A3: World scene

**Module:** `foundation`
**Description:** `scenes/main/world.tscn` per SPEC-foundation: `World` (Y-sort) with `Floor` and `Walls` `TileMapLayer`s, `Entities` (Y-sort), `Players`, `Camera`, `FX`. A 20x20 test floor with a wall ring and spawn areas.

**Acceptance criteria:**
- [x] Node layout matches the spec; `Players` is ready to receive a `MultiplayerSpawner` (W1-B8)
- [ ] Walls block movement; Y-sort orders a test sprite behind and in front of a wall correctly (manual, after W1-A6 gives something that moves)
- [x] Scene instantiates headless

**Verification:**
- [x] `tests/unit/test_world.gd` (layout, typed refs, Y-sort flags, test floor painting, `is_walkable`); `test_scenes_load` arrives with W1-B4
- [ ] Manual: walk a placeholder sprite around the wall ring (after W1-A6)

**Dependencies:** W1-A2
**Files likely touched:** `scenes/main/world.tscn`, `scenes/main/world.gd`
**Estimated scope:** S

## Task W1-A4: Player scene skeleton

**Module:** `player-controller`
**Description:** `scenes/player/player.tscn` + `player.gd` with the composition from SPEC-player-controller: `CharacterBody2D` root, placeholder child nodes for `StatBlock`, `Health`, `Hurtbox`, `Sprite2D`, and networking state nodes.

**Acceptance criteria:**
- [x] Scene instantiates headless; every node in the spec layout exists by name
- [x] `Player` has every public field and signal from the spec's "Interfaces provided", typed (`character` and `class_data` are `Resource` until classes-characters defines their classes)
- [x] `is_local` is `peer_id == multiplayer.get_unique_id()`

**Verification:**
- [x] `tests/unit/test_player_scene.gd`: node names, fields, signals, methods, defaults, `is_local`, 16 directional animations, `play_directional`
- [ ] `test_scenes_load` passes (arrives with W1-B4)

**Dependencies:** W1-A3
**Files likely touched:** `scenes/player/player.tscn`, `scenes/player/player.gd`, `tests/unit/test_player_scene.gd`
**Estimated scope:** S

## Task W1-A5: StateMachine and State components, Idle and Move

**Modules:** `player-controller` (component is shared under `scripts/components/`, Dev B reviews)
**Description:** `scripts/components/state_machine.gd` and `state.gd`: node-based, `change_to(name)` with states able to refuse, `enter`, `exit`, `physics_update(delta)`, `handle_input`. Player states `Idle` and `Move` are implemented in `scenes/player/states/`.

**Acceptance criteria:**
- [x] `change_to` calls `exit` then `enter`, emits `state_changed`
- [x] A state returning false from `can_exit()` blocks the transition (and `can_enter()` on the target)
- [x] Player starts in `Idle`, moves to `Move` on input, back to `Idle` when input stops (states read `Player.move_input`, so they run headless without the Input Map)

**Verification:**
- [x] `tests/unit/test_state_machine.gd` (9) and `tests/unit/test_player_states.gd` (4). Initial state enters on the actor's `ready` so the actor's `@onready` references exist
- [ ] Manual: state label overlay shows Idle/Move switching (debug overlay arrives in week 2)

**Dependencies:** W1-A4
**Files likely touched:** `scripts/components/state_machine.gd`, `scripts/components/state.gd`, `scenes/player/states/idle.gd`, `scenes/player/states/move.gd`, `tests/unit/test_state_machine.gd`
**Estimated scope:** M

## Task W1-A6: Isometric movement and facing

**Module:** `player-controller`
**Description:** In `Move`: read the four `move_*` actions into a vector, pass through `Iso.input_to_world()`, accelerate to full speed in ~4 frames, friction to stop, base speed 120 px/s constant, face in 8 sectors.

**Acceptance criteria:**
- [x] WASD moves along isometric axes; all 8 directions have equal on-screen speed (cardinals screen-aligned, diagonals on the tile axes)
- [x] Facing index updates in 8 sectors with no flicker at boundaries (3 degree hysteresis in `Iso.facing_index`)
- [x] Remote player instances do not read local input (`is_local` gate in `_physics_process`)

**Verification:**
- [x] `tests/unit/test_player_facing.gd` (11): sectors, boundaries, hysteresis, speed in 8 directions, acceleration and friction in 4 frames, facing persists into Idle, remote input untouched
- [ ] Manual feel check: snappy start/stop, no diagonal speed-up (needs W1-B2 Input Map and W1-B6 main scene to run in-game)

**Dependencies:** W1-A1, W1-A5
**Files likely touched:** `scenes/player/states/move.gd`, `scenes/player/states/idle.gd`, `scenes/player/player.gd`, `tests/unit/test_player_facing.gd`
**Estimated scope:** M

## Task W1-A7: Game camera

**Module:** `player-controller`
**Description:** `scenes/main/camera.gd` on `World/Camera`: `set_targets(players)`, position smoothing (~8), follows the local player in solo; with multiple targets frames the centroid and zooms out automatically.

**Acceptance criteria:**
- [x] Solo: camera follows the single tracked player (smoothing on; pixel jitter check is manual after W1-B1 integer scaling)
- [x] Two players walking apart zoom the camera out to 0.6 then clamp movement at the edges (`Player.clamp_to_camera()` from Move, only when 2+ targets)
- [x] `shake(5, 0.3)` offsets within strength, decays quadratically, respects `screen_shake`

**Verification:**
- [x] `tests/unit/test_camera_framing.gd` (14): fit zoom math, centroid, in-tree framing, view rect, clamp, shake, World/Camera auto-tracks `Players` children, co-op clamp through the player
- [ ] Manual two-instance: walk apart, confirm clamp on both screens (needs W1-B7 to W1-B9)

**Dependencies:** W1-A3, W1-A6
**Files likely touched:** `scenes/main/camera.gd`, `scenes/main/world.tscn`, `tests/unit/test_camera_framing.gd`
**Estimated scope:** M

### Both

## Task W1-AB1: Client prediction, correction, and two-instance smoke

**Modules:** `networking`, `player-controller`
**Description:** Local player moves immediately from its own input; host simulates the same input; `StateSync` position corrects drift on the client with a small lerp (snap if error > 64 px). Remote players are smooth and authoritative.

**Acceptance criteria:**
- [ ] At 0 ms latency, no visible correction on the local player (reconcile implemented in W1-B9; visual check is Dev A's)
- [ ] Remote players move smoothly (interpolation implemented in W1-B9; visual check is Dev A's)
- [ ] Facing and animation match on both screens (facing_index and current_anim replicated on change; visual check is Dev A's)

**Verification:**
- [x] Two-instance smoke steps 1 and 2 pass headless (`tools/smoke_two.sh`), recorded in the surface-week1 PR
- [ ] Three-instance sanity via `run_two.ps1 -Clients 2` (Dev A)

**Dependencies:** W1-B9, W1-A6, W1-A7
**Files likely touched:** `scenes/player/player.gd`, `scenes/player/states/move.gd`, `scripts/autoload/network_manager.gd`
**Estimated scope:** S

## Task W1-AB2: Week 1 checkpoint and tag

**Description:** Fill the WEEKLY.md template for week 1, run the full checklist, tag `week-1` on `main`. Write back resolved open questions (GUT version, CI action) into SPEC-foundation.

**Acceptance criteria:**
- [x] Design doc week 1 "Done when" met and recorded (WEEKLY.md entry, 2026-10-18)
- [x] CI green on `main` (workflow triggers on push to main; import + GUT jobs green locally; live Actions run not observable from this machine — outstanding, non-blocking, recorded in HANDOFF/WEEKLY)
- [ ] Both developers pulled `main` and ran the two-instance smoke on their own machine (Dev A on their machine: outstanding, non-blocking; one-machine smoke 15/15 green)

**Verification:**
- [x] `git tag week-1` pushed
- [x] `specs/WEEKLY.md` entry present

**Dependencies:** all W1 tasks
**Files likely touched:** `specs/WEEKLY.md`, `specs/SPEC-foundation.md`
**Estimated scope:** XS

## Task W1-AB3: Asset pipeline skeleton and credits file

**Module:** `art-audio`
**Description:** Claude Code produces every asset from this point on (SPEC-art-audio, decision 2026-10-19). Create `tools/art/` (`requirements.txt`, `palette.py` with the 7 locked biome palettes, `pixel.py` stub, `build_all.py` stub, `README.md` with the run commands), `tools/audio/` (`README.md`, `sfx/` and `music/` folders), `CREDITS.md` at repo root with the schema header, `docs/asset-review/INDEX.md`. No real assets yet; week 1 stays on the Godot placeholders.

**Acceptance criteria:**
- [ ] `python -m pip install -r tools/art/requirements.txt` then `python tools/art/build_all.py --check` exits 0 on an empty asset set
- [ ] `palette.py` exposes every color named in SPEC-art-audio
- [ ] `CREDITS.md` has the six-column header and a row for every third-party file already under `assets/` or `addons/` fonts (expected: none yet)
- [ ] WEEKLY.md template gains the "asset review sheets approved" line

**Verification:**
- [ ] `pytest tools/art` runs (a single smoke test is enough)
- [ ] Reviewer skims `palette.py` hex values against the spec table

**Dependencies:** W1-B1 (folders)
**Files likely touched:** `tools/art/*`, `tools/audio/*`, `CREDITS.md`, `docs/asset-review/INDEX.md`, `specs/WEEKLY.md`
**Estimated scope:** S

## Checkpoint: Week 1 day 2
- [ ] W1-B1, W1-B2, W1-B3, W1-B4, W1-B5, W1-A1, W1-A2 merged
- [ ] Import zero warnings, CI green on an empty-content PR
- [ ] Both developers' editors open the project clean

## Checkpoint: Week 1 day 4
- [ ] W1-B6, W1-B7, W1-B8, W1-A3, W1-A4, W1-A5 merged
- [ ] `--host` + `--join` connect; two `Player` nodes visible on both screens

## Checkpoint: Week 1 end
- [ ] `tools/art/`, `tools/audio/`, `CREDITS.md` skeletons exist (W1-AB3)
- [ ] All W1 tasks merged; `test_iso`, `test_player_facing`, `test_state_machine`, `test_camera_framing`, `test_network_manager`, `test_scenes_load`, `test_data_loads`, `test_autoloads`, and `test_input_map` pass
- [ ] Two-instance smoke steps 1 and 2 pass; `week-1` tagged

---

## Week 2: Combat core

**Done when:** Light/heavy attacks, dodge, weapon swap, Health/Hitbox/Hurtbox components, 3 enemies with telegraphs, all synced in co-op.

### Dev A
- [ ] W2-A1 `[combat-core]` `Health`, `Hitbox`, `Hurtbox`, `HitInfo`, `StatusApplication`, `Team`. Accept: components on player; `about_to_die` prevention hook; from-behind angle; host-only hit resolution.
- [ ] W2-A2 `[combat-core]` `AttackController`: light combo with step reset and input buffer, heavy charge/release, tap heavy, swap with lockout, attack speed scale. Accept: spec behaviors.
- [ ] W2-A3 `[combat-core]` Hit reactions: `HitStun` state, knockback impulse with wall block, 0.4 s player i-frames. Accept: spec values.
- [ ] W2-A4 `[combat-core]` Hit feedback: `hit_flash.gdshader`, camera shake tiers, `TimeManager.hit_stop` calls, `DamageNumberPool` in `World/FX`. Accept: visible on every hit; crits distinguished.
- [ ] W2-A5 `[combat-core]` `AttackPattern` Resource + `Telegraph` scene (circle, cone, line, ring, fill over windup) + windup/active/recovery driver. Accept: no hit without telegraph.
- [ ] W2-A6 `[combat-core]` `Projectile` base + `ProjectilePool` (pierce, bounce, homing, lifetime, reflectable, time-scaled). Accept: 500 pooled projectiles no allocs.
- [ ] W2-A7 `[weapons]` `WeaponData`, `AttackSpec`, `WeaponController`, `WeaponAttack` base, Pickaxe and Crossbow scenes and `.tres`. Accept: light/heavy/swap on both; ground crack line; charged state.
- [ ] W2-A8 `[player-controller]` Dodge roll with i-frames, cooldown from stat, perfect-dodge window, `dodge_charges`, `reset_dodge_cooldown()`. Accept: spec values.
- [ ] W2-A9 `[enemies-ai]` `enemy_base.tscn`, `EnemyData`, standard states, `Targeting`, grid or nav pathfinding, separation via spatial hash, time-scaled movement. Accept: 3 enemies.
- [ ] W2-A10 `[enemies-ai]` Hollow Miner, Rock Tick, Lantern Wisp `.tres`, states, attack patterns, placeholder sprites. Accept: each attacks through windup/active/recovery.
- [ ] W2-A11 `[art-audio]` Asset pipeline bootstrap (Pit side): `tools/art/palette.py` (global ramps, 7 locked biome palettes, `ELEMENT`, UI, rarity), `tools/art/pixel.py` primitives, `gen_enemy.py`, `gen_character.py` (4 drawn dirs + mirror), `build_all.py`, `review_sheet.py`, `tools/art/tests/`. Accept: `pytest tools/art` green; deterministic bytes.
- [ ] W2-A12 `[art-audio]` First real sprites: Hollow Miner, Rock Tick, Lantern Wisp sheets (idle/run/windup/attack/hurt/death), Pickaxe and Crossbow held sprites + bolt projectile + 2 weapon icons, `hit_<type>` sparks x5, `hit_heavy`, `crit` emitters, `hit_flash` shader textures. Accept: review sheet in `docs/asset-review/week-2/` approved by Dev A; `make_sprite_frames.gd` emits mirrored `SpriteFrames`.
- [ ] W2-A13 `[art-audio]` Combat SFX via `tools/audio/synth.py`: hit x5 types, heavy hit, crit, dodge, perfect dodge, enemy hurt small/large, enemy death, 3 enemy attack cues. Accept: waveform sheet reviewed; ids in `SfxBank`.

### Dev B
- [x] W2-B1 `[time-manager]` `scale_for`, groups, slow/stop stack, per-entity scale, `hit_stop`, `timer`, RPC broadcast of effects. Accept: spec API; players unaffected by enemy slow.
- [x] W2-B2 `[stats-status]` `StatBlock` (11 stats, flat then percent, handles, `remove_source`, clamps, MAX_HP ratio) + `Damage.compute` + golden file. Accept: spec formula.
- [x] W2-B3 `[networking]` Enemy and projectile `MultiplayerSpawner`s under `World/Entities`, `StateSync` on enemy base (position, anim, HP), host-only hit resolution verified. Accept: client sees state.
- [x] W2-B4 `[debug-tools]` Debug console UI + parser + `register()`, core commands (`spawn`, `give`, `gold`, `skip` stub, `seed`, `god`, `kill`, `heal`, `timestop`, `fps`, `dump`), request commands to host.
- [x] W2-B5 `[ui-hud]` HUD v0: own HP bar, teammate HP bars, weapon slots, floor label placeholder; `HudModel` adapter bound to replicated state; `Theme` v0 with pixel font. Accept: visible in test room.
- [x] W2-B6 `[art-audio]` `AudioManager` real implementation (two-player crossfade, pooled SFX, buses), `SfxBank` with placeholder clicks for the week 2 SFX ids.
- [ ] W2-B7 `[art-audio]` Asset pipeline bootstrap (Surface side): `tools/audio/synth.py` + `build_sfx.py` + `tools/audio/tests/`, `tools/art/gen_ui.py`, `tools/art/gen_icons.py`, `CREDITS.md` schema + `test_credits.gd`, `docs/asset-review/INDEX.md`, `tools/art/capture.gd`. Propose (ask first) a CI step for `pytest tools/` and `build_all.py --check`. Accept: pipeline docs in SPEC-art-audio match the files.
- [ ] W2-B8 `[art-audio]` Source 3 OFL pixel fonts (UI, damage numbers, title) and credit them; UI theme v0 pieces from `gen_ui.py` (panel nine-patch, HP/teammate bars, weapon slot frame, cursor); UI SFX click/hover/confirm/cancel/error synthesized. Accept: review sheet approved by Dev B; HUD v0 uses the theme.

### Checkpoint: Week 2 end
- [ ] Every W2 `[art-audio]` task has an approved review sheet in `docs/asset-review/week-2/` (or a dated polish-list entry); `build_all.py --check` clean
- [x] Two-instance smoke steps 1 to 3 (`tools/smoke_two.sh` 28/28 ok, exit 0); manual feel pass recorded in WEEKLY; all W2 tests green in GUT (338/338)
- [ ] `week-2` tagged — **blocked on Dev A**: W2-A1..A13 not landed, so the full Week 2 checkpoint (incl. Dev A's tasks) hasn't passed; state recorded in WEEKLY (BRIEF Assumption 10)

---

## Week 3: Floor generation

**Done when:** Procedural floors with Start, Combat, Elite Combat, Treasure, Rope, Exit rooms, locking combat rooms, seed sync for co-op, downed/revive.

### Dev A
- [ ] W3-A1 `[floor-generation]` `FloorGenerator.generate()` steps 1 to 5 (seeded RNG only, room placement with retries, MST + loops, L corridors, type assignment, painting, walkable data, `AStarGrid2D` pathing).
- [ ] W3-A2 `[floor-generation]` `Floor` scene (`paint`, `Room` nodes, `Door` nodes, `room_at`), door lock on enter, `room_cleared`, Exit rule, placeholder START/EXIT/ROPE markers.
- [ ] W3-A3 `[floor-generation]` Populator registry + 500-seed soak test across placeholder biomes (reachability flood fill, exit reachable, counts, rope on floor 2, no overlaps, corridor width).
- [ ] W3-A4 `[enemies-ai]` `SpawnDirector.fill_room` v1 (budget by floor, single wave, no spawn near players) registered as COMBAT/ELITE_COMBAT populator.
- [ ] W3-A5 `[player-controller]` `Downed` and `Dead` states, bleed-out 30 s, hold-F revive to 40% (3 s, `revive_speed_mult`), solo skips to Dead, `Interactable` component and nearest-interactable query.
- [ ] W3-A6 `[art-audio]` `gen_tiles.py collapsed_mines`: real Biome 1 tileset (floor x3 variants, wall x4 faces + corners, pit, door open/locked, corridor, 8 props: lantern, cart, beam, rail, rubble, crate, barrel, ore vein) + START/EXIT/ROPE markers as real sprites, ground shadow ellipses. Accept: review sheet + in-engine capture of a generated floor approved; `test_palette.gd` passes; palette `collapsed_mines` locked on approval.
- [ ] W3-A7 `[art-audio]` Player `downed` and `death` placeholder frames on the placeholder body; rope, door lock/unlock, room clear, footstep (stone x2) SFX. Accept: review approved.

### Dev B
- [x] W3-B1 `[run-economy]` `GameState` real: `RunState`, `RunPlayerState`, `start_run`, `next_floor`, `end_run`, `RunResult`, `run_started`/`floor_changed`/`run_ended` signals; floor advance threshold states. Accept: `tests/unit/test_run_state.gd` + `tests/unit/test_game_state_run.gd` green (28 tests in the latter, incl. host-only `Events.room_cleared` -> `rooms_cleared`, `exit_open` at the threshold, `can_advance_floor()`, and `next_floor()` refused with a recorded reason while shut). The Exit rule's concrete determinant — all `COMBAT`/`ELITE_COMBAT` rooms on a Start–Exit path — is **blocked on Dev A (W3-A2)**; until it lands the generated floor writes `required_rooms_cleared` and the default `0` means "nothing required".
- [x] W3-B2 `[run-economy]` ROPE populator + `Rope` interactable (solo immediate extract), run end on all players downed/dead (`DEFEAT`), placeholder death/extract summary print. Rope half landed 2026-10-19 (W3-B2a): `scripts/run/rope.gd`, `scenes/dungeon/interactables/rope.tscn` and `tests/unit/test_rope.gd` (22 tests / 138 asserts) green, `NetworkManager.request_vote_rope` + `can_send_request()` added, populator registration is a guarded no-op **blocked on Dev A (W3-A3)** (`FloorGenerator.register_populator`). `DEFEAT` half landed 2026-10-19 (W3-B2b): `GameState` listens to `Events.player_downed`/`player_died`, marks `RunPlayerState.is_downed`/`is_dead` and ends the run with `DEFEAT` when no slice `is_standing()` (solo ends on the first down), printing the placeholder summary `[run] <REASON> — seed S, floors cleared N, players: <peer> <status>, …` (kept in `GameState.last_run_summary`). Accept: `tests/unit/test_run_end_defeat.gd` green (22 tests / 81 asserts, driven from test-local `Player` doubles; 1/2/4-player cases, solo, downed-vs-dead, duplicate/unknown-peer/client/ended-run/re-entrant guards, summary text) plus the headless defeat print in `.goals/evidence/g6-defeat-summary.log`; full suite 432/432. The real `Downed`/`Dead` states and their emitters are **blocked on Dev A (W3-A5)**; the host already listens to the spec's events, so that swap-in is nothing on my side.
- [x] W3-B3 `[networking]` `floor_ready(seed, floor_index, biome_id, modifiers)` broadcast, client local generation, hash assertion with host-layout fallback, `--seed` arg plumbed. All five sub-tasks landed 2026-10-20: **W3-B3a-1/a-2/a-3** (`NetworkManager.floor_ready` + client-local generation through `FloorGeneratorSeam`, `--seed` through `GameState.start_run`, the two-instance shared-seed floor-hash **equality** check in `tools/smoke_two.sh`, and the smoke's `OUT`/`--port` tooling fixes) and **W3-B3b** (the `layout_asserted` / `floor_layout` hash assertion with the host-layout fallback). **W3-B3c** landed 2026-10-20: `tests/integration/test_floor_generation_seeds.gd`, the lane-B floor determinism soak — 500 seeds over floors 1..30 and all six biomes, 8 tests / 41 069 asserts green in 1.9 s (`res://tests/integration/test_floor_generation_seeds.gd`), asserting same-inputs-same-`layout_hash`, 500 distinct hashes with zero neighbouring collisions, `to_wire()`→`from_wire()` round-trip equality, every room rect inside the 96×96 grid, `room_count` in 8..14, and the one-input-changed negative control; it found and fixed a real defect (`FloorLayoutPlaceholder` placed room origins at 0..95 so a room could run up to 16 tiles past the grid edge). Accept: `tests/integration/test_floor_generation_seeds.gd` green (8/8, 41 069 asserts, 1.9 s — under the spec's 60 s headless budget), full suite 487/487, import exit 0. The spec's own soak is still unstruck and is **blocked on Dev A (W3-A3)**: it runs over `FloorGenerator.generate()` (flood fill from Start, Exit reachable, exactly one `ROPE` on floor 2, no overlaps, 3-wide corridors) and `scripts/generation/` is still empty, so this soak covers the lane-B `FloorLayoutPlaceholder` that `FloorGeneratorSeam` returns for every peer today — recorded as blocked on Dev A W3-A3, with the swap-in mechanical (the soak's last case asserts the seam's source, so it cannot silently keep soaking the placeholder once the real generator lands).
- [x] W3-B4 `[networking]` Downed/revive sync: `request_revive`, `player_downed`/`player_revived` broadcast, StateSync of downed flag. **W3-B4a** (broadcast + downed-flag sync) landed 2026-10-20: `Player.is_downed` is now a replicated `StateSync` property (`.:is_downed`, `ON_CHANGE`, in the spawn state) whose setter stops the player simulating on every peer and emits its own `downed` signal; `NetworkManager` gained `broadcast_player_downed(peer_id)` / `broadcast_player_revived(peer_id, by_peer_id)` (`@rpc("authority","call_local","reliable")`, sender-validated through the new shared `can_accept_host_broadcast`), the plain `apply_player_downed` / `apply_player_revived` bodies that write the registry and emit the matching `Events` signal, the `route_*` senders with `remote_peer_ids()`, and the `Events` → router connections guarded by `_announces_player_state()` (`is_host and multiplayer.is_server()`, the `TimeManager` shape) so a client's own emit is not re-broadcast. Accept: `tests/unit/test_player_sync.gd` 19 → 37 tests / 113 asserts green (written first; the core criterion observed failing as `ARRAY([]) != ARRAY([^".:is_downed"])` in `.goals/evidence/g2/red-player-sync.log`), full suite 505/505 (`.goals/evidence/g2/gut-full.log`), import exit 0, headless `-- --host --smoke=6` exit 0, and the two-instance smoke green (35 `ok`, 0 FAIL) before the commit. **W3-B4b** (`request_revive` + the host revive rule) landed 2026-10-20: `NetworkManager.request_revive(target_peer_id)` is `@rpc("any_peer","call_remote","reliable")` with the sender read from `multiplayer.get_remote_sender_id()`, and `Player.request_revive(target)` (Dev A's stub, the file flagged for Dev A's review) now forwards to the new `send_revive_request(peer_id)`, which emits `revive_requested` before it sends; the host decides through the `can_apply_revive_request(sender, target)` seam and the `apply_revive_request(sender, target)` body, which records one of eight `REVIVE_REFUSAL_*` reasons in `last_revive_refusal` (not the host, not a request, no target, target not downed, target dead this floor, no such reviver, self-revive, out of range) and warns rather than erroring; a valid ask routes through the existing `apply_player_revived` (so host-apply and client-broadcast converge on one body, and the player's own `revived(by)` signal — G2's deferred promise — is emitted there); the numbers live on the autoload as `REVIVE_RANGE = 48.0`, `REVIVE_SECONDS = 3.0`, `REVIVE_HP_FRACTION = 0.4`, with `revive_seconds_for(reviver)` (scaled by `revive_speed_mult`, clamped at `REVIVE_SPEED_MULT_MIN`) and `revive_hp_for(max_hp)` (floored at 1 HP) as the readable halves; and `GameState._on_player_revived` now clears the run slice's `is_downed` (host-only, through the existing `_is_tracking_run()` / `_slice_for()` seam, subscribing in `_subscribe_player_events`), so `RunPlayerState.is_standing()` is true again while `is_dead` is left alone ("Dead for the rest of the floor"). Accept: `tests/unit/test_revive.gd` 24 tests / 108 asserts green, written first and observed failing for the right reason (`Invalid call. Nonexistent function 'apply_revive_request' in base 'Node (network_manager.gd)'`, `.goals/evidence/g3/red-test-revive.log`); full suite **35 scripts / 529 tests / 529 passing / 54 014 asserts** exit 0 (`.goals/evidence/g3/gut-full.log`, up from 505), `--import` exit 0 with 0 error lines (`g3/import.log`), headless `-- --host --smoke=6` exit 0 (`g3/launch-host.log`), and the two-instance smoke green (35 `ok`, 0 FAIL, floor hashes unchanged) before the commit (`.goals/evidence/g3-smoke/run-smoke.log`); negative control forced — `REVIVE_RANGE` widened to 480.0 failed exactly `test_the_reviver_must_stand_within_revive_range` and nothing else (`g3/negative-control-revive-range.log`); no `Engine.time_scale`, no global RNG, no base-stat write. The hold-to-revive input, the `Downed`/`Dead` states and the 30 s bleed-out that make a real revive happen are **blocked on Dev A (W3-A5)** (writing the restored HP is blocked on Dev A W2-A1), and the two-process downed/revive proof is still G11a/G11b, not here.
- [x] W3-B5 `[debug-tools]` `skip`, `floor <n>`, `seed` wired to GameState; `net_lag` placeholder. **W3-B5a** (`skip` and `floor <n>`, 2026-10-20): `DebugCommands._cmd_skip` now calls `GameState.next_floor()` and reports `GameState.last_advance_refusal` as a readable phrase (`_advance_refusal_text`), and the new registered `floor <n>` walks to the target one `next_floor()` call per floor — validating 1..30, refusing a non-integer, out-of-range, behind-the-current-floor, no-run, client and shut-exit target with a readable message and advancing nothing. Accept: `tests/unit/test_console_parser.gd` 43/43 / 145 asserts green (written first and observed failing for the right reason — 16 red, `.goals/evidence/g4/red-console-parser.log`), full suite **35 scripts / 543 tests / 543 passing / 54 081 asserts** exit 0 (`g4/gut-full.log`, up from the 529 baseline), `--import` exit 0 with 0 error lines (`g4/import.log`), headless `-- --host --smoke=6` exit 0 (`g4/launch-host.log`), and the two-instance smoke green (35 `ok`, 0 FAIL, `g4/smoke-run.log`) even though this commit adds no RPC; no `Engine.time_scale`, no global RNG. **W3-B5b** (`seed` confirmation + the `net_lag` placeholder, 2026-10-20): `seed <n>` is now proven end to end — the console is run for real, then `GameState.start_run(<different caller seed>, …)` is asserted to start on the forced seed (the W3-B1 precedence rule `forced_seed` → caller seed → host roll), and `seed 0` is asserted to clear the field so the caller's seed comes through; `net_lag <ms> [loss%]` is registered with its help line and implemented as the spec's Week 3 placeholder — it validates a whole non-negative millisecond value and an optional percentage (clamped 0–100), records them on `NetworkManager.net_lag_ms` / `NetworkManager.net_lag_loss`, clears on `net_lag 0`, rejects a non-integer ms, a negative ms and a non-numeric loss without changing the recorded values, and carries "placeholder, the real delay proxy lands in W4-B11" in every result line and in the `dump` payload. Accept: `tests/unit/test_console_parser.gd` **54/54 / 179 asserts** green (written first and observed failing for the right reason — 11 red on `unknown command: net_lag` and `Invalid access to property 'net_lag_ms'`, `.goals/evidence/g5/red-console-parser.log`); full suite **35 scripts / 554 tests / 554 passing / 54 115 asserts** exit 0 (`g5/gut-full.log`, up from 543); `--import` exit 0 with 0 error lines (`g5/import.log`); headless `-- --host --debug-tools --smoke=6` exit 0 with 0 script/parse errors (`g5/launch-host.log`); two-instance smoke **35 `ok`, 0 FAIL**, exit 0 (`g5/smoke-run.log`, logs in `g5/smoke/`) — run before the commit because it touches `network_manager.gd`; both banned-literal greps empty. Known limitation recorded in HANDOFF decision 36 and in the command's doc comment: `net_lag` is a per-peer setting but a client's console line routes to the host through `request_debug`, so W4-B11 needs a per-peer path before one side can be lagged in co-op; nothing is delayed or dropped yet, and no traffic reads the two fields.
- [ ] W3-B6 `[art-audio]` Rope vote prompt and floor label UI pieces, downed/revive HUD icons, placeholder death and extract summary panel theme; SFX: rope, revive, downed, UI menu open/close. Accept: review approved. **Open, dated 2026-10-20** — an art-audio task that is not in this run's task list; carried, not cut, and the master placeholder rule stands (SPEC's "coloured square with the first letter" plus the generated 5×7 placeholder font and placeholder click SFX from W2-B6). Recorded in the Week 3 checkpoint block above and in `specs/WEEKLY.md`.

### Checkpoint: Week 3 end

State at the 2026-10-20 close-out (verdict **partial**; `specs/WEEKLY.md` Week 3 entry and `HANDOFF.md` decision 37 hold the full record):

- [ ] Every W3 `[art-audio]` task has an approved review sheet in `docs/asset-review/week-3/` (or a dated polish-list entry); `build_all.py --check` clean — **open**: W3-B6 is not done and W3-A6/A7 have not landed. W3-B6 (rope vote prompt, floor label pieces, downed/revive HUD icons, death/extract summary theme, rope/revive/downed/menu SFX) is an art-audio task outside this run's task list; the spec's placeholder rule is in force. Dated deferral, not a cut.
- [x] 500-seed test green — **locally**: `tests/integration/test_floor_generation_seeds.gd`, 8 tests / 41 069 asserts / 1.9 s, in the GUT suite. The soak covers the lane-B `FloorLayoutPlaceholder` that `FloorGeneratorSeam` hands every peer, because the spec's own soak runs over `FloorGenerator.generate()` and is **blocked on Dev A (W3-A3)** (`scripts/generation/` holds only `.gdkeep`); the soak's last case asserts the seam's source so the swap cannot pass unnoticed. CI's own run of this test is not observable from this machine (no `gh`/token) — outstanding and non-blocking, the same item as weeks 1 and 2.
- [x] floor hashes match — **met in two processes**: `tools/smoke_two.sh` compares each host/client pair's `layout_hash` for **equality** (35 `ok`, 0 FAIL, exit 0) on seeds `20261020` → `3600649381522393848` and `987654321` → `536024383148136417`, with a committed negative control showing the helper's FAIL path.
- [ ] Two-instance smoke steps 1 to 5 — **steps 1 to 3 pass**, plus the floor-sync phase (shared-seed agreement and the client's own layout assertion). **Step 4** (client picks a relic at a Shrine) has no driver: the Shrine is W4-B5 and no Shrine exists to walk to. **Step 5** (client goes down, host revives) has no driver and no emitter: the `Downed`/`Dead` states that down a player are **blocked on Dev A (W3-A5)**. Both recorded as blocked, not skipped.
- [ ] `week-3` tagged — **NOT created.** The design-doc "Done when" line is partial (W3-A1..A7 unlanded: no procedural floors, no room types, no locking combat rooms), and a milestone tag claims the whole line rather than one lane's task list — the precedent set for `week-2` at `HANDOFF.md` decision 22. Reason recorded in `specs/WEEKLY.md`, `HANDOFF.md` decision 37 and `.goals/LOG.md`.

---

## Week 4: Effect system + loot

**Done when:** Events bus, StatBlock, TimeManager, status effects, element combos, 20 relics, Shrine rooms, elites with affixes, gold/ore/Echo drops.

### Dev B
- [x] W4-B1 `[effect-system]` `Events` full signal set from spec, emitted by owning modules. **Signal-set half landed 2026-10-20**: `tests/unit/test_events_bus.gd` is the conformance test — it parses the signal table out of `specs/SPEC-effect-system.md` at run time and asserts the exact names with no extras and none missing, plus every signal's parameter names, order, count and declared type; two drifts were found and fixed (`run_started`'s parameter renamed to the spec's `seed`, and the real `HitData`/`RunResult` classes declared instead of `RefCounted` on the six hit/result signals), and every remaining placeholder now carries one machine-parsed `## TODO(<module>): <SpecType> <- <Placeholder> (blocked on Dev X, <task-id>)` line asserting its replacing class and owner. Accept: `tests/unit/test_events_bus.gd` 10/10 / 330 asserts green (`tests/unit/test_events_bus.gd`), full suite **36 scripts / 564 tests / 564 passing / 54 445 asserts** exit 0 (up from 554), `--import` exit 0 with 0 error or warning lines, headless `-- --host --smoke=6` exit 0, two-instance smoke **35 `ok` / 0 FAIL** exit 0; red run kept at `.goals/evidence/g7/red-test-events-bus.log`; HANDOFF decision 38 records the signature changes. **Emitter half landed 2026-10-20 (G8)**: `tests/helpers/event_emitter.gd` (`EventEmitterHelper`) is the test-only emitter — one named method per bus signal (37), each emitting with valid fake arguments built from `tests/helpers/` doubles (`Player.new()` never added to the tree, `EnemyBaseStub`, a new `EventEmitterNodeStub` for the `Node`-typed parameters, a plain `Resource` for the `*Data` parameters — since G27 (2026-10-20) `relic_picked`/`relic_removed` carry a real `RelicData` from `_relic()` instead), plus `callable_for(name)`, `all_signal_names()` and `dev_a_owned_signals()`; `cleanup()` frees every double it built. `tests/unit/test_events_emitters.gd` (10 tests / 413 asserts) parses the signal names out of `specs/SPEC-effect-system.md` `### Events bus` and asserts exactly one emitter method per signal with no extras and none missing (via `get_script_method_list()`, so the inherited `Object.emit_signal()` is not miscounted), asserts each of the 37 calls reaches a named-method listener with the signal's declared argument count, asserts the emitters Dev B already owns fire from their real owner (`GameState` for `run_started`/`run_ended`, the host's `GameState.run.rooms_cleared` counter for `room_cleared`, `NetworkManager.apply_player_downed`/`apply_player_revived` for `player_downed`/`player_revived`), and asserts each of the nine Dev A-owned signals carries a `blocked on Dev A (W4-A4)` line in the helper's doc comment. Accept: full suite **37 scripts / 574 tests / 574 passing / 54 858 asserts** exit 0 (`.goals/evidence/g8/gut-full.log`, up from 564); `--import` exit 0 with 0 error/warning lines (`g8/import.log`); two-instance smoke **35 `ok` / 0 FAIL** exit 0 (`g8/smoke-run.log`); red run kept at `g8/red-test-events-emitters.log`; negative control inside the suite (a dropped and an invented signal are both reported). No production file changed — the emitter is a test instrument. **Dev A's nine production emitters remain blocked on Dev A (W4-A4)**: `hit_landed`, `crit_landed`, `player_damaged`, `heavy_attack_released`, `weapon_swapped`, `projectile_fired`, `enemy_killed`, `enemy_spawned`, `player_dodged` — the helper emits all nine so the effects listening to them can be tested now, and the swap-in is deleting the helper call once combat-core emits them. The trigger harness (`tests/helpers/effect_harness.gd`) is W4-B3/G19, not this task.
- [ ] W4-B2 `[effect-system]` `Effect` base (attach/detach, `listen`, `every_seconds`, `once_per_room`, `modify`, `spawn`, `deal_damage`, `apply_status`, `chance`, `fire_projectile`), `EffectHost` and event dispatch. **Started 2026-10-20 (G9)**: the two interfaces everything else imports are in — `scripts/effects/tags.gd` (`Tags`: the spec's 19-tag closed vocabulary as `StringName` constants, `ALL`, `is_valid`) and `scripts/effects/projectile_spec.gd` (`ProjectileSpec`: the spec's six fields plus its plain-type dictionary form for the spawner). Accept: `tests/unit/test_tags.gd` 15/15 / 258 asserts green (red first, parse error — neither class existed), full suite **38 scripts / 589 tests / 589 passing / 55 116 asserts** exit 0 (up from 574), `--import` exit 0 with 0 error or warning lines, headless `--host --smoke=6` exit 0, both negative controls forced and kept (`.goals/evidence/g9/`). `ProjectileSpec.element` is the mirror type and stays **blocked on Dev A (W2-A1)** for the real `HitInfo.Element`; no spawner is called yet (that is G15). **Then 2026-10-20 (G10)**: `scripts/effects/effect.gd` is in — `class_name Effect extends Node` with the spec's members (`player`, `source`, `stacks`, `_handles`, `_timers`), `attach`/`detach`/`_on_attach`/`_on_detach`, and the cleanup that is the class's whole point: `detach()` removes every `StatBlock` modifier by handle, `queue_free()`s every timer it parented and disconnects every recorded connection, then calls `_on_detach()`; a second attach is refused and an unattached `detach()` is a no-op. `listen`/`modify`/`_start_timer` ship at their G10 depth (`chance`/`apply_status`/`deal_damage` were **not** in at that point — G12 added them). Accept: `tests/unit/test_effect_base.gd` 14/14 / 64 asserts green (red first, parse error — `Effect` did not exist), full suite **39 scripts / 603 tests / 603 passing / 55 180 asserts** exit 0 (up from 589), `--import` exit 0 with 0 error or warning lines, headless `--host --smoke=6` exit 0, two-instance smoke 35 `ok` / 0 FAIL, and the cleanup assertion's failing path forced and kept (`.goals/evidence/g10/negative-control-release-handles.log`). The stat block is resolved from the player's `StatBlock` node by name and cast-checked, so the player scene stays untouched while its component nodes are bare (`player.gd:159` `TODO(stats-status)`) — a player without the component gets a warning and an inert effect, not a crash (HANDOFF decision 39). **Then 2026-10-20 (G11)**: `listen` now filters where the signal gives it something to filter on — the `Player` argument is located from the signal's *declaration* (read off the `Events` autoload's own script), index 0 on `player_dodged`, index 1 on `room_entered`, and a signal with no `Player` argument (`enemy_killed`, `hit_landed`) is connected untouched; the connection goes through a bound forwarder (one per signal arity, `_dispatch0`–`_dispatch4`, because `Callable.bind()` appends its arguments after the signal's) so an effect on player 1 never reacts to player 2's event, and every connect now goes through `_connect_tracked()` so `detach()` disconnects a filtered connection exactly like an unfiltered one. `once_per_room(key)` is in: true the first time a key is asked for in a room, false after, granted again when `room_entered` fires — the base subscribes to the reset directly rather than through `listen()`, because the reset is the room's and not the entering player's, and each key set is per-effect and per-name (HANDOFF decision 40). Accept: `tests/unit/test_effect_base.gd` 24/24 / 98 asserts green (red first — 10 failing for the right reason), full suite **39 scripts / 613 tests / 613 passing / 55 214 asserts** exit 0 (up from 603), `--import` exit 0 with 0 error or warning lines, two-instance smoke 35 `ok` / 0 FAIL, and both negative controls forced and kept (`g11/negative-control-player-filter.log` — filter removed, exactly the two filter cases fail; `g11/negative-control-room-reset.log` — reset subscription stubbed out, exactly four reset/connection tests fail). **Then 2026-10-20 (G12)**: the four data helpers a relic's effect script changes the game through are in. `chance(p)` rolls `_resolve_rng().randf() < p` on the effect's own seeded generator (the `EffectHost` injection seam, seeded from `GameState.run.seed`, fixed fallback otherwise) and short-circuits `p <= 0.0` / `p >= 1.0` **without drawing**, so a certainty never advances the run's stream. `apply_status(target, status, stacks)` reaches the target's `StatusEffects` component (found by node name + `has_method`, since W4-B4's class does not exist) and passes the effect as the `source`; `status` is an `int` until G20 retypes it to the enum. `deal_damage(target, hit)` stamps `hit.proc_depth = trigger_depth + 1`, tags the hit `proc` once, and delivers it to the target's `Hurtbox` — it does **not** emit `hit_landed`, because combat-core's hurtbox owns that signal (HANDOFF decision 41). `HitData` gained `proc_depth: int = 0`, the field G16's gate will read. Accept: new `tests/unit/test_effect_helpers.gd` **22/22 / 57 asserts** green (red first — 17 failing, every failure `Nonexistent function 'chance'/'apply_status'/'deal_damage'`), full suite **40 scripts / 635 tests / 635 passing / 55 271 asserts** exit 0 (up from 613), `--import` exit 0 with 0 error or warning lines, headless `--host --smoke=6` exit 0, two-instance smoke 35 `ok` / 0 FAIL, and three failing paths forced and kept in one run (`.goals/evidence/g12/negative-controls.log` — extremes short-circuit removed, `+ 1` on proc depth dropped, `stat_block.base[…]` written from an effect; each failed exactly its own tests). **Then 2026-10-20 (G13)**: `every_seconds(interval, callable)` is in — the spec's periodic clock, armed on `TimeManager.timer(player, interval)` and re-armed one tick at a time. A time stop aimed at the enemies never pauses a relic's own clock (Clockwork Heart's "every 10 s" keeps counting while the dungeon is frozen), while an override aimed at this player's own node (hit-stop) does pause it. The effect puts its player in `TimeManager`'s PLAYER group at the point of use, since `player-controller` does not register the player yet and an unregistered node silently reads the default scale. The loop is tracked per effect (`_periodic`, keyed by a never-reused id) and `detach()` disarms the pending tick and forgets the loop, so a relic dropped at a Shrine stops ticking at once and the pending timer holds no reference to the effect; a handler that detaches during its own tick does not re-arm (HANDOFF decision 42). No engine `Timer` is used for a loop (`_timers` stays empty), and no `TimeManager` API was added. Accept: new `tests/unit/test_effect_timers.gd` **16/16 / 53 asserts** green (red first — parse error, `every_seconds()` not found), full suite **41 scripts / 651 tests / 651 passing / 55 326 asserts** exit 0 (up from 40/635/55 271), `--import` exit 0, `grep -rn "Engine.time_scale" scripts/ scenes/` empty, two-instance smoke 35 `ok` / 0 FAIL, and both failing paths forced and kept (`.goals/evidence/g13/negative-control-enemy-group.log` — the player put in the ENEMY group, the stop/group/PLAYER-effect cases fail; `.goals/evidence/g13/negative-control-engine-timer.log` — the loop armed on `_start_timer`, the armed-on-the-player, hit-stop-pause, PLAYER-group and no-engine-timer cases fail). **Then 2026-10-20 (G14)**: `scripts/effects/effect_host.gd` is in — `class_name EffectHost extends Node`, the node every player carries, with the spec's `add(source, stacks)` (instantiates the source's `effect_script` under the host, injects the host's seeded generator, calls `attach`; refuses no source / no id / no `effect_script` / a non-`Effect` script / a duplicate id / no player), `remove(source)` (detaches while the node is alive, then `queue_free()`s, returning whether it removed anything), `get_effect(id)` (live effect or null) and `list_tags()` (tag → count, weighted by `stacks`, empty when nothing is attached), plus `has_effect`/`effect_count`/`effects` and the host-owned `rng` G12's injection seam promised. `player.tscn` stays untouched: `tests/helpers/effect_host_player.gd` installs the host as the child named `EffectHost` (idempotent), **blocked on Dev A (W2-A1, player.tscn)** for the eventual scene composition. Accept: new `tests/unit/test_effect_host.gd` **17/17 / 85 asserts** green (red first — parse error, `EffectHost` did not exist), full suite **42 scripts / 668 tests / 668 passing / 55 411 asserts** exit 0 (up from 41/651/55 326), `--import` exit 0 with 0 error or warning lines, two-instance smoke 35 `ok` / 0 FAIL (`.goals/evidence/g14/`), and the tag-weighting failing path forced and kept (`g14/negative-control-tag-stacks.log` — counting each tag once fails exactly the two `list_tags` cases). Remaining: proc dispatch — G16. **Then 2026-10-20 (G15)**: `spawn` and `fire_projectile` are in. New `scripts/effects/effect_spawner.gd` (`class_name EffectSpawner extends Node`) is the seam both helpers go through — `spawn_node(scene, pos, setup, source_id, depth)` instantiates, stamps `proc_source_id`/`proc_depth`, positions, runs the caller's `setup` callable **before** `add_child()`, then parents under its container; `spawn_projectile(spec, from, dir, source_id, depth)` hands the whole `ProjectileSpec` (scene, speed, damage, element, pierce, bounce) to the shipping `ProjectileSpawner` and stamps the same numbers on the projectile it returns. `EffectHost` gained the seam (`spawner`, `spawner_path` resolved once on `_ready()`, `spawn_proc()`, `fire_proc_projectile()`, `can_spawn()` over a `_can_spawn()` seam defaulting to `multiplayer.is_server()`) and now sets `Effect.host` on `add()`; `Effect.spawn()`/`fire_projectile()` reach the world only through that host, never by node path (SPEC-project forbids cross-module tree-path reach-through). Both helpers stamp `proc_depth = trigger_depth + 1`, the rule SPEC-effect-system's "Proc chain limits" states for `deal_damage`, `spawn` and `fire_projectile` alike (HANDOFF decision 44). Provenance lands as a property when the spawned root declares it, otherwise as metadata, read back through `EffectSpawner.read_stamp()` so an `art-audio` FX scene cannot silently lose it. Accept: new `tests/unit/test_effect_spawn.gd` **25/25 / 93 asserts** green (red first — against an `Effect` without the helpers, 23/25 fail `Nonexistent function 'spawn'`), full suite **43 scripts / 693 tests / 693 passing / 55 504 asserts** exit 0 (up from 42/668/55 411), `--import` exit 0 with 0 error lines, two-instance smoke 35 `ok` / 0 FAIL, headless `-- --host --debug-tools --smoke=6` exit 0 with zero error lines, the five other effect test files run individually and unchanged (25/103, 17/85, 22/57, 25/93, 16/53), and the failing path forced and kept (`.goals/evidence/g15/negative-control.log` — the `+ 1` dropped from `spawn`'s depth fails exactly the four depth cases). **Blocked on Dev A (W4-A4)**: the FX-with-gameplay spawner and combat-core's real `Projectile` do not exist, so `EffectSpawner` is not yet wired into `world.tscn` (`world.tscn` is foundation/both lanes and was not edited) and the game drops effect spawns with a warning; the swap-in is a wiring change — one container node and one `ProjectileSpawner` reference. Remaining: proc dispatch, the depth gate and the 64-per-frame cap — W4-B3 (G16–G18).
- [x] W4-B3 `[effect-system]` Proc limits (depth 3, no self-retrigger, 64/frame cap), trigger test harness + template test, duplication rule. **Depth half landed 2026-10-20 (G16)**: `Effect.MAX_PROC_DEPTH = 3` (the spec's number, with SPEC-effect-system's "Proc chain limits" rule-1 sentence quoted in its doc comment and asserted verbatim against the spec file in the suite) and the gate itself in `Effect._forward()` — the one dispatch wrapper `listen()` puts in front of every handler it connects, so no effect script carries its own copy. `listen()` now routes a signal through the wrapper when the signal *carries a hit* and not only when it declares a `Player` argument: `hit_landed(hit)` declares none, so the pre-G16 code connected the game's busiest event raw and the gate could never fire on it. A signal with neither a player nor a hit is still connected untouched. `_forward()` reads the event's own depth (the max `proc_depth` across its `HitData` arguments), drops the event at the limit, and otherwise publishes that depth as `trigger_depth` for the duration of the handler and restores what it found — which is what makes `deal_damage`/`spawn`/`fire_projectile`'s already-shipped `+ 1` a chain step rather than a constant, and keeps nested procs correct. The hit itself is untouched by the gate — the hurtbox already delivered and announced it — so "its hits still damage" holds by construction. Accept: new `tests/unit/test_proc_limits.gd` **10/10 / 59 asserts** green (red first — `Cannot find member "MAX_PROC_DEPTH" in base "Effect"`), full suite **44 scripts / 705 tests / 705 passing / 55 620 asserts** exit 0 (up from 43/693/55 504), `--import` exit 0 with 0 error lines, two-instance smoke 35 `ok` / 0 FAIL, and the failing path forced and kept (`.goals/evidence/g16/negative-control.log` — the limit raised to 5, the chains run all five links and only the gate assertions fail). One pre-existing assertion's contract was deliberately changed and its intent preserved (HANDOFF decision 45); the new test's chain advances through a stub of Dev A's hurtbox, **blocked on Dev A (W2-A2)**. Remaining here: the 64-spawn-per-frame cap (G18), the trigger harness and template test, and the Mimic Crown duplication rule (G19). **Self-retrigger half landed 2026-10-20 (G17)**: SPEC-effect-system "Proc chain limits" rule 2 — "An effect never reacts to a hit whose `tags` already contain its own id" — is enforced in the same `Effect._forward()` dispatch wrapper as G16's depth gate, just before it: `_is_own_hit(values)` returns true when any hit the event carries has `source_id()` in its `tags`, so a relic whose own damage comes back to it (Ember Boots' trail, Volatile Core's death explosion) does not re-trigger itself, while the hit itself is still delivered and still damages. The comparison is the **content id**, never the class name, so two effects built from one script are suppressed independently; an effect attached with no source has no id and suppresses nothing. `_event_hits()` now backs both rules, so "what counts as a hit" is one decision. The tag is the *producer's* to stamp (`deal_damage` adds `proc` and nothing else — stamping the source id there would make G16's self-triggering chain shape inexpressible and trade a backstop for a single mechanism; HANDOFF decision 46 records the reading), and `listen()`'s doc comment says so. Accept: `tests/unit/test_proc_limits.gd` **18/18 / 111 asserts** green (up from 10/59; 8 new cases, red first with six failing — `.goals/evidence/g17/red-test-proc-limits.log`), full suite **44 scripts / 713 tests / 713 passing / 55 672 asserts** exit 0 (up from 44/705/55 620 at `c20b4e4`), `--import` exit 0 with 0 error lines, two-instance smoke 35 `ok` / 0 FAIL, and the failing path forced and kept (`.goals/evidence/g17/negative-control.log` — with `_is_own_hit()` short-circuited, exactly the five rule-2 cases fail and nothing else moves). The G16 chain-of-five fixture's routing tag moved from the effect's own id to a separate `hop_N` namespace, because rule 2 makes id-routed chains un-routable by construction; every assertion in that case is unchanged. **Spawn-cap half landed 2026-10-20 (G18)**: SPEC-effect-system "Proc chain limits" rule 3 — "Per-frame cap: at most 64 effect-spawned nodes per player per frame; the rest are dropped and counted in a debug stat" — is enforced on `EffectHost`, the one boundary every effect reaches to spawn, so no effect script can bypass it. `EffectHost.MAX_SPAWNS_PER_FRAME = 64` and `_spend_spawn_budget()` gate `spawn_proc()` and `fire_proc_projectile()` on **one shared per-player budget** (the spec's unit is "effect-spawned nodes", so a relic cannot buy a second 64 by firing projectiles instead): the 65th request of either kind in a frame is refused, and the 200-in-one-frame case leaves exactly 64 nodes with 136 counted as dropped. Three public frame-keyed counters — `spawns_this_frame`, `spawns_dropped`, `drop_reports` — are the "debug stat" the rule requires and the interface the debug overlay (W4-B11) reads; they are computed from `Engine.get_physics_frames()` rather than reset in a process callback, so "resets on the next physics frame" holds by construction and `EffectHost` needs no `_physics_process`. The first drop of a frame writes one warning; the rest only count, so a build that caps out does not write hundreds of lines. Accept: `tests/unit/test_proc_limits.gd` **26/26 / 158 asserts** green (up from 18/111; 8 new cases, all red first — `Cannot find member "MAX_SPAWNS_PER_FRAME" in base "EffectHost"`, `.goals/evidence/g18/red-test-proc-limits.log`), full suite **44 scripts / 721 tests / 721 passing / 55 719 asserts** exit 0 (up from 44/713/55 672 at `67d9bbe`), `--import` exit 0 with 0 error and 0 warning lines, the five other effect test files unchanged (25/25, 17/17, 22/22, 25/25, 16/16), and the failing path forced and kept (`.goals/evidence/g18/negative-control.log` — with the cap set to 5, exactly the eight cap cases fail and no depth or self-tag case moves); the once-per-frame announcement is also verified in the real run log (9 warnings for 9 host-frames that capped, one per host per frame). **Harness half landed 2026-10-20 (G19a)**: SPEC-effect-system's "Interfaces provided" names `tests/helpers/effect_harness.gd` as the shared instrument every content module uses ("creates a headless player with `EffectHost`, attaches an effect, fires any `Events` signal with fake arguments, asserts spawns, stat changes, statuses, and damage via a `SpyWorld`"). `EffectHarness` builds one autofreed root, a player double (the real `player.tscn` with a `StatBlock` component, a `StatusEffects` double, a `SpyHurtbox` and an `EffectHost`) and a target double, attaches sources through the real `EffectHost.add()`, fires any bus signal by its own `Signal` object after checking the name and argument count, and asserts all four categories — each available twice, as a pure `check_*` predicate and as a GUT-reporting `assert_*` wrapper, so a case can pin the *negative*. `SpyWorld` (`tests/helpers/spy_world.gd`, extends `EffectSpawnerSpy`) records every spawn and every landed hit; `SpyHurtbox` reports hits and announces them on request; `HarnessSampleEffect` is the sample relic the template drives. The harness's `##` doc comment carries the copy-paste recipe for a new relic case, and `tests/unit/test_effect_template.gd` asserts that recipe is still there. Accept: `tests/unit/test_effect_template.gd` **7/7 / 49 asserts** green (written and run red first — parse error, `Identifier "EffectHarness" not declared in the current scope`, `.goals/evidence/g19a/red-test-effect-template.log`), full suite **45 scripts / 728 tests / 728 passing / 55 768 asserts** exit 0 (up from 44/721/55 719 at `799646c`, the delta being exactly this file), `--import` exit 0 with 0 error lines, the seven effect test files re-run with the six pre-existing counts unchanged, and the failing path forced and kept (`.goals/evidence/g19a/negative-control.log` — with the self-test's `assert_false(check_spawned(1))` flipped, exactly that case fails, 6 passing / 1 failing). No production file changed and no smoke run (the commit adds test-only files). **Mimic Crown half landed 2026-10-20 (G19b) — W4-B3 complete.** SPEC-effect-system "Proc chain limits" rule 4 — "Mimic Crown copies the last picked relic's effect; the copy is a second `Effect` instance with its own id suffix so rule 2 still applies" — is enforced on the host, in the helpers, and never in an effect script. `EffectHost.MIMIC_CROWN_SUFFIX` (`__crown`) plus the static `EffectHost.suffixed_id()` is the one place a copy's id is built; `EffectHost.add()` gained the trailing `id_suffix` parameter, so the copy is attached through **the same** `add()` every other effect uses (one `effect_script.new()` in the file, asserted), keyed, named and seeded as `ember_boots__crown`. `Effect` gained `id_suffix`, and `Effect.source_id()` returns `EffectHost.suffixed_id(source.id, id_suffix)` — which is what makes rule 4's "so rule 2 still applies" true: the copy holds the *same* `ContentData` as its original, so without the suffix a hit tagged `ember_boots` would suppress both of them; with it, a hit tagged `ember_boots` suppresses only the original while the copy still reacts, and vice versa. `EffectHost.add_mimic_copy(copied, owner_id)` records which crown owns the copy, and `remove()` drops the copies that go with the effect it removed — the copy the removed crown owned, and the copy of a relic the player no longer holds — so removing Mimic Crown detaches only the copy while the copied relic stays attached and keeps reacting; `EffectHost.has_mimic_copy_of(id, owner_id)` is the read side of that ownership, and the suite asserts each record is erased when its copy goes, so the bookkeeping cannot leak an entry per crown attached. The crown's own behaviour is `MimicCrownStub` (`tests/helpers/`, the week-8 relic's double: it copies the host's most recent attachment and calls the same helper), so the case reads exactly like the rule. `tests/unit/test_mimic_crown.gd` **13/13 / 107 asserts** green (written and run red first — `Cannot find member "MIMIC_CROWN_SUFFIX" in base "EffectHost"`, `.goals/evidence/g19b/red-test-mimic-crown.log`), full suite **46 scripts / 741 tests / 741 passing / 55 875 asserts** exit 0 (up from 45/728/55 768 at `013ab25`, the delta being exactly this file), `--import` exit 0 with 0 error and 0 warning lines, the nine effect-family test files re-run individually with every pre-existing count unchanged (`test_effect_base` 25/103, `test_effect_host` 17/85, `test_effect_helpers` 22/57, `test_effect_spawn` 25/93, `test_effect_timers` 16/53, `test_effect_template` 7/49, `test_proc_limits` 26/158, `test_tags` 15/258), and the failing path forced and kept (`.goals/evidence/g19b/negative-control.log` — with `Effect.source_id()` ignoring the suffix, exactly the six suffix-dependent cases fail, 7 passing / 6 failing, 94/107 asserts, including "the copied relic stays attached"; the spec-quote, suffix-form, one-attach-path, refusal, empty-crown and tag-count cases do not move). No smoke run: the commit touches no RPC, replication or spawner wiring (BRIEF C17). Judgement call recorded as HANDOFF decision 49 (a copy counts once in `list_tags()`, and `remove()` cascades in both directions).
- [x] W4-B4 `[stats-status]` `StatusEffects` component with 7 statuses and stacking rules, 6 combos, Elementalist/Reactive multiplier hooks, boss resistance field. **Started 2026-10-20 (G20)**: the component core is in — `scripts/components/status_effects.gd` (`class_name StatusEffects extends Node`) with `enum Status { BURN, CHILL, FREEZE, SHOCK, TOXIN, MARK, BLEED, UNRAVEL }`, the two signals (`status_applied(status, stacks)`, `status_expired(status)`), `apply_status()`/`has()`/`stacks()`/`clear()`/`clear_all()` plus the reads the rest of the game needs, every spec-table number as a named constant and the lookup tables built from those constants — "the 7 statuses, their API and host-only scaled ticking". Ticking runs in `_physics_process` on `delta * TimeManager.scale_for(entity())` and deals its damage as a finished `HitData` through `Health.apply_damage()` (never a direct HP write, never `Engine.time_scale`); the tick's rate is a fraction of the `StatBlock` max HP (BURN 4 %/stack/s, TOXIN 1.5 %, BLEED 2 %). The player gate reads the entity's `PLAYER_TAG` group, never a script class, and `PlayerSpawner` tags every player it spawns, so the player scene stays the other lane's. `Effect.apply_status()`'s `status` parameter is retyped to `StatusEffects.Status` — the retype its own comment promised — and the effect suite is unchanged at 22/57. Accept: `tests/unit/test_status_effects.gd` **26/26 / 192 asserts** green (red first — parse error, "Could not find base class StatusEffects"), full suite **47 scripts / 768 tests / 768 passing / 56 069 asserts** exit 0 (up from 46/741/55 875 at `8948af4`), `--import` exit 0 with 0 error lines, the three touched files re-run individually and unchanged (`test_effect_helpers` 22/57, `test_status_effects` 26/192, `test_player_spawner` 17/55, the spawner case red first at 16/17), **two-instance smoke exit 0 with every check `ok`** because the tag line is spawner wiring and spawner wiring is sync (BRIEF C17), and both failing paths forced and kept (`.goals/evidence/g20/negative-control-1.log` — the tick ignoring `scale_for()`, 24/26, fails exactly the stop/clear-resume and 0.5-slow cases; `.goals/evidence/g20/negative-control-2.log` — `is_player()` returning false, 24/26, fails exactly the gate case and the refused-application bus case). Remaining: the rows' own behaviour — G21 (BURN, CHILL to FREEZE, MARK) and G22 (SHOCK, TOXIN, BLEED, UNRAVEL) — then the six combos, the multiplier hooks and the resistance field (G23–G26). **Then 2026-10-20 (G21)**: BURN, CHILL and MARK have their spec rows' own behaviour — BURN pinned by its own cases (4 % of max HP per second per stack at 1 and 5 stacks, the 5-stack cap, a re-apply that refreshes the 4 s clock rather than adding a second one, expiry on 4 s of *scaled* time); CHILL's `-12% move and attack speed per stack` as named-constant `StatBlock` **percent** modifiers under the new per-status source `CHILL_SOURCE` (`status:chill`), with the **fifth stack never held as Chill** — `apply_status()` routes it through `_freeze_from_chill()`, which clears the Chill and its slow first and applies FREEZE for `FREEZE_DURATION`, while a player (forbidden FREEZE by the table's last line) caps at five Chill and does not convert; FREEZE pinning move speed to 0 with `FREEZE_IMMOBILE_PERCENT` under `FREEZE_SOURCE`, "can't act" as the `can_act()` read (attack speed is clamped at 0.2, so a zero would be unreachable), a one-shot double spent by `consume_freeze_double()` which also clears all Chill (Permafrost's "always" is G23's attacker-side `status_mult` term, not a second flag), and `_release_modifiers()` taking back a status's modifiers and its unspent double however it leaves; MARK a single stack read by `mark_forces_crit()` and spent by `consume_mark()`. `base` is never written — every change is a `StatBlock` modifier handle. Accept: `tests/unit/test_status_effects.gd` **40/40 / 249 asserts** green (26/192 at G20 — 14 new cases, red first, "Could not find member `CHILL_SLOW_PER_STACK` in base `StatusEffects`"), full suite **47 scripts / 782 tests / 782 passing / 56 126 asserts** exit 0 (up from 47/768/56 069 at `1216c11`), `--import` exit 0 with 0 error lines, two-instance smoke 35 `ok` / 0 FAIL, headless `-- --host --debug-tools --smoke=6` exit 0, and both failing paths forced and kept (`.goals/evidence/g21/negative-control.log` — the conversion branch disabled, **exactly** the 2 conversion cases fail; `g21/negative-control-2.log` — the Chill percent zeroed, **exactly** the 2 slow cases fail), each reverted and the suite re-greened. Remaining: SHOCK, TOXIN, BLEED and UNRAVEL (G22), then the six combos, the multiplier hooks and the resistance field (G23–G26). **Then 2026-10-20 (G22)**: SHOCK, TOXIN, BLEED and UNRAVEL have their spec rows' own behaviour, which closes the eight-row table — SHOCK chains `30 %` of the applying hit's damage to up to 2 enemies within 96 px (the trigger arrives as a trailing optional `trigger_damage` on `apply_status()`, `chain_targets()` reads the `ENEMY_TAG` group nearest-first, a bare application chains nothing, a re-apply refreshes and chains once); Lightning Rod's `+2 chains` and Plague Doctor's Mask's "disables expiry" are read as **ids off the governing `EffectHost`s** through `has_relic()` (`LIGHTNING_ROD_ID`/`PLAGUE_DOCTORS_MASK_ID`), never hard-coded, so the relics stay W4-B6 content (both hosts are read — the applier's and the target's own — and each has a case); the mask re-arms TOXIN's clock instead of pinning a sentinel duration. TOXIN is unlimited-stack and `healing_multiplier()` (0.5) is applied **on the heal path** so the row's `-50 %` is asserted on the HP that landed; BLEED's tick is gated on `is_moving()` (0 while still, 2 %/stack/s while moving, capped at 10); UNRAVEL's `+10 %` per stack is the new `damage_taken_multiplier()`, folded by `Damage.compute`'s new trailing optional `target_statuses` into the formula's `status_mult` term (only the UNRAVEL term — Kindling's and Permafrost's are G23's). Two test doubles carry the seam: `tests/helpers/status_enemy_stub.gd` (a `CharacterBody2D` in the `enemy` group with a `Health` double) and `tests/helpers/relic_marker_effect.gd` (a no-op effect so a test can hold a relic id before W4-B6's `.tres` files exist). Accept: `tests/unit/test_status_effects.gd` **54/54 / 314 asserts** green (40/249 at G21 — 14 new cases, red first, "Could not find member `SHOCK_CHAIN_DAMAGE_FRACTION` in base `StatusEffects`"), full suite **47 scripts / 796 tests / 796 passing / 56 191 asserts** exit 0 (up from 47/782/56 126 at `247839f`), `--import` exit 0 with 0 error lines, `test_damage.gd` re-run beside it unchanged at 15/15, the SHOCK chain fraction zeroed as the forced negative control (**exactly** the 5 chain cases fail, 49/54, `g22/negative-control.log`, reverted byte-exact at `sha1 e31884b3…`), and **no smoke run** because the commit adds no RPC, replication or spawner wiring (BRIEF C17). **Then 2026-10-20 (G23)**: `Damage.compute`'s week-2 literals are the formula — `status_mult` is `1.0 (+0.25 Kindling on BURN) (+1.0 Permafrost on FREEZE, once) (+UNRAVEL stacks * 0.1)`, composed in one read on the target's component (`incoming_damage_multiplier(attacker_host)`, handed the attacking entity's `EffectHost` looked up as `parent/EffectHost`, so no relic id reaches `Damage` and `compute()`'s signature is unchanged); reading it spends the freeze double — even for a Permafrost holder, so a one-shot cannot be banked for an attacker who has neither relic — and Permafrost's own `+1.0` needs no charge. MARK now forces the crit from the *target's* component (`mark_forces_crit()` read and `consume_mark()` called before the crit roll, so the forced crit still draws nothing — proven by four paired draws on two generators seeded alike, one of which had a marked hit computed against it first), while `HitData.force_crit` stays for a caller that forces its own. `status_resistance` is an `@export var ... : float` on `StatusEffects` defaulting to 1.0, multiplied into every applied duration by `resisted_duration()` (including a Chill-cap conversion; above 1.0 it lengthens, it is not a cap), and at or below 0.0 `degrades_freeze()` sends FREEZE to `_heavy_chill()` — CHILL at the 5-stack cap, the −60 % slow, announced as the Chill it is with `can_act()` true, and the Chill cap's own conversion to FREEZE held back so the downgrade cannot be walked back; the degraded Chill deliberately keeps the Chill table's full duration, because a 0.0-multiplied downgrade would be the "doing nothing" the spec's clause exists to avoid, while every other row does take the multiplied 0.0 and expires on the next tick. The golden table is now **18 rows** (the 12 week-2 rows byte-identical, six status rows added at 25/26/40/40/30/55 by hand), and `hit_data.gd`'s `force_crit` doc lost its stale "StatusEffects has not landed" claim. Accept: `tests/unit/test_damage.gd` **22/22 / 78 asserts** and `tests/unit/test_status_effects.gd` **65/65 / 371 asserts** green (red first: `test_damage` 14/22 with all six new rows failing at 20/20/20/20/20/30, `test_status_effects` a parse error naming the missing constants and fields), full suite **47 scripts / 814 tests / 814 passing / 56 281 asserts** exit 0 (up from 47/796/56 191 at `eb2d0a3`), `--import` exit 0 with 0 error lines, one forced negative control (`KINDLING_BURN_BONUS` 0.25 → 0.5: exactly the four cases that assert that number fail, reverted byte-exact at `sha1 435f043e…`), and **no smoke run** because the commit adds no RPC, replication or spawner wiring (BRIEF C17); a headless `-- --host --debug-tools --smoke=6` boot exit 0 ran instead. Remaining: the Elementalist/Reactive multiplier hooks (G25–G26). **Then 2026-10-20 (G24)**: the six element combos are in. `scripts/components/combo.gd` (`class_name Combo extends RefCounted`) declares the bus payload — `enum Kind` is SPEC-stats-status's "Element combos" table in row order (SHATTER, CONDUCT, BLIGHT_EXPLOSION, HEMORRHAGE, SUPERCONDUCT, COLLAPSE), `NAMES` maps each to its printed name, and the fields are the ones a row's Effect column names (`kind`, `damage`, `duration`, `radius`, `stacks`) — so `Events.combo_triggered(target: Node, combo: Combo, source: Node)` names the real class and its `StatusEffects.Status <- int` placeholder TODO line is gone (`grep -c "TODO(stats-status): Combo" scripts/autoload/events.gd` is 0), with `test_events_bus.gd` moved from the placeholder pins to the real-class `TYPE_MAP` entries (**Ask-first, decision 54** — it spends the pin `events.gd` already carried for itself; no other signal's signature moved). `StatusEffects` reads the pair rules **before** the write (`_combo_for()`) and fires one **after** it (`_maybe_trigger_combo()`), so "a target that already has another element's status" is decided against what the application reacted to; the rules are the table's rows in the table's own order, so a target holding two eligible elements fires **exactly one** combo — the spec's "the combo fires once" — and same-element re-applies (and the Chill cap's FREEZE conversion) fire nothing. "Consumes the listed stacks" is read in the same past tense as the trigger, so SHATTER spends the frost that was already there and BURN + CHILL/FREEZE can still coexist — which is what keeps G23's `status_mult` fixture and G21's "clearing one status leaves the rest" green rather than weakened (**decision 54**). SHATTER bursts for 200 % of the trigger damage in 64 px, BLIGHT_EXPLOSION for 40 % per Toxin stack (both consuming, both through the same hurtbox seam as SHOCK's chain), HEMORRHAGE makes Bleed tick crit for 4 s at 2.0×, SUPERCONDUCT puts −30 % Defense for 8 s on a `StatBlock` modifier with its own source and releases it on expiry, CONDUCT spreads the shock to the connected water area, COLLAPSE asks every enemy within 128 px to pull to the target; every number is a named constant beside the status rows it derives from, and the two lasting rows tick on `TimeManager`-scaled time (never `Engine.time_scale`). The two world-facing rows ask through names and never reach: `wet` + `connected_water_targets()` on the entity, `pull_toward(origin, radius)` on each in-range enemy, both no-ops when absent, both providers Dev A's — **blocked on Dev A (W2-A1 / W4-A1, floor-generation water tiles)** — so the cases assert the request, not water that spread or an enemy that moved. Accept: new `tests/unit/test_combos.gd` **17/17 / 118 asserts** green (red first — `Parse Error: Could not find type "Combo" in the current scope`, `Cannot find member "SHATTER_BURST_FRACTION" in base "StatusEffects"`, `.goals/evidence/g24-combos/red-test-combos.log`), one case per table row plus the negative half (re-apply, an unlisted pair, one-combo-per-application, a non-hosting peer); full suite **48 scripts / 831 tests / 831 passing / 56 403 asserts** exit 0 (up from 47/814/814/56 281 at `8220c5b`), `--import` exit 0 with 0 error lines, `test_events_bus` 10/10, `test_status_effects` 65/65 and `test_damage` 22/22 re-run unchanged, one forced negative control (`SHATTER_BURST_FRACTION` 2.0 → 3.0: exactly the six assertions that read that number fail, reverted byte-exact at `sha256 30943fbb…`), and **no smoke run** because the commit adds no RPC, replication or spawner wiring (BRIEF C17). Remaining: none — the header's last item, the Elementalist/Reactive multiplier hooks, lands in G25–G26 at the end of this note, which is why the box is ticked. **Blocked on the bosses lane**: `BossData` does not exist, so `status_resistance` has no setter in a running build — the field, the multiplier and the downgrade are proven by unit cases and every non-boss entity keeps the default 1.0. **Blocked on Dev A (W4-A1)**: `ENEMY_TAG`'s real registrant is Dev A's enemy base, so a running build's chain would find nobody. **Blocked on Dev A (W2-A1)**: `player.tscn`'s `StatusEffects` node is still bare and there is no real `Health`, so no running build carries a status yet; the stacks property on the entity's `StateSync` is the HUD's (W4-B10, G51). **Then 2026-10-20 (G25–G26)**: the Elementalist/Reactive multiplier hooks and `Scaling` are in, which closes this task's header. A combo's damage now reads a multiplier through the **applying entity's own `EffectHost`**: `StatusEffects.scaled_combo_damage()` multiplies the settled `Combo.damage` by `combo_damage_multiplier(source)`, which walks `host.effects()` and multiplies the factor every effect answering `combo_damage_multiplier()` (`COMBO_MULTIPLIER_METHOD`) returns, from `COMBO_DAMAGE_BASE` (1.0); a null source, a non-effect source, a freed host and a non-numeric answer all contribute nothing, and `tests/helpers/combo_consumer_stub.gd` stands in for both real consumers — the week-7 Reactive skill node's +40 % and the week-8 Elementalist synergy's ×2 — which attach to the player's `EffectHost` as content rather than being registered anywhere. The multiplication happens in exactly one place, between `_maybe_trigger_combo()`'s settling and delivering passes and guarded by `combo.damage > 0`, so a row that lands no damage (HEMORRHAGE's flag, COLLAPSE's pull) is untouched and a row added to the first match later cannot be excluded from it; `COMBO_ELEMENTALIST_MULTIPLIER` (2.0) and `COMBO_REACTIVE_BONUS` (0.40) name the spec's two numbers, while the factor itself is the consumer's own field so a later goal can rebalance its content without editing this component. `test_combos.gd` **22/22 / 163 asserts** green (17/17 / 118 at G24: five new cases — ×2, +40 %, both composed to 2.8 rather than summed to 3.4, no consumer exactly 1.0, and a `RelicMarkerEffect` under the `elementalist` id contributing nothing, so the hook is the method and not a relic id). `scripts/scaling.gd` (`class_name Scaling extends RefCounted`, twelve `const`s and seven static functions, never instantiated) is the other half: `enemy_hp_mult(biome_index) = pow(1.0 + BIOME_STEP, biome_index - 1)` with `BIOME_HP_MULTIPLIER` derived from `BIOME_STEP` so the design doc's "about 12 %" and the spec's `1.12` cannot drift apart, `enemy_damage_mult` delegating to it because the spec says "same for damage", the curve clamped below at the first biome and deliberately not above (the formula is defined for any depth), `elite_hp(max_hp) = max_hp * ELITE_HP_MULTIPLIER` (2.0, the design doc's "+100 % HP") as a pure function so `enemies-ai` can call it on a number it already computed, and `enemies_per_room`/`elite_chance` as a base plus a per-floor step, capped and clamped at both ends of floors 1…30 — the two curves the design doc names without a formula, monotonic by construction rather than by a hand-maintained table. `enemy_max_hp(base_hp, biome_index)` composes the biome curve with `NetworkManager.enemy_hp_multiplier()` and never restates the co-op rule, which the test proves by making a second peer appear and watching `Scaling`'s answer move. Accept: `tests/unit/test_scaling.gd` **8/8 / 195 asserts** green (red first, "Identifier \"Scaling\" not declared in the current scope" — a new `class_name` needs `--import` before the tests can find it), `test_combos` 22/22 / 163, full suite **49 scripts / 844 tests / 844 passing / 56 636 asserts** exit 0 (up from 48/831/831/56 403 at `28eec11`), `--import` exit 0 with 0 error or warning lines, `grep -rn "Engine.time_scale" scripts/ scenes/` empty (a doc comment that used the literal as an example now says "the engine's own time scale", with the `TimeManager.scale_for()` rule unchanged), two forced negative controls each reverted byte-exact (`BIOME_STEP` 0.12 → 0.20 fails exactly the three assertions that read the spec's 12 %; the host scan short-circuited fails exactly the three multiplier cases), and **no smoke run** because the commit adds no RPC, replication or spawner wiring (BRIEF C17). `Scaling.rune_room_chance` and `Scaling.modifier_chance` (SPEC-floor-generation's rolls) are deliberately **not** provided — SPEC-stats-status's own "Scaling constants" sentence lists neither and no Week 4 goal asks — so they are recorded as absent rather than invented here. **Blocked on Dev A (W4-A1 / W4-A2)**: `SpawnDirector` v2 and the elite affix work are `Scaling`'s real callers, so no enemy spawns with these numbers today, and no real consumer is attached to any player yet.
- [ ] W4-B5 `[relics]` `RelicData`, `RelicRoller` (rarity weights, Luck, no cursed at shrines, max_stacks), `Shrine` interactable + SHRINE populator, `request_pick_relic`, `relic_picked`, codex workflow. **`RelicData` half landed 2026-10-20 (G27)**: `scripts/data/relic_data.gd` ships the spec's `Rarity`/`Kind` enums, `rarity`/`kind`/`description`/`max_stacks` (1)/`active_cooldown`/`active_charges`/`weight` (1.0), the Shrine weights (`RARITY_WEIGHT_COMMON` 60, `RARE` 28, `EPIC` 10, `LEGENDARY` 2, no `CURSED`) behind `roll_weight()`, and `WEEK_4_IDS` — design doc 9.1 nos. 1 to 20 — with `id`/`display_name`/`tags`/`effect_script`/`icon` left on `ContentData` (nothing renamed or shadowed); `Events.relic_picked`/`relic_removed` now carry `RelicData` and their `## TODO(relics)` pin is deleted (decision 56); `tests/helpers/event_emitter.gd` gains `_relic()`. Accept: new `tests/unit/test_relic_data.gd` **10/10 / 104 asserts** green, written and run red first (parse error naming `RelicData`, `.goals/evidence/g3/red-test-relic-data.log`) — it walks `data/relics/`, applies the rules to every `.tres` found, demonstrates every rule on fixtures it writes itself, and pins the weights and the 20 ids against SPEC-relics and design doc 9.1 parsed at run time; full suite **50 scripts / 854 tests / 854 passing / 56 737 asserts** exit 0 (up from 49/844/844/56 636 at `91ec4a3`); `--import` exit 0 with 0 error lines; `test_events_bus.gd` 10/10, `test_events_emitters.gd` 10/10, `test_autoloads.gd` 7/7 and `integration/test_data_loads.gd` 2/2 after the retype; one forced negative control (the tag-count check short-circuited) failing **exactly the two tag rules** (9 passing / 1 failing, 100/102 asserts), reverted byte-exact and re-green; no smoke run (no RPC/replication/spawner wiring). Still open in this task: the `Shrine` + SHRINE populator (G9), `request_pick_relic` + the codex (G10), the 20 `.tres` (G5–G8); `data/relics/` holds only `.gdkeep` today so the scan examines zero files. **`RelicRoller` half landed 2026-10-20 (G4)**: `scripts/relics/relic_roller.gd` (new module folder, decision 58) ships `roll(player, count, allow_cursed)` — SPEC-relics' own interface — over `roll_from_pool(pool, held, luck, count, allow_cursed, rng)`, with the two stages in the spec's order: the tier on the four Shrine weights read from `RelicData.RARITY_ROLL_WEIGHTS` (common 60 / rare 28 / epic 10 / legendary 2) shifted by `Stat.LUCK` through the spec's own `rarity_roll += LUCK * 0.01` (`LUCK_SHIFT_PER_POINT`, parsed out of SPEC-run-economy by the test), then a second weighted pick *inside* the tier on `RelicData.weight`; `held >= max_stacks` filters on occurrence counts off the player's replicated `RunPlayerState.relics`; cursed is excluded from both the weight table and the candidate list unless `allow_cursed` (decision 57 sets its weight-only-when-allowed constant); an exhausted tier walks to the nearest one with something (`nearest_tiers()`). Accept: new `tests/unit/test_relic_roller.gd` **25/25 / 303 asserts** green, written and run red first (parse error naming `RelicRoller`, `.goals/evidence/g4/red-test-relic-roller.log`) — the distribution gate is **10 000 rolls** at seed 20261020 over a synthetic 9-relic pool built in the test, tally `{COMMON 5911, RARE 2837, EPIC 1056, LEGENDARY 196}`, worst deviation **0.0089** against the spec's **0.02**, zero cursed; full suite **51 scripts / 879 tests / 879 passing / 57 038 asserts** exit 0 (up from 50/854/56 737); `--import` exit 0 with 0 error lines; one forced negative control (`LUCK_SHIFT_PER_POINT` 0.01 → 0.00) failing **exactly the four Luck cases** (21/25, 295/303 asserts), reverted byte-exact and re-green at the same tally; no smoke run (no RPC/replication/spawner wiring, no `.tscn`, no autoload, no `scripts/data/` Resource touched).
- [ ] W4-B6 `[relics]` 20 relics: On Dodge 1 to 6, On Hit 7 to 14, On Kill 15 to 20 (`.tres` + effect scripts + harness case each). **PARTIAL — 6 of the 20 landed 2026-10-20 (G5); the box stays open until G8**, which is the goal PLAN.md's own goal→task mapping names as the one that completes W4-B6 (G5 ships raw goal G32 / relics 1–6 only, the same one-half annotation W4-B5 already carries). **On Dodge 1 to 6 landed 2026-10-20 (G5)**; On Hit 7 to 14 and On Kill 15 to 20 not started. Six `data/relics/<id>.tres` and six effect scripts in a new `scripts/effects/relics/` (decision 59), one per relic — Ember Boots, Storm Sandals, Mirror Step, Frostwalkers, Ghost Wrap, Rebound Spring — each listening on `Events.player_dodged(player, perfect)` and each asserted to fire **exactly once**; the batch case drives `EventEmitterHelper` as a second player, so "fires for its own holder's dodge and not a team-mate's" is asserted from the other side of `Effect.listen()`'s player filter. Criterion 4 is parsed, not restated: `tests/integration/test_relic_triggers.gd` reads 9.1's display names and descriptions out of `SINKHOLE_SPEC.md` at run time, checks the tags against the synergy table (`dodge` on all six; `fire`/`storm`/`frost`/`shadow` on the four that 9.1 gives an element), links the three stated numbers to the constants that are them (`CLONE_FUSE_SECONDS` 1.0 ↔ "1s", `INVISIBLE_SECONDS` 2.0 ↔ "2s", `DODGE_DISTANCE_MULTIPLIER` 2.0 ↔ "doubled"), and reads the scene each spawning relic takes from its own `vfx_id` (`relic_proc_fire`/`storm`/`frost`/`shadow`/`dodge`, SPEC-art-audio's `relic_proc_<tag>`). Unlanded providers stay asks, never fakes: `blocked on art-audio (W4-B12/B13)` for the three proc scenes (a missing scene drops the spawn rather than erroring), `blocked on Dev A (W4-A4)` for the FX-with-gameplay roots and the gameplay in them, `blocked on Dev A (W2-A8, the Dodge state)` for `DodgeSeam.request_wall_bounce()`, and `blocked on Dev A (enemies-ai)` for Ghost Wrap's untargetability (nothing registers into `StatusEffects.ENEMY_TAG` in a running build either, so Storm Sandals' scan reads a double's candidate set — the ask is asserted, the population is not). Two new doubles: `tests/helpers/relic_fx_root_stub.gd` and `tests/helpers/dodge_seam_stub.gd`. Accept: the file **10/10 / 181 asserts**; full suite **52 scripts / 889 tests / 889 passing / 57 276 asserts** exit 0 (`.goals/evidence/g5/gut-full-final.log`), against G4's 51 / 879 / 57 038 — the +57 asserts are three existing folder-walkers (`test_relic_data.gd`, `test_tags.gd`, `test_relic_roller.gd`) meeting real content for the first time, measured by moving this file aside (51 / 879 / 57 095, `gut-without-new-file.log`), so 57 038 + 57 + 181 closes exactly; content-absent control (six `.tres` moved aside) fails **exactly the ten new cases** and nothing else; six per-relic negative controls each fail their own case plus the batch case, every one reverted byte-identical; `--import` exit 0 with 0 error lines; `-- --host --smoke=6` exit 0 with 0 script errors; two-instance smoke **35 `ok` / 0 FAIL** exit 0; red run kept at `.goals/evidence/g5/g5-red.log` (32 parse errors naming all six missing classes). One pre-existing test rewritten — `test_relic_roller.gd`'s "empty folder" case could not survive six real `.tres` files (decision 63) — and one HANDOFF section added (G5) with decisions 59 to 63.
- [ ] W4-B7 `[relics]` `ActiveRelicController` slot 1 (C), charges, cooldown, HUD hook (actives themselves arrive week 8).
- [ ] W4-B8 `[run-economy]` Currencies: `Pickup` scene + magnet, `LootTable`, gold/ore/echo drops from `EnemyData.loot_table`, chests, breakables, mining hooks.
- [ ] W4-B9 `[time-manager]` `slow_enemies`/`stop_enemies` consumers, `register_rewindable`/`rewind`, broadcast of entity effects; `timestop` console command verified in co-op.
- [ ] W4-B10 `[ui-hud]` `ChoicePopup` (relic 1-of-3 with tags and rarity colors), relic icon strip with stacks, currencies, `Minimap` from `FloorLayout`, status icons.
- [ ] W4-B11 `[debug-tools]` Perf scene (60 units, 4 fake players, 128 emitters, FPS log), `net_lag` real implementation, effect overlay.
- [ ] W4-B12 `[art-audio]` 20 relic icons (`gen_icons.py relics`, rarity frame colors), pickup sprites (gold, ore, echo, rune, relic, potion) with `pickup_sparkle` tint, `ChoicePopup` theme (rarity colors, tag chips), relic strip, currency icons, minimap glyphs, status icons (7). Accept: review approved; `test_assets.gd` relic icon coverage.
- [ ] W4-B13 `[art-audio]` SFX: pickup gold/ore/echo/rune/relic, potion, relic proc generic x3, choice open/pick. Accept: review approved.

**Suite-integrity note, dated 2026-10-20 (G15a) — resolved and residual.** `tests/unit/test_audio_manager.gd::test_plain_pool_respects_the_cap`'s timing flake is **fixed in the fixture**: the pool is now filled through the real acquire path with a looping click (`_looping_click()`) so "all 16 are playing" is a property of the test rather than of CPU speed, and a new case (`test_plain_pool_reclaims_a_stopped_player`) pins the reclaim rule the flake depended on. No assertion was deleted or weakened. The **same-class residual is recorded here rather than silently changed**, per the goal's own rule: `test_plain_pool_grows_while_players_are_busy` (one real 16 ms `ui_click` play, then one acquire) and the `.playing` assertions that follow an explicit `play_music`/`stop_music` all sit inside the same real-time window. None was observed failing in 6 solo full suites, 8 parallel full suites, 3 pre-fix loaded full suites, 5 post-fix full suites or 40 file-alone runs; `.goals/evidence/g15a/real-time-assertions.log` lists every assertion examined and why each was left as-is. If one does flake, it gets its own dated item and is fixed the same way — this note is not a claim that they cannot.

### Dev A
- [ ] W4-A1 `[enemies-ai]` Elites: outline shader, +100% HP, 6 affixes with behaviors, `elite_killed`.
- [ ] W4-A2 `[enemies-ai]` `SpawnDirector` v2: waves (1 to 3, next at 40%), elite chance by floor, Double Elites hook, `EnemyPool`, off-room processing pause, spatial-hash separation perf.
- [ ] W4-A3 `[floor-generation]` SHRINE room placement rule (1 per floor) + interactable anchor; ELITE_COMBAT counts by floor.
- [ ] W4-A4 `[combat-core]` Emit `hit_landed`, `crit_landed`, `player_damaged`, `heavy_attack_released`, `weapon_swapped`, `projectile_fired`; `enemy_killed`, `enemy_spawned`; `player_dodged` and related events.
- [ ] W4-A5 `[weapons]` Blacksmith damage tier hook and `Stat.ATTACK` wiring through `Damage.compute`.
- [ ] W4-A6 `[art-audio]` Status VFX emitters (`burn`, `chill`, `freeze`, `shock`, `toxin`, `mark`, `bleed`, `unravel`) + 6 combo emitters, `elite_outline.gdshader`, `elite_spawn` burst, `gen_vfx_textures.py` (dot, spark, ring, shard, puff, glyphs, 64 px light). Accept: `vfx <id>` console capture per emitter in the review sheet; 128-emitter perf scene holds 60 FPS.
- [ ] W4-A7 `[art-audio]` Shrine, chest, breakable (3), ore vein, elite affix glyph sprites; SFX: status apply per element (7), elite spawn, chest, breakable, shrine pick. Accept: review approved.

### Checkpoint: Week 4 end
- [ ] Every W4 `[art-audio]` task has an approved review sheet in `docs/asset-review/week-4/` (or a dated polish-list entry); `build_all.py --check` clean
- [ ] Pathological proc build holds 60 FPS; 20 relics harness-tested and co-op checked; smoke steps 1 to 6; perf numbers in WEEKLY; `week-4` tagged

---

## Week 5: Abilities + classes v1 + extraction

**Done when:** Ability system with 10 abilities, Rune rooms, ultimates, class system with Warrior, Ranger, Mage (passives + class skills), rope points and votes, death rules, town v1, save/load.

### Dev A
- [ ] W5-A1 `[abilities]` `AbilityData`, `AbilityRank`, `AbilityController` (2 slots, cooldown with CDR, charges, rank-up by duplicate, rank-3 to gold, stored runes, `request_cast`), `AbilityCast` and effect hooks.
- [ ] W5-A2 `[abilities]` 10 abilities: Meteor Call, Flame Dash, Glacier Spike, Chain Lightning, Thunder Step, Shadow Clones, Toxic Cloud, Stone Skin, Black Hole, Barrier Dome (+ harness case each).
- [ ] W5-A3 `[abilities]` `UltimateController` meter (deal/take rates, Spite Totem x3), `ultimate` input, Cave-In ultimate.
- [ ] W5-A4 `[classes-characters]` `ClassData`, `AscensionData`, `CharacterData`, `ClassPairData`, `ClassTreeNodeData` definitions; `ClassController` (passive attach, affinity attach/detach, class skill and character selection hooks).
- [ ] W5-A5 `[classes-characters]` Warrior (Rage, Battle Cry, affinity heavy charge), Ranger (Far Shot, Tumble Volley, +1 pierce), Mage (Arcane Flow, Blink, double element) + Wren (ore +25%, breakage boost), plus affinity hooks.
- [ ] W5-A6 `[weapons]` `affinity_active_changed` signal, `"affinity"` hit tag, Lantern Staff `.tres` (third starting weapon) so Mage has an affinity weapon.
- [ ] W5-A7 `[enemies-ai]` `FriendlyUnit` base (`owner_player`, lifetime, follow, Team.PLAYER) for Shadow Clones now and minions later.
- [ ] W5-A8 `[art-audio]` Wren real body sheet (`tools/art/chars/wren.py`: idle, run, dodge, hurt, downed, death, cast) + attack sheets for 3 weapon types (blade, ranged, magic: light x4, heavy x6) + Lantern Staff held sprite, icon, projectile. Accept: review sheet (all drawn + mirrored rows) and in-engine capture approved by Dev A; `test_assets.gd` frame counts pass.
- [ ] W5-A9 `[art-audio]` 10 ability icons (`gen_icons.py abilities`, element tints from `palette.ELEMENT`) + 10 `ability_<id>` emitters + `ult_cave_in` emitter; SFX: cast per school for the 5 schools in use, ultimate, class skill x3. Accept: review approved; every `AbilityData.vfx_id`/`sfx_id`/`icon` resolves.

### Dev B
- [ ] W5-B1 `[save-system]` `SaveManager` (debounced atomic save, `.bak`, load with migrations, corrupt recovery), `PlayerProfile` with all fields and `defaults()`, `merge_run_gains`.
- [ ] W5-B2 `[run-economy]` Rope votes (all living, downed excluded, `no` cancels, solo immediate) via `request_vote_rope`/`rope_vote_updated`; death vs extract table per currency.
- [ ] W5-B3 `[run-economy]` Map Room start floors (`start_floor`, Ascension timing flags), SHOP populator + `Shopkeeper`, `PotionController` (heal, slots, E key), relic room hooks.
- [ ] W5-B4 `[town]` `town.tscn` v1 (walkable hub, pit edge stage 0, 11 `Building` nodes at level 0 signs, 3 functional: Blacksmith buy weapons, Shrine of Echoes entry stub, Tavern Dive), `Building` container and flow.
- [ ] W5-B5 `[town]` `RunSetup` flow (character, class, 2 weapons, start floor, ready per player) feeding `GameState.start_run` with `PlayerSpawnInfo`.
- [ ] W5-B6 `[ui-hud]` Main menu (Solo, Host, Join with IP, Settings stub, Codex stub, Quit), pause overlay, run/inventory screen (Tab), rope vote prompt, death screen from `RunResult`, town menu interactions.
- [ ] W5-B7 `[art-audio]` Town v1 art: `gen_town.py` ground tiles + props, 11 buildings at L0 (128x128 signs/ruins), pit edge stage 0, Wren portrait (`gen_portraits.py wren`), main menu theme (title font, buttons, IP field), pause and inventory screen theme, death screen theme. Accept: review sheet + town capture approved by Dev B.
- [ ] W5-B8 `[art-audio]` Music: main menu and town theme (sourced CC0 or `tracker.py` chiptune, loop points set), credited; `tools/audio/tracker.py` + `tools/audio/music/*.json` if generated. Accept: both tracks loop seamlessly in the menu and town; `CREDITS.md` rows present.

### Checkpoint: Week 5 end (mid-project gate is end of week 6)
- [ ] Every W5 `[art-audio]` task has an approved review sheet in `docs/asset-review/week-5/` (or a dated polish-list entry); `build_all.py --check` clean
- [ ] Full loop: town, select, dive, floors, shrine, rune, rope vote, extract or die, bank, town; save survives restart; co-op end to end; `week-5` tagged

---

## Week 6: Biome 1 complete + story base

**Done when:** All Biome 1 enemies, first boss fights, dialogue system, first NPCs and story flags, Shop rooms, Rest rooms.

### Dev A
- [ ] W6-A1 `[biomes]` `BiomeData` + Collapsed Mines `.tres` (floor 1 to 5, Copper, room sizes, palette, ambient light, lore floor 4), Biome 1 tileset wired, `CanvasModulate` + player `PointLight2D` and hazard hooks.
- [ ] W6-A2 `[biomes]` Dynamite Goblin, Cave Bat Swarm (flyer) + hazards: falling rocks, mine cart, gas pocket (Fire ignition via `gas` flag).
- [ ] W6-A3 `[bosses]` `BossData`, `BossPhase`, `Boss` + `BossStateMachine` (Intro, Phase, Transition, Stagger, Death with slow-mo, rope spawn), arena scene base, boss bar data.
- [ ] W6-A4 `[bosses]` Boomer Jack and The Foreman, with each boss's attack set and death reward flow.
- [ ] W6-A5 `[floor-generation]` Placement rules for SHOP, REST, RUNE, ANVIL, LORE, hazard placement from biome data.
- [ ] W6-A6 `[art-audio]` Biome 1 real asset pass completion: Dynamite Goblin, Cave Bat Swarm sheets; hazard sprites + animations (falling rocks, mine cart, gas pocket + ignite); Boomer Jack (96, with `special_1..n` per attack, `phase_transition`) and The Foreman (192, intro, slams, summon, cave-in); `dissolve.gdshader`; `boss_death` emitter; torch `PointLight2D` texture. Accept: review sheets + boss arena capture approved; mid-project gate shows no placeholder in Biome 1 pit content.
- [ ] W6-A7 `[art-audio]` SFX: hazards (rocks, cart, gas), boss roar, boss phase, boss death, Goblin bomb, bat swarm, player death, downed, revive. Accept: review approved.

### Dev B
- [ ] W6-B1 `[story-dialogue]` `StoryManager` (flags with namespaces, `flags.json` declaration, `act()`, `evaluate()` condition language, `unlock_lore`), `DialogueData` loader from JSON with schema validation.
- [ ] W6-B2 `[story-dialogue]` `DialogueBox` UI (portrait, name, typewriter, choices, per-player in town), `start_dialogue`, `LorePage` pickup + LORE populator, codex list stub.
- [ ] W6-B3 `[story-dialogue]` Act 1 content: early NPC lines + forum topics + boss-defeated reactions; story flags and progression hooks.
- [ ] W6-B4 `[town]` NPC nodes with `start_dialogue`, Alchemist (slots, heal potion), Map Room (start at reached ropes, next-floor modifier preview), building level sprites x4 states, pit edge staging.
- [ ] W6-B5 `[run-economy]` Shop and Rest room interactables polished, currency scaling by biome.
- [ ] W6-B6 `[art-audio]` 8 NPC walk/idle sheets + 8 portraits (Hilde, Gruff, Moss, Pip, Sister Ash, Old Tom, Vesper, rescued miner v1), `DialogueBox` theme (portrait frame, name plate, choice buttons, typewriter blip), lore page UI, codex list theme, Alchemist and Map Room L1 building states. Accept: review sheet + dialogue capture approved.
- [ ] W6-B7 `[art-audio]` Music: Biome 1 track, mini-boss theme, The Foreman theme; SFX: dialogue blip, lore pickup, shop buy/sell, rest heal. Accept: tracks loop and crossfade in-game; credited.

### Both
- [ ] W6-AB1 `[art-audio]` Mid-project asset gate: both lanes confirm Biome 1 has zero placeholders (tiles, 5 enemies, 2 bosses, hazards, Wren + 3 weapon types, town v1, 8 NPCs + portraits, 5 tracks, core SFX); `docs/asset-review/INDEX.md` lists every week 2 to 6 sheet as `approved` or `polish-list`.

### Checkpoint: Week 6 end (mid-project gate)
- [ ] Every W6 `[art-audio]` task has an approved review sheet in `docs/asset-review/week-6/` (or a dated polish-list entry); `build_all.py --check` clean
- [ ] Biome 1 playable end to end in co-op with relics, abilities, 3 classes, town, story, save; if slipped > 3 days, team meets on cut list; `week-6` tagged

---

## Week 7: Skill tree + weapons + Ascensions

**Done when:** Full skill tree UI and all branches, 10 weapons, anvil rooms with mutations, Ascensions for the first 3 classes, class XP and mastery, rescue mission system.

### Dev B
- [ ] W7-B1 `[progression-trees]` `SkillNodeData` + 38 node `.tres` with `requires`, `ui_position`, costs; `Progression` static (`rank`, `can_buy`, `buy`, `respec`, daily rule); Abyss gate on completion.
- [ ] W7-B2 `[progression-trees]` 38 node effects (`Effect` scripts: stat nodes via `modify`, behavior nodes for dodge/timing/utility), `Progression` graph logic.
- [ ] W7-B3 `[progression-trees]` `SkillTreeScreen` (pan/zoom canvas, nodes with rank pips, `Line2D` edges, locked/purchasable/bought states, tooltip, branch tabs) opened from Shrine of Echoes and town flow.
- [ ] W7-B4 `[story-dialogue]` Rescue missions: `rescues.json`, `Cage` interactable placed by generator hook, escort spawn via `EscortNpc`, rope-reach logic, reward flow.
- [ ] W7-B5 `[art-audio]` Skill tree UI: 38 node icons (`gen_icons.py skills`, branch tints Steel/Grit/Arcane/Delver/Abyss), node frame states (locked/purchasable/bought) + rank pips, edge line texture, tooltip nine-patch, branch tabs; Shrine of Echoes L1 building state. Accept: review sheet + tree capture approved.
- [ ] W7-B6 `[art-audio]` Rescue mission UI (cage marker, escort HP), Ascension popup theme; SFX: node buy, respec, tab, rescue start/complete. Accept: review approved.

### Dev A
- [ ] W7-A1 `[weapons]` Weapon skill trigger (perfect window + heavy, 6 s cooldown), `Channel` state for hold attacks, thrown/recall projectile support, `WaterTile`, `SoulOrb`, `lit` flag.
- [ ] W7-A2 `[weapons]` 8 more weapons to reach 10: Longsword, Twin Daggers, Sledgehammer, Shortbow, Hand Cannon, Spore Tome, Chain Whip, Grave Scythe (scene, `.tres`, skill, affinity tags).
- [ ] W7-A3 `[weapons]` `MutationData`, `Anvil` interactable + ANVIL populator, mutation attach as `Effect`, `specs/content/mutations.md` started; 60 mutations for the 10 weapons.
- [ ] W7-A4 `[classes-characters]` Ascension choice flow (after floor 5 boss or at start if deeper; duplicate rejection via host; `ascension_chosen`), Tier 1 Ascensions for a first set of classes.
- [ ] W7-A5 `[classes-characters]` Class XP earn hooks (kills, floors, bosses by biome) into `RunPlayerState`, mastery thresholds, `class_xp_gained`; skill data and progression integration.
- [ ] W7-A6 `[enemies-ai]` `EscortNpc` (follow 64 px, Health, flee, teleport catch-up, death fails rescue).
- [ ] W7-A7 `[art-audio]` 8 weapon held sprites + icons + projectiles (Longsword, Twin Daggers, Sledgehammer, Shortbow, Hand Cannon, Spore Tome, Chain Whip, Grave Scythe), Wren attack sheets for the 2 remaining weapon types (heavy, exotic), `WaterTile`, `SoulOrb` sprites. Accept: review approved.
- [ ] W7-A8 `[art-audio]` Mutation icon system: 24 overlay glyphs x element/rarity tint composited on weapon icons by `gen_icons.py mutations` from `specs/content/mutations.md`; 60 icons; Anvil, Cage, EscortNpc (48, walk/idle/hurt/death) sprites; Ascension choice icons for the first T1 set. Accept: review approved; `test_assets.gd` icon coverage.
- [ ] W7-A9 `[art-audio]` SFX: weapon skill trigger x5 types, anvil, channel loop, recall, cage open, escort hurt, level-up/mastery. Accept: review approved.

### Checkpoint: Week 7 end
- [ ] Every W7 `[art-audio]` task has an approved review sheet in `docs/asset-review/week-7/` (or a dated polish-list entry); `build_all.py --check` clean
- [ ] 38 nodes buyable with effects; 10 weapons + 60 mutations; 6 T1 Ascensions; rescue flow; `week-7` tagged

---

## Week 8: Biomes 2 and 3

**Done when:** Enemies, hazards, mini-bosses, bosses for Fungal Caverns and Crystal Hollows, 40 relics, synergies.

### Dev A
- [ ] W8-A1 `[biomes]` Fungal Caverns: `BiomeData` (Iron, lore floor 9), 5 enemies, hazards, and flavor adjustments.
- [ ] W8-A2 `[bosses]` Sporelord Twins and Bloom Mother, with teamfight and environment hooks.
- [ ] W8-A3 `[biomes]` Crystal Hollows: `BiomeData` (Crystal, lore 14), 4 enemies and hazards.
- [ ] W8-A4 `[bosses]` Gem Collector and Prism Queen, with reflective beam and crystal state logic.
- [ ] W8-A5 `[biomes]` Biome 2/3 lore pages and rare drops plus hidden-room markers.
- [ ] W8-A6 `[art-audio]` Fungal Caverns pass: `gen_tiles.py fungal_caverns` (+ spore vent, bouncy mushroom, darkness zone hazards), Shroomling, Spore Spitter, Mycel Brute, Glow Moth, Root Strangler sheets, Sporelord Twins (96 x2) and Bloom Mother (192) sheets, `spore_fog.gdshader`, lore page prop. Accept: review sheets + floor and arena captures approved; palette locked.
- [ ] W8-A7 `[art-audio]` Crystal Hollows pass: `gen_tiles.py crystal_hollows` (+ reflective crystal, beam pillar hazards), Shard Golem, Prism Bat, Geode Turtle, Crystal Mimic sheets, Gem Collector (96 mech) and Prism Queen (192 + mirror copy tint) sheets, `crystal_refract.gdshader`, hidden-room wall marker. Accept: review approved; palette locked.
- [ ] W8-A8 `[art-audio]` SFX: spore, beam, crystal shatter, split, grab, blind, mimic reveal, 4 boss roars/phases, footsteps fungal + crystal. Accept: review approved.

### Dev B
- [ ] W8-B1 `[relics]` Relics 21 to 42 minus two, reaching 40 with actives and harness cases each.
- [ ] W8-B2 `[relics]` `SynergyData` x12 + effects, `SynergyTracker` (recompute on pick/remove), `synergy_activated`, HUD progress pips and active glow.
- [ ] W8-B3 `[relics]` Codex data for relics seen/picked into profile; Relic Vault codex view v1 in town.
- [ ] W8-B4 `[story-dialogue]` Act 2 flags and lore JSON, NPC lines and hints for the new zones.
- [ ] W8-B5 `[networking]` Co-op soak session with simulated latency, fix list triaged into issues.
- [ ] W8-B6 `[art-audio]` Relic icons 21 to 40 (incl. active relic icons with charge pips), 12 synergy icons + HUD progress pips + active glow texture, Relic Vault codex view theme. Accept: review approved; icon coverage test.
- [ ] W8-B7 `[art-audio]` Music: Fungal Caverns and Crystal Hollows tracks, Bloom Mother and Prism Queen themes; Act 2 NPC portrait expressions (2 per NPC where dialogue needs them). Accept: credited; crossfade verified.

### Checkpoint: Week 8 end
- [ ] Every W8 `[art-audio]` task has an approved review sheet in `docs/asset-review/week-8/` (or a dated polish-list entry); `build_all.py --check` clean
- [ ] Biomes 1 to 3 playable; 40 relics; 12 synergies active; `week-8` tagged

---

## Week 9: Biomes 4 and 5

**Done when:** Drowned City and Ember Forge with all enemies and bosses, all 19 weapons, all 30 abilities, characters 2 to 4, Rogue, Necromancer, Engineer, Lightbearer.

### Dev A
- [ ] W9-A1 `[biomes]` Drowned City: `BiomeData` (Pearl, lore 19), 5 enemies, hazards, and water-state interactions.
- [ ] W9-A2 `[bosses]` Captain Saltbones and Tide King, with water-level and cannon-crew behavior.
- [ ] W9-A3 `[biomes]` Ember Forge: `BiomeData` (Ember Ore, lore 24), 5 enemies, hazards, and heat conditions.
- [ ] W9-A4 `[bosses]` Iron Maiden and Old Vulkar, with forge-state and weapon-rune damage loops.
- [ ] W9-A5 `[weapons]` Remaining 9 main weapons and affix coverage.
- [ ] W9-A6 `[abilities]` Remaining 20 abilities + harness cases (all schools incl. Earth, Blood, Void, Utility).
- [ ] W9-A7 `[abilities]` Character ultimates and class twist scripts for all 7 classes.
- [ ] W9-A8 `[classes-characters]` Additional characters and 28 combos selectable.
- [ ] W9-A9 `[classes-characters]` Support character unlock flags and affix hooks.
- [ ] W9-A10 `[art-audio]` Drowned City pass: `gen_tiles.py drowned_city` (+ deep water, current, rising water tile states), Deepkin, Eel Lurker, Drowned Priest, Barnacle Crab, Siren sheets, Captain Saltbones (96 + cannon crew 32) and Tide King (192 + throne) sheets, `water_distort.gdshader`. Accept: review approved; palette locked.
- [ ] W9-A11 `[art-audio]` Ember Forge pass: `gen_tiles.py ember_forge` (+ lava river, conveyor, molten pour, steam vent), Forge Imp, Slag Golem, Bellows Drone, Clockwork Sentry, Ashen Smith sheets, Iron Maiden (96, 3 mode sheets) and Old Vulkar (192, forged-weapon props) sheets, `heat_haze.gdshader`. Accept: review approved; palette locked.
- [ ] W9-A12 `[art-audio]` Brann, Ivy, Kestrel body sheets + 5 weapon-type attack sheets each; 9 remaining weapon sprites + icons + projectiles; 20 ability icons + emitters; character and class ultimate emitters (all 7 classes). Accept: review approved; every `AbilityData`, `WeaponData`, `CharacterData` asset field resolves.
- [ ] W9-A13 `[art-audio]` SFX: remaining cast schools (Earth, Blood, Void, Utility), class skills x4, hazards water/lava/steam, 4 boss cues, footsteps drowned + ember, Siren pull, cannon. Accept: review approved.

### Dev B
- [ ] W9-B1 `[story-dialogue]` Rescue data and Act 2 dialogue for all NPCs; Biome 4/5 lore.
- [ ] W9-B2 `[ui-hud]` Class resource bars, Ascension popup polish, minion/turret count HUD, boss bar with phase markers.
- [ ] W9-B3 `[town]` Training Grounds v1; Relic Vault pick + Rune Library pick (level 2 behaviors).
- [ ] W9-B4 `[networking]` 4-instance soak on two machines with simulated lag; external playtest round 1 notes filed.
- [ ] W9-B5 `[art-audio]` Class resource bars x7, boss bar with phase markers, minion/turret HUD counters, Training Grounds dummies (32, hurt/death) + DPS panel theme, Rune Library and Relic Vault L2 states, Brann/Ivy/Kestrel portraits. Accept: review approved.
- [ ] W9-B6 `[art-audio]` Music: Drowned City and Ember Forge tracks, Tide King and Old Vulkar themes; SFX: class select UI, Ascension popup. Accept: credited; crossfade verified.

### Checkpoint: Week 9 end
- [ ] Every W9 `[art-audio]` task has an approved review sheet in `docs/asset-review/week-9/` (or a dated polish-list entry); `build_all.py --check` clean
- [ ] Biomes 1 to 5; 19 weapons; 30 abilities; 7 classes T1; 4 characters; external playtest 1 notes; `week-9` tagged

---

## Week 10: Biome 6 + final boss + story

**Done when:** The Heart, The Hollow You, The Sinkhole 3-phase fight, all 3 endings, all NPC dialogue, Lore rooms and 40+ lore pages.

### Dev A
- [ ] W10-A1 `[biomes]` The Heart: `BiomeData` (Heartstone, lore 29), corrupted pool, Veinling, Heart Guard, and hazard hooks.
- [ ] W10-A2 `[bosses]` The Hollow You, with build snapshot APIs consumed and enemy-side effects.
- [ ] W10-A3 `[bosses]` The Sinkhole phases 1 and 2, plus phase 3 hook to story resolution logic and duel variants.
- [ ] W10-A4 `[floor-generation]` Biome 6 generation quirks and floor 30 arena; 500-seed test over all 6 real biomes.
- [ ] W10-A5 `[art-audio]` The Heart pass: `gen_tiles.py the_heart` (+ spike wall, breathing floor, shrinking room edge), Veinling, Heart Guard, Echo sheets, `corrupted.gdshader` palette swap verified on all 24 prior enemies, The Hollow You (player sheets + corrupted shader + dark aura emitter), The Sinkhole phases 1 to 3 (192; phase 3 size ask-first), `phase_transition` frames, `portal` emitter. Accept: review approved; palette locked.
- [ ] W10-A6 `[art-audio]` SFX: spike, pulse, shrink, Veinling drain, Echo copy, Hollow You cues, Sinkhole phase 1 to 3 cues, final death; footsteps heart. Accept: review approved.

### Dev B
- [ ] W10-B1 `[story-dialogue]` Act 3 flags and all NPC dialogue through Act 3 and endings.
- [ ] W10-B2 `[story-dialogue]` `final_choice(context)` ending logic (Seal, Keeper, True gated on Watcher + all lore), 3 ending dialogue sequences + scripted scenes, `ending.*` flags.
- [ ] W10-B3 `[story-dialogue]` Lore to 40+ (Biome 6 + preceding journals), codex screen.
- [ ] W10-B4 `[ui-hud]` Victory screen, boss name banners, ending credits roll.
- [ ] W10-B5 `[town]` Pit edge stages 1 to 3 and ending visuals; Rescue Camp with rescued miner NPCs.
- [ ] W10-B6 `[art-audio]` Victory screen, boss name banners, ending credits roll theme (renders `CREDITS.md` attribution), pit edge stages 1 to 3, Rescue Camp + rescued miner sprites x3 variants, 3 ending scene art (static 960x540 pixel illustrations from generators + palette), codex screen theme. Accept: review approved.
- [ ] W10-B7 `[art-audio]` Music: The Heart track, The Sinkhole final boss track, victory, death, credits; `vignette_darkness.gdshader`. Accept: 17/17 tracks present; credited; loop points set.

### Checkpoint: Week 10 end
- [ ] Every W10 `[art-audio]` task has an approved review sheet in `docs/asset-review/week-10/` (or a dated polish-list entry); `build_all.py --check` clean
- [ ] Full 30-floor run to each ending in co-op (debug skips allowed); all dialogue; 40+ lore; `week-10` tagged

---

## Week 11: Content and endgame

**Done when:** Tier 2 Ascensions and all class trees, class pair bonuses, all 88 relics, Cursed Altars, Challenge rooms, Secret rooms, all 120 mutations, secret bosses, Deep Mode, heat levels, all final UI and economic tuning.

### Dev A
- [ ] W11-A1 `[classes-characters]` 14 Tier 2 Ascension effects and alternate class skill logic.
- [ ] W11-A2 `[classes-characters]` Class tree node data for all 7, node effects + harness, alternate class skills at mastery 5, `ClassPairData` effects.
- [ ] W11-A3 `[weapons]` Leviathan's Tooth + 6 mutations; remaining mutations to 120.
- [ ] W11-A4 `[abilities]` Alternate ultimates and final class-specific ultimate unlock flows.
- [ ] W11-A5 `[floor-generation]` CHALLENGE, SECRET, CURSED_ALTAR placement and generation edge cases.
- [ ] W11-A6 `[bosses]` Secret bosses and hideout triggers.
- [ ] W11-A7 `[enemies-ai]` Deep Mode extra attack pool per biome and heat-phase data for all bosses.
- [ ] W11-A8 `[art-audio]` Leviathan's Tooth sprite + icon + 6 mutation icons; mutation icons to 120; Rat King (96), Mushroom Hermit (96), Leviathan (192), Watcher (192) sheets + hideout triggers (hidden wall, golden spore, fishing rod, well eye); Cursed Altar, Challenge and Secret room props; Deep Mode extra attack `special_<n>` frames per boss; alternate ultimate emitters; T2 Ascension icons. Accept: review approved; `test_assets.gd` asserts 16 bosses, 27 enemies, 20 weapons, 120 mutations, 30 abilities.
- [ ] W11-A9 `[art-audio]` SFX: secret boss cues x4, cursed altar, challenge start/pass/fail, secret room reveal, deep mode toggle; any missing combat id from the full SFX list. Accept: `SfxBank` has no placeholder among Pit-lane ids.

### Dev B
- [ ] W11-B1 `[relics]` Relics to 88: Movement, Economy, Transformation (13 Legendary), fillers, remaining actives (8), 8 cursed; `CursedAltar` interactable.
- [ ] W11-B2 `[progression-trees]` Class tree tabs + purchase with Class XP, `MasteryScreen`, `Progression.class_rank`.
- [ ] W11-B3 `[town]` All 11 buildings x 3 levels with sprites and effects: Blacksmith tiers, Alchemist types/starting, Map Room L3, Shrine L3, Tavern lobby/daily board, Relic Vault, Rune Library, and final town progression.
- [ ] W11-B4 `[endgame]` Deep Mode (toggle, boss deep phases, deep attacks, loot shift, x1.5 Echo, final mode gating), 10 `HeatModifier` effects with multipliers.
- [ ] W11-B5 `[endgame]` Daily Dive (date seed, fixed setup from unlocked-at-start content, one attempt, score, local leaderboard 30 days, share code), 50+ `AchievementData` + `AchievementTracker`.
- [ ] W11-B6 `[ui-hud]` Achievements list screen, Daily Dive board widget, heat selection UI, Wardrobe grid, Bounty Board UI.
- [ ] W11-B7 `[art-audio]` Relic icons to 88 (13 Legendary frames, 8 cursed), all 11 buildings x L1 to L3 states (44 total), 50+ achievement icons (32x32), Daily Dive board, heat selection, Wardrobe grid + cosmetic sprites (boss hats/skins as overlay sheets), Bounty Board theme, `MasteryScreen` and class tree tab icons for 7 classes. Accept: review approved; `test_assets.gd` asserts 88 relic icons, 44 building states, achievement icon coverage.
- [ ] W11-B8 `[art-audio]` SFX: achievement unlock, daily start, heat up/down, wardrobe equip, bounty complete, codex unlock; any missing UI id from the full SFX list. Accept: `SfxBank` has no placeholder among Surface-lane ids.

### Checkpoint: Week 11 end
- [ ] Every W11 `[art-audio]` task has an approved review sheet in `docs/asset-review/week-11/` (or a dated polish-list entry); `build_all.py --check` clean
- [ ] Every design doc count met in data tests; `week-11` tagged

---

## Week 12: Polish

**Done when:** Final art/audio/VFX pass, balancing, co-op bug fixing, achievements, settings, external playtests.

### Dev A
- [ ] W12-A1 `[stats-status]`/`[weapons]` Balance pass: damage golden file review with Dev B, weapon feel on Training Grounds, enemy HP/damage curve, boss timings.
- [ ] W12-A2 `[art-audio]` Final in-engine visual pass: stacked 4-player build captured in every biome; readability fixes (silhouette, telegraph frames, VFX clutter) as parameter edits + re-run; every element, ability, relic proc has a distinct VFX verified from the `vfx` console.
- [ ] W12-A3 `[networking]` Co-op bug fixing from playtests (Dev A's modules). Accept: issue list closed or deferred with notes.
- [ ] W12-A4 `[art-audio]` Pit-lane polish list: every item rejected twice in weeks 2 to 11 redone and re-reviewed; remaining VFX ids (`relic_proc_<tag>` tints checked per element, `room_clear`, `level_up`, `pickup_sparkle` variants); `build_all.py --check` clean; `docs/asset-review/INDEX.md` shows no `pending` Pit entries.

### Dev B
- [ ] W12-B1 `[ui-hud]` Settings: audio buses, video (window, scale, vsync), screen shake, damage numbers toggle, full key rebinding with conflict detection, controller deadzone; persisted.
- [ ] W12-B2 `[progression-trees]`/`[town]`/`[run-economy]` Economy tuning: tree total in 25 to 40 runs, town ore costs matched, Echo curve, shop prices (`economy.md`).
- [ ] W12-B3 `[debug-tools]` Release export preset excluding `scripts/debug/`, Windows export verified, debug console absent in export.
- [ ] W12-B4 `[networking]` Co-op bug fixing (Dev B's modules), simulated-latency pass.
- [ ] W12-B5 `[art-audio]` Surface-lane polish list: every item rejected twice redone and re-reviewed; settings screen theme; master audio pass (all SFX -16 LUFS short-term, music -14 LUFS, bus defaults); `CREDITS.md` audited against `assets/` by `test_credits.gd`; credits roll shows every CC-BY row; `docs/asset-review/INDEX.md` shows no `pending` entries.

### Both
- [ ] W12-AB1 `[art-audio]` Final asset sign-off: full SFX list and 17 tracks present, every icon and portrait count met, `CREDITS.md` complete and rendered in the credits roll, `build_all.py --check` and `pytest tools/` clean, polish list empty.
- [ ] W12-AB2 External playtest round 2 (5+ people), 4-player 30-floor run on two or more machines, final WEEKLY entry, `week-12` tag, SPEC-project success criteria all checked.

### Checkpoint: Complete
- [ ] Asset inventory in SPEC-art-audio fully present; `test_assets.gd`, `test_credits.gd`, `test_palette.gd` green; no `pending` in `docs/asset-review/INDEX.md`
- [ ] All SPEC-project success criteria checked
- [ ] Every module in CAPABILITY_MAP status `done` or dated cut-list entry (expected: none)
- [ ] Ready for release
