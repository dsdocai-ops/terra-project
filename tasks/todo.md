# Sinkhole task list

Lanes: **A** = Alex (Dev A, The Pit), **B** = Daniel (Dev B, Surface + Systems), **AB** = both. Module ids from `specs/CAPABILITY_MAP.md`. Branch name: `feat/<module-id>-<task-id-lowercase>-<short>`. Every task ships its tests in the same PR (SPEC-project). Shared systems (`scripts/autoload/`, `scripts/components/`, `scripts/data/`, `project.godot`, `.github/`, `addons/`) need the other developer's review.

Week 1 is fully detailed. Weeks 2 to 12 are listed with brief acceptance and are expanded into the week 1 format at the start of each week.

---

## Week 1: Foundation + networking

**Done when:** Isometric TileSet, Y-sort, player movement, camera. 2 players can connect and see each other move (host + client).

### Dev B (Daniel)

## Task W1-B1: Project settings and folder tree

**Module:** `foundation`
**Description:** Set every `project.godot` value from the SPEC-foundation settings table (960x540, canvas_items, keep, integer, gl_compatibility both methods, nearest filter, 2D pixel snap both, 60 physics ticks, `untyped_declaration` Error, `inferred_declaration` Warn, `unsafe_*` Warn, debugger char limit raised). Create the full folder tree from SPEC-project with a `.gdkeep` in each empty folder.

**Acceptance criteria:**
- [ ] `project.godot` matches the SPEC-foundation table line for line
- [ ] Every folder under `scenes/`, `scripts/`, `data/`, `assets/`, `tests/` from SPEC-project exists
- [ ] Headless import produces zero warnings and zero errors

**Verification:**
- [ ] `godot --headless --path . --import` exits 0 with no warnings
- [ ] Manual: editor opens, viewport 960x540, test window 1920x1080 shows integer-scaled crisp pixels on a placeholder sprite

**Dependencies:** None
**Files likely touched:** `project.godot`, `*/.gdkeep`
**Estimated scope:** S

## Task W1-B2: Input Map

**Module:** `foundation`
**Description:** Add every action from the SPEC-foundation Input Map table with its keyboard/mouse binding and a controller binding. Movement is four actions; no deadzone tuning yet.

**Acceptance criteria:**
- [ ] All 24 action names exist exactly as spelled in SPEC-foundation
- [ ] Each gameplay action has one keyboard/mouse and one controller event
- [ ] `debug_console` bound to backtick

**Verification:**
- [ ] `tests/unit/test_input_map.gd`: asserts `InputMap.has_action()` for every name in a constant list and that each has at least 2 events
- [ ] Manual: Input Map panel shows controller icons next to each

**Dependencies:** W1-B1
**Files likely touched:** `project.godot`, `tests/unit/test_input_map.gd`
**Estimated scope:** S

## Task W1-B3: Autoload stubs and ContentData base

**Module:** `foundation`
**Description:** Create the 7 autoload scripts in SPEC-foundation order (`Events`, `TimeManager`, `GameState`, `SaveManager`, `StoryManager`, `AudioManager`, `NetworkManager`) with the public API shapes from their module specs, every method typed and bodied with `pass` or a trivial return, doc comment naming the owning module and the Sync line. Register them. Create `scripts/data/content_data.gd` (`ContentData extends Resource` with `id`, `display_name`, `tags`, `effect_script`, `icon`, `vfx_id`, `sfx_id`).

**Acceptance criteria:**
- [ ] All 7 autoloads registered in the specified order and reachable by name from a test
- [ ] Each stub exposes every signal, constant, and method named in its spec's "Interfaces provided" block, fully typed
- [ ] `ContentData` loads and a test `.tres` extending it round-trips

**Verification:**
- [ ] `tests/unit/test_autoloads.gd`: each autoload is non-null and `has_method()` for every spec method
- [ ] Import exits 0 with `untyped_declaration` as Error

**Dependencies:** W1-B1
**Files likely touched:** `scripts/autoload/*.gd` (7), `scripts/data/content_data.gd`, `project.godot`, `tests/unit/test_autoloads.gd`
**Estimated scope:** M

## Task W1-B4: GUT and test skeleton

**Module:** `foundation`
**Description:** Vendor the latest GUT 9.x release compatible with 4.7 into `addons/gut/`, enable the plugin, add `tests/unit/`, `tests/integration/`, `tests/helpers/`, write `test_scenes_load.gd` (instantiates every `.tscn` under `scenes/`) and `test_data_loads.gd` (loads every `.tres` under `data/`, asserts `id` equals filename when it extends `ContentData`). Confirm the SPEC-project test command runs headless and exits non-zero on a failing test. Record the GUT version in SPEC-foundation.

**Acceptance criteria:**
- [ ] `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` exits 0
- [ ] A deliberately failing test makes it exit non-zero (then removed)
- [ ] `test_scenes_load` and `test_data_loads` pass on the current tree

**Verification:**
- [ ] Run the command above twice: once green, once with the failing test
- [ ] SPEC-foundation open question for GUT version resolved

**Dependencies:** W1-B1
**Files likely touched:** `addons/gut/**`, `project.godot`, `tests/integration/test_scenes_load.gd`, `tests/integration/test_data_loads.gd`, `specs/SPEC-foundation.md`
**Estimated scope:** M

## Task W1-B5: CI workflow

**Module:** `foundation`
**Description:** `.github/workflows/ci.yml` on `pull_request` and `push` to `main`: check out, install Godot 4.7.2 headless (verify the chosen setup action publishes 4.7.2, else download the official Linux headless zip by URL), run `--import`, run the GUT command, fail on non-zero. Target under 5 minutes. Record the action choice in SPEC-foundation.

**Acceptance criteria:**
- [ ] A PR shows a CI status check that passes on the current tree
- [ ] A PR with a failing test shows red
- [ ] Runtime under 5 minutes

**Verification:**
- [ ] Open a throwaway PR with a failing test, observe red, fix, observe green
- [ ] SPEC-foundation open question for the setup action resolved

**Dependencies:** W1-B4
**Files likely touched:** `.github/workflows/ci.yml`, `specs/SPEC-foundation.md`
**Estimated scope:** S

## Task W1-B6: Main scene and launch args

**Module:** `foundation`
**Description:** `scenes/main/main.tscn` + `main.gd` as the project main scene. Parses `OS.get_cmdline_user_args()` for `--host`, `--join=<ip>`, `--seed=<int>`; sets `GameState.world` after loading `world.tscn`; with no args shows a placeholder menu with Host and Join (IP field) buttons that call `NetworkManager`. Not the real main menu (that is `ui-hud` week 5).

**Acceptance criteria:**
- [ ] `godot --path . -- --host` reaches the world scene with no menu
- [ ] `godot --path . -- --join=127.0.0.1` attempts a join with no menu
- [ ] No args shows the placeholder menu; Host button works

**Verification:**
- [ ] `tests/unit/test_launch_args.gd`: arg parser function returns the right struct for each arg combination
- [ ] Manual: launch each variant

**Dependencies:** W1-B1, W1-B3 (NetworkManager stub), W1-A3 (world scene path; can use a placeholder until A3 lands)
**Files likely touched:** `scenes/main/main.tscn`, `scenes/main/main.gd`, `project.godot` (main_scene), `tests/unit/test_launch_args.gd`
**Estimated scope:** S

## Task W1-B7: NetworkManager host, join, peer tracking

**Module:** `networking`
**Description:** Replace the stub with the real `NetworkManager`: `host(port)`, `join(ip, port)`, `start_solo()`, `disconnect_all()`, `is_host`, `local_peer_id`, `peer_ids`, `players`, `player_count()`, `enemy_hp_multiplier()`, constants, signals `player_joined`, `player_left`, `connection_failed`, `host_disconnected`. ENet, port 7777, max 4. Solo is a host with one peer.

**Acceptance criteria:**
- [ ] Two instances on one machine connect; host logs `player_joined(peer_id)`; client logs connection
- [ ] Closing the client fires `player_left` on host; closing the host fires `host_disconnected` on client
- [ ] `start_solo()` sets `is_host` true with `peer_ids == [1]`

**Verification:**
- [ ] `tests/unit/test_network_manager.gd`: `enemy_hp_multiplier()` for 1 to 4 players (1.0, 1.5, 2.0, 2.5), `start_solo()` state
- [ ] Manual two-instance connect/disconnect via W1-B6 args

**Dependencies:** W1-B3, W1-B6
**Files likely touched:** `scripts/autoload/network_manager.gd`, `tests/unit/test_network_manager.gd`
**Estimated scope:** M

## Task W1-B8: Player spawning through MultiplayerSpawner

**Module:** `networking`
**Description:** `MultiplayerSpawner` under `World/Players` with the player scene registered. On `player_joined` (and for the host itself at world load), the host calls `spawn()` with a `PlayerSpawnInfo` dictionary (`peer_id`, placeholder `character_id`, `class_id`, `weapon_ids`). Spawned player gets `peer_id` set and `is_local` computed. `NetworkManager.players` filled as spawns complete. Uses Alex's `player.tscn` from W1-A4.

**Acceptance criteria:**
- [ ] Host and one client each see two `Player` nodes under `World/Players` with distinct `peer_id`
- [ ] Late joiner sees existing players; existing players see the late joiner
- [ ] Leaving removes the node on all peers

**Verification:**
- [ ] `tests/unit/test_spawn_info.gd`: `PlayerSpawnInfo` to/from dictionary round trip
- [ ] Manual two-instance: spawn, late join (start client after host has been running), leave

**Dependencies:** W1-B7, W1-A4
**Files likely touched:** `scenes/main/world.tscn` (Players spawner node; coordinate with Alex, owner), `scripts/network/player_spawn_info.gd`, `scripts/autoload/network_manager.gd`, `tests/unit/test_spawn_info.gd`
**Estimated scope:** M

## Task W1-B9: InputSync and StateSync configuration

**Module:** `networking` (PR into Alex's `player.tscn`, Alex reviews)
**Description:** Configure the two `MultiplayerSynchronizer` nodes Alex placed in `player.tscn` (W1-A4). `InputSync`: authority = owning peer, replicates `move_input: Vector2`, `aim_position: Vector2`, pressed-action bitmask, to host. `StateSync`: authority = host (1), replicates `position`, `velocity`, `facing_index`, animation name, to all. Set per-peer authority in the spawn path from W1-B8. Document the convention in `player.gd` doc comment ("Sync:" line).

**Acceptance criteria:**
- [ ] Client input moves the client's player on the host
- [ ] Host position updates appear on the client for both players
- [ ] A third instance joining sees both others moving

**Verification:**
- [ ] Manual three-instance test (host + 2 clients) with `tools/run_two.ps1` extended to accept a count
- [ ] Grep check: `player.gd` doc comment contains "Sync:"

**Dependencies:** W1-B8, W1-A4, W1-A6
**Files likely touched:** `scenes/player/player.tscn`, `scenes/player/player.gd`, `scripts/autoload/network_manager.gd`
**Estimated scope:** S

## Task W1-B10: Two-instance launcher

**Module:** `debug-tools` (pulled forward from week 2 because week 1 smoke needs it)
**Description:** `tools/run_two.ps1` and `tools/run_two.sh` launching `--host` and `--join=127.0.0.1` with windows positioned side by side, optional count for more clients. Configure Godot's Debug > "Run Multiple Instances" with the same args so F5 works too. Document in SPEC-project commands.

**Acceptance criteria:**
- [ ] Running the script opens two windows that connect
- [ ] F5 in the editor with multi-instance enabled does the same

**Verification:**
- [ ] Manual run of both paths

**Dependencies:** W1-B6, W1-B7
**Files likely touched:** `tools/run_two.ps1`, `tools/run_two.sh`, `specs/SPEC-project.md`
**Estimated scope:** XS

### Dev A (Alex)

## Task W1-A1: Iso helper

**Module:** `foundation`
**Description:** `scripts/iso.gd` static class `Iso` with `to_screen(tile: Vector2i) -> Vector2`, `to_tile(screen: Vector2) -> Vector2i`, `input_to_world(dir: Vector2) -> Vector2` for 64x32 diamond-down tiles. `input_to_world` rotates WASD onto the isometric axes and normalizes so diagonal and cardinal moves have equal on-screen speed.

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
**Description:** `assets/tilesets/placeholder_iso.tres`: TileSet, Isometric shape, Diamond Down layout, 64x32, atlas with floor, wall, pit tiles in flat colors, physics layer on walls, custom data layer `walkable: bool`. `tools/make_placeholders.gd` EditorScript generating the atlas PNG, a colored diamond sprite with a facing arrow for 8 directions, and lettered 16x16 icons. Import preset `pixel` (nearest, no mipmaps, lossless) applied to `assets/`.

**Acceptance criteria:**
- [ ] TileSet has the three tiles, walls collide, `walkable` is true on floor and false on wall/pit
- [ ] Generator runs from the editor and writes PNGs with correct sizes
- [ ] Imported textures use nearest filtering

**Verification:**
- [ ] `tests/unit/test_tileset.gd`: tile count, custom data values, physics layer present
- [ ] Manual: 20x20 diamond renders crisp at 1920x1080

**Dependencies:** W1-B1 (folders)
**Files likely touched:** `assets/tilesets/placeholder_iso.tres`, `assets/tilesets/placeholder/*.png`, `tools/make_placeholders.gd`, `assets/.import presets`, `tests/unit/test_tileset.gd`
**Estimated scope:** M

## Task W1-A3: World scene

**Module:** `foundation`
**Description:** `scenes/main/world.tscn` per SPEC-foundation: `World` (Y-sort) with `Floor` and `Walls` `TileMapLayer`s, `Entities` (Y-sort), `Players`, `Camera`, `FX`. A 20x20 test floor with a wall ring painted so week 1 has somewhere to walk. `world.gd` exposes typed references to the child nodes for `GameState.world`.

**Acceptance criteria:**
- [ ] Node layout matches the spec; `Players` is ready to receive a `MultiplayerSpawner` (W1-B8)
- [ ] Walls block movement; Y-sort orders a test sprite behind and in front of a wall correctly
- [ ] Scene instantiates headless

**Verification:**
- [ ] `test_scenes_load` passes with `world.tscn` present
- [ ] Manual: walk a placeholder sprite around the wall ring

**Dependencies:** W1-A2
**Files likely touched:** `scenes/main/world.tscn`, `scenes/main/world.gd`
**Estimated scope:** S

## Task W1-A4: Player scene skeleton

**Module:** `player-controller`
**Description:** `scenes/player/player.tscn` + `player.gd` with the composition from SPEC-player-controller: `CharacterBody2D` root, placeholder child nodes for `StatBlock`, `Health`, `Hurtbox`, `StatusEffects` (empty `Node`s named for later weeks), `StateMachine`, `Sprite` (`AnimatedSprite2D` with the placeholder diamond), `WeaponPivot`, `InputSync`, `StateSync` (empty `MultiplayerSynchronizer`s for W1-B9), `InteractArea`. `Player` exposes the spec's fields and signals (`peer_id`, `is_local`, `facing`, `facing_index`, `aim_position`, `dodge_charges`, etc.) with typed defaults. Doc comment with "Sync:" line.

**Acceptance criteria:**
- [ ] Scene instantiates headless; every node in the spec layout exists by name
- [ ] `Player` has every public field and signal from the spec's "Interfaces provided", typed
- [ ] `is_local` is `peer_id == multiplayer.get_unique_id()`

**Verification:**
- [ ] `tests/unit/test_player_scene.gd`: node names present, fields exist
- [ ] `test_scenes_load` passes

**Dependencies:** W1-A3
**Files likely touched:** `scenes/player/player.tscn`, `scenes/player/player.gd`, `tests/unit/test_player_scene.gd`
**Estimated scope:** S

## Task W1-A5: StateMachine and State components, Idle and Move

**Modules:** `player-controller` (component is shared under `scripts/components/`, Daniel reviews)
**Description:** `scripts/components/state_machine.gd` and `state.gd`: node-based, `change_to(name)` with states able to refuse, `enter`, `exit`, `physics_update(delta)`, `handle_input`. Player states `Idle` and `Move` under `scenes/player/states/`. Scaled delta hook left as a pass-through for `TimeManager` (week 2).

**Acceptance criteria:**
- [ ] `change_to` calls `exit` then `enter`, emits `state_changed`
- [ ] A state returning false from `can_exit()` blocks the transition
- [ ] Player starts in `Idle`, moves to `Move` on input, back to `Idle` when input stops

**Verification:**
- [ ] `tests/unit/test_state_machine.gd`: transitions, refusal, signal
- [ ] Manual: state label overlay shows Idle/Move switching

**Dependencies:** W1-A4
**Files likely touched:** `scripts/components/state_machine.gd`, `scripts/components/state.gd`, `scenes/player/states/idle.gd`, `scenes/player/states/move.gd`, `tests/unit/test_state_machine.gd`
**Estimated scope:** M

## Task W1-A6: Isometric movement and facing

**Module:** `player-controller`
**Description:** In `Move`: read the four `move_*` actions into a vector, pass through `Iso.input_to_world()`, accelerate to full speed in ~4 frames, friction to stop, base speed 120 px/s constant (StatBlock hookup in week 2). Facing: 8-direction `facing_index` from aim vector (mouse) when attacking later, from move vector now; `play_directional(anim)` picks `<anim>_<dir>`. Placeholder animations `idle_<dir>`, `walk_<dir>` from the diamond+arrow sprites. Local player only reads input; remote players are driven by `StateSync` (W1-B9).

**Acceptance criteria:**
- [ ] WASD moves along isometric axes; all 8 directions have equal on-screen speed
- [ ] Facing index updates in 8 sectors with no flicker at boundaries (hysteresis of a few degrees)
- [ ] Remote player instances do not read local input

**Verification:**
- [ ] `tests/unit/test_player_facing.gd`: vector to index for all 8 sectors and boundary cases
- [ ] Manual feel check: snappy start/stop, no diagonal speed-up

**Dependencies:** W1-A1, W1-A5
**Files likely touched:** `scenes/player/states/move.gd`, `scenes/player/states/idle.gd`, `scenes/player/player.gd`, `tests/unit/test_player_facing.gd`
**Estimated scope:** M

## Task W1-A7: Game camera

**Module:** `player-controller`
**Description:** `scenes/main/camera.gd` on `World/Camera`: `set_targets(players)`, position smoothing (~8), follows the local player in solo; with multiple targets frames the centroid and zooms out until all fit with 96 px margin, zoom clamped 1.0 to 0.6, movement clamped to camera bounds so no one leaves the frame. `shake(strength, duration)` trauma-based, reads a `screen_shake` setting (default 1.0). 

**Acceptance criteria:**
- [ ] Solo: camera follows smoothly without pixel jitter at integer scale
- [ ] Two players walking apart zoom the camera out to 0.6 then clamp movement at the edges
- [ ] `shake(5, 0.3)` visibly shakes and settles

**Verification:**
- [ ] `tests/unit/test_camera_framing.gd`: zoom math for given target spreads, clamp bounds
- [ ] Manual two-instance: walk apart, confirm clamp on both screens

**Dependencies:** W1-A3, W1-A6
**Files likely touched:** `scenes/main/camera.gd`, `scenes/main/world.tscn`, `tests/unit/test_camera_framing.gd`
**Estimated scope:** M

### Both

## Task W1-AB1: Client prediction, correction, and two-instance smoke

**Modules:** `networking`, `player-controller`
**Description:** Local player moves immediately from its own input; host simulates the same input; `StateSync` position corrects drift on the client with a small lerp (snap if error > 64 px). Remote players interpolate between synced positions. Run the SPEC-networking two-instance smoke steps 1 and 2 (connect, both visible moving and facing). Record results in the PR.

**Acceptance criteria:**
- [ ] At 0 ms latency, no visible correction on the local player
- [ ] Remote players move smoothly (no stutter at 20 Hz sync rate)
- [ ] Facing and animation match on both screens

**Verification:**
- [ ] Manual two-instance smoke, steps 1 and 2, recorded in the PR
- [ ] Three-instance sanity via `run_two.ps1 -Clients 2`

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
- [ ] All W1 tasks merged; `test_iso`, `test_player_facing`, `test_state_machine`, `test_camera_framing`, `test_network_manager`, `test_scenes_load`, `test_data_loads`, `test_autoloads`, `test_input_map` green
- [ ] Two-instance smoke steps 1 and 2 pass; `week-1` tagged

---

## Week 2: Combat core

**Done when:** Light/heavy attacks, dodge, weapon swap, Health/Hitbox/Hurtbox components, 3 enemies with telegraphs, all synced in co-op.

### Dev A
- [ ] W2-A1 `[combat-core]` `Health`, `Hitbox`, `Hurtbox`, `HitInfo`, `StatusApplication`, `Team`. Accept: components on player; `about_to_die` prevention hook; from-behind angle; host-only `receive`. Verify: `test_health`, `test_hit_info`. Deps: W1-A4, W2-B2. Scope: M
- [ ] W2-A2 `[combat-core]` `AttackController`: light combo with step reset and input buffer, heavy charge/release, tap heavy, swap with lockout, attack speed scale. Accept: spec behaviors. Verify: `test_attack_controller`. Deps: W2-A1, W2-A7. Scope: M
- [ ] W2-A3 `[combat-core]` Hit reactions: `HitStun` state, knockback impulse with wall block, 0.4 s player i-frames. Accept: spec values. Verify: scripted hit test. Deps: W2-A1. Scope: S
- [ ] W2-A4 `[combat-core]` Hit feedback: `hit_flash.gdshader`, camera shake tiers, `TimeManager.hit_stop` calls, `DamageNumberPool` (128) in `World/FX`. Accept: visible on every hit; crits distinct. Verify: pool stays allocation-free after warmup. Deps: W2-A1, W2-B1, W1-A7. Scope: M
- [ ] W2-A5 `[combat-core]` `AttackPattern` Resource + `Telegraph` scene (circle, cone, line, ring, fill over windup) + windup/active/recovery driver. Accept: no hit without telegraph; CI test asserts windup >= 0.2. Verify: `test_attack_pattern`. Deps: W2-A1. Scope: M
- [ ] W2-A6 `[combat-core]` `Projectile` base + `ProjectilePool` (pierce, bounce, homing, lifetime, reflectable, time-scaled). Accept: 500 pooled projectiles no allocs. Verify: perf check, `test_projectile`. Deps: W2-A1, W2-B1. Scope: M
- [ ] W2-A7 `[weapons]` `WeaponData`, `AttackSpec`, `WeaponController`, `WeaponAttack` base, Pickaxe and Crossbow scenes and `.tres`. Accept: light/heavy/swap on both; ground crack line; charged piercing bolt. Verify: `test_weapon_data`, `test_weapon_controller`. Deps: W2-A2, W2-A6. Scope: M
- [ ] W2-A8 `[player-controller]` Dodge roll with i-frames, cooldown from stat, perfect-dodge window (0.12 s blocked-hit detection via Hurtbox), `dodge_charges`, `reset_dodge_cooldown()`. Accept: `Events.player_dodged(player, perfect)` only when a hit was blocked. Verify: `test_dodge_timing`. Deps: W2-A1, W2-B2. Scope: M
- [ ] W2-A9 `[enemies-ai]` `enemy_base.tscn`, `EnemyData`, standard states, `Targeting`, grid or nav pathfinding (decide, record in spec), separation via spatial hash, time-scaled movement. Accept: enemy chases nearest player around walls. Verify: `test_targeting`, `test_enemy_data`. Deps: W2-A1, W2-A5, W2-B1. Scope: M
- [ ] W2-A10 `[enemies-ai]` Hollow Miner, Rock Tick, Lantern Wisp `.tres`, states, attack patterns, placeholder sprites. Accept: each attacks through windup/active/recovery; Wisp fires pooled fireballs. Verify: data test, manual. Deps: W2-A9, W2-A6. Scope: M

### Dev B
- [ ] W2-B1 `[time-manager]` `scale_for`, groups, slow/stop stack, per-entity scale, `hit_stop`, `timer`, RPC broadcast of effects. Accept: spec API; players unaffected by enemy slow. Verify: `test_time_manager`; CI grep for `Engine.time_scale`. Deps: W1-B3. Scope: M
- [ ] W2-B2 `[stats-status]` `StatBlock` (11 stats, flat then percent, handles, `remove_source`, clamps, MAX_HP ratio) + `Damage.compute` + golden file. Accept: spec formula. Verify: `test_stat_block`, `test_damage`, `damage_table.json`. Deps: W1-B3. Scope: M
- [ ] W2-B3 `[networking]` Enemy and projectile `MultiplayerSpawner`s under `World/Entities`, `StateSync` on enemy base (position, anim, HP), host-only hit resolution verified. Accept: client sees enemies move, take damage, die once. Verify: two-instance smoke step 3. Deps: W2-A9, W2-A6. Scope: S
- [ ] W2-B4 `[debug-tools]` Debug console UI + parser + `register()`, core commands (`spawn`, `give`, `gold`, `skip` stub, `seed`, `god`, `kill`, `heal`, `timestop`, `fps`, `dump`), `request_debug` RPC, excluded from release export. Accept: commands work from client and host. Verify: `test_console_parser`. Deps: W1-B7, W2-A9. Scope: M
- [ ] W2-B5 `[ui-hud]` HUD v0: own HP bar, teammate HP bars, weapon slots, floor label placeholder; `HudModel` adapter bound to replicated state; `Theme` v0 with pixel font (decide CC0 font). Accept: HUD correct on client after host-side damage. Verify: `test_hud_model`, `test_ui_scenes`. Deps: W2-A1, W2-A7. Scope: M
- [ ] W2-B6 `[art-audio]` `AudioManager` real implementation (two-player crossfade, pooled SFX, buses), `SfxBank` with placeholder clicks for the week 2 SFX ids (hit per weapon type, dodge, enemy hurt/death). Accept: `play_sfx("hit_blade")` plays. Verify: `test_audio_manager`. Deps: W1-B3. Scope: S

### Checkpoint: Week 2 end
- [ ] Two-instance smoke steps 1 to 3; manual feel pass recorded; all W2 tests green; `week-2` tagged

---

## Week 3: Floor generation

**Done when:** Procedural floors with Start, Combat, Elite Combat, Treasure, Rope, Exit rooms, locking combat rooms, seed sync for co-op, downed/revive.

### Dev A
- [ ] W3-A1 `[floor-generation]` `FloorGenerator.generate()` steps 1 to 5 (seeded RNG only, room placement with retries, MST + loops, L corridors, type assignment, painting, walkable data, `AStarGrid2D`), `FloorLayout`, `RoomSpec`, `layout_hash`. Accept: identical hash for same inputs. Verify: `test_room_rules`, determinism test. Deps: W1-A2, W1-A3. Scope: M
- [ ] W3-A2 `[floor-generation]` `Floor` scene (`paint`, `Room` nodes, `Door` nodes, `room_at`), door lock on enter, `room_cleared`, Exit rule, placeholder START/EXIT/ROPE markers. Accept: combat doors lock until clear; exit opens per rule. Verify: `test_exit_rule`, manual. Deps: W3-A1. Scope: M
- [ ] W3-A3 `[floor-generation]` Populator registry + 500-seed soak test across placeholder biomes (reachability flood fill, exit reachable, counts, rope on floor 2, no overlaps, corridor width) under 60 s. Accept: test green in CI. Verify: `test_floor_generation_seeds`. Deps: W3-A2. Scope: S
- [ ] W3-A4 `[enemies-ai]` `SpawnDirector.fill_room` v1 (budget by floor, single wave, no spawn near players) registered as COMBAT/ELITE_COMBAT populator. Accept: rooms fill deterministically from seed. Verify: `test_spawn_director` v1. Deps: W3-A2, W2-A10. Scope: S
- [ ] W3-A5 `[player-controller]` `Downed` and `Dead` states, bleed-out 30 s, hold-F revive to 40% (3 s, `revive_speed_mult`), solo skips to Dead, `Interactable` component and nearest-interactable prompt hook. Accept: spec behaviors. Verify: state tests, manual. Deps: W2-A1, W2-A8. Scope: M

### Dev B
- [ ] W3-B1 `[run-economy]` `GameState` real: `RunState`, `RunPlayerState`, `start_run`, `next_floor`, `end_run`, `RunResult`, `run_started`/`floor_changed`/`run_ended` signals; floor advance through EXIT. Accept: run flows floor 1 to 3 in solo. Verify: `test_game_state`. Deps: W1-B3, W3-A2. Scope: M
- [ ] W3-B2 `[run-economy]` ROPE populator + `Rope` interactable (solo immediate extract), run end on all players downed/dead (`DEFEAT`), placeholder death/extract summary print. Accept: spec. Verify: integration run. Deps: W3-B1, W3-A5. Scope: S
- [ ] W3-B3 `[networking]` `floor_ready(seed, floor_index, biome_id, modifiers)` broadcast, client local generation, hash assertion with host-layout fallback, `--seed` arg plumbed. Accept: 20 manual floors hash-match; mismatch path logs and recovers. Verify: two-instance, unit test of assertion logic. Deps: W3-A1, W3-B1. Scope: M
- [ ] W3-B4 `[networking]` Downed/revive sync: `request_revive`, `player_downed`/`player_revived` broadcast, StateSync of downed flag. Accept: two-instance smoke step 5. Verify: manual. Deps: W3-A5. Scope: S
- [ ] W3-B5 `[debug-tools]` `skip`, `floor <n>`, `seed` wired to GameState; `net_lag` placeholder. Accept: commands work. Verify: manual. Deps: W3-B1. Scope: XS

### Checkpoint: Week 3 end
- [ ] 500-seed test green in CI; two-instance smoke steps 1 to 5; floor hashes match; `week-3` tagged

---

## Week 4: Effect system + loot

**Done when:** Events bus, StatBlock, TimeManager, status effects, element combos, 20 relics, Shrine rooms, elites with affixes, gold/ore/Echo drops.

### Dev B
- [ ] W4-B1 `[effect-system]` `Events` full signal set from spec, emitted by owning modules (coordinate the combat/movement/enemy emitters with Alex via small PRs). Accept: every signal in spec exists and fires. Verify: `test_events_emitted` with fakes. Deps: W2-*, W3-*. Scope: M
- [ ] W4-B2 `[effect-system]` `Effect` base (attach/detach, `listen`, `every_seconds`, `once_per_room`, `modify`, `spawn`, `deal_damage`, `apply_status`, `chance`, `fire_projectile`), `EffectHost`, `Tags`, FX spawner for effect results. Accept: spec API; clean detach. Verify: `test_effect_base`. Deps: W4-B1, W2-B2, W2-B1. Scope: M
- [ ] W4-B3 `[effect-system]` Proc limits (depth 3, no self-retrigger, 64/frame cap), trigger test harness `tests/helpers/effect_harness.gd` + template test, Mimic Crown duplication rule. Accept: pathological chain stops. Verify: `test_proc_limits`, `test_tags`. Deps: W4-B2. Scope: S
- [ ] W4-B4 `[stats-status]` `StatusEffects` component with 7 statuses and stacking rules, 6 combos, Elementalist/Reactive multiplier hooks, boss resistance field, client tint/icon replication. Accept: every table row. Verify: `test_status_effects`, `test_combos`. Deps: W2-B2, W4-B1. Scope: M
- [ ] W4-B5 `[relics]` `RelicData`, `RelicRoller` (rarity weights, Luck, no cursed at shrines, max_stacks), `Shrine` interactable + SHRINE populator, `request_pick_relic`, `relic_picked`, codex write. Accept: 1-of-3 flow in co-op. Verify: `test_relic_roller`, two-instance. Deps: W4-B2, W4-A3. Scope: M
- [ ] W4-B6 `[relics]` 20 relics: On Dodge 1 to 6, On Hit 7 to 14, On Kill 15 to 20 (`.tres` + effect scripts + harness case each). Accept: data test + 20 harness cases. Verify: `test_relic_data`, `test_relic_triggers`. Deps: W4-B5, W4-B3. Scope: L (split into two PRs of 10)
- [ ] W4-B7 `[relics]` `ActiveRelicController` slot 1 (C), charges, cooldown, HUD hook (actives themselves arrive week 8). Accept: API ready, slot UI shows empty. Verify: unit. Deps: W4-B5. Scope: S
- [ ] W4-B8 `[run-economy]` Currencies: `Pickup` scene + magnet, `LootTable`, gold/ore/echo drops from `EnemyData.loot_table`, chests (3 tiers) and TREASURE populator, breakables, `MiningNode`, elite and floor-clear Echo payouts, shared vs per-player visibility. Accept: spec table. Verify: `test_loot_table`, `test_echo_shards`, two-instance. Deps: W3-B1, W4-A1. Scope: L (split: pickups+tables / chests+nodes+payouts)
- [ ] W4-B9 `[time-manager]` `slow_enemies`/`stop_enemies` consumers, `register_rewindable`/`rewind`, broadcast of entity effects; `timestop` console command verified in co-op. Accept: smoke step 6. Verify: two-instance. Deps: W2-B1. Scope: S
- [ ] W4-B10 `[ui-hud]` `ChoicePopup` (relic 1-of-3 with tags and rarity colors), relic icon strip with stacks, currencies, `Minimap` from `FloorLayout`, status icons. Accept: client popup confirms via host. Verify: `test_ui_scenes`, two-instance. Deps: W4-B5, W3-A1. Scope: M
- [ ] W4-B11 `[debug-tools]` Perf scene (60 units, 4 fake players, 128 emitters, FPS log), `net_lag` real implementation (decide approach), effect overlay (active effects, last 20 procs with depth). Accept: perf numbers logged; overlay lists procs. Verify: manual, recorded in WEEKLY. Deps: W4-B3, W4-A2. Scope: M

### Dev A
- [ ] W4-A1 `[enemies-ai]` Elites: outline shader, +100% HP, 6 affixes with behaviors, `elite_killed`. Accept: each affix per table. Verify: `test_affixes`. Deps: W2-A9. Scope: M
- [ ] W4-A2 `[enemies-ai]` `SpawnDirector` v2: waves (1 to 3, next at 40%), elite chance by floor, Double Elites hook, `EnemyPool`, off-room processing pause, spatial-hash separation perf. Accept: 60 units at 60 FPS in perf scene. Verify: `test_spawn_director`, `test_pooling`, perf. Deps: W3-A4, W4-A1. Scope: M
- [ ] W4-A3 `[floor-generation]` SHRINE room placement rule (1 per floor) + interactable anchor; ELITE_COMBAT counts by floor. Accept: 500-seed test updated. Verify: CI. Deps: W3-A3. Scope: XS
- [ ] W4-A4 `[combat-core]` Emit `hit_landed`, `crit_landed`, `player_damaged`, `heavy_attack_released`, `weapon_swapped`, `projectile_fired`; `enemy_killed`, `enemy_spawned`; `player_dodged` into the real `Events`. Accept: harness can drive relics from real combat. Verify: `test_events_emitted`. Deps: W4-B1. Scope: S
- [ ] W4-A5 `[weapons]` Blacksmith damage tier hook and `Stat.ATTACK` wiring through `Damage.compute` (replace week 2 constants with StatBlock reads across player/enemies). Accept: golden file unchanged. Verify: tests. Deps: W2-B2. Scope: S

### Checkpoint: Week 4 end
- [ ] Pathological proc build holds 60 FPS; 20 relics harness-tested and co-op checked; smoke steps 1 to 6; perf numbers in WEEKLY; `week-4` tagged

---

## Week 5: Abilities + classes v1 + extraction

**Done when:** Ability system with 10 abilities, Rune rooms, ultimates, class system with Warrior, Ranger, Mage (passives + class skills), rope points and votes, death rules, town v1, save/load.

### Dev A
- [ ] W5-A1 `[abilities]` `AbilityData`, `AbilityRank`, `AbilityController` (2 slots, cooldown with CDR, charges, rank-up by duplicate, rank-3 to gold, stored runes, `request_cast`), `AbilityCast` base, `Zone`, `RuneStone` pickup + RUNE populator + `AbilitySwapStation` in Shrine rooms. Accept: spec. Verify: `test_ability_controller`, `test_ability_data`. Deps: W4-B2, W2-A6. Scope: M
- [ ] W5-A2 `[abilities]` 10 abilities: Meteor Call, Flame Dash, Glacier Spike, Chain Lightning, Thunder Step, Shadow Clones, Toxic Cloud, Stone Skin, Black Hole, Barrier Dome (+ harness case each). Accept: data + 10 harness cases; Barrier Dome blocks projectiles for allies in co-op. Verify: tests, two-instance. Deps: W5-A1, W4-A2 (FriendlyUnit base for clones). Scope: L (two PRs of 5)
- [ ] W5-A3 `[abilities]` `UltimateController` meter (deal/take rates, Spite Totem x3), `ultimate` input, Cave-In ultimate. Accept: meter fills, Cave-In stuns room. Verify: `test_ultimate_meter`. Deps: W5-A1. Scope: S
- [ ] W5-A4 `[classes-characters]` `ClassData`, `AscensionData`, `CharacterData`, `ClassPairData`, `ClassTreeNodeData` definitions; `ClassController` (passive attach, affinity attach/detach, class skill on Shift with cooldown, class resource, `request_class_skill`); `SelectionState` validation. Accept: spec API. Verify: `test_class_data` skeleton. Deps: W4-B2, W2-A7. Scope: M
- [ ] W5-A5 `[classes-characters]` Warrior (Rage, Battle Cry, affinity heavy charge), Ranger (Far Shot, Tumble Volley, +1 pierce), Mage (Arcane Flow, Blink, double element) + Wren (ore +25%, breakable walls flag, Cave-In). Accept: each passive/skill harness case; playable. Verify: harness, manual solo and co-op. Deps: W5-A4, W5-A3. Scope: L (one PR per class)
- [ ] W5-A6 `[weapons]` `affinity_active_changed` signal, `"affinity"` hit tag, Lantern Staff `.tres` (third starting weapon) so Mage has an affinity weapon. Accept: Mage double-element with Lantern Staff. Verify: harness. Deps: W5-A4. Scope: S
- [ ] W5-A7 `[enemies-ai]` `FriendlyUnit` base (`owner_player`, lifetime, follow, Team.PLAYER) for Shadow Clones now and minions later. Accept: clones copy attacks for duration. Verify: unit. Deps: W2-A9. Scope: S

### Dev B
- [ ] W5-B1 `[save-system]` `SaveManager` (debounced atomic save, `.bak`, load with migrations, corrupt recovery), `PlayerProfile` with all fields and `defaults()`, `merge_run_gains`. Accept: round trip, recovery. Verify: `test_save_round_trip`, `test_save_migrations`, `test_save_recovery`. Deps: W1-B3. Scope: M
- [ ] W5-B2 `[run-economy]` Rope votes (all living, downed excluded, `no` cancels, solo immediate) via `request_vote_rope`/`rope_vote_updated`; death vs extract table per currency incl. node hooks; co-op split; `run_summary` per peer; banking into profile; save on return to town. Accept: table rows. Verify: `test_death_rules`, `test_vote`, two-instance. Deps: W5-B1, W3-B2. Scope: M
- [ ] W5-B3 `[run-economy]` Map Room start floors (`start_floor`, Ascension timing flags), SHOP populator + `Shopkeeper` (4 items, prices, Vesper 10%), `PotionController` (heal, slots, E key), REST populator (heal or upgrade). Accept: spec. Verify: unit + manual. Deps: W5-B2. Scope: M
- [ ] W5-B4 `[town]` `town.tscn` v1 (walkable hub, pit edge stage 0, 11 `Building` nodes at level 0 signs, 3 functional: Blacksmith buy weapons, Shrine of Echoes entry stub, Tavern Dive), `BuildingData` with costs, purchase flow writing profile. Accept: buy Longsword with gold, persists. Verify: `test_town_data`, `test_building_purchase`. Deps: W5-B1. Scope: M
- [ ] W5-B5 `[town]` `RunSetup` flow (character, class, 2 weapons, start floor, ready per player) feeding `GameState.start_run` with `PlayerSpawnInfo`. Accept: 3 classes selectable, co-op ready gate. Verify: two-instance. Deps: W5-B4, W5-A4. Scope: S
- [ ] W5-B6 `[ui-hud]` Main menu (Solo, Host, Join with IP, Settings stub, Codex stub, Quit), pause overlay, run/inventory screen (Tab), rope vote prompt, death screen from `RunResult`, town menus v1 widgets, ability/ultimate/class resource HUD elements. Accept: all screens reachable. Verify: `test_ui_scenes`, manual. Deps: W5-B2, W5-A1. Scope: L (two PRs: menus / run screens)

### Checkpoint: Week 5 end (mid-project gate is end of week 6)
- [ ] Full loop: town, select, dive, floors, shrine, rune, rope vote, extract or die, bank, town; save survives restart; co-op end to end; `week-5` tagged

---

## Week 6: Biome 1 complete + story base

**Done when:** All Biome 1 enemies, Boomer Jack, The Foreman, dialogue system, first NPCs and story flags, Shop rooms, Rest rooms.

### Dev A
- [ ] W6-A1 `[biomes]` `BiomeData` + Collapsed Mines `.tres` (floor 1 to 5, Copper, room sizes, palette, ambient light, lore floor 4), Biome 1 tileset wired, `CanvasModulate` + player `PointLight2D` + torch pooling (16 cap). Accept: Biome 1 lighting on Compatibility at 60 FPS. Verify: `test_biome_data`. Deps: W3-A2. Scope: M
- [ ] W6-A2 `[biomes]` Dynamite Goblin, Cave Bat Swarm (flyer) + hazards: falling rocks, mine cart, gas pocket (Fire ignition via `gas` flag). Accept: spec behaviors. Verify: data tests, `test_hazards`. Deps: W6-A1, W4-B4. Scope: M
- [ ] W6-A3 `[bosses]` `BossData`, `BossPhase`, `Boss` + `BossStateMachine` (Intro, Phase, Transition, Stagger, Death with slow-mo, rope spawn), arena scene base, boss bar data, floor 3 and 5 arena rooms in generator. Accept: framework drives a dummy boss. Verify: `test_boss_phases`. Deps: W2-A9, W3-A2. Scope: M
- [ ] W6-A4 `[bosses]` Boomer Jack (dynamite, mines) and The Foreman (slams, Rock Tick summons, cave-in at 50%, rope after, `boss_defeated`, Ascension trigger emit). Accept: both beatable solo and co-op with telegraphs. Verify: data test, manual. Deps: W6-A3. Scope: M
- [ ] W6-A5 `[floor-generation]` Placement rules for SHOP (floors 2 to 4), REST (3 to 4), RUNE (chance), ANVIL (every 2 floors, guaranteed 4/9/...), LORE (biome lore floor), hazard placement from `BiomeData.hazards`, 500-seed test extended. Accept: CI green. Verify: soak. Deps: W6-A1. Scope: S

### Dev B
- [ ] W6-B1 `[story-dialogue]` `StoryManager` (flags with namespaces, `flags.json` declaration, `act()`, `evaluate()` condition language, `unlock_lore`), `DialogueData` loader from JSON with schema validation, `specs/content/dialogue-schema.md`. Accept: every operator; bad file fails tests. Verify: `test_story_conditions`, `test_dialogue_data`. Deps: W5-B1. Scope: M
- [ ] W6-B2 `[story-dialogue]` `DialogueBox` UI (portrait, name, typewriter, choices, per-player in town), `start_dialogue`, `LorePage` pickup + LORE populator, codex list stub. Accept: dialogue plays from JSON with choices setting flags. Verify: `test_ui_scenes`, manual. Deps: W6-B1. Scope: M
- [ ] W6-B3 `[story-dialogue]` Act 1 content: Hilde, Gruff, Moss, Pip, Sister Ash, Old Tom intro + Act 1 lines + Foreman-defeated reactions; `story.foreman_defeated`, `story.miners_possessed`, `story.pit_calls` set by boss/floor listeners; Brann unlock flag; 6 Biome 1 lore pages. Accept: town dialogue changes after Foreman. Verify: data test, read-through. Deps: W6-B2, W6-A4. Scope: M
- [ ] W6-B4 `[town]` NPC nodes with `start_dialogue`, Alchemist (slots, heal potion), Map Room (start at reached ropes, next-floor modifier preview), building level sprites x4 states, pit edge stage by `act()`. Accept: spec. Verify: `test_town_data`, manual. Deps: W6-B1, W5-B3. Scope: M
- [ ] W6-B5 `[run-economy]` Shop and Rest room interactables polished (Vesper dialogue hook, potion refill), currency `Scaling` by biome. Accept: spec. Verify: unit. Deps: W5-B3. Scope: S

### Both
- [ ] W6-AB1 `[art-audio]` First real assets: player 8-dir sheet (Wren) via `make_sprite_frames.gd` + manifest, Biome 1 tiles, Biome 1 music placeholder loop replaced, core SFX set; art source decision recorded. Accept: `test_assets` green. Verify: tests, visual. Deps: W1-A2. Scope: M

### Checkpoint: Week 6 end (mid-project gate)
- [ ] Biome 1 playable end to end in co-op with relics, abilities, 3 classes, town, story, save; if slipped > 3 days, team meets on cut list; `week-6` tagged

---

## Week 7: Skill tree + weapons + Ascensions

**Done when:** Full skill tree UI and all branches, 10 weapons, anvil rooms with mutations, Ascensions for the first 3 classes, class XP and mastery, rescue mission system.

### Dev B
- [ ] W7-B1 `[progression-trees]` `SkillNodeData` + 38 node `.tres` with `requires`, `ui_position`, costs; `Progression` static (`rank`, `can_buy`, `buy`, `respec`, daily rule); Abyss gate on Foreman flag; `test_tree_economy` 25 to 40 runs. Accept: data + economy tests. Verify: `test_skill_data`, `test_progression`, `test_tree_economy`. Deps: W5-B1. Scope: M
- [ ] W7-B2 `[progression-trees]` 38 node effects (`Effect` scripts: stat nodes via `modify`, behavior nodes: Perfect Dodge slow, Dual Wielder, Undying, Safe Line, Curse Breaker, Third Rune, Pit Sight, Alt Ultimates flags, Executioner, Archmage, Ore Heart...) attached at run start with ranks; harness case each. Accept: 38 harness cases. Verify: harness. Deps: W7-B1, W4-B3. Scope: L (PR per branch)
- [ ] W7-B3 `[progression-trees]` `SkillTreeScreen` (pan/zoom canvas, nodes with rank pips, `Line2D` edges, locked/purchasable/bought states, tooltip, branch tabs) opened from Shrine of Echoes and town pause. Accept: buy and respec through UI. Verify: manual usability pass, `test_ui_scenes`. Deps: W7-B1. Scope: M
- [ ] W7-B4 `[story-dialogue]` Rescue missions: `rescues.json`, `Cage` interactable placed by generator hook (35% per eligible floor, guaranteed floor 4), escort spawn via `EscortNpc`, rope-reached completion setting `rescue.<id>`, `miner_rescued`, class unlock + free weapon, miner appears in town; Sly Nettie (Rogue) data. Accept: rescue Nettie unlocks Rogue (class itself week 9; unlock flag and weapon now). Verify: integration test, two-instance. Deps: W6-B1, W7-A6, W3-A2. Scope: M

### Dev A
- [ ] W7-A1 `[weapons]` Weapon skill trigger (perfect window + heavy, 6 s cooldown), `Channel` state for hold attacks, thrown/recall projectile support, `WaterTile`, `SoulOrb`, `lit` flag. Accept: engine support for all mechanics in spec list. Verify: unit. Deps: W2-A7, W2-A8. Scope: M
- [ ] W7-A2 `[weapons]` 8 more weapons to reach 10: Longsword, Twin Daggers, Sledgehammer, Shortbow, Hand Cannon, Spore Tome, Chain Whip, Grave Scythe (scene, `.tres`, skill, affinity tags). Accept: distinct feel per "Feel" column; data test. Verify: `test_weapon_data`, Training Grounds later; manual. Deps: W7-A1. Scope: L (PRs of 2 to 3)
- [ ] W7-A3 `[weapons]` `MutationData`, `Anvil` interactable + ANVIL populator (1 of 3, Armory +1), mutation attach as `Effect`, `specs/content/mutations.md` started; 60 mutations for the 10 weapons incl. Thunderhead, Phantom Pair, Grapeshot, Reaper's Harvest. Accept: 60 harness cases. Verify: `test_mutation_triggers`. Deps: W7-A2, W4-B3. Scope: L (PRs per weapon)
- [ ] W7-A4 `[classes-characters]` Ascension choice flow (after floor 5 boss or at start if deeper; duplicate rejection via host; `ascension_chosen`), Tier 1 Ascensions for Warrior (Berserker, Guardian), Ranger (Beastmaster wolf via FriendlyUnit, Sharpshooter), Mage (Pyromancer, Stormcaller) + harness cases; `ChoicePopup` 1-of-2 (Daniel's widget). Accept: 6 T1 playable. Verify: `test_ascension_timing`, harness, co-op. Deps: W5-A5, W6-A4. Scope: L (PR per class)
- [ ] W7-A5 `[classes-characters]` Class XP earn hooks (kills, floors, bosses by biome) into `RunPlayerState`, mastery thresholds, `class_xp_gained`; `specs/content/class-trees.md` with Warrior/Ranger/Mage node lists. Accept: XP banks per class. Verify: `test_mastery`. Deps: W5-B2. Scope: S
- [ ] W7-A6 `[enemies-ai]` `EscortNpc` (follow 64 px, Health, flee, teleport catch-up, death fails rescue). Accept: survives a floor walk in two-instance. Verify: manual, unit. Deps: W5-A7. Scope: S

### Checkpoint: Week 7 end
- [ ] 38 nodes buyable with effects; 10 weapons + 60 mutations; 6 T1 Ascensions; rescue flow; `week-7` tagged

---

## Week 8: Biomes 2 and 3

**Done when:** Enemies, hazards, mini-bosses, bosses for Fungal Caverns and Crystal Hollows, 40 relics, synergies.

### Dev A
- [ ] W8-A1 `[biomes]` Fungal Caverns: `BiomeData` (Iron, lore floor 9), 5 enemies (Shroomling split, Spore Spitter, Mycel Brute, Glow Moth blind, Root Strangler), hazards (spore vents, bouncy mushrooms, darkness zones), palette/lighting, 5 Lost Lanterns placement + `lantern.N` flags. Accept: data tests; playable. Verify: tests, manual. Deps: W6-A1. Scope: L (enemies / hazards PRs)
- [ ] W8-A2 `[bosses]` Sporelord Twins (`TwinLink`, 10 s revive) and Bloom Mother (`WeakPoint`, spore fill). Accept: mechanics work co-op. Verify: unit + manual. Deps: W6-A3. Scope: M
- [ ] W8-A3 `[biomes]` Crystal Hollows: `BiomeData` (Crystal, lore 14), 4 enemies (Shard Golem split, Prism Bat, Geode Turtle behind-only, Crystal Mimic as chest), hazards (reflecting crystals via `reflectable`, laser beams). Accept: tests; playable. Verify: tests, manual. Deps: W6-A1. Scope: M
- [ ] W8-A4 `[bosses]` Gem Collector (gold steal/drop) and Prism Queen (3 mirrors, bouncing beams). Accept: mechanics. Verify: unit + manual. Deps: W6-A3. Scope: M
- [ ] W8-A5 `[biomes]` Biome 2/3 lore pages (6 each) data handoff to Daniel; Golden Spore rare drop + Mushroom Hermit hidden room marker (fight week 11). Accept: drops and flags exist. Verify: data test. Deps: W8-A1. Scope: XS

### Dev B
- [ ] W8-B1 `[relics]` Relics 21 to 42 minus two (On Getting Hit, Crit, Elemental, Ability) to reach 40 with Bomb Bag and Healing Totem actives; harness case each; final tag assignments satisfying >= 4 per synergy tag. Accept: `test_relic_data` 40, tags rule green. Verify: harness, two-instance. Deps: W4-B6. Scope: L (PRs of 10)
- [ ] W8-B2 `[relics]` `SynergyData` x12 + effects, `SynergyTracker` (recompute on pick/remove, Elementalist and Doomed rules), `synergy_activated`, HUD progress pips and active glow. Accept: `test_synergies`; HUD on client. Verify: tests, two-instance. Deps: W8-B1, W4-B3. Scope: M
- [ ] W8-B3 `[relics]` Codex data for relics seen/picked into profile; Relic Vault codex view v1 in town. Accept: entries persist. Verify: unit. Deps: W5-B1. Scope: S
- [ ] W8-B4 `[story-dialogue]` Act 2 flags (`story.vulkar_journals`, `story.drowned_city_found`, `story.pit_has_done_this_before` stubs), Biome 2/3 lore JSON, Pip depth-keyed lines, Old Tom hints for Rat King and Hermit. Accept: data test. Verify: read-through. Deps: W6-B3. Scope: S
- [ ] W8-B5 `[networking]` Co-op soak session with `net_lag 100 2%`, fix list triaged into issues. Accept: WEEKLY notes. Verify: manual. Deps: all. Scope: S

### Checkpoint: Week 8 end
- [ ] Biomes 1 to 3 playable; 40 relics; 12 synergies active; `week-8` tagged

---

## Week 9: Biomes 4 and 5

**Done when:** Drowned City and Ember Forge with all enemies and bosses, all 19 weapons, all 30 abilities, characters 2 to 4, Rogue, Necromancer, Engineer, Lightbearer (unlocked through their rescues).

### Dev A
- [ ] W9-A1 `[biomes]` Drowned City: `BiomeData` (Pearl, lore 19), 5 enemies (Deepkin, Eel Lurker ambush, Drowned Priest heal/shield, Barnacle Crab, Siren pull), hazards (deep water `wet` + slow, currents, rising water), Conduct interplay, Fishing Rod rare drop + `FishingSpot` marker. Accept: tests; Conduct spreads across puddles. Verify: tests, manual. Deps: W6-A1, W4-B4. Scope: L
- [ ] W9-A2 `[bosses]` Captain Saltbones (cannon crew adds) and Tide King (`WaterLevel` rings). Accept: mechanics. Verify: unit + manual. Deps: W6-A3. Scope: M
- [ ] W9-A3 `[biomes]` Ember Forge: `BiomeData` (Ember Ore, lore 24), 5 enemies (Forge Imp, Slag Golem lava trail, Bellows Drone push, Clockwork Sentry, Ashen Smith buff), hazards (lava, conveyors, molten pour, steam vents). Accept: tests; playable. Verify: tests, manual. Deps: W6-A1. Scope: L
- [ ] W9-A4 `[bosses]` Iron Maiden (mode swap) and Old Vulkar (forges players' weapons as enemy attacks). Accept: mechanics. Verify: unit + manual. Deps: W6-A3, W9-A5. Scope: M
- [ ] W9-A5 `[weapons]` Remaining 9 main weapons: Greataxe, Rust Anchor, Throwing Knives, Tide Orb, Blood Grimoire, Drill Gauntlets, Saw Boomerang, Reaper's Chain, plus Crossbow/Pickaxe/Lantern Staff skill polish, to reach 19; 6 mutations each for the 9 (54, incl. Wrecking Ball, Twin Saws) reaching 114. Accept: data tests 19/114; harness. Verify: tests, Training Grounds DPS. Deps: W7-A3. Scope: L (PRs of 2 to 3)
- [ ] W9-A6 `[abilities]` Remaining 20 abilities + harness cases (all schools incl. Earth, Blood, Void, Utility: Grapple Hook, Turret Drop, Mine Field, Decoy Lantern, Smoke Bomb, Rift Walk, Unmake, Fault Line small-kill...). Accept: 30 total. Verify: `test_ability_data`, `test_ability_casts`. Deps: W5-A2. Scope: L (PRs of 5)
- [ ] W9-A7 `[abilities]` Character ultimates: Foreman's Fury, Sunrise, Thousand Cuts + class twist scripts for all 7 classes. Accept: harness per ultimate and twist. Verify: tests, manual. Deps: W5-A3, W9-A8. Scope: M
- [ ] W9-A8 `[classes-characters]` Rogue (Backstab, Smoke Step, Assassin/Trickster T1), Necromancer (Soul Harvest skeletons via FriendlyUnit, Corpse Burst, Gravelord/Plague Lord T1), Engineer (Scrap, Deploy turrets, Mechanist mech state/Demolitionist T1), Lightbearer (Radiance aura, Sanctuary, Paladin/Oracle T1); class unlock on rescue flags; free weapons. Accept: harness per passive/skill/T1; each tested solo + co-op. Verify: tests, WEEKLY. Deps: W7-A4, W7-B4. Scope: L (PR per class)
- [ ] W9-A9 `[classes-characters]` Brann (armor stacks still), Ivy (light, `lit` +15%), Kestrel (dodge reset) with unlock flags; 28 combos selectable. Accept: harness x3; select screen shows unlock state. Verify: tests. Deps: W9-A8. Scope: M

### Dev B
- [ ] W9-B1 `[story-dialogue]` Rescue data for Cogsworth, Mortimer, Elian + 4 non-class miners with Rescue Camp bonus ids; Act 2 dialogue for all NPCs; Biome 4/5 lore. Accept: data tests; rescues complete in play. Verify: tests, manual. Deps: W7-B4. Scope: M
- [ ] W9-B2 `[ui-hud]` Class resource bars for 7 classes, Ascension popup polish, minion/turret count HUD, boss bar with phase markers wired to `BossHealthBarData`. Accept: all shown on client. Verify: two-instance. Deps: W9-A8, W6-A3. Scope: M
- [ ] W9-B3 `[town]` Training Grounds v1 (dummy with DPS readout) so Alex can tune weapons; Relic Vault pick + Rune Library pick (level 2 behaviors). Accept: DPS readout; picks applied at run start. Verify: unit, manual. Deps: W8-B3. Scope: M
- [ ] W9-B4 `[networking]` 4-instance soak on two machines with `net_lag`; triage. External playtest round 1 (5 people) organized; notes in WEEKLY. Accept: notes filed. Verify: WEEKLY. Deps: all. Scope: S

### Checkpoint: Week 9 end
- [ ] Biomes 1 to 5; 19 weapons; 30 abilities; 7 classes T1; 4 characters; external playtest 1 notes; `week-9` tagged

---

## Week 10: Biome 6 + final boss + story

**Done when:** The Heart, The Hollow You, The Sinkhole 3-phase fight, all 3 endings, all NPC dialogue, Lore rooms and 40+ lore pages.

### Dev A
- [ ] W10-A1 `[biomes]` The Heart: `BiomeData` (Heartstone, lore 29), corrupted pool (`corrupted_of` variants + tint shader + Unravel on hit), Veinling (latch/drain until dodge), Heart Guard (front immune), Echo (casts `last_cast`), hazards (spike walls, breathing floor, shrinking rooms). Accept: tests; playable. Verify: tests, manual. Deps: W9-*. Scope: L
- [ ] W10-A2 `[bosses]` The Hollow You: build snapshot APIs consumed (`relics_of`, `abilities_of`, `weapons_of`, `class_state_of`, `StatBlock.snapshot`), `hollow_safe` relic flags, enemy-side effect translation, co-op picks top damage dealer. Accept: `test_hollow_you` with fake build; mirrors in play. Verify: tests, manual. Deps: W6-A3, W9-A8. Scope: M
- [ ] W10-A3 `[bosses]` The Sinkhole phases 1 and 2 (attack sets drawn from prior bosses, `arena_collapse`), phase 3 hook to `StoryManager.final_choice()`, three duel variants (Seal relic sacrifice, Keeper dark buffs, True miners' ghosts via FriendlyUnit). Accept: all 3 endings reachable in a debug-skipped run. Verify: manual x3, unit for phase thresholds. Deps: W10-A2, W10-B2. Scope: L (two PRs)
- [ ] W10-A4 `[floor-generation]` Biome 6 generation quirks (shrinking rooms as modifier of room bounds), floor 30 arena, 500-seed test over all 6 real biomes. Accept: CI green. Verify: soak. Deps: W10-A1. Scope: S

### Dev B
- [ ] W10-B1 `[story-dialogue]` Act 3 flags and all NPC dialogue through Act 3 and endings; Vesper dialogue; The Rescued dialogue sets; 12 character events (3 per character) with `character` conditions. Accept: data tests (required entries per NPC, 12 events); read-through. Verify: tests. Deps: W9-B1. Scope: L (PRs per act/NPC group)
- [ ] W10-B2 `[story-dialogue]` `final_choice(context)` ending logic (Seal, Keeper, True gated on Watcher + all lore), 3 ending dialogue sequences + scripted scenes, credits, `ending.*` flags, Deep Mode unlock flag. Accept: `test_story_acts` ending rules. Verify: tests, manual. Deps: W10-B1. Scope: M
- [ ] W10-B3 `[story-dialogue]` Lore to 40+ (Biome 6 + Vulkar journals), codex screen (relics, abilities, enemies, bosses, lore by biome, read state). Accept: 40+ in data test; codex UI. Verify: tests, manual. Deps: W8-B3. Scope: M
- [ ] W10-B4 `[ui-hud]` Victory screen (ending title, Deep Mode notice), boss name banners, ending credits roll. Accept: shown after each ending. Verify: manual. Deps: W10-B2. Scope: S
- [ ] W10-B5 `[town]` Pit edge stages 1 to 3 and ending visuals; Rescue Camp with rescued miner NPCs. Accept: stage follows `act()`/ending. Verify: fixture profiles. Deps: W6-B4. Scope: S

### Checkpoint: Week 10 end
- [ ] Full 30-floor run to each ending in co-op (debug skips allowed); all dialogue; 40+ lore; `week-10` tagged

---

## Week 11: Content and endgame

**Done when:** Tier 2 Ascensions and all class trees, class pair bonuses, all 88 relics, Cursed Altars, Challenge rooms, Secret rooms, all 120 mutations, secret bosses, Deep Mode, heat levels, all town buildings.

### Dev A
- [ ] W11-A1 `[classes-characters]` 14 Tier 2 Ascension effects (Blood Frenzy, Bulwark, Pack Leader hawk, Deadeye time slow, Phoenix, Eye of the Storm, Death Mark, Master Thief, Lord of the Dead golem merge, Pestilence zombies, War Machine ally ride, Chain Reaction, Avatar of Light wings, Foresight) attached after Biome 4 boss or deep start. Accept: harness x14; co-op checked. Verify: tests, WEEKLY. Deps: W9-A8. Scope: L (PRs per class)
- [ ] W11-A2 `[classes-characters]` Class tree node data for all 7 (6 to 8 each, `class-trees.md` complete), node effects + harness; alternate class skills at mastery 5 (7); 4 `ClassPairData` effects. Accept: data tests; harness. Verify: tests. Deps: W7-A5. Scope: L
- [ ] W11-A3 `[weapons]` Leviathan's Tooth (design recorded) + 6 mutations; remaining mutations to 120 (`mutations.md` complete). Accept: 20 weapons, 120 mutations in data test; harness 120. Verify: tests. Deps: W9-A5. Scope: M
- [ ] W11-A4 `[abilities]` Alternate ultimates (Pit's Embrace, Echo Storm, Last Light) gated by Alt Ultimates node, Spore Bloom gated by Hermit flag, ultimate select in RunSetup. Accept: harness x4. Verify: tests. Deps: W9-A7, W7-B2. Scope: M
- [ ] W11-A5 `[floor-generation]` CHALLENGE (timed / no-hit with loot), SECRET (breakable wall, Wren/Treasure Map reveal, Rat King flagged wall), CURSED_ALTAR placement (25%, not floor 1), all 6 floor modifiers wired (Darkness, Double Elites, Fast, Low Gravity, Gold Rush, Explosive), Map Room preview. Accept: soak updated; modifiers visible. Verify: `test_modifiers`, soak. Deps: W6-A5. Scope: M
- [ ] W11-A6 `[bosses]` Secret bosses: Rat King (hidden wall, Legendary + Rat cosmetic), Mushroom Hermit (Golden Spore handoff, Spore Bloom unlock), Leviathan (fishing timing press, flooded arena, Tooth drop), The Watcher (town well after ending, `secret.watcher_defeated`). Accept: 16 bosses in data test; each beatable. Verify: tests, manual. Deps: W10-A3. Scope: L (PR per boss)
- [ ] W11-A7 `[enemies-ai]` Deep Mode extra attack pool per biome (`deep_attacks`), boss `deep_mode_phase` and `heat_phase` data for all 16. Accept: data present. Verify: data tests. Deps: W11-A6. Scope: M

### Dev B
- [ ] W11-B1 `[relics]` Relics to 88: Movement, Economy, Transformation (13 Legendary), fillers, remaining actives (8), 8 cursed; `CursedAltar` interactable; Curse Breaker and Doomed interplay; Abyssal Attunement second slot (B key); Relic Vault start pick incl. rares at level 3; Pit Pact / Chaos Engine floor hooks. Accept: 88 in data test; 88 harness cases; tags >= 4 rule. Verify: tests, two-instance. Deps: W8-B1. Scope: L (PRs of 10 to 12)
- [ ] W11-B2 `[progression-trees]` Class tree tabs + purchase with Class XP, `MasteryScreen` (level, XP bar, alt skill, cosmetics), `Progression.class_rank`. Accept: buy nodes for all 7. Verify: `test_progression` extended, manual. Deps: W11-A2. Scope: M
- [ ] W11-B3 `[town]` All 11 buildings x 3 levels with sprites and effects: Blacksmith tiers, Alchemist types/starting, Map Room L3, Shrine L3, Tavern lobby/daily board, Relic Vault, Rune Library L3 rank 2, Training Grounds elite/boss dummies, Rescue Camp passives (4+ `CampBonus` effects), Bounty Board (date-seeded dailies/weeklies, `BountyTracker`), Wardrobe (equip cosmetics, applied at spawn). Accept: `test_town_data` 33 levels; `test_bounties`. Verify: tests, fixtures. Deps: W6-B4. Scope: L (PR per 2 to 3 buildings)
- [ ] W11-B4 `[endgame]` Deep Mode (toggle, boss deep phases, deep attacks, loot shift, x1.5 Echo, The Keeper variant via Hollow You API on Keeper ending), 10 `HeatModifier` effects with multipliers, RunSetup toggles. Accept: `test_heat`; Keeper appears. Verify: tests, manual. Deps: W10-A2, W11-A7. Scope: M
- [ ] W11-B5 `[endgame]` Daily Dive (date seed, fixed setup from unlocked-at-start content, one attempt, score, local leaderboard 30 days, share code), 50+ `AchievementData` + `AchievementTracker` + toasts + cosmetic rewards, codex completion percentages. Accept: `test_daily_dive`, `test_achievements`, >= 50. Verify: tests. Deps: W5-B1, W10-B3. Scope: L (two PRs)
- [ ] W11-B6 `[ui-hud]` Achievements list screen, Daily Dive board widget, heat selection UI, Wardrobe grid, Bounty Board UI. Accept: all reachable. Verify: `test_ui_scenes`. Deps: W11-B5. Scope: M

### Checkpoint: Week 11 end
- [ ] Every design doc count met in data tests (see SPEC-project success criteria); `week-11` tagged

---

## Week 12: Polish

**Done when:** Final art/audio/VFX pass, balancing, co-op bug fixing, achievements, settings, external playtests.

### Dev A
- [ ] W12-A1 `[stats-status]`/`[weapons]` Balance pass: damage golden file review with Daniel, weapon feel on Training Grounds, enemy HP/damage curve, boss timings. Accept: golden file updated and both signed off. Verify: tests, WEEKLY. Scope: M
- [ ] W12-A2 `[art-audio]` Final enemy, boss, biome tile art per priority list; VFX per element/ability/relic proc complete. Accept: `test_assets` green; "looks as crazy as it feels" check. Verify: tests, visual. Scope: L
- [ ] W12-A3 `[networking]` Co-op bug fixing from playtests (Alex's modules). Accept: issue list closed or deferred with notes. Verify: two-machine sessions. Scope: M

### Dev B
- [ ] W12-B1 `[ui-hud]` Settings: audio buses, video (window, scale, vsync), screen shake, damage numbers toggle, full key rebinding with conflict detection, controller deadzone; persisted. Accept: `test_rebinding`; manual. Verify: tests. Scope: M
- [ ] W12-B2 `[progression-trees]`/`[town]`/`[run-economy]` Economy tuning: tree total in 25 to 40 runs, town ore costs matched, Echo curve, shop prices (`economy.md`). Accept: `test_tree_economy` green with final numbers. Verify: tests. Scope: S
- [ ] W12-B3 `[debug-tools]` Release export preset excluding `scripts/debug/`, Windows export verified, debug console absent in export, `.github` optional export job stays off. Accept: exported build runs a full loop. Verify: manual. Scope: S
- [ ] W12-B4 `[networking]` Co-op bug fixing (Daniel's modules), simulated-latency pass. Accept: issue list closed or deferred. Verify: sessions. Scope: M

### Both
- [ ] W12-AB1 `[art-audio]` Final music tracks (town, 6 biomes, mini-boss, 5 boss themes, final, menu, victory, death), full SFX list, portraits, icons, `CREDITS.md`. Accept: `test_assets`; credits complete. Verify: tests. Scope: L
- [ ] W12-AB2 External playtest round 2 (5+ people), 4-player 30-floor run on two or more machines, final WEEKLY entry, `week-12` tag, SPEC-project success criteria all checked.

### Checkpoint: Complete
- [ ] All SPEC-project success criteria checked
- [ ] Every module in CAPABILITY_MAP status `done` or dated cut-list entry (expected: none)
- [ ] Ready for release
