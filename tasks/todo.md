# Sinkhole task list

Lanes: **A** = Dev A (Pit lane), **B** = Dev B (Systems lane), **AB** = both. Module ids from `specs/CAPABILITY_MAP.md`. Branch name: `feat/<module-id>-<task-id-lowercase>-<short-desc>`.

Week 1 is fully detailed. Weeks 2 to 12 are listed with brief acceptance and are expanded into the week 1 format at the start of each week.

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
- [ ] Design doc week 1 "Done when" met and recorded
- [ ] CI green on `main`
- [ ] Both developers pulled `main` and ran the two-instance smoke on their own machine

**Verification:**
- [ ] `git tag week-1` pushed
- [ ] `specs/WEEKLY.md` entry present

**Dependencies:** all W1 tasks
**Files likely touched:** `specs/WEEKLY.md`, `specs/SPEC-foundation.md`
**Estimated scope:** XS

## Checkpoint: Week 1 day 2
- [ ] W1-B1, W1-B2, W1-B3, W1-B4, W1-B5, W1-A1, W1-A2 merged
- [ ] Import zero warnings, CI green on an empty-content PR
- [ ] Both developers' editors open the project clean

## Checkpoint: Week 1 day 4
- [ ] W1-B6, W1-B7, W1-B8, W1-A3, W1-A4, W1-A5 merged
- [ ] `--host` + `--join` connect; two `Player` nodes visible on both screens

## Checkpoint: Week 1 end
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

### Dev B
- [ ] W2-B1 `[time-manager]` `scale_for`, groups, slow/stop stack, per-entity scale, `hit_stop`, `timer`, RPC broadcast of effects. Accept: spec API; players unaffected by enemy slow.
- [ ] W2-B2 `[stats-status]` `StatBlock` (11 stats, flat then percent, handles, `remove_source`, clamps, MAX_HP ratio) + `Damage.compute` + golden file. Accept: spec formula.
- [ ] W2-B3 `[networking]` Enemy and projectile `MultiplayerSpawner`s under `World/Entities`, `StateSync` on enemy base (position, anim, HP), host-only hit resolution verified. Accept: client sees state.
- [ ] W2-B4 `[debug-tools]` Debug console UI + parser + `register()`, core commands (`spawn`, `give`, `gold`, `skip` stub, `seed`, `god`, `kill`, `heal`, `timestop`, `fps`, `dump`), request commands to host.
- [ ] W2-B5 `[ui-hud]` HUD v0: own HP bar, teammate HP bars, weapon slots, floor label placeholder; `HudModel` adapter bound to replicated state; `Theme` v0 with pixel font. Accept: visible in test room.
- [ ] W2-B6 `[art-audio]` `AudioManager` real implementation (two-player crossfade, pooled SFX, buses), `SfxBank` with placeholder clicks for the week 2 SFX ids.

### Checkpoint: Week 2 end
- [ ] Two-instance smoke steps 1 to 3; manual feel pass recorded; all W2 tests green; `week-2` tagged

---

## Week 3: Floor generation

**Done when:** Procedural floors with Start, Combat, Elite Combat, Treasure, Rope, Exit rooms, locking combat rooms, seed sync for co-op, downed/revive.

### Dev A
- [ ] W3-A1 `[floor-generation]` `FloorGenerator.generate()` steps 1 to 5 (seeded RNG only, room placement with retries, MST + loops, L corridors, type assignment, painting, walkable data, `AStarGrid2D` pathing).
- [ ] W3-A2 `[floor-generation]` `Floor` scene (`paint`, `Room` nodes, `Door` nodes, `room_at`), door lock on enter, `room_cleared`, Exit rule, placeholder START/EXIT/ROPE markers.
- [ ] W3-A3 `[floor-generation]` Populator registry + 500-seed soak test across placeholder biomes (reachability flood fill, exit reachable, counts, rope on floor 2, no overlaps, corridor width).
- [ ] W3-A4 `[enemies-ai]` `SpawnDirector.fill_room` v1 (budget by floor, single wave, no spawn near players) registered as COMBAT/ELITE_COMBAT populator.
- [ ] W3-A5 `[player-controller]` `Downed` and `Dead` states, bleed-out 30 s, hold-F revive to 40% (3 s, `revive_speed_mult`), solo skips to Dead, `Interactable` component and nearest-interactable query.

### Dev B
- [ ] W3-B1 `[run-economy]` `GameState` real: `RunState`, `RunPlayerState`, `start_run`, `next_floor`, `end_run`, `RunResult`, `run_started`/`floor_changed`/`run_ended` signals; floor advance threshold states.
- [ ] W3-B2 `[run-economy]` ROPE populator + `Rope` interactable (solo immediate extract), run end on all players downed/dead (`DEFEAT`), placeholder death/extract summary print.
- [ ] W3-B3 `[networking]` `floor_ready(seed, floor_index, biome_id, modifiers)` broadcast, client local generation, hash assertion with host-layout fallback, `--seed` arg plumbed.
- [ ] W3-B4 `[networking]` Downed/revive sync: `request_revive`, `player_downed`/`player_revived` broadcast, StateSync of downed flag.
- [ ] W3-B5 `[debug-tools]` `skip`, `floor <n>`, `seed` wired to GameState; `net_lag` placeholder.

### Checkpoint: Week 3 end
- [ ] 500-seed test green in CI; two-instance smoke steps 1 to 5; floor hashes match; `week-3` tagged

---

## Week 4: Effect system + loot

**Done when:** Events bus, StatBlock, TimeManager, status effects, element combos, 20 relics, Shrine rooms, elites with affixes, gold/ore/Echo drops.

### Dev B
- [ ] W4-B1 `[effect-system]` `Events` full signal set from spec, emitted by owning modules.
- [ ] W4-B2 `[effect-system]` `Effect` base (attach/detach, `listen`, `every_seconds`, `once_per_room`, `modify`, `spawn`, `deal_damage`, `apply_status`, `chance`, `fire_projectile`), `EffectHost` and event dispatch.
- [ ] W4-B3 `[effect-system]` Proc limits (depth 3, no self-retrigger, 64/frame cap), trigger test harness + template test, duplication rule.
- [ ] W4-B4 `[stats-status]` `StatusEffects` component with 7 statuses and stacking rules, 6 combos, Elementalist/Reactive multiplier hooks, boss resistance field.
- [ ] W4-B5 `[relics]` `RelicData`, `RelicRoller` (rarity weights, Luck, no cursed at shrines, max_stacks), `Shrine` interactable + SHRINE populator, `request_pick_relic`, `relic_picked`, codex workflow.
- [ ] W4-B6 `[relics]` 20 relics: On Dodge 1 to 6, On Hit 7 to 14, On Kill 15 to 20 (`.tres` + effect scripts + harness case each).
- [ ] W4-B7 `[relics]` `ActiveRelicController` slot 1 (C), charges, cooldown, HUD hook (actives themselves arrive week 8).
- [ ] W4-B8 `[run-economy]` Currencies: `Pickup` scene + magnet, `LootTable`, gold/ore/echo drops from `EnemyData.loot_table`, chests, breakables, mining hooks.
- [ ] W4-B9 `[time-manager]` `slow_enemies`/`stop_enemies` consumers, `register_rewindable`/`rewind`, broadcast of entity effects; `timestop` console command verified in co-op.
- [ ] W4-B10 `[ui-hud]` `ChoicePopup` (relic 1-of-3 with tags and rarity colors), relic icon strip with stacks, currencies, `Minimap` from `FloorLayout`, status icons.
- [ ] W4-B11 `[debug-tools]` Perf scene (60 units, 4 fake players, 128 emitters, FPS log), `net_lag` real implementation, effect overlay.

### Dev A
- [ ] W4-A1 `[enemies-ai]` Elites: outline shader, +100% HP, 6 affixes with behaviors, `elite_killed`.
- [ ] W4-A2 `[enemies-ai]` `SpawnDirector` v2: waves (1 to 3, next at 40%), elite chance by floor, Double Elites hook, `EnemyPool`, off-room processing pause, spatial-hash separation perf.
- [ ] W4-A3 `[floor-generation]` SHRINE room placement rule (1 per floor) + interactable anchor; ELITE_COMBAT counts by floor.
- [ ] W4-A4 `[combat-core]` Emit `hit_landed`, `crit_landed`, `player_damaged`, `heavy_attack_released`, `weapon_swapped`, `projectile_fired`; `enemy_killed`, `enemy_spawned`; `player_dodged` and related events.
- [ ] W4-A5 `[weapons]` Blacksmith damage tier hook and `Stat.ATTACK` wiring through `Damage.compute`.

### Checkpoint: Week 4 end
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

### Dev B
- [ ] W5-B1 `[save-system]` `SaveManager` (debounced atomic save, `.bak`, load with migrations, corrupt recovery), `PlayerProfile` with all fields and `defaults()`, `merge_run_gains`.
- [ ] W5-B2 `[run-economy]` Rope votes (all living, downed excluded, `no` cancels, solo immediate) via `request_vote_rope`/`rope_vote_updated`; death vs extract table per currency.
- [ ] W5-B3 `[run-economy]` Map Room start floors (`start_floor`, Ascension timing flags), SHOP populator + `Shopkeeper`, `PotionController` (heal, slots, E key), relic room hooks.
- [ ] W5-B4 `[town]` `town.tscn` v1 (walkable hub, pit edge stage 0, 11 `Building` nodes at level 0 signs, 3 functional: Blacksmith buy weapons, Shrine of Echoes entry stub, Tavern Dive), `Building` container and flow.
- [ ] W5-B5 `[town]` `RunSetup` flow (character, class, 2 weapons, start floor, ready per player) feeding `GameState.start_run` with `PlayerSpawnInfo`.
- [ ] W5-B6 `[ui-hud]` Main menu (Solo, Host, Join with IP, Settings stub, Codex stub, Quit), pause overlay, run/inventory screen (Tab), rope vote prompt, death screen from `RunResult`, town menu interactions.

### Checkpoint: Week 5 end (mid-project gate is end of week 6)
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

### Dev B
- [ ] W6-B1 `[story-dialogue]` `StoryManager` (flags with namespaces, `flags.json` declaration, `act()`, `evaluate()` condition language, `unlock_lore`), `DialogueData` loader from JSON with schema validation.
- [ ] W6-B2 `[story-dialogue]` `DialogueBox` UI (portrait, name, typewriter, choices, per-player in town), `start_dialogue`, `LorePage` pickup + LORE populator, codex list stub.
- [ ] W6-B3 `[story-dialogue]` Act 1 content: early NPC lines + forum topics + boss-defeated reactions; story flags and progression hooks.
- [ ] W6-B4 `[town]` NPC nodes with `start_dialogue`, Alchemist (slots, heal potion), Map Room (start at reached ropes, next-floor modifier preview), building level sprites x4 states, pit edge staging.
- [ ] W6-B5 `[run-economy]` Shop and Rest room interactables polished, currency scaling by biome.

### Both
- [ ] W6-AB1 `[art-audio]` First real assets: player 8-dir sheet, Biome 1 tiles, music placeholder loop, core SFX set; art source decisions recorded.

### Checkpoint: Week 6 end (mid-project gate)
- [ ] Biome 1 playable end to end in co-op with relics, abilities, 3 classes, town, story, save; if slipped > 3 days, team meets on cut list; `week-6` tagged

---

## Week 7: Skill tree + weapons + Ascensions

**Done when:** Full skill tree UI and all branches, 10 weapons, anvil rooms with mutations, Ascensions for the first 3 classes, class XP and mastery, rescue mission system.

### Dev B
- [ ] W7-B1 `[progression-trees]` `SkillNodeData` + 38 node `.tres` with `requires`, `ui_position`, costs; `Progression` static (`rank`, `can_buy`, `buy`, `respec`, daily rule); Abyss gate on completion.
- [ ] W7-B2 `[progression-trees]` 38 node effects (`Effect` scripts: stat nodes via `modify`, behavior nodes for dodge/timing/utility), `Progression` graph logic.
- [ ] W7-B3 `[progression-trees]` `SkillTreeScreen` (pan/zoom canvas, nodes with rank pips, `Line2D` edges, locked/purchasable/bought states, tooltip, branch tabs) opened from Shrine of Echoes and town flow.
- [ ] W7-B4 `[story-dialogue]` Rescue missions: `rescues.json`, `Cage` interactable placed by generator hook, escort spawn via `EscortNpc`, rope-reach logic, reward flow.

### Dev A
- [ ] W7-A1 `[weapons]` Weapon skill trigger (perfect window + heavy, 6 s cooldown), `Channel` state for hold attacks, thrown/recall projectile support, `WaterTile`, `SoulOrb`, `lit` flag.
- [ ] W7-A2 `[weapons]` 8 more weapons to reach 10: Longsword, Twin Daggers, Sledgehammer, Shortbow, Hand Cannon, Spore Tome, Chain Whip, Grave Scythe (scene, `.tres`, skill, affinity tags).
- [ ] W7-A3 `[weapons]` `MutationData`, `Anvil` interactable + ANVIL populator, mutation attach as `Effect`, `specs/content/mutations.md` started; 60 mutations for the 10 weapons.
- [ ] W7-A4 `[classes-characters]` Ascension choice flow (after floor 5 boss or at start if deeper; duplicate rejection via host; `ascension_chosen`), Tier 1 Ascensions for a first set of classes.
- [ ] W7-A5 `[classes-characters]` Class XP earn hooks (kills, floors, bosses by biome) into `RunPlayerState`, mastery thresholds, `class_xp_gained`; skill data and progression integration.
- [ ] W7-A6 `[enemies-ai]` `EscortNpc` (follow 64 px, Health, flee, teleport catch-up, death fails rescue).

### Checkpoint: Week 7 end
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

### Dev B
- [ ] W8-B1 `[relics]` Relics 21 to 42 minus two, reaching 40 with actives and harness cases each.
- [ ] W8-B2 `[relics]` `SynergyData` x12 + effects, `SynergyTracker` (recompute on pick/remove), `synergy_activated`, HUD progress pips and active glow.
- [ ] W8-B3 `[relics]` Codex data for relics seen/picked into profile; Relic Vault codex view v1 in town.
- [ ] W8-B4 `[story-dialogue]` Act 2 flags and lore JSON, NPC lines and hints for the new zones.
- [ ] W8-B5 `[networking]` Co-op soak session with simulated latency, fix list triaged into issues.

### Checkpoint: Week 8 end
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

### Dev B
- [ ] W9-B1 `[story-dialogue]` Rescue data and Act 2 dialogue for all NPCs; Biome 4/5 lore.
- [ ] W9-B2 `[ui-hud]` Class resource bars, Ascension popup polish, minion/turret count HUD, boss bar with phase markers.
- [ ] W9-B3 `[town]` Training Grounds v1; Relic Vault pick + Rune Library pick (level 2 behaviors).
- [ ] W9-B4 `[networking]` 4-instance soak on two machines with simulated lag; external playtest round 1 notes filed.

### Checkpoint: Week 9 end
- [ ] Biomes 1 to 5; 19 weapons; 30 abilities; 7 classes T1; 4 characters; external playtest 1 notes; `week-9` tagged

---

## Week 10: Biome 6 + final boss + story

**Done when:** The Heart, The Hollow You, The Sinkhole 3-phase fight, all 3 endings, all NPC dialogue, Lore rooms and 40+ lore pages.

### Dev A
- [ ] W10-A1 `[biomes]` The Heart: `BiomeData` (Heartstone, lore 29), corrupted pool, Veinling, Heart Guard, and hazard hooks.
- [ ] W10-A2 `[bosses]` The Hollow You, with build snapshot APIs consumed and enemy-side effects.
- [ ] W10-A3 `[bosses]` The Sinkhole phases 1 and 2, plus phase 3 hook to story resolution logic and duel variants.
- [ ] W10-A4 `[floor-generation]` Biome 6 generation quirks and floor 30 arena; 500-seed test over all 6 real biomes.

### Dev B
- [ ] W10-B1 `[story-dialogue]` Act 3 flags and all NPC dialogue through Act 3 and endings.
- [ ] W10-B2 `[story-dialogue]` `final_choice(context)` ending logic (Seal, Keeper, True gated on Watcher + all lore), 3 ending dialogue sequences + scripted scenes, `ending.*` flags.
- [ ] W10-B3 `[story-dialogue]` Lore to 40+ (Biome 6 + preceding journals), codex screen.
- [ ] W10-B4 `[ui-hud]` Victory screen, boss name banners, ending credits roll.
- [ ] W10-B5 `[town]` Pit edge stages 1 to 3 and ending visuals; Rescue Camp with rescued miner NPCs.

### Checkpoint: Week 10 end
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

### Dev B
- [ ] W11-B1 `[relics]` Relics to 88: Movement, Economy, Transformation (13 Legendary), fillers, remaining actives (8), 8 cursed; `CursedAltar` interactable.
- [ ] W11-B2 `[progression-trees]` Class tree tabs + purchase with Class XP, `MasteryScreen`, `Progression.class_rank`.
- [ ] W11-B3 `[town]` All 11 buildings x 3 levels with sprites and effects: Blacksmith tiers, Alchemist types/starting, Map Room L3, Shrine L3, Tavern lobby/daily board, Relic Vault, Rune Library, and final town progression.
- [ ] W11-B4 `[endgame]` Deep Mode (toggle, boss deep phases, deep attacks, loot shift, x1.5 Echo, final mode gating), 10 `HeatModifier` effects with multipliers.
- [ ] W11-B5 `[endgame]` Daily Dive (date seed, fixed setup from unlocked-at-start content, one attempt, score, local leaderboard 30 days, share code), 50+ `AchievementData` + `AchievementTracker`.
- [ ] W11-B6 `[ui-hud]` Achievements list screen, Daily Dive board widget, heat selection UI, Wardrobe grid, Bounty Board UI.

### Checkpoint: Week 11 end
- [ ] Every design doc count met in data tests; `week-11` tagged

---

## Week 12: Polish

**Done when:** Final art/audio/VFX pass, balancing, co-op bug fixing, achievements, settings, external playtests.

### Dev A
- [ ] W12-A1 `[stats-status]`/`[weapons]` Balance pass: damage golden file review with Dev B, weapon feel on Training Grounds, enemy HP/damage curve, boss timings.
- [ ] W12-A2 `[art-audio]` Final enemy, boss, biome tile art per priority list; VFX per element/ability/relic proc complete.
- [ ] W12-A3 `[networking]` Co-op bug fixing from playtests (Dev A's modules). Accept: issue list closed or deferred with notes.

### Dev B
- [ ] W12-B1 `[ui-hud]` Settings: audio buses, video (window, scale, vsync), screen shake, damage numbers toggle, full key rebinding with conflict detection, controller deadzone; persisted.
- [ ] W12-B2 `[progression-trees]`/`[town]`/`[run-economy]` Economy tuning: tree total in 25 to 40 runs, town ore costs matched, Echo curve, shop prices (`economy.md`).
- [ ] W12-B3 `[debug-tools]` Release export preset excluding `scripts/debug/`, Windows export verified, debug console absent in export.
- [ ] W12-B4 `[networking]` Co-op bug fixing (Dev B's modules), simulated-latency pass.

### Both
- [ ] W12-AB1 `[art-audio]` Final music tracks, full SFX list, portraits, icons, `CREDITS.md`.
- [ ] W12-AB2 External playtest round 2 (5+ people), 4-player 30-floor run on two or more machines, final WEEKLY entry, `week-12` tag, SPEC-project success criteria all checked.

### Checkpoint: Complete
- [ ] All SPEC-project success criteria checked
- [ ] Every module in CAPABILITY_MAP status `done` or dated cut-list entry (expected: none)
- [ ] Ready for release
