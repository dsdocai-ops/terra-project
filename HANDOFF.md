# HANDOFF — Weeks 1 to 3 (W1-B1 .. W1-B10, W2-B1 .. W2-B6, W3-B1 .. W3-B5)

A plain-language rundown of what the Dev B (Surface + Systems) lane shipped in
week 1, week 2 and week 3, how each piece works, every decision that was made
without a human in the loop, and how to run the build solo and in co-op. Written
for Dev A and the human who review this handoff; the task list is
`tasks/todo.md`.

**Verified baselines:**

- Week 1 (2026-10-18) on `main` @ `75ed7c2`: import exit 0; 18 GUT scripts /
  204 tests green in ~7 s; `tools/smoke_two.sh` 15/15 (steps 1 + 2).
- Week 2 (2026-10-19) on `main` @ `ee62cb7`: import exit 0 with no errors;
  27 GUT scripts / 338 tests green in ~14 s; `tools/smoke_two.sh` 28/28
  (steps 1 + 2 + 3). `week-2` tag held off until Dev A's W2 tasks land (see
  `specs/WEEKLY.md`).
- Week 2 gate re-verified (2026-10-19) on `main` @ `3b992de`, before Week 3
  began: import exit 0; 27 GUT scripts / 338 tests green in ~7 s;
  W2-B1 .. W2-B6 ticked, W2-B7 / W2-B8 and W2-A1 .. W2-A13 open; `week-2` not
  tagged. Full verdict in decision 22 below.
- Week 3 close-out (2026-10-20, after W3-B5b, tree at `84395b4`): import exit 0
  with 0 error lines (`.goals/evidence/g6/import.log`); **35 GUT scripts /
  554 tests / 554 passing / 54 115 asserts, exit 0** in 9.8 s
  (`.goals/evidence/g6/gut-full.log`); `tools/smoke_two.sh` **35 `ok` lines /
  0 FAIL / exit 0** (`.goals/evidence/g6/smoke-run.log`, per-peer logs in
  `.goals/evidence/g6/smoke/`). Dev A's W3-A1 .. W3-A7 are still unlanded
  (`scripts/generation/` holds only `.gdkeep`), so every floor is generated
  through the lane-B seam; **`week-3` is not tagged** — the design-doc "Done
  when" line is partial. Verdict and reason in decision 37 below and in
  `specs/WEEKLY.md`.

---

## What shipped, task by task

### W1-B1 — Project settings and folder tree (`foundation`)

`project.godot` now matches the SPEC-foundation settings table: 960x540 base
viewport with a 1920x1080 dev default window, `canvas_items` stretch with
integer scaling, nearest texture filter, 2D pixel snap on both transforms and
vertices, Compatibility renderer for desktop and mobile, and
`untyped_declaration` as an Error so missing type hints fail the build. The six
2D physics layer names (`world`, `player`, `enemy`, `hitbox_player`,
`hitbox_enemy`, `interactable`) are set so scenes read clearly. Every folder in
the SPEC-project layout was created (`.gdkeep` in the empty ones). The setting
table's values are asserted line-for-line by `tests/unit/test_project_settings.gd`.

### W1-B2 — Input Map (`foundation`)

All 23 actions from the SPEC-foundation table are bound: 20 gameplay actions
each have a keyboard/mouse binding plus one controller binding, and three
(`weapon_1`, `weapon_2`, `debug_console`) are keyboard-only by design.
`debug_console` is the backtick key. The canonical list lives in
`tools/configure_input_map.gd`, which writes `project.godot` — edit the tool,
never the `[input]` section by hand. `tests/unit/test_input_map.gd` checks every
name, binding class, specific key/button/axis, that no joypad button is bound
twice, and that synthetic key and stick events drive the actions through
`Input`.

### W1-B3 — Autoload stubs and ContentData (`foundation`)

Seven autoloads are registered in the dependency-ordered sequence `Events`,
`TimeManager`, `GameState`, `SaveManager`, `StoryManager`, `AudioManager`,
`NetworkManager`. `Events` already carries the full signal set (signals only, no
logic). The others are typed stubs exposing the exact public API their owning
module will fill in during later weeks, so consumers compile against the real
names from day one; `StoryManager` has a working in-memory flag/lore set.
`scripts/data/content_data.gd` is the base `ContentData` Resource (`id`,
`display_name`, `tags`, `effect_script`, `icon`, `vfx_id`, `sfx_id`) that every
content Resource extends so data-driven tests can check ids match file names.
`tests/unit/test_autoloads.gd` verifies order, API shape, and a `.tres` round trip.

### W1-B4 — GUT and test skeleton (`foundation`)

GUT 9.7.1 is vendored under `addons/gut/` and the plugin is enabled. The test
tree (`tests/unit/`, `tests/integration/`, `tests/helpers/`) exists with smoke
tests that instantiate every scene (`test_scenes_load.gd`) and load every
`.tres` (`test_data_loads.gd`). A deliberately failing test was verified to make
GUT exit 1, then removed — so the green/red behavior is proven, not assumed.

### W1-B5 — CI workflow (`foundation`)

`.github/workflows/ci.yml` runs on every PR and on every push to `main`:
checkout, download Godot 4.7.2 headless, `--import`, run the full GUT suite,
fail on any non-zero exit. The import step is required first — it refreshes the
global class cache, and without it every test file fails to parse. Details of
the setup download are in the decisions section. `timeout-minutes: 10`; the job
is a single import + test run, expected well under 5 minutes.

### W1-B6 — Main scene and launch args (`foundation`)

`scenes/main/main.tscn` + `main.gd` are the project entry. `main.gd` loads
`world.tscn`, registers it on `GameState.world` (the only sanctioned path to the
world for other modules), and parses user launch args via
`scripts/launch_args.gd`:

- `--host` → host a game and skip the menu.
- `--join=<ip[:port]>` → join and skip the menu (hostname or IP accepted).
- `--seed=<int>` → force the run seed into `GameState`.
- `--smoke[=<sec>]` → headless smoke mode used by `tools/smoke_two.sh` (see
  decisions; it is a Dev B addition not in the original spec list).
- No args → show a placeholder menu (Play Solo / Host / Join with an IP field);
  connection failures put the menu back with a status line.

Covered by `tests/unit/test_launch_args.gd` and `tests/unit/test_main_scene.gd`.

### W1-B7 — NetworkManager: host, join, peer tracking (`networking`)

The stub became the real `scripts/autoload/network_manager.gd`. It opens an ENet
server on port 7777 (`host`), connects as a client (`join`, with address
validation before ENet), and offers `start_solo()` (an offline server, see
decisions), `disconnect_all()`, `is_host` / `local_peer_id` / `peer_ids` /
`players`, `get_player()`, `player_count()`, and the co-op enemy HP multiplier
`1.0 + 0.5 * (players - 1)`. `player_joined` / `player_left` /
`connection_failed` / `host_disconnected` signals drive everything else in the
networking lane. Solo is just a host with one peer, so there is no separate
single-player code path. `tests/unit/test_network_manager.gd` covers the
multiplier table, session refusal, disconnect reset, and address validation.

### W1-B8 — Player spawning via MultiplayerSpawner (`networking`)

`PlayerSpawner` (a `MultiplayerSpawner` with `spawn_path = World/Players`) spawns
exactly one `Player` per peer. The host calls `spawn()` with a
`PlayerSpawnInfo` dictionary (`peer_id`, `character_id`, `class_id`,
`weapon_ids`, `spawn_position`, `slot`); the spawner's custom spawn function
replays it on every peer, including late joiners, and despawns automatically
when the host frees the node. Each player's `InputSync` is authored to its
owning peer and only visible to the host; the rest stays host-owned. Players
spawn on a ring around the floor center so they never overlap, and each peer
gets the lowest free co-op slot (which decides its color). See the decisions
section for how this extends the spec. `tests/unit/test_player_spawner.gd`
covers the round trip, late join, leave, registry, and replace-on-respawn.

### W1-B9 — InputSync / StateSync and client prediction (`networking`)

The two `MultiplayerSynchronizer` nodes in `scenes/player/player.tscn` (Dev A's
scene; this config landed through a PR Dev A reviewed) are wired:

- **InputSync** — authority is the owning peer; replicates `move_input`,
  `aim_position`, and `input_tick` up to the host only.
- **StateSync** — authority is the host; replicates `synced_position`,
  `synced_velocity`, `facing_index`, `current_anim`, and `acked_input_tick`
  down to all peers.

The local player moves immediately from its own input (client prediction); the
host simulates the same input and the `StateSync` position corrects drift with a
small lerp (reconcile against the last acked input tick). Remote players are
host-authoritative and interpolate smoothly. `tests/unit/test_player_sync.gd`
covers replication config, publish, roles, reconcile, interpolate, and anim
replay; the two-instance smoke proves both directions across the wire.

### W1-B10 — Two-instance launcher and headless smoke (`debug-tools`)

`tools/run_two.ps1` (Windows) and `tools/run_two.sh` (POSIX) launch a host and
N clients side by side with windows placed at fixed positions:
`.\tools\run_two.ps1 -Clients 1` for one client, `-Clients 2` for two.
`tools/smoke_two.sh` runs the same flow headless: a host and a client connect,
both players spawn on both sides, each side's local player walks right so
movement must cross the wire in both directions, and the client leaves first so
the host sees the peer go — 15 checks, exit 0 on pass. This is the two-instance
smoke required before any PR that touches sync.

### W2-B1 — TimeManager: group/per-entity scaling, slow/stop stack, hit-stop, scaled timers (`time-manager`)

`scripts/autoload/time_manager.gd` is the one answer to "how fast does time
move for this entity right now". Enemies and enemy projectiles multiply their
delta by `scale_for(self)`; the engine's global time scale is never touched
(the `Engine.time_scale` grep over `scripts/`/`scenes/` is empty).

- `set_group(node, Group)` — player and enemy scripts register in `_ready`
  (`Group.PLAYER` / `Group.ENEMY`).
- `scale_for(node)` — a per-entity override always wins (hit-stop, single-target
  slows); otherwise PLAYER-group and unregistered nodes run at normal speed and
  only ENEMY-group nodes take the global slow/stop stack. So `slow_enemies` /
  `stop_enemies` never touch players, while an entity-level effect still can.
- Global stack is min-of-factor with replace-on-same-source: `slow_enemies(0.5)`
  then `stop_enemies` gives 0.0; each effect is `{source, factor,
  expires_on_frame}` and expiry is **physics-frame based**, not scaled seconds,
  so a slow that runs out during a stop still expires on the stopped world.
- `clear_source(source)` removes every global and per-entity effect carrying
  that source (e.g. Deadeye release).
- `hit_stop(a, b, frames)` freezes exactly the two nodes for N physics frames
  (3 light / 6 heavy / 10 boss-kill per spec); the camera, HUD, and everyone
  else keep running.
- `timer(node, seconds)` returns a signal that fires once after `seconds` of
  time *scaled by* `scale_for(node)` — plain `Timer`/`create_timer` are
  forbidden for enemy gameplay because they ignore time effects. The timer
  stores the node by instance id and reads it back with the global
  `instance_from_id()` (not a static call, which does not exist), so a freed
  node cannot keep a timer alive.
- Rewind hooks (`register_rewindable` / `unregister_rewindable` / `rewind`) are
  stubbed for week 4's Time Hourglass per spec scope.
- Sync: host-authoritative. The host decides every effect and broadcasts the
  start as reliable authority RPCs — `time_effect_applied(group, factor,
  seconds, source)` for the group stacks, `entity_time_applied(world-relative
  path, ...)` for per-entity effects — and clients apply the same duration
  locally, so expiry stays in lockstep and a frozen entity keeps reporting the
  same pose through MultiplayerSynchronizer.
- Tests: `tests/unit/test_time_manager.gd` (14) plus
  `tests/integration/test_time_scale_movement.gd` (2), which proves a scripted
  mover travels 0 px during a 1 s stop and resumes afterward.

### W2-B2 — StatBlock + Damage.compute + golden table (`stats-status`)

`scripts/components/stat_block.gd` (`StatBlock extends Node`) is the math layer
every stat change flows through. It defines the 11-stat enum (MAX_HP, ATTACK,
DEFENSE, MOVE_SPEED, ATTACK_SPEED, DODGE_COOLDOWN, CRIT_CHANCE, CRIT_DAMAGE,
ABILITY_POWER, COOLDOWN_REDUCTION, LUCK) and computes
`(base + sum(flat)) * (1 + sum(percent))` per stat, clamped (CRIT_CHANCE 0–1,
COOLDOWN_REDUCTION ≤ 0.6, ATTACK_SPEED ≥ 0.2). Base values are written once at
spawn setup from CharacterData/ClassData/EnemyData via `set_base`; every other
change is a modifier carrying an int handle: `add_modifier(stat, flat, percent,
source)` returns the handle, `remove_modifier(handle)` and `remove_source` back
it out (a removed relic drops all its modifiers at once), `snapshot()` serves
effect-system. `current_hp_ratio` lives on the block (kept by Health) so a
MAX_HP change never alters the fill fraction, and `stat_changed(stat, value)`
signals the HUD. Sync: modifier lists are host-only; the host ships the 11
values + HP ratio in StateSync and clients render the same numbers.

`scripts/components/damage.gd` (`Damage.compute`, static, host-only) is the
single damage formula:
`raw = base_damage * ATTACK/100 * ability_power_scale(AP)`, crit rolled against
CRIT_CHANCE + bonus (forced when the target has MARK — shipped as a `force_crit`
flag on HitData, the week-2 seam StatusEffects sets in week 4), crit multiplier
`1.5 + CRIT_DAMAGE`, `status_mult` a literal 1.0 (BURN/PERMAFROST/UNRAVEL terms
land with week-4 StatusEffects), defense mitigation `100/(100+DEF)`, final
rounded and min 1 on a connecting hit. `hit` is `scripts/components/hit_data.gd`
— the week-2 mirror of Dev A's combat-core `HitInfo`; the formula reads the
spec'd fields by name, so the swap-in is mechanical (blocked on Dev A, W2-A1).
`tests/unit/damage_table.json` is a 12-row hand-computed golden the formula test
reads; deterministic rows use crit chance 0/1 or `force_crit`, and the
in-between chance band is covered by a seeded 400-roll test.

> **G13a (2026-10-20) — the crit roll is no longer a global roll.** The week-2
> formula drew its crit from Godot's global RNG, which the definition of done
> forbids anywhere under `scripts/`. `Damage.compute` now takes a fourth,
> `null`-defaulted parameter — `rng: RandomNumberGenerator` — and draws the crit
> from `randf_range(0.0, 1.0)` on it; a caller that passes none gets a
> `Damage`-owned generator created on first use and seeded from clock entropy.
> A `force_crit` (MARK) still short-circuits before the draw, so it consumes
> none. No formula number changed: the 12 golden rows are byte-identical and
> every week-2 test still passes. See decision 28 for the seam choice.

### W2-B3 — Enemy/projectile spawners + enemy StateSync (`networking`)

`EnemySpawner` and `ProjectileSpawner` (`scripts/network/`, `MultiplayerSpawner`
subclasses) are wired under `World/Entities` in `scenes/main/world.tscn`
(y-sorted, `spawn_path = ..`). The host calls `spawn_enemy(EnemySpawnInfo)` /
`spawn_projectile(ProjectileSpawnInfo)`; the custom spawn function replays the
plain-type info dict on every peer including late joiners, names the node
(`Enemy<fight_id>` / `Projectile<N>`), and MultiplayerSpawner despawns it when
the host frees the root. Spawning is host-gated through an overridable
`_can_spawn()` seam (default `multiplayer.is_server()`); a client call gets a
`push_warning` refusal and returns null, never a spawn. The info types
(`scripts/network/enemy_spawn_info.gd`, `projectile_spawn_info.gd`) are plain
wire dicts following `player_spawn_info.gd`: `EnemySpawnInfo` carries
enemy_id/fight_id/position/elite (affixes slot in when Dev A's affix system
lands), `ProjectileSpawnInfo` carries projectile_id/position/velocity/
owner_peer_id; `fight_id` of 0 gets one assigned so every enemy names itself.

Dev A's `enemy_base.tscn` (W2-A9), `Projectile` base (W2-A6), and `Health`/
`HitInfo` (W2-A1) have not landed, so the spawners preload placeholder scenes
under `scenes/network/` (`placeholder_enemy.tscn`, `placeholder_projectile.tscn`)
and tests use `tests/helpers/enemy_base_stub.gd`, a CharacterBody2D with
`synced_position` / `current_anim` / `current_hp` / `fight_id` / `elite` — the
spec'd node shape — plus `apply_hit(amount)` with an overridable
`_resolves_hits()` seam (host-only by default) so unit tests can drive the
client-refusal path without a second instance (an unstarted ENet peer still
reports `is_server() == true`, so the true client check lives in the
two-instance smoke). Swap-in is mechanical and data-only: point
`EnemySpawner.enemy_scene` / `ProjectileSpawner.projectile_scene` at Dev A's
scenes, which must keep the replicated-prop names `synced_position` /
`current_anim` / `current_hp` (enemy) and `synced_position` / `synced_velocity`
/ `owner_peer_id` (projectile). Tests: `tests/unit/test_entity_spawners.gd`
(13); smoke step 3 drives the stub end to end.

### W2-B4 — Debug console, parser, core commands, `request_debug` (`debug-tools`)

`scripts/debug/debug_console.gd` is a `CanvasLayer` UI: a scrollback +
`LineEdit` toggled by the backtick (`debug_console`) action, plus the command
registry (`register(name, callable, help)`). `scripts/debug/debug_parser.gd`
tokenizes a line (whitespace split, double-quoted args keep spaces, `\"`
escapes). `scripts/debug/debug_commands.gd` installs the core set: `help`,
`spawn <enemy_id> [count] [elite] [affix]`, `give <type> <id> [stacks]`,
`gold <n>`, `skip` (a stub as of W2-B4; **superseded 2026-10-20 by W3-B5a**,
which wired it to `GameState.next_floor()` and added `floor <n>`), `seed <n>`,
`god`, `kill`, `heal`, `timestop <s>`,
`timeslow <factor> <s>`, `fps`, `dump`. Commands run on the **host**: a client's
console sends the line through `NetworkManager.request_debug(cmd, peer_id)`
(a validated `any_peer`/`call_remote`/`reliable` RPC that emits
`debug_command_requested`); the host's console executes and targets the issuing
peer (spawn at that player, gold/heal/god on that player).

Where a command touches a system that has not landed yet it validates its input
and reports the deferral rather than failing: `give`/`heal` wait on
weapons/abilities/relics/run-economy/combat-core (weeks 4-5), `skip` did until
W3-B5a wired it to `GameState` (**superseded 2026-10-20**), and `spawn`/`kill`
work today against the W2-B3
enemy placeholders. The console is added by `main.gd` in debug builds or with
`--debug-tools`, loaded lazily (never preloaded) so a release export that
filters `scripts/debug/` out never references it. There is no
`export_presets.cfg` yet, so the actual export filter is a week-12 step; the
lazy-load seam above is the part that must be in place by then (recorded in
`specs/SPEC-debug-tools.md` open items).

### W2-B5 — HUD v0, HudModel, Theme (`ui-hud`)

`scripts/ui/hud_model.gd` (`HudModel`, pure presentation, never queries
gameplay nodes by path) is the typed adapter the HUD widgets bind to:
`local_hp_ratio` / `local_is_downed` / `local_slot`, a `teammates` list of
`HudTeammate` (peer_id, name, hp_ratio, is_downed, slot), two `HudWeaponSlot`
entries (name, active, cooldown_fraction), and `floor_label`. It binds a
callable player registry (`NetworkManager.players` in game, a fake in tests);
`refresh(local_peer_id)` recomputes from that registry and emits `changed`.
HP is duck-read from the player's `Health` node with a full-bar fallback while
Dev A's W2-A1 hasn't landed. `cooldown_fraction(time_left, total)` is a static
helper; `set_weapon_cooldown(slot_index, tl, total)`,
`set_weapon_active(slot_index)`, and `set_floor_label(text)` drive the widgets.

`scenes/ui/hud.tscn` + `scenes/ui/hud.gd` (widget scripts `hp_bar.gd`,
`weapon_slot.gd`) is a CanvasLayer HUD: own HP bar, teammate bars with names
and a downed tint, two weapon-slot frames with an active gold border + cooldown
sweep, and a "FLOOR -" placeholder label. It wires `Events.player_*`,
`weapon_swapped`, `GameState.floor_changed`, and
`NetworkManager.player_joined/left` with **exact-arity handlers** (a shared
0-arg callback errors at runtime when a signal emits more args than the method
accepts — a bug the headless launch caught, not the GUT suite), plus a 0.25 s
poll. `main.gd` instantiates it lazily over the world flow via
`ResourceLoader.exists()` + `load()`, never preloaded. `assets/ui/theme.tres`
is the Theme v0: placeholder pixel font at 8 px (and 16 px) generated by
`tools/make_placeholder_font.gd` — the spec's CC0 m5x7 download is JS-gated on
itch.io, so a generated 5x7 atlas (CC0 by construction) ships now and a sourced
OFL font swap is the art-audio lane's recorded continuation — plus panel
styleboxes and the rarity/element palettes from SPEC-ui-hud. Tests:
`tests/unit/test_hud_model.gd` (15) + `tests/integration/test_ui_scenes.gd`
(6, instantiates the HUD with a fake `HudModel`); visual on-screen
confirmation is recorded as a manual check.

### W2-B6 — AudioManager real implementation + SfxBank placeholders (`art-audio`)

`scripts/autoload/audio_manager.gd` replaces the week-1 stub with the real
implementation: `play_music(track, fade)` crossfades between two
`AudioStreamPlayer`s (fade 0 switches instantly), `stop_music(fade)` fades
out and stops **every** player (so a stop issued mid-crossfade cannot leave
the incoming track playing), `play_sfx(id, pos, pitch_variance)` plays from a
pooled `AudioStreamPlayer2D` pool when `pos` is given and a non-positional
pool otherwise (both capped at 16; a full pool steals the oldest rather than
dropping a sound), `set_bus_volume(bus, linear)` maps linear→dB on the
Master/Music/SFX/UI buses, and a missing sfx id logs once and plays a
placeholder click. Time effects never change pitch. The four buses are
created at `_ready` if absent (see decision 16). `data/audio/sfx_bank.tres`
(a `SfxBank` Resource) maps the 20 week-2 ids to placeholder clicks generated
by `tools/make_placeholder_sfx.gd` under `assets/audio/sfx/<id>.wav`; the
real synth pipeline (W2-B7 / W2-A13) replaces the files later without
touching the bank. Tests: `tests/unit/test_audio_manager.gd` (21).

### W3-B1a — `RunState`, `RunPlayerState`, `RunResult`, `RunEndReason` (`run-economy`)

*Written retrospectively at the Week 3 close-out (2026-10-20); the code shipped
2026-10-19 and the per-task writeup was the debt this goal closes.*

The run's data model, and the first thing every other week-3 module reads. Four
`RefCounted` classes, each with a `Sync:` line in its doc comment:

- `scripts/run/run_state.gd` (`RunState`) — the seed, `floor_index` clamped to
  `MIN_FLOOR`..`MAX_FLOOR` (1..30), a **derived** `biome_index` (`(floor-1)/5+1`,
  1..6 — derived rather than stored so floor and biome cannot disagree), players
  keyed by peer id, the shared gold/ore pools, the kill/clear counters, and the
  advance threshold (`rooms_cleared`, `required_rooms_cleared`, `exit_open`,
  `can_advance()`, `advance_floor()`).
- `scripts/run/run_player_state.gd` (`RunPlayerState`) — one slice per player:
  peer/character/class ids, the weapon ids with their per-weapon mutations, relic
  and ability and potion ids, ascension, echo shards, class XP, gold share, and
  the downed/dead flags (`is_downed`, `is_dead`, `is_standing()`).
- `scripts/run/run_result.gd` (`RunResult`) — what a finished run reports:
  reason, seed, floors cleared, and per-peer `kept`/`lost` tables with a
  documented `empty_table()` key shape.
- `scripts/run/run_end_reason.gd` (`RunEndReason.Reason`) — `DEFEAT`, `EXTRACT`,
  `VICTORY`, `ABORT`. Its own file with a nested enum so `GameState.end_run` can
  type its parameter without depending on `RunResult`.

Content ids on a slice are `StringName`, because `RelicData`/`AbilityData` are
weeks 4 and 5; the swap-in keeps the field names and only replaces the element
type. Tests: `tests/unit/test_run_state.gd` (20 tests / 154 asserts).

### W3-B1b — the `GameState` run lifecycle (`run-economy`)

`scripts/autoload/game_state.gd` became the real lifecycle. `run: RunState` now
replaces the week-1 `RefCounted` stub, and three host-only calls drive it:

- `start_run(run_seed, start_floor, party)` — resolves the seed
  (**`forced_seed` verbatim when non-zero → the explicit caller seed → a host
  roll**), builds the `RunState` at `start_floor`, makes one `RunPlayerState`
  per `PlayerSpawnInfo`, and emits `run_started` plus the `Events` mirror. The
  host roll mixes clock entropy into a **seeded** `RandomNumberGenerator`; there
  is no global roll call anywhere on this path (decision 23).
- `next_floor()` — advances through `RunState.advance_floor()`, refuses past
  floor 30 and while the exit is shut, and emits `floor_changed(floor_index,
  biome)`.
- `end_run(reason: RunEndReason.Reason)` — builds the `RunResult` with
  `empty_table()` `kept`/`lost` placeholders, **clears `run` before emitting**
  (so a re-entrant listener is refused and `run_ended` fires exactly once), then
  emits `run_ended` plus the bus mirror.

All three warn and refuse on a client. `scripts/run/biome_placeholder.gd`
(`BiomePlaceholder`, id 1..6) gives the `Resource`-typed `floor_changed` biome
argument something real until Dev A's `BiomeData` lands — one line to swap in
`GameState.biome_for_index()`. `Events.floor_entered` is deliberately **not**
emitted here: floor-generation owns it, and emitting it too would update the HUD
twice for one floor. Tests: `tests/unit/test_game_state_run.gd` (18, later 28)
and `tests/integration/test_run_lifecycle_flow.gd` (2, which drives the real
`hud.tscn` so the `floor_changed` → HUD seam is checked at runtime). Decisions
23 and 24.

### W3-B1c — floor advance threshold states and `can_advance_floor()` (`run-economy`)

The rest of the loop: what counts as "this floor is done". `start_run()`
subscribes the host to `Events.room_cleared(room: Node)` through the named
handler `_on_room_cleared()` — never a lambda, which GUT never fires and which
cannot be disconnected — guarded by `is_connected()` so a second `start_run()`
replacing a live run cannot double-count, and disconnected in `end_run()` so a
finished run stops counting. The handler guards on `NetworkManager.is_host and
run != null` rather than being subscribed conditionally, because `Events` is a
global bus a client's own `Room` nodes will also drive: the counter is
host-authoritative state. New public API: `can_advance_floor() -> bool`
(`run != null and run.exit_open`, a pure predicate with **no** host check so the
HUD can read it on a client) and `last_advance_refusal: StringName` with the
`ADVANCE_REFUSAL_{NONE,NOT_HOST,NO_RUN,EXIT_SHUT,LAST_FLOOR}` constants, so
"refused, and why" is a readable value instead of only a log line. `next_floor()`
clears the refusal on every call, distinguishes its four branches, and the
`exit_shut` message carries the live `rooms_cleared of required_rooms_cleared`
ratio. `required_rooms_cleared` keeps its default of `0` = "no requirement
declared yet", which is deliberate: the real determinant is Dev A's Exit rule
(**blocked on Dev A (W3-A2)**), and `0` must not wedge an advanceable run.
Tests: `test_game_state_run.gd` 18 → 28 (10 new, written red first). Decision 25.

### W3-B2a — `Rope` interactable and the ROPE room populator (`run-economy`)

`scripts/run/rope.gd` (`class_name Rope extends Area2D`) is the extraction rope
and the first module-registered room populator. It satisfies the interactable
contract SPEC-player-controller's scan duck-types on (`prompt_text`,
`hold_seconds = 0.0`, `interact(player: Player) -> void`), sits on physics layer
6 ("interactable"), and is instantiated from
`scenes/dungeon/interactables/rope.tscn` — the SPEC-project location for room
interactables, in a folder that held only a `.gdkeep`, so no other lane's file
is touched. Three paths, each observable through its own signal
(`interaction_forwarded` / `extract_applied` / `extract_deferred`): the host
with a one-player run ends it immediately with `EXTRACT`; the host with two or
more players logs the week-5 vote deferral and leaves the rope usable; a client
hands its use to `NetworkManager.request_vote_rope` and never ends its own run.
`Rope.rope_populator()` returns the `Callable(room) -> void` a registry takes,
and `Rope.register_populator()` — called once from `main.gd`'s `_ready()` —
registers it against `FloorGenerator.register_populator(RoomType.ROPE, …)`,
reading `RoomType.ROPE` off Dev A's script constant map at runtime so this file
names no type that does not exist yet. Until that script exists the call is a
recorded no-op (**blocked on Dev A (W3-A3)**); the headless launch prints the
blocker line and carries on. `NetworkManager` gains the transport the client
path needs: the `request_vote_rope(yes)` RPC (SPEC-networking's `request_*`
convention, first line validating the sender) plus the two predicates behind
its guards, `can_apply_rope_request(sender)` and `can_send_request()`. Tests:
`tests/unit/test_rope.gd` (22 tests / 138 asserts), written and confirmed red
first, with `tests/helpers/interactable_stub.gd` standing in for Dev A's
`Interactable` component.

### W3-B2b — run ends with `DEFEAT` when every player is downed or dead (`run-economy`)

`GameState` now owns the run's failure branch. `start_run()` subscribes the
host to `Events.player_downed(player)` and `Events.player_died(player)` through
named handlers (`_subscribe_player_events`, idempotent, disconnected in
`end_run()`), and each handler writes the event into the run slice —
`RunPlayerState.is_downed` / `is_dead` — then runs `_check_run_defeat()`. That
check walks the party and, when no slice is still standing, prints
`[run] every player is downed or dead; ending the run` and calls
`end_run(RunEndReason.Reason.DEFEAT)`. The rule is SPEC-run-economy's "run ends
when every player is downed or dead (`DEFEAT`)" and BRIEF Assumption 7: a
downed player is not living, so **a solo run ends on its first down** and co-op
ends on the last one. Wire-visible results: `run_ended` (and `Events.run_ended`)
fire exactly once, `GameState.run` becomes null, and the `Events.room_cleared`
counter stops.

`RunPlayerState` gains `is_dead` and `is_standing()` (`not is_downed and not
is_dead`). `is_dead` is kept apart from `is_downed` so the summary can say
*which* happened; both make a player not-standing, so the check itself reads
one predicate.

The placeholder death/extract summary is one printed line, built by
`_run_summary_line(result, finished)` from the `RunState` snapshot (end_run has
already cleared the live one) and kept in the new public `GameState.last_run_summary`:

```
[run] DEFEAT — seed 4242, floors cleared 3, players: 1 downed, 2 dead
```

It prints for **every** end reason, not only defeat, because the same line is
the extraction summary until `ui-hud` builds the real panel (week 5). The
headless defeat path and its line are in
`.goals/evidence/g6-defeat-summary.log`; the full suite is 432 tests green in
`.goals/evidence/g6-gut.log`. Tests: `tests/unit/test_run_end_defeat.gd`
(22 tests / 81 asserts), written and confirmed red first (19 of 22 failing),
driving `Events.player_downed` / `Events.player_died` from test-local `Player`
doubles — bare `Player.new()` objects with only `peer_id` set, never added to
the tree, so nothing in Dev A's `player.tscn` or its states is touched
(**blocked on Dev A (W3-A5)** for the real `Downed`/`Dead` states and their
emitters; the swap-in is nothing on my side — the host already listens to the
spec's events).

### W3-B3a — `floor_ready` broadcast, client-local generation, `--seed` plumbing (`networking`)

The seed-sync half of the week-3 co-op promise: one broadcast seed, one floor on
every screen.

- **New `scripts/network/floor_generator_seam.gd`** (`FloorGeneratorSeam`) — the
  bridge to Dev A's `FloorGenerator`: `generate(run_seed, floor_index,`
  `biome_id, modifiers)`, `layout_hash_of(layout)`, `source_of(layout)`,
  `roll_modifiers(run_seed, floor_index)`, and a test-only injected generator.
  **blocked on Dev A (W3-A1)**: `scripts/generation/floor_generator.gd` still
  does not exist, so generation runs on the lane-B placeholder and says so once
  per process. The swap-in is nothing on this side — the seam resolves the real
  script the moment it lands and calls its `generate`/`roll_modifiers`. The one
  remaining swap is `GameState.biome_for_index`, which returns `BiomeData`
  instead of `BiomePlaceholder` then (**blocked on Dev A W3-A1/A6**); until it
  does, the generator is deliberately skipped rather than called with a biome
  its typed signature would reject.
- **New `scripts/network/floor_layout_placeholder.gd`**
  (`FloorLayoutPlaceholder`) — the lane-B stand-in for Dev A's `FloorLayout`:
  the same `layout_hash` field, derived deterministically from
  (seed, floor_index, biome_id, modifiers) through a seeded
  `RandomNumberGenerator`, with 8–14 room rects sampled from it (SPEC's room
  count and size ranges) and integer-only seed/hash arithmetic, so two processes
  cannot disagree.
- **`NetworkManager.floor_ready(seed, floor_index, biome_id, modifiers)`** —
  `@rpc("authority", "call_local", "reliable")`, exactly the payload
  SPEC-networking declares. Its first line validates the sender through
  `can_accept_floor_ready(sender)`: the host accepts only its own local
  authority call (sender 0), a client only the host's broadcast (peer 1).
  `apply_floor_ready` is the one place a floor is generated and recorded
  (`floor_seed`, `last_floor_layout`, `last_floor_modifiers`), and on a client it
  tells `GameState` which floor the host is on. `broadcast_floor_ready` (host
  only) applies locally and `rpc_id`s every remote peer. The broadcast is
  triggered by `GameState.run_started` (floor 1, before anyone moves) and
  `GameState.floor_changed` (every later floor), and re-sent to a peer that
  joins mid-run.
- **`GameState`** — `apply_remote_floor(floor_index, biome_id, modifiers)` (client
  only; refused on the host, which owns the run and already emits
  `floor_changed`), `biome_for_index(biome_id)` as the single biome swap point,
  and the `remote_floor_index` / `remote_floor_modifiers` the client records.
- **`--seed` plumbing** — the launch arg already landed in
  `GameState.forced_seed`; `start_run` resolves it, `run_started` carries it, and
  `broadcast_floor_ready` puts that same value in the payload. Two instances
  launched with `--seed=20261020` logged the same `layout_hash`
  (`3525914442204165144`, floor 1, biome 1) in the manual pair recorded at
  `.goals/evidence/g7-floor-smoke/`.
- **`--smoke-floor[=<sec>]`** (new `LaunchArgs` arg, the `--smoke3` pattern) and
  a `Main._start_smoke_floor` driver: the host starts a run once a client has
  joined (5 s wait, so a single instance still exercises the path) and both
  peers log the `[floor]` line, which is what the W3-B3a-2 smoke will compare.
- **Tests**: `tests/unit/test_floor_sync.gd` (20 tests / 65 asserts) written and
  confirmed red first (GUT ignored the script — parse error, both new classes
  absent), plus `tests/helpers/floor_generator_stub.gd` (a `FloorGenerator`-shaped
  double, **blocked on Dev A (W3-A1)**) and 4 new
  `tests/unit/test_launch_args.gd` cases. Verified: full GUT 33 scripts / 459
  tests / 12674 asserts exit 0 (`.goals/evidence/g7-gut.log`); headless import
  exit 0 with 0 error lines (`.goals/evidence/g7-import.log`); `tools/smoke_two.sh`
  28/28 ok exit 0 before the sync-touching commit (`.goals/evidence/g7-smoke.log`);
  headless `-- --host --smoke-floor=8` exit 0 with no script errors
  (`.goals/evidence/g7-launch-floor.log`); a `grep` for `Engine.time_scale` under
  `scripts/` and `scenes/` and a `grep` for `randi()` / `randf()` / `shuffle(`
  under `scripts/` both came back empty; no Dev A file touched.

### W3-B3a-2 — two-instance proof that one `--seed` gives one floor (`networking`)

W3-B3a proved the RPC shape in a single process and proved the agreement once by
hand. This task makes the agreement a standing, failing-capable assertion inside
the smoke, so a future change to the seed path breaks the build instead of
silently desyncing floors.

- **`tools/smoke_two.sh` gained a floor-sync phase** after step 3: two more
  host/client pairs, each launched with the *same* `--seed` on both sides
  (`run_floor_pair <tag> <seed>`), and comparisons rather than prints:
  - the `layout_hash` each peer logged for floor 1 is extracted with
    `floor_hash <file> <seed>` (`grep -Eo` on
    `[floor] ready seed <seed> floor 1 biome <n> …layout_hash <n>`) and the two
    values are compared for **equality** — the `check()` helper is only used for
    presence (both peers armed, the host started the run with the client in it);
    a hash that is missing, zero or different fails the run;
  - a third pair on a different seed asserts the hash actually **tracks** the
    seed, so a constant that both peers happen to print cannot pass;
  - the seed is part of the extraction pattern, so a peer that generated from
    some other seed yields an empty hash and fails rather than accidentally
    matching.
- **Result** (`.goals/evidence/g7b-smoke/`, `GODOT=… bash tools/smoke_two.sh`,
  33 checks, exit 0, 55 s):

  | seed | host `layout_hash` | client `layout_hash` |
  |---|---|---|
  | `20261020` | `3525914442204165144` | `3525914442204165144` |
  | `987654321` | `708545516277063756` | `708545516277063756` |

- **Negative control** (`.goals/evidence/g7b-smoke/negative-control.log`): the
  same helper and the same equality branch, run over fabricated logs, take the
  `FAIL` path for divergent hashes and for a peer on another seed, and the `ok`
  path only for a genuinely identical pair. A check that cannot fail proves
  nothing, so the failing path is recorded too.
- **Dev A's `FloorGenerator` had still not landed** when this ran
  (`scripts/generation/` holds only `.gdkeep`; re-checked at the start of this
  task), so the proof runs against the lane-B placeholder layout through
  `FloorGeneratorSeam` — **blocked on Dev A (W3-A1)**. The check itself is
  generator-agnostic: it reads the `layout_hash` the seam produced, so re-running
  `GODOT=… bash tools/smoke_two.sh` after W3-A1 lands re-runs this exact proof
  against the real generator with no edit to the script.
- **Tests / import**: full GUT 33 scripts / 459 tests / 12674 asserts exit 0
  (`.goals/evidence/g7b-gut.log`); headless `--import` exit 0 with 0 error lines
  (`.goals/evidence/g7b-import.log`). No `scripts/` or `scenes/` file changed —
  this task is the smoke harness plus its evidence.
- **Still only floor 1.** The driver starts the run once the client is in, so
  the pair proves the `run_started` broadcast; the `floor_changed` re-broadcast
  is covered by `tests/unit/test_floor_sync.gd` and reaches two processes in the
  later smoke steps. Walking a floor advance through the smoke needs a driver
  change (the `skip` console command was a stub at the time of this writeup;
  **W3-B5a landed it 2026-10-20**, so only the driver is missing) and is on the
  manual-check list rather than claimed here.

### W3-B3a-3 — smoke tooling: `$OUT` is created, and one `PORT` reaches both peers (`debug-tools`)

The smoke is the verifier's tool as much as mine, and it had two defects that
were recorded at W3-B3a-2 but owned by nobody: every log is a plain
`> "$OUT/…"` redirect with no `mkdir`, and `PORT` reached only the client's
`--join` while the host kept binding `NetworkManager.DEFAULT_PORT` (7777). Both
made a *different* invocation of the script silently meaningless, which is
worse than failing. This task closes both.

- **`$OUT` is created by the script.** One `mkdir -p "$OUT"` next to
  `OUT="${OUT:-$(mktemp -d)}"` — no behaviour change when the directory already
  exists, and the DoD's "step output is copied to `.goals/evidence/…`" no longer
  depends on somebody else having made the directory.
- **`PORT` has a real home: `LaunchArgs --port=<n>`.** `main.gd` already passed
  `options.port` to `NetworkManager.host()` and `NetworkManager.join()`; the only
  gap was that nothing parsed a port for the host (`LaunchArgs.port` defaulted to
  `NetworkManager.DEFAULT_PORT`, and only `--join=ip:port` could move it). New
  arg, parsed like `--seed`/`--smoke3`:
  - `--port=<n>` must be an integer in `1..65535`; anything else is an error line
    and the default port stays (validated, like every other arg).
  - an explicit port inside `--join=ip:port` **wins over** `--port`, whichever
    order the two appear in (`port_arg` is resolved into `port` after the whole
    argv is read, and `_join_port_given` records the more specific form). The
    join's own port is the more specific statement of intent.
  - `--port` alone does not change the mode (still `MENU`), matching `--seed`.
  - `tools/smoke_two.sh` now passes `--port=$PORT` to **both** peers of all three
    pairs (steps 1+2, step 3, and both floor pairs) and keeps the client's
    `--join=127.0.0.1:$PORT`, so the host binds exactly what the client joins.
- **Both paths proven, plus the pre-fix failure as a negative control**
  (`.goals/evidence/g7c-smoke/`):

  | run | before the fix | after the fix |
  |---|---|---|
  | `OUT=<tmp>/nested` (dir absent) | `exit 1` — `nested/host.log: No such file or directory`, `FAIL client never connected` (`negative-control-prefix-out.log`) | `exit 0`, all checks `ok`, logs land in the nested dir (`run-default-port-nested-out.log`) |
  | `PORT=7901` | `exit 1` — host logged `hosting on port 7777`, client logged `joining 127.0.0.1:7901`, `FAIL client never connected` (`negative-control-prefix-port.log`) | `exit 0`, 33 checks, a real two-peer pair per phase (`run-port-7901-nested-out.log`) |

  The pre-fix logs are committed because a check whose failing path was never
  observed is an assumption (W3-B3a-2's rule): they show that a wrong port
  produced a *one-player host that still ran to completion*, which is exactly the
  silent degradation this task removes.
- **Tests / import**: `tests/unit/test_launch_args.gd` gained 6 tests (port sets
  the host port, port alone keeps `MENU`, port applies to a join without one,
  `--join` port wins in either order, six bad values reported once each with the
  default kept, inclusive `1`/`65535` bounds), written first and confirmed red
  (5 failures) before the parser change. Full GUT 33 scripts / 465 tests /
  12697 asserts exit 0 (`g7c-gut.log`); headless `--import` exit 0 with 0 error
  lines (`g7c-import.log`). No Dev A file touched; no `.tscn` touched; no
  `project.godot` / Input Map / autoload-signature / `Events` / save-schema / CI
  / addons change.
- **Not claimed**: the smoke still runs its pairs sequentially on one port, so a
  parallel smoke is untested; the default port remains 7777 and nothing else in
  the project reads `--port`. `net_lag` and the rest of W3-B5's console work were
  untouched **by this task** — it owns only the two tooling findings. (Both
  landed afterwards: `skip`/`floor <n>` at W3-B5a and `seed`/`net_lag` at
  W3-B5b, 2026-10-20.)

### W3-B3b — layout hash assertion with the host-layout fallback (`networking`)

`SPEC-networking` "Seed sync" asks for three things in one sentence: the host
*hashes* the layout, clients *assert* the same hash, and a mismatch *logs an
error and requests the host's layout as a fallback*. W3-B3a shipped the first
half of the sentence only — every peer generated a floor from the broadcast seed
and printed its hash, but nothing compared them, so a client that quietly
generated a different floor would have played it.

- **The host asserts, the client compares.** `NetworkManager.last_floor_hash` is
  now recorded wherever a floor is generated (`apply_floor_ready`), and
  `broadcast_floor_ready` sends it to every remote peer right after `floor_ready`
  through a new `@rpc("authority","call_local","reliable") layout_asserted(
  layout_hash)`. The payload of `floor_ready` itself is untouched — the spec
  fixes it at `(seed, floor_index, biome_id, modifiers)` and a test asserts those
  four argument names — so the hash travels in its own broadcast rather than as a
  fifth field. A late joiner gets both, in that order.
- **Agreement is silent.** `apply_layout_assertion` (the plain client-side check,
  driven directly by the unit tests the same way `apply_floor_ready` is) logs
  `[floor] layout asserted: floor N layout_hash H agrees with the host on peer P`
  and changes nothing: no regeneration, no second `floor_changed`, no request.
- **A mismatch recovers instead of crashing.** It `push_error`s
  (`[floor] layout hash mismatch on floor N: local L, host H — asking the host
  for its layout`), records the divergence in `GameState`
  (`note_floor_divergence` → `floor_divergence_floor/_local_hash/_host_hash`,
  read back through `has_floor_divergence()`), and sends the new
  `request_floor_layout(floor_index)` RPC to the host. There is **no retry**:
  regenerating from the same inputs is exactly what produced the wrong layout.
- **The fallback carries the host's layout, not its inputs.** The host answers
  with `floor_layout(floor_index, layout_hash, layout)` —
  `@rpc("authority","call_local","reliable")`, sender-validated — where
  `layout` is the layout's wire form. `FloorLayoutPlaceholder.to_wire()` /
  `from_wire()` send the rooms as a flat `PackedInt32Array` of `(x, y, w, h)`
  quadruples plus the hash, so the peer that applies it holds the host's *rooms*
  and the host's hash; `FloorGeneratorSeam.serialize_layout` /
  `deserialize_layout` are the seam that lets Dev A's real `FloorLayout` describe
  itself the same way (`to_wire()` / `from_wire()`), blocked on Dev A (W3-A1).
  The client applies it without generating anything and without re-announcing the
  floor — it already followed that floor from `floor_ready`.
- **Verified.** `tests/unit/test_floor_sync.gd` 20 → 34 tests / 135 asserts,
  written first and confirmed red (GUT ignored the file: parse error). New tests
  cover: the three RPCs' existence, argument names and `@rpc` configuration; the
  shared sender rule (`can_accept_floor_broadcast`) on host and client; the
  host-serves-only-a-remote-client rule; the host hashing what it generated; the
  agreement path changing nothing; the mismatch path logging an error
  (`assert_push_error`), recording the divergence, requesting the layout and
  *not* regenerating (proved with an injected `FloorGeneratorStub` that records
  zero calls); the host refusing to apply a layout it is sent; an unusable reply
  leaving the client where it was; and the wire round-trip. Full GUT 33 scripts /
  479 tests / 12767 asserts exit 0 (`g8-gut.log`); headless `--import` exit 0
  with 0 error lines (`g8-import.log`); headless `-- --host --smoke=6` exit 0
  with 0 script/parse errors (`g8-launch.log`); `tools/smoke_two.sh` exit 0 with
  35 `ok` lines (`g8-smoke-run-default-port.log`, logs in `.goals/evidence/
  g8-smoke/`) — including the new check that the **client's own assertion line
  names the host's hash** (`3525914442204165144` for seed `20261020`,
  `708545516277063756` for `987654321`), which is what makes the assertion a
  two-process fact rather than a unit-test one. Both banned-literal greps empty.
  No Dev A file, no `.tscn`, no `project.godot` / Input Map / autoload-signature
  / `Events` / `scripts/data/` / save-schema / CI / addons change.
- **Not claimed**: the mismatch path is proven in one process, with the host's
  reply applied by hand — the smoke's two peers agree by construction (that is
  the point of the seed sync), so a real end-to-end mismatch would need a
  deliberately divergent generator, which is Dev A's `FloorGenerator` (W3-A1) and
  not a lane-B thing to fake in a shipped build. What the smoke proves is that
  the assertion *runs and agrees* between two real processes.
- **Environment note (not a code change).** The first smoke run of this task
  failed `FAIL client never connected` because two leftover headless `--host`
  instances from the previous step (started 00:55, no `--smoke` timer, so they
  run forever) were still bound to UDP 7777 — the smoke's default port. G7c's
  `--port` override ran the whole smoke green on `7901` while they were alive;
  they were then killed and the smoke re-run green on the default port. A plain
  `--host` instance has no exit timer by design, so this is expected behaviour of
  a manual/two-instance run, not a defect — but it does mean a stray host can
  make a *default-port* smoke fail confusingly, and `PORT=<free>` is the fix.

### W3-B3c — the lane-B floor determinism soak (`networking`)

*Written retrospectively at the Week 3 close-out (2026-10-20); the soak shipped
2026-10-20 as `2bd4cd1` and this is the per-task writeup.*

Week 3's checkpoint asks for a 500-seed floor soak. Dev A's
`scripts/generation/floor_generator.gd` does not exist, so the only soak that can
actually run is over the layout the game genuinely generates today: the lane-B
`FloorLayoutPlaceholder` that `FloorGeneratorSeam` hands **every** peer. That is
not a consolation prize — it is the exact class the two-process `layout_hash`
comparison compares, so the soak covers the production path rather than a double
that could agree with itself.

`tests/integration/test_floor_generation_seeds.gd` — 8 tests / **41 069 asserts**
/ 1.9 s, well under SPEC-floor-generation's 60 s headless budget. It soaks 500
seeds across floors 1..30 and all six biomes and asserts: the same
`(run_seed, floor_index, biome_id, modifiers)` rebuilds the same `layout_hash`,
rooms and `room_count`; 500 different seeds give **500 distinct** hashes with 0
neighbouring collisions; `to_wire()` → `from_wire()` keeps the identical hash,
rooms, count, seed, floor and biome; every room rect lies inside the 96×96 grid;
`room_count` stays in the spec's 8..14; and a one-input-changed negative control
(floor_index, biome_id, a modifier) moves the hash, so the equality assertions
cannot pass vacuously.

Written red first, and it found a real defect: `FloorLayoutPlaceholder.for_floor`
drew room origins from a flat 0..95, so a room could run up to 16 tiles past the
grid edge. Origins are now bounded by `GRID_TILES - size`. That fix changes every
placeholder `layout_hash`, which is why the smoke's numbers moved from the
G7b/G8 values — the smoke compares its two peers **to each other**, not to a
recorded constant, so it stayed green. The spec's own soak (over
`FloorGenerator.generate()`, with flood-fill reachability, Exit reachable, exactly
one `ROPE` on floor 2, no overlapping rooms, 3-wide corridors) is still unstruck
and is **blocked on Dev A (W3-A3)**; the soak's last case asserts the *seam's
source*, so the moment the real generator lands the test tells the next author
that the loops above now soak the wrong class instead of silently passing.

### W3-B4a — `player_downed` / `player_revived` broadcast and downed-flag sync (`networking`)

`SPEC-networking`'s week-3 row reads "downed and revive synced", and the plan
line (G2) names three things: the downed flag travels in StateSync, and the two
`Events` signals have a host broadcast behind them. Until now the downed flag
belonged to nobody: `Player.is_downed` was a bare field that no peer ever wrote,
so a client could not have known a teammate was down even if Dev A's `Downed`
state had existed.

- **The flag is `is_downed`, not `downed`.** The plan line says "add a `downed`
  replicated property", but the field already existed under the name the rest of
  the code reads — SPEC-player-controller's `Downed`, `HudModel.local_is_downed`,
  `GameState`'s defeat check — and `downed` on its own is already the player's
  *signal*. Renaming the field to match the plan's prose would have meant a
  second name for one fact (or a signal and a property with the same name, which
  GDScript does not allow). A test asserts the downed-named replicated set is
  exactly `[.:is_downed]`, so the divergence from the plan's wording is checked,
  not incidental.
- **`is_downed` moves from a bare field to the replicated one.** In
  `player.tscn`'s `StateSync` `SceneReplicationConfig` it is
  `NodePath(".:is_downed")`, `replication_mode = 2` (`ON_CHANGE` — a down is an
  edge, not a per-frame value) and `spawn = true`, so a peer joining mid-run is
  told at once that someone is already down. In `player.gd` the field gained a
  setter so that *either* route — the replicated value or a broadcast — runs the
  same reaction.
- **The reaction is one method, `_apply_downed_state()`.** It re-runs
  `refresh_authority()` and, going down, emits the player's own `downed` signal.
  `refresh_authority` and `simulates` now both subtract `is_downed`: a downed
  player runs no state and takes no input on any peer, and `_process_unhandled_input`
  is off too. That is the presentation half of `Downed`.
- **The host announces, the client obeys.** `NetworkManager._ready` connects
  `Events.player_downed` / `Events.player_revived` to `_on_player_downed` /
  `_on_player_revived`. On the announced host those call
  `route_player_downed` / `route_player_revived`, which `rpc_id` the new
  `@rpc("authority","call_local","reliable") broadcast_player_downed(peer_id)` /
  `broadcast_player_revived(peer_id, by_peer_id)` to every **remote** peer. On a
  client, the event *is* the broadcast landing, and the handler stops at the host
  guard — so the bus event is not re-broadcast in a loop.
- **The broadcast applies to the registry, not to a node.** `apply_player_downed`
  / `apply_player_revived` are the plain, directly-testable bodies (the split
  W3-B3a/B3b established, because a single process cannot fake a client's sender
  id — LESSONS): they look the peer up in `NetworkManager.players`, write
  `is_downed`, and emit the bus event for the rest of the game to read
  (`GameState`'s defeat check, the HUD). An unknown peer is a `push_warning` and
  `false`, not a crash. A revive also carries **who** did it; `by_peer_id == 0`
  means "no reviver", which is how the wipe path revives.
- **One sender rule, shared.** The new `can_accept_host_broadcast(sender)` is the
  general form of the existing `can_accept_floor_broadcast`, which now forwards
  to it: the host accepts only its own local call (sender 0), a client accepts
  only `HOST_PEER_ID`. No existing signature changed.
- **`remote_peer_ids()` is the target list.** New public helper, host or not: the
  reverse of `local_peer_id` in `peer_ids`. Both routers check it first and
  return `false` when it is empty — which is the solo case, and the one real bug
  this task found (the first version returned `true` unconditionally after the
  loop and so reported a send that never happened).
- **Verified, red first.** `tests/unit/test_player_sync.gd` 19 → 37 tests
  (113 asserts), written first and confirmed failing for the right reasons
  (`.goals/evidence/g2/red-player-sync.log`: the core criterion fails with
  `ARRAY([]) != ARRAY([^".:is_downed"])`, i.e. the property was genuinely not in
  the replication config). New tests cover: the replicated path exists, is
  `ON_CHANGE`, is in the spawn state, and is the *only* downed-named path (a
  typo like `is_downned` would not resolve, and a test asserts that it does not);
  every replicated path resolves on the player; the flag reaching the HUD model a
  client actually renders from, and clearing again on revive; a downed player
  stops simulating on a client while a live one still does; `downed` emitted
  exactly once, and not on a redundant write; a client taking the flag from the
  host's broadcast; both broadcasts emitting the bus event on the client; an
  unknown peer applying nothing and returning `false`; both RPCs' `@rpc`
  configuration (`authority`, `call_local`, `reliable`) and both argument names;
  the sender rule on host and client, including a client's local call to the
  broadcast body being refused; the auto-connect between the bus and the router;
  the router targeting remote peers only, returning `false` with nobody to tell,
  refusing on a client, and refusing an event that names no player. Full GUT
  **34 scripts / 505 tests / 505 passing / 53906 asserts, exit 0**
  (`.goals/evidence/g2/gut-full.log`, up from 487); headless `--import` exit 0
  with 0 error lines (`g2/import.log`); headless `-- --host --smoke=6` exit 0
  with 0 script/parse errors (`g2/launch-host.log`); `tools/smoke_two.sh` exit 0
  with 35 `ok` lines and 0 FAIL (`g2-smoke/run-smoke.log`) — run **before** the
  commit, as the sync rule requires.
- **The `player.tscn` edit is a judgment call, recorded.** `player.tscn` is
  nominally Dev A's file, but `tests/unit/test_player_sync.gd`'s own header
  already says "Owned by networking (PR into player.tscn, Dev A reviews)", and
  PLAN G2 sanctions registering this property. The change is three lines inside
  the `StateSync` sub-resource and nothing else: no new node, no change to
  `InputSync`, and the input/position fields are untouched. It is the one place
  where the flag can be replicated at all, so it was not possible to meet the
  goal without it; it is flagged here for review rather than asked about,
  because it is the plan's own stated deliverable. No other `.tscn`, no
  `project.godot` / Input Map / `Events` signal / `scripts/data/` Resource / save
  schema / CI / addon was touched, and no Dev A logic.
- **Not claimed: a two-process downed sync.** Everything above is proved in one
  process, with the client side driven through the `_become_client()` seam
  (`is_host = false`, `local_peer_id = 2`, `peer_ids = [1, 2]`) and the
  broadcast body called directly, because the offline multiplayer peer always
  reports `is_server == true` and a single process cannot forge a remote sender
  (LESSONS). The two-instance proof of a downed flag crossing the wire needs a
  driver that downs a player on one peer and an assertion on the other, which is
  PLAN **G11a** (smoke driver + launch arg) and **G11b** (step-5 green run) —
  reserved for those goals rather than faked here. Also, nothing yet *causes* a
  real down: Dev A's `Downed`/`Dead` states and bleed-out timer (W3-A5) are the
  emitters, and `Player.request_revive` was still a `pass` stub **at this
  writeup** — W3-B4b filled it in on 2026-10-20 (see the section below), so the
  only remaining gap is the states that emit the down. What this task
  proves is that when those land, the flag and the two signals already have a
  host-owned broadcast and a replicated path behind them.

---

### W3-B4b — `request_revive` and the host revive rule (`networking`)

W3-B4a left the flag and the two signals with a host-owned broadcast behind
them; the third deliverable on the same task line — `request_revive`, and the
rule the host applies when a client asks — was still missing, and
`Player.request_revive` was a `pass` stub. This is that half: a client asks, the
host decides, and a refused ask is a readable reason rather than a silence.

- **The client asks, the host decides.** `NetworkManager.request_revive(target_peer_id)`
  is `@rpc("any_peer","call_remote","reliable")` — the same shape as
  `request_vote_rope` / `request_floor_layout`, with one named argument
  (`target_peer_id`) — and the host resolves the asking peer from
  `multiplayer.get_remote_sender_id()`, never from the payload. The player's own
  `Player.request_revive(target)` now forwards to the new
  `NetworkManager.send_revive_request(target.peer_id)`, which emits a
  `revive_requested` signal *before* it sends, so a single-process test can see
  the ask even when there is nobody to ask (`can_send_request()` is false in a
  faked client, and the RPC is deliberately not sent — the same trick
  `floor_layout_requested` uses at W3-B3b).
- **The seam and the rule are two functions.** `can_apply_revive_request(sender,
  target)` is the yes/no seam the plan asked for; `apply_revive_request(sender,
  target)` is the body, which re-derives the reason through
  `revive_refusal_reason(sender, target)` and records it in
  `last_revive_refusal`. The split is deliberate: a boolean is what a caller
  branches on, and the `StringName` is what the debug console (W3-B5) and the
  refusal log line need to say *why*.
- **Eight reasons, all of them refusals a real session can produce.** Not the
  host; not a request (sender 0 — a local call); no such target; the target is
  not downed; the target is dead this floor; the sender is not a player in this
  session; the sender *is* the target; out of range. The order matters and is
  checked: "not downed" is tested before the reviver is even looked up, so a
  request naming a stranger and a standing player reads as `target_not_downed`
  rather than as a spurious `no_reviver`. Every refusal is a `push_warning`, not
  a `push_error` — a refusal is the system working, and GUT counts engine errors
  as failures (LESSONS).
- **The distance is local `position`, deliberately.** `revive_distance` reads
  `reviver.position.distance_to(target.position)`, not the global transform. In
  the running game every player is a direct child of `World/Players`, so local
  positions are comparable; outside the tree a player double has no global
  transform to read, and reading one raises an engine error that GUT would score
  as a failure. The boundary is exact: a teammate standing at exactly
  `REVIVE_RANGE` revives.
- **The numbers live on `NetworkManager`, and the swap point is named.**
  `REVIVE_RANGE = 48.0` (1.5 tiles at 32 px), `REVIVE_SECONDS = 3.0`,
  `REVIVE_HP_FRACTION = 0.4`, plus `REVIVE_SPEED_MULT_MIN = 0.1` as the floor
  under `revive_speed_mult`. `revive_seconds_for(reviver)` and
  `revive_hp_for(max_hp)` turn them into values other modules and tests can
  read: the first divides by the reviver's `revive_speed_mult` (clamped at the
  minimum, so a 0.0 or negative multiplier cannot produce an infinite or
  backwards hold), and the second rounds to a whole number of HP and never
  returns less than 1, so a revive of a 0-max-HP player still leaves them alive.
  `revive_hp_for` is the read half only — **writing** the restored HP is Dev A's
  `Health` (blocked on Dev A W2-A1) and is not done here.
- **A revive stands the player up through the existing path.** The host apply
  calls the same `apply_player_revived(target.peer_id, sender)` W3-B4a wrote for
  the receiving half of a broadcast, so host-apply and client-broadcast converge
  on one body: `is_downed` is cleared, the bus event `Events.player_revived`
  fires, and the host's `route_player_revived` takes it from there. That also
  honours G2's deferred promise — `apply_player_revived` now resolves the reviver
  once and emits the player's own `revived(by)` signal first, which is the one
  emitter decision 33 reserved for the revive path.
- **`GameState` needed a revive handler, and that was the real gap.**
  `RunPlayerState.is_downed` could be set by `_on_player_downed` but nothing ever
  cleared it, so "the revived slice leaves the downed state and `is_standing()`
  becomes true again" was unsatisfiable before this task. The new host-only
  `_on_player_revived(player, by)` clears `is_downed` through the existing
  `_is_tracking_run()` / `_slice_for()` seam and is connected in
  `_subscribe_player_events()` / disconnected in `_unsubscribe_player_events()`,
  so an ended run cannot be resurrected by a late event. It writes `is_downed`
  only: `is_dead` is untouched, which is how SPEC-player-controller's "Dead for
  the rest of the floor" (and the week-5 next-floor revive) stays true.
- **The `player.gd` edit is a cross-lane change, flagged.** `Player.request_revive`
  is Dev A's signature and its body was a stub carrying the comment "Filled in
  by networking week 3" — so filling it is this task, but the file is Dev A's and
  it is recorded here for Dev A's review rather than assumed. It is two lines
  (a null guard and the forward) plus the doc comment stating that networking
  owns the rule; no other member of `player.gd` was touched.
- **Verified, red first.** `tests/unit/test_revive.gd` is new: **24 tests /
  108 asserts**, written before the implementation and confirmed failing for the
  right reason — `Invalid call. Nonexistent function 'apply_revive_request' in
  base 'Node (network_manager.gd)'` on all 24, kept at
  `.goals/evidence/g3/red-test-revive.log`. It covers the three constants and
  both derived numbers (including the `revive_speed_mult` scaling and its floor,
  and `revive_hp_for` at 100 → 40, 250 → 100, 7 → 3, 1 → 1, 0 → 1); the RPC
  contract (`any_peer`, `call_remote`, reliable, argument name `target_peer_id`,
  and that a *local* call is not a client's request); each refusal reason in
  turn, with the exact-range boundary passing where just-outside does not; a
  valid request standing the teammate up with the bus event emitted exactly once
  and `[target, holder]` as its arguments, the target's own `revived` signal
  naming the reviver exactly once, and a repeated request reviving nothing; the
  client-authority cases; and the run slice's downed flag clearing so
  `is_standing()` is true again while `is_dead` is left alone. Full GUT
  **35 scripts / 529 tests / 529 passing / 54014 asserts, exit 0**
  (`.goals/evidence/g3/gut-full.log`, up from 505); headless `--import` exit 0
  with 0 error lines (`g3/import.log`); headless `-- --host --smoke=6` exit 0
  with 0 script/parse errors (`g3/launch-host.log`); `tools/smoke_two.sh` exit 0
  with **35 `ok` lines and 0 FAIL** (`g3-smoke/run-smoke.log`, logs in
  `g3-smoke/run/`) — run **before** the commit, as sync commits require — with
  the floor hashes unchanged from G1/G2 (`3600649381522393848` for seed
  `20261020`, `536024383148136417` for `987654321`). `Engine.time_scale` and
  global-RNG greps over `scripts/` and `scenes/` are empty, and no base stat is
  written anywhere in the three changed files.
- **The negative control was forced, and is kept.** With `REVIVE_RANGE`
  temporarily widened to `480.0`, exactly one test failed —
  `test_the_reviver_must_stand_within_revive_range` — and nothing else, which is
  what makes the range criterion a check rather than an assumption
  (`.goals/evidence/g3/negative-control-revive-range.log`). The constant was
  restored and the suite re-run green.
- **Not claimed: a real revive in a real session.** Nothing in the game calls
  `request_revive` yet — the hold-to-revive input, the `Downed`/`Dead` states
  and the 30 s bleed-out are Dev A's **W3-A5** (the swap point PLAN G3 names),
  and a live revive is driven end-to-end by that input. The 3 s is a number the
  host and the UI can both read; the timer that counts a hold is not built here,
  and `revive_hp_for`'s result is not written to `Health` (blocked on Dev A
  W2-A1). A two-process revive needs the smoke driver of PLAN **G11a/G11b**.
  What this task proves is that when the input lands, the ask, the host's rule,
  the refusal reasons and the slice-clearing all exist and are checked.

### W3-B5a — `skip` and `floor <n>` wired to `GameState` (`debug-tools`)

**What shipped.** `skip` is no longer a stub: `DebugCommands._cmd_skip` calls
`GameState.next_floor()` and then reads the authority's own reason out of
`GameState.last_advance_refusal`, returning either `skipped to floor N (biome B)`
or `skip refused: <reason>`. `floor <n>` is new and registered in
`DebugCommands._register()`: it validates its argument against
`RunState.MIN_FLOOR`..`RunState.MAX_FLOOR`, then walks to the target by calling
`GameState.next_floor()` **once per floor** rather than writing `floor_index`
directly — so every floor it passes through is announced on `floor_changed`, the
same exit rule applies as a normal advance, and there is no teleport that can
step over a shut exit or a last floor. The wording of a refusal lives in the new
private `_advance_refusal_text(reason)`, one readable phrase per
`GameState.ADVANCE_REFUSAL_*` code, so `GameState` keeps carrying a reason code
and nothing about presentation.

**Files.** `scripts/debug/debug_commands.gd` (skip rewritten, floor + the
refusal-text helper + `MAX_FLOOR_JUMPS` added, two help lines updated) and
`tests/unit/test_console_parser.gd` (the `skip` stub test replaced by 15 cases).
No other file changed.

**How it was verified.** Tests first, red for the right reason
(`.goals/evidence/g4/red-console-parser.log`: 16 failing, the old stub's text in
every `skip` failure and `unknown command: floor` in every `floor` failure),
then green. `test_console_parser.gd` 43/43 / 145 asserts
(`.goals/evidence/g4/gut-console.log`); full suite **35 scripts / 543 tests /
543 passing / 54 081 asserts**, exit 0, up from the 529 baseline
(`.goals/evidence/g4/gut-full.log`); `--headless --path . --import` exit 0 with
0 error lines (`g4/import.log`); headless `-- --host --smoke=6` exit 0 with 0
script/parse errors (`g4/launch-host.log`); `GODOT=… bash tools/smoke_two.sh`
exit 0 with **35 `ok` lines and 0 FAIL** (`g4/smoke-run.log`, logs in
`g4/smoke/`) — run even though this commit adds no RPC, because the smoke is the
standing two-process proof; `grep -rn "Engine.time_scale" scripts/ scenes/` and
the global-RNG grep both print nothing.

**The cases.** `skip` advances exactly one floor and emits `floor_changed` once;
`floor 5` from floor 1 lands on floor 5 with 4 advances and 4 `floor_changed`
emits; `floor 30` is accepted, `floor 0` / `floor 31` / `floor upstairs` are
refused with a readable reason and change nothing; a target behind the current
floor is refused as behind; and each refusal branch is a separate case — no live
run (a host session with a null run, so the reason is `no_run` and not
`not_host`), a client, a shut exit (`required_rooms_cleared` raised above
`rooms_cleared`), and the run's last floor.

**Judgment calls.** Recorded as decision 35.

**Not claimed.** `floor <n>` only advances: there is no API that moves the run
backwards and none is invented here, so a target behind the current floor is a
readable refusal rather than a jump. Nothing drives the console line from a
launched game in this task — the unit tests run the real `DebugConsole.run()`
against the real `GameState` and `NetworkManager`, and the console's
LineEdit-submit path (host-gated, unchanged) is what a human uses in the editor.
The two-process smoke still does not walk a floor advance: adding that driver is
PLAN **G12b**, which this task unblocks.

---

### W3-B5b — `seed` confirmed end to end, and the `net_lag` placeholder (`debug-tools`)

**What shipped.** Two halves of the last open Week 3 Dev B item.
(1) `seed <n>` was already writing `GameState.forced_seed`; what was missing was
the proof that it reaches a **run**, so the command's contract is now asserted
end to end: `seed 4242` → `GameState.start_run(999, …)` → `run.seed == 4242`
(the W3-B1 precedence rule `forced_seed` → caller seed → host roll), and
`seed 0` clears the field so the caller's seed comes through instead.
(2) `net_lag <ms> [loss%]` is registered with its help line and implemented as
the placeholder SPEC-debug-tools asks for in Week 3: it validates a whole
non-negative millisecond value and an optional percentage, records them on
`NetworkManager` (`net_lag_ms`, `net_lag_loss`), clamps loss to 0–100, clears on
`net_lag 0`, and says in its result that it is a placeholder whose real delay
proxy lands in **W4-B11** — so a call can never be mistaken for a working
simulation. The values also appear in the `dump` payload.

**Files.** `scripts/debug/debug_commands.gd` (net_lag registered, `_cmd_net_lag`
added, class doc and `dump` payload updated), `scripts/autoload/network_manager.gd`
(two documented fields with the `TODO(debug-tools, W4-B11)` swap), and
`tests/unit/test_console_parser.gd` (12 new cases: 2 seed-precedence, 10 net_lag,
plus the `CORE_COMMANDS` entry and the autoload reset in `after_each`). No other
file changed, and the commit added no RPC.

**How it was verified.** Tests first, red for the right reason
(`.goals/evidence/g5/red-console-parser.log`: **11 failing / 43 passing**, every
net_lag case failing on `unknown command: net_lag` and on
`Invalid access to property 'net_lag_ms'`), then green. `test_console_parser.gd`
**54/54 / 179 asserts**; full suite **35 scripts / 554 tests / 554 passing /
54 115 asserts**, exit 0, up from the 543 baseline of W3-B5a
(`.goals/evidence/g5/gut-full.log`); `--headless --path . --import` exit 0 with
0 error lines (`g5/import.log`); headless `-- --host --debug-tools --smoke=6`
exit 0 with 0 script/parse errors (`g5/launch-host.log`); `GODOT=… bash
tools/smoke_two.sh` **35 `ok` lines, 0 FAIL**, exit 0, logs in `g5/smoke/`
(`g5/smoke-run.log`) — run before the commit because it touches
`network_manager.gd`; `grep -rn "Engine.time_scale" scripts/ scenes/` and the
global-RNG grep both print nothing.

**Judgment calls.** Recorded as decision 36. The one worth repeating: `net_lag`
is a **local** setting (`SPEC-debug-tools`: "simulated latency on this peer"),
but a client's console line routes to the host through `request_debug`, so a
client cannot yet lag itself — W4-B11 needs a per-peer path before the smoke can
lag one side. That is a limitation of the placeholder stated here, not a bug
introduced now.

**Not claimed.** Nothing is delayed or dropped: `net_lag` records intent only,
and no traffic reads the two fields. The per-peer routing gap above is open.
`seed` is proven against `GameState`, not against a launched game's console
LineEdit — the unit tests drive the real `DebugConsole.run()`, real `GameState`
and real `NetworkManager`.

### W4-B1 — `Events` conformance test, real parameter types, pinned placeholders (`effect-system`)

W4-B1 is "the full signal set from the spec, emitted by owning modules". The bus
already declared all 37 signals, so this goal made that declaration *checkable*
and closed the two drifts the check found. The emitter half landed next (G8,
2026-10-20) and is written up at the end of this section.

**`tests/unit/test_events_bus.gd` (10 tests / 330 asserts) reads the spec rather
than transcribing it.** It parses the `signal …` lines out of the fenced block
under `### Events bus` in `specs/SPEC-effect-system.md` at run time and compares
them against `Events.get_script().get_script_signal_list()` — deliberately the
script's *own* signals, because `get_signal_list()` also returns Node's inherited
ones (`ready`, `renamed`, …). It asserts the name set is equal with no extras and
none missing, and for every signal the exact parameter names, order, count and
declared type. Type comparison runs through a `TYPE_MAP` from the spec's type
name to the declaration expected today: a built-in (`int`, `float`, `bool`,
`StringName`, `Dictionary`, plus the bare `Node`/`Resource` the spec itself
writes) is compared against `type_string()`, anything else against the argument's
`class_name`. A spec type with no `TYPE_MAP` entry fails, so a new signal in the
spec cannot slip past the map unnoticed.

**The two drifts it found, both fixed:**

1. `run_started(run_seed: int)` → `run_started(seed: int)`. The spec writes
   `seed`. Every emit and connect site is positional, so this is a pure rename;
   `GameState.run_started(run_seed)` is the autoload's own, separate signal and
   keeps its name.
2. Five signals still declared their hit payload as `RefCounted` and `run_ended`
   still declared `RefCounted`, though both real classes exist in this repo now.
   `hit_landed`, `crit_landed`, `player_damaged`, `enemy_killed` and
   `elite_killed` declare `hit: HitData`; `run_ended` declares `result: RunResult`.
   `HitData` is stats-status's week-2 mirror of combat-core's `HitInfo`, matching
   field-for-field; the test pins that mapping in one place, so the week the real
   `HitInfo` lands the swap is a rename in the bus plus one line of `TYPE_MAP`.

**The placeholders are pinned rather than described.** Every parameter still
waiting on a real class has exactly one line in `events.gd` of the form
`## TODO(<module>): <SpecType> <- <Placeholder> (blocked on Dev X, <task-id>)`.
The test asserts one such line per placeholder type, that each names the class
which replaces it, and that the owner set matches a hard-coded map: `HitInfo` and
`Projectile` → combat-core, `Enemy` → enemies-ai, `Room` → floor-generation,
`Pickup` → run-economy, `RelicData`/`SynergyData` → relics, `WeaponData`/
`MutationData` → weapons, `AbilityData` → abilities, `AscensionData` →
classes-characters, `StatusEffects.Status`/`Combo` → stats-status. The blocker ids
are the real ones from `tasks/todo.md` (W2-A1, W2-A6, W2-A9, W3-A2, W5-A1, W5-A4,
W7-A3), so "we retype this when the owner lands" cannot rot into a comment nobody
re-checks.

Also asserted: the five signals the spec says clients re-emit (`hit_landed`,
`enemy_killed`, `relic_picked`, `room_cleared`, `currency_gained`) — with that
list itself parsed out of the spec's sentence, so it cannot drift either — and
that the bus carries signals only: no script-declared method and no property
flags `PROPERTY_USAGE_SCRIPT_VARIABLE`.

**Negative controls (BRIEF C13).** The comparison helpers are pure functions, so
one test drives the failing path directly against mutated tables: a dropped
signal, an undeclared extra signal, a renamed parameter, an untouched
placeholder and an invented type each produce a mismatch, while the real bus
produces none. The red run is kept at `.goals/evidence/g7/red-test-events-bus.log`
— 9 tests, 4 passing, 5 failing, every failure for the right reason (the
`run_started` parameter name, the five `RefCounted` hits, the `RefCounted`
result, and the previous free-text TODO block that did not parse).

**Verified:** `-gtest=res://tests/unit/test_events_bus.gd` 10/10 green
(`.goals/evidence/g7/test-events-bus.log`); full suite **36 scripts / 564 tests /
564 passing / 54 445 asserts** exit 0 (`g7/gut-full.log`, up from the 554
baseline); `--import` exit 0 with **0** error or warning lines
(`g7/import.log`); headless `-- --host --debug-tools --smoke=6` exit 0 with 0
script/parse errors (`g7/launch-host.log`); two-instance smoke **35 `ok`, 0
FAIL**, exit 0 (`g7/g7-smoke/run-smoke.log`), run before the commit.

**The emitter half (G8, 2026-10-20) — `tests/helpers/event_emitter.gd` and
`tests/unit/test_events_emitters.gd` (10 tests / 413 asserts).**

`EventEmitterHelper` is the test-only emitter the rest of Week 4 listens
through: one named method per bus signal (`emit_hit_landed()`,
`emit_player_dodged()`, … — 37 of them), each building its own valid fake
arguments and emitting on `Events`, plus `callable_for(name)` returning the
`Callable` for a named emitter method so a test never writes a method name as a
literal, `all_signal_names()` and `dev_a_owned_signals()`. Listeners are always
connected as named methods — a connected lambda never fires under GUT — and the
test picks the handler by the signal's declared arity, because a handler whose
arity does not match is an engine error.

Arguments are built from `tests/helpers/` doubles: a bare `Player.new()` that is
never added to the tree (so Dev A's `_ready` never runs — the
`test_run_end_defeat.gd` pattern), an `EnemyBaseStub` for the enemy signals, a
plain `Resource` carrying a `resource_name` for the `*Data` parameters whose
Resources land in W4-B5/later, and a new `EventEmitterNodeStub` for the
parameters still declared `Node` (`Room`, `Pickup`, `Projectile`, `source`).
The helper frees every node it created in `cleanup()`, which the test calls in
`after_each`.

The test file covers four things:

- **Coverage against the spec.** It parses the signal names out of the same
  `### Events bus` block `test_events_bus.gd` reads, and asserts the emitter
  table is exactly that set: an emitter method for every signal, no method
  without a signal, exactly one method each, and every emitter method taking
  zero arguments. `get_script_method_list()` is used rather than
  `get_method_list()`, because the latter also returns the inherited
  `Object.emit_signal()` and would read as a stray emitter. A pure
  `_coverage_problems()` helper does the comparison, and a negative-control test
  drives it with a dropped and an invented signal so the check is known to be
  able to fail (BRIEF C13).
- **Every emitter reaches a listener.** For all 37 signals: connect a named
  recorder, call the emitter through `callable_for()`, assert exactly one call
  and that it carried the signal's declared number of arguments, then
  disconnect. A further case asserts the player-first signals carry a real
  `Player` and the hit signals a real `HitData`.
- **The emitters Dev B owns fire from their real owner**, not from the helper:
  `GameState.start_run` emits `Events.run_started` and `GameState.end_run` emits
  `Events.run_ended`; a `room_cleared` on the bus is counted by the host in
  `GameState.run.rooms_cleared`; `NetworkManager.apply_player_downed` /
  `apply_player_revived` emit `Events.player_downed` / `player_revived` with the
  named peer and reviver.
- **The blocked record.** The nine signals W4-A4 names (`hit_landed`,
  `crit_landed`, `player_damaged`, `heavy_attack_released`, `weapon_swapped`,
  `projectile_fired`, `enemy_killed`, `enemy_spawned`, `player_dodged`) each
  carry a `blocked on Dev A (W4-A4)` line in the helper's doc comment — asserted
  per name with a regex, so a line cannot go missing — and the phrase is
  asserted present in `tasks/todo.md`.

**Nothing in the production bus changed in this goal.** No file under
`scripts/` or `scenes/` was touched: the emitter is a test instrument, so the
"Ask first" list is untouched and no new decision is required. Where an emitter
is still missing in production, it is because its module does not exist yet:
run-economy's loot emitters are W4-B8, relics' `relic_picked` is W4-B5/B6,
stats-status's status/combat signals are W4-B4, and time's `entity_time_applied`
is W4-B9 — each lands in its own task, and this helper is what lets the relics
that listen to them be tested in the meantime. Dev A's nine are W4-A4.

**Verified:** `-gtest=res://tests/unit/test_events_emitters.gd` 10/10 / 413
asserts green (`.goals/evidence/g8/`); red run first, GUT refusing the file with
a parse error because neither new class existed
(`.goals/evidence/g8/red-test-events-emitters.log`); full suite **37 scripts /
574 tests / 574 passing / 54 858 asserts** exit 0 (`g8/gut-full.log`, up from
the 564 baseline); `--import` exit 0 with **0** error or warning lines
(`g8/import.log`); two-instance smoke **35 `ok`, 0 FAIL**, exit 0
(`g8/smoke-run.log`), run because the bus is the interface every sync-adjacent
module emits on. No `Engine.time_scale`, no global RNG, no Dev A file, no
`.tscn`, no `project.godot` / Input Map / autoload-signature / `Events` /
`scripts/data/` / save-schema / CI / addons change.

---

## Decisions made without a human

These are the judgment calls taken during weeks 1 and 2 that were not dictated
by a spec, so the accountability contract is explicit. Where a decision is
already recorded in a spec or a comment, the location is given.

1. **`physics_interpolation = true` in `project.godot`** — not in the
   SPEC-foundation settings table. Turned on so networked movement (positions
   arriving once per physics tick) renders smoothly instead of stepping. It goes
   with the W1-B9-era fix to draw players and camera between physics ticks
   (`61195b1`). If it ever causes problems with the pixel art, it is a one-line
   revert, but the rendering path was written against it.
2. **`inferred_declaration` stays at Ignore** (Godot's default, not written to
   `project.godot`) — Warn would flag every `:=`, which the code style uses
   everywhere, and would bury real warnings. Recorded in SPEC-foundation.
3. **Controller binding deviation** — `ability_2` = RB, `ability_3` = R3,
   `ultimate` = L3. The Input Map has no chords, so the original "A for
   interact" conflict was resolved by giving interact A and moving the others.
   Recorded in SPEC-foundation and `tasks/todo.md`.
4. **GUT 9.7.1 vendored** — the exact release (tag `v9.7.1`), resolving the
   SPEC-foundation open question on which GUT version. Recorded in SPEC-foundation.
5. **CI downloads Godot itself** — the workflow `curl`s the official
   `Godot_v4.7.2-stable_linux.x86_64` zip from `godotengine/godot-builds` and
   runs it from a temp dir. No third-party setup action, so there is no
   dependency on an action publishing 4.7.2. Recorded in SPEC-foundation.
6. **Stale `C:\Godot` doc path** — SPEC-project.md documents Godot at
   `C:\Godot\Godot_v4.7.2-stable_win64_console.exe`, and `tools/run_two.ps1`
   defaults to `C:\Godot\...`. That path does **not** exist on this machine;
   the working binary is the console build at
   `C:\Users\Dsedg\Downloads\Godot_v4.7.2-stable_win64.exe\`. All commands in
   this handoff use the real path or the `godot` on PATH. Docs are not updated
   here because that is a project-doc change the human should sign off on.
7. **`--smoke` launch arg added** — not in the spec's launch-arg list, but the
   headless two-instance smoke needs a way to autowalk, log positions, and quit
   by itself. Implemented in `LaunchArgs`/`main.gd`, documented in the script
   doc comment and `tools/smoke_two.sh`.
8. **Solo = host with one peer** — solo play runs `start_solo()` on an
   `OfflineMultiplayerPeer` through the exact same code path as hosting, so
   there is no separate single-player branch to keep in sync. Decided in
   SPEC-networking.
9. **Spawn positions and `PlayerSpawnInfo` fields** — the spec's spawn dict is
   `{peer_id, character_id, class_id, weapon_ids}`; the shipped `PlayerSpawnInfo`
   adds `spawn_position` (a ring around tile (10,10), radius 48, y halved so
   players never overlap) and `slot` (lowest free co-op slot, drives player
   color). Both are host-authored and serialized to plain types for the
   spawner. Recorded in `player_spawn_info.gd` / `player_spawner.gd`.
10. **`max_chars_per_second = 131072`** — raised from the default so future
    debug-console and log spam is not silently dropped mid-session. In
    SPEC-foundation's table.
11. **`World/Players` is Y-sorted itself** — Godot only interleaves a child
    container's children with its siblings when that container is also
    Y-sorted, so players drawn in front of/behind walls needs the flag on
    `Players` (commit `b79f7c0`). Recorded in SPEC-foundation.
12. **W1-B9 landed in Dev A's scene via a reviewed PR** — `player.tscn` is
    Dev A's; the synchronizer configuration was contributed as a PR into it
    with Dev A reviewing, per the cross-owner seam rules. `player.gd` carries
    the required "Sync:" ownership line.
13. **Client prediction scope** — prediction covers local movement only (move,
    face, animate). Attacks will start on client input but hits are decided by
    the host (spec'd, not yet implemented). The local player reconciles against
    the last acked input tick rather than snapping to the host position.
14. **CI observability limits** — no PR workflow is in use (we develop on
    `main`), so CI is triggered by pushing to `main` rather than by a PR; the
    Actions run may not be queryable from this machine (no `gh`/token).
    The workflow config was reviewed, and the same import + test jobs are run
    locally and green. Confirmation of a live green Actions run is outstanding
    and non-blocking.
15. **W2-B4 debug console design** — (a) the console is wired into `main.gd`
    (foundation, both lanes) behind `OS.is_debug_build() or --debug-tools`,
    loaded with `load()` + `ResourceLoader.exists()` rather than `preload` so a
    release export that filters `scripts/debug/` never references it (no
    `export_presets.cfg` exists yet, so the export-filter step itself is
    week-12; the lazy-load seam is what must be ready now). (b) `request_debug`
    lives on `NetworkManager` per SPEC-networking's `request_*` convention and
    emits a new `debug_command_requested(command_line, peer_id)` signal for the
    console; the host validates `get_remote_sender_id() == peer_id` and only
    then executes. (c) Command handlers live on a `DebugCommands` instance the
    console holds (not a static/transient object) so bound callables never
    dangle. (d) Backtick is polled in `_process` instead of `_unhandled_input`
    so the toggle still works while the `LineEdit` has focus (the key would
    otherwise be eaten as text). (e) The command result is shown on the
    **host's** console; a client's own console echoes "sent to host: <line>"
    — a result round-trip RPC was judged not worth the extra surface for week 2
    and is recorded as a possible polish. (f) `--debug-tools` was added to
    `LaunchArgs` (a user arg, no `project.godot` change) because
    SPEC-debug-tools names it. Blocked-on-Dev-A seams are recorded in
    `.goals/LOG.md`: `give`/`heal` need run-economy/relics/weapons/combat-core,
    `skip` needed floor-generation (met by W3-B5a, **2026-10-20** — `skip` and
    `floor <n>` now drive `GameState` directly), `god` is debug-local state
    until Health consumes it.
16. **W2-B6 AudioManager buses are created at runtime** — SPEC-art-audio names
    the Master/Music/SFX/UI buses, but the repo ships no
    `default_bus_layout.tres` and a `project.godot` `[audio]` edit is on the
    ask-first list, so `AudioManager._ensure_buses()` adds any missing bus
    idempotently at `_ready` (`AudioServer.add_bus()` + `set_bus_name(...)`;
    `add_bus()` returns void in 4.7, so the new index is `bus_count - 1`). If
    a bus layout file ever lands, the runtime path becomes a no-op for
    existing buses.
17. **W2-B6 SfxBank is a lazy id→path map, not a preload of streams** —
    `data/audio/sfx_bank.tres` is a `SfxBank` Resource holding
    `Dictionary[StringName, String]` res paths; `get_stream(id)` loads the
    file on first use. That lets `tools/make_placeholder_sfx.gd` write the 20
    placeholder `.wav`s and the bank in a single pass with no
    import-ordering dependency (the wavs need not be imported before the bank
    is saved), and the bank survives later wav re-imports. Generic
    `hit_light`/`hit_heavy` stand in for the spec's 5 per-weapon-type hits
    until Dev A's weapons land (blocked on Dev A, W2-A7); the real synth SFX
    (W2-B7 / W2-A13) swap in by replacing the wav files, without touching the
    bank.
18. **W2-B1 TimeManager expiry is physics-frame based, not wall-clock** — each
    effect is `{source, factor, expires_on_frame}` where the frame is
    `Engine.get_physics_frames() + frames`, so a stop on the ENEMY stack does
    not freeze the stack that manages it (a slow expiring mid-stop still
    expires). The RPC broadcast is start-only (`time_effect_applied` /
    `entity_time_applied`); clients re-derive the same expiry from the shared
    duration, keeping lockstep without a second round trip. Rewind hooks stay
    stubbed for week 4. A scaled `timer()` stores nodes by instance id and
    resolves them with the global `instance_from_id()` — `Object.instance_from_id`
    is not a static call in GDScript (a G5 gotcha).
19. **W2-B2 damage-deviations and the mirror type** — the ability-power scale is
    applied only when `hit.scales_with_ability_power` is set, so weapon hits
    are unaffected; the MARK-forced crit requirement ships as `HitData.force_crit`
    (StatusEffects sets it in week 4 — the term is in the formula now);
    `status_mult` is a literal 1.0 with its week-4 terms documented in the
    formula's doc comment; `current_hp_ratio` lives on `StatBlock` so MAX_HP
    base changes keep the fill fraction. Dev A's `HitInfo` (W2-A1) is mirrored
    by `HitData` with matching field names — blocked on Dev A, mechanical swap.
20. **W2-B3 placeholders and the host-only seam** — `EnemySpawner` /
    `ProjectileSpawner` live under `World/Entities` (y-sorted, `spawn_path = ..`)
    as `MultiplayerSpawner` subclasses; clients are refused via an overridable
    `_can_spawn()` seam and `push_warning` (push_error would trip GUT's
    error-counting). Dev A's assets haven't landed (W2-A9/A6/A1), so
    `scenes/network/placeholder_{enemy,projectile}.tscn` stand in and
    `tests/helpers/enemy_base_stub.gd` drives tests + smoke step 3; the stub's
    `apply_hit` is host-gated through `_resolves_hits()`. Swap-in is data-only:
    Dev A points their scenes at the spawner exports, keeping the replicated
    prop names. No files were created in Dev A's `scenes/enemies/`,
    `scenes/projectiles/`, or combat-core.
21. **W2-B5 HUD wiring and font** — Events → HUD uses exact-arity named
    handlers only (a shared 0-arg callback errors at runtime when a signal
    emits more args than the method accepts; the headless launch caught it,
    the synthetic GUT tree does not). HP is duck-read from the player's Health
    node with a full-bar fallback until W2-A1. The Theme's pixel font is a
    generated 5x7 placeholder (CC0 by construction) because the spec's m5x7
    download is JS-gated; an OFL font swap is the art-audio continuation — no
    acceptance criterion depends on the specific font. HUD is added lazily by
    `main.gd` and "visible in test room" is met by the fake-HudModel scene test
    + headless launch; the on-screen pointer check is manual.

### Week 3 decisions

22. **Week 2 gate verdict — recorded before Week 3 starts (2026-10-19).**
    Verdict: **partial**. Re-verified on `main` @ `3b992de` immediately before
    Week 3 began, from the repo rather than from memory:

    - `tasks/todo.md`: W2-B1 .. W2-B6 are all ticked; W2-B7 and W2-B8 are open;
      all 13 of Dev A's W2-A1 .. W2-A13 are open.
    - `git tag`: lists `week-1` only. **`week-2` is not created and will not be
      created retroactively** — the design doc's Week 2 "Done when" includes
      Dev A's combat core (attacks, dodge, weapon swap, Health/Hitbox/Hurtbox,
      3 enemies), none of which has landed, so the milestone is genuinely
      unmet. `specs/WEEKLY.md` already records "Met: partial" and the withheld
      tag; creating the tag now would claim a milestone that did not happen.
    - `"$GODOT" --headless --path . --import` exits 0 with no parse errors
      (`/c/Users/Dsedg/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`),
      log at `.goals/evidence/g1-import.log`.
    - Full GUT suite exits 0: **27 scripts / 338 tests / 12110 asserts, all
      passing**, ~7 s, log at `.goals/evidence/g1-gut.log`.
    - `specs/WEEKLY.md` week-2 entry already says "Met: partial" and names the
      open items.

    What this means for the rest of the run: Dev B's lane is complete for
    Week 2, so nothing in my lane is repaired here; the open ids
    (**W2-A1..W2-A13, W2-B7, W2-B8**) are carried as blockers, not as tasks.
    Week 3 proceeds on the basis that every Dev A dependency is unlanded, so
    each W3-B task is built against the spec interface plus a `tests/helpers/`
    stub and records `blocked on Dev A (W3-Ax)`. `week-3` will be tagged only
    if Dev A's W3-A1 .. W3-A7 also land during this run; otherwise the gap is
    stated in `WEEKLY.md`, here, and in `.goals/LOG.md`. This is recorded
    rather than asked because the run is unattended (BRIEF Assumption 1) and
    because the raw goal's own rule — tag `week-3` "once Dev A's tasks are also
    done" — shows the human expects milestone tags gated on the whole
    checkpoint.

    **Resolved 2026-10-20 by decision 37:** Dev A's W3-A1 .. W3-A7 did not land
    during this run, so the gap is stated in `WEEKLY.md`, in decision 37 and in
    `.goals/LOG.md`, and `week-3` is **not** created — exactly as this decision
    said it would be.

23. **`GameState` run lifecycle (W3-B1b) — seed precedence, `end_run`
    signature, and emit order.**
    - `end_run(reason: RunEndReason.Reason)` replaces the week-1 `int`
      placeholder. This is **not** an unasked API change: the stub's own doc
      comment said "`reason` is RunEndReason once run-economy defines it", and
      `SPEC-run-economy.md` declares the parameter by that name. Call sites
      passing `RunEndReason.Reason.X` are unchanged.
    - **Seed precedence** in `start_run`: `GameState.forced_seed` (the `--seed`
      launch arg, set by `main.gd`) wins when non-zero; otherwise an explicit
      caller seed is used; otherwise the host rolls one. This satisfies both
      readings of BRIEF Assumption 12 — `forced_seed` non-zero is used
      verbatim, and a run with no seed at all still gets a non-zero one.
    - The host roll comes from clock entropy (`Time.get_unix_time_from_system()`
      ms mixed with `Time.get_ticks_usec()`) fed into a **seeded**
      `RandomNumberGenerator`; there is no global roll call anywhere in the
      lifecycle, and the rolled seed is the single value both peers later
      generate floors from (`floor_ready`, W3-B3).
    - `end_run` **clears `run` before emitting** `run_ended`, so a listener that
      calls `end_run` again (or a second caller in the same frame) is refused
      and `run_ended` fires exactly once per run. The `RunResult` is built from
      the finished run captured in a local, and per-player `kept`/`lost` tables
      are seeded with `RunResult.empty_table()` for every player (the real keep
      rules are week 5, BRIEF Assumption 9).
    - `start_run` is **replace**-on-second-call (with a warning) rather than
      refuse. A run that is somehow started twice is recoverable and the newest
      run is the live one, which avoids a refuse-on-restart dead end before the
      Map Room exists to sequence it (week 5).
    - `RunState.can_advance()` already gates `advance_floor()`, so `next_floor`
      is refused while the current floor's exit is shut as well as past floor
      30. The explicit `can_advance_floor()` helper and the `Events.room_cleared`
      counter subscription are W3-B1c (the next goal), not this one.
    - `request_extract_vote` got a real body — host guard plus the week-5
      deferral print — instead of staying `pass`, so the co-op rope path is
      honest about what it does rather than silently "succeeding".

24. **`BiomePlaceholder` and the Events-bus mirror (W3-B1b).**
    - `GameState.floor_changed(floor_index, biome)` keeps its `Resource`-typed
      parameter (BRIEF Assumption 17) and now carries a real value: the new
      `scripts/run/biome_placeholder.gd` (`BiomePlaceholder extends Resource`,
      `id` 1..6) derived from `RunState.biome_index`. Dev A's `BiomeData` (W6,
      blocked on W3-A1/A6) replaces it with a one-line change in
      `GameState._biome_for()` plus deleting the file. `null` was rejected
      because the HUD and floor generation both need the biome to read
      something, and the BRIEF's out-of-scope note explicitly says to use a
      `Resource`-typed placeholder plus an integer `biome_id`.
    - `start_run` / `end_run` also emit the **`Events` bus** signals
      `run_started(seed)` / `run_ended(result)` (the bus argument was renamed
      from `run_seed` to the spec's `seed` by W4-B1/G7 on 2026-10-20, and
      `run_ended` now takes the real `RunResult` rather than `RefCounted`;
      `GameState.run_started(run_seed)` is this autoload's own signal and keeps
      its name), because
      `SPEC-run-economy.md`'s "Interfaces provided" lists them as Events that
      run-economy emits. `Events.floor_entered` is **not** emitted here — that
      one belongs to floor-generation (SPEC-floor-generation), and dual-emitting
      it from `next_floor` would make the HUD update twice for one event.

25. **Floor advance threshold states (W3-B1c).** The seam BRIEF Assumption 6
    describes is now wired end to end, host-side, with no Dev A code in it.
    - `GameState` subscribes to `Events.room_cleared(room: Node)` in
      `start_run()` through the named handler `_on_room_cleared()` — a lambda
      would never fire under GUT (LESSONS) and cannot be disconnected, and the
      named handler matches the signal's exact arity (LESSONS: arity mismatches
      error at runtime). `end_run()` disconnects it, so a finished run stops
      counting rooms; `_subscribe_room_cleared()` guards with `is_connected`,
      so a second `start_run()` replacing a live run cannot double-count.
    - The handler **guards on `NetworkManager.is_host` and on `run != null`
      rather than only being subscribed conditionally.** `Events` is a global
      bus that a client's own `Room` nodes will also drive once Dev A lands
      them (SPEC-floor-generation emits `room_cleared` per peer's local room),
      so a client must be unable to move the counters even if something wires
      the signal for it. The counter is host-authoritative state.
    - The handler counts **every** `room_cleared`, not just combat rooms. Per
      `SPEC-floor-generation.md` only locking rooms (COMBAT / ELITE_COMBAT)
      emit it — Treasure and Shrine never lock and never clear — so filtering
      here would duplicate a rule that already lives in the emitter.
    - `required_rooms_cleared` keeps its default of `0`, which means
      "this floor has not declared a requirement yet" and leaves `exit_open`
      true. That is deliberate: Dev A's Exit rule (all COMBAT/ELITE_COMBAT
      rooms on at least one Start–Exit path, `SPEC-floor-generation.md` §55)
      has not landed — **blocked on Dev A (W3-A2)** — and until it does, the
      floor generator writes the count into this field and `0` must not wedge
      the run. It also keeps the W3-B1b `next_floor` tests honest, since a
      floor with no requirement is genuinely advanceable.
    - **New public API, recorded as a judgment call:** `GameState.can_advance_floor() -> bool`
      (`run != null and run.exit_open`) and `GameState.last_advance_refusal`
      with its `ADVANCE_REFUSAL_*` constants. `can_advance_floor()` comes from
      BRIEF Assumption 6 verbatim. `last_advance_refusal` is mine: the goal
      asks `next_floor()` to refuse "with a recorded reason", and a
      `push_warning` alone is not readable back. `RunState.can_advance()` stays
      as the underlying predicate, so the field is a diagnostic on top of the
      existing gate, not a second source of truth.
    - `next_floor()` now distinguishes its four refusals
      (`not_host` / `no_run` / `exit_shut` / `last_floor`) instead of one
      combined warning, and clears `last_advance_refusal` on every call so a
      stale reason is never read as the current one. The `exit_shut` message
      carries the live `rooms_cleared of required_rooms_cleared` ratio.
    - Nothing on this path touches a base stat or a time scale: it reads one
      `Events` signal and increments one integer.
    - ~~**Handle for G12:** `next_floor()` is now gated, so the debug console's
      `floor <n>` jump cannot go through it … W3-B5 must jump via
      `RunState.floor_index` directly — or set `required_rooms_cleared` to 0
      first — rather than expect the gate to let a debug jump through.~~
      **Superseded 2026-10-20 by W3-B5a (decision 35).** The prediction was
      wrong and the code is better for it: `floor <n>` **walks** one
      `next_floor()` call per floor rather than assigning `floor_index`, so a
      debug jump is subject to exactly the rules a real walk to the Exit is —
      it cannot teleport over a shut exit, it announces every floor it passes on
      `floor_changed`, and `floors_cleared` stays honest. No second write path
      onto run state was invented, and the gate was not weakened. The stale
      prescription is struck rather than left to contradict the tree.

26. **The rope and its ROPE populator (W3-B2a).** Six calls the specs leave
    open, all taken in the direction the specs already point:
    - *"Solo" means a one-player run, not "nobody else is standing".* BRIEF
      Assumption 8 and PLAN G5 both say that a two-player run defers to the
      week-5 vote prompt, so `Rope._apply_use` branches on
      `RunState.players.size()`. The week-5 rule ("all *living* players must
      vote yes, downed players don't vote") is recorded in that function's
      comment for the vote prompt to adopt; implementing it now would let a
      lone standing player rope out of a floor while their downed teammate is
      still on it, which nothing asks for.
    - *`interaction_forwarded` fires before the transport guard.* The signal
      means "the client handed its use to the request path", so it fires for
      any client that has a session. What follows is a warning and no send
      when the session has no remote host (solo, an offline peer, a
      single-process test) — `rpc_id` to the local peer under `call_remote` is
      an engine error, and GUT runs on an offline peer, so the guard is what
      keeps `test_rope.gd` free of engine noise without changing what a real
      client does.
    - *`NetworkManager.can_send_request()` is new public API*, beyond the
      signatures the specs declare: `is_active and not is_host and not
      multiplayer.is_server()`. It is the honest form of "is there a remote
      host to send a `request_*` to", and it is why `Rope` never pretends to
      have forwarded inside one process.
    - *`request_vote_rope` refuses sender 0.* A direct local call has no remote
      sender, so it is not a client's request; the host's own rope use goes
      through `Rope._apply_use` instead. The handler forwards to
      `GameState.request_extract_vote`, which is still the week-5 deferral, so
      the vote keeps exactly one host-side application path.
    - *`rope.tscn` uses a `Polygon2D` for its placeholder art*, matching
      `scenes/network/placeholder_enemy.tscn`, rather than a PNG from
      `assets/sprites/icons/placeholder/` — that folder holds A–Z letter
      sprites (the font atlas' source), none of which reads as a rope. The
      BRIEF's "placeholder art already in `assets/`" is met in spirit: the
      rope's shape is placeholder geometry until W3-B6's art pass.
    - *The rope sits at the room's origin.* `RoomSpec.interactable anchor` is
      Dev A's (W3-A2); the populator carries a `TODO` naming it and the
      swap-in is the single `rope.position` line.

27. **The all-downed run end and its summary (W3-B2b).** Five calls the specs
    leave open:
    - *`RunPlayerState.is_dead` is new.* SPEC-run-economy lists `is_downed` but
      needs a dead player to count as not-standing too ("every player is downed
      **or dead**"). One flag could not carry both facts, and the summary is
      required to say which happened, so death gets its own field and
      `is_standing()` is the single predicate the defeat check reads. The
      alternative — reusing `is_downed` for a death — would have made the
      end-of-run line lie about how a teammate finished.
    - *The summary names each player and their status.* The key shape
      (`reason`, `seed`, `floors_cleared`, per-peer kept/lost) is already in
      `RunResult`; the line adds the standings, because a `DEFEAT` line with no
      players is not a summary of anything. Format is
      `[run] <REASON> — seed S, floors cleared N, players: <peer> <status>, …`,
      one line so the smoke and the evidence greps can find it.
    - *The line prints for every end reason, not just `DEFEAT`.* The task text
      calls it the "death/extract summary", so `EXTRACT` and `ABORT` print it
      too; a separate defeat-only print would mean two formats for one screen.
    - *`GameState.last_run_summary` is new public API*, beyond the declared
      signatures: the printed text is otherwise only observable by capturing
      stdout, and the upcoming death/extract screen (`ui-hud`, week 5) and the
      debug console both want the string rather than a second copy of the
      format. `_run_summary_line()` itself stays private.
    - *The placeholder print is verified by a headless GUT run, not a launched
      game.* No launch arg reaches a defeat yet (the rope extracts, `god`/`kill`
      are debug-local, and `--smoke=N` only autowalks), and adding a
      `--smoke-defeat` driver would be a launch-arg the specs don't ask for.
      `test_run_end_defeat.gd` drives the real path — `Events.player_downed` →
      `GameState` → `end_run` → print — under `--headless`, and its log is the
      evidence (`.goals/evidence/g6-defeat-summary.log`). The in-game defeat is
      on the manual-check list below until Dev A's `Downed`/`Dead` states
      (W3-A5) emit these events for real.

28. **The crit roll's seeded-generator seam (G13a).** The week-2 formula drew
    its crit from the global RNG, which the definition of done forbids under
    `scripts/`. The plan offered two seams and asked for the choice to be
    recorded — `Damage.compute` takes an optional seeded `RandomNumberGenerator`,
    or it reads one the combat path owns. Four calls:
    - *The parameter wins over a module-owned generator.* The generator's
      lifetime belongs to the **run**, not to a formula. `GameState.start_run`
      already resolves a per-run seed through a seeded generator (decision 23),
      and Dev A's floor generation (W3-A1) needs that same seed, so one seed
      should reproduce a floor *and* a crit sequence. A generator hidden inside
      a static class could not be handed that seed without a rewrite; a
      parameter *is* the hand-off, and it is `null`-defaulted so every existing
      call site compiles untouched.
    - *The null path falls back to a `Damage`-owned generator, not a global
      roll, and not a constant seed.* It is created on first use and seeded from
      clock entropy — the pattern `GameState` already uses for its host seed
      roll. A fixed constant seed was rejected: with no production caller yet,
      a constant is exactly what a first integration would silently hit, and it
      would have shipped a permanent crit sequence — a stealth always-crit or
      never-crit bug — at the same point in every run, for every player.
    - *A forced crit consumes no draw.* MARK short-circuits before the roll, so
      adding a MARK cannot shift the crit sequence of every later hit in the
      run. Nothing depends on this yet, which is the point: it would have been
      invisible until the sequence was replay-checked, and would have read as a
      desync when it was.
    - *The band test drives an injected generator instead of seeding the global
      RNG.* It used to call `seed(20241019)`; the formula no longer reads the
      global RNG, so that seeding would have gone on passing while proving
      nothing about the path the formula actually takes. The 400-roll band now
      runs on an explicitly seeded generator. The deterministic rows — crit
      chance 0/1 and `force_crit` — are untouched, so the golden table's
      semantics are unchanged.

    What the seam does **not** yet do: roll a crit in a live game. `Hurtbox.receive`,
    the caller the module doc names, is Dev A's combat core (W2-A1, still open),
    so **no production path calls `Damage.compute` at all** and the fallback
    generator is what a first integration would hit. What is verified is the
    seam itself — same seed replays the same sequence, a different seed moves
    it, and the null path still rolls in band — plus a clean headless launch.
    Threading `GameState`'s run generator into `compute` is on the manual-check
    list until that caller lands.

29. **Floor sync: the broadcast shape and the generator seam (W3-B3a/G7).**
    SPEC-networking fixes the payload and the RPC conventions but not how the
    host reaches the broadcast, how a client receives it, or what generates a
    floor while Dev A's `FloorGenerator` does not exist. Seven calls:
    - *The host applies its own floor explicitly and `rpc_id`s the remotes,
      instead of relying on `rpc()` with `call_local`.* `call_local` on an
      authority RPC does make a host's `floor_ready.rpc(...)` run locally, but
      it would also mean the host has to know it must never call the bare
      method, and it makes "did the host already generate this floor?" depend on
      multiplayer internals. `broadcast_floor_ready` calls `apply_floor_ready`
      once and then sends to every peer that is not `local_peer_id`, so the host
      generates exactly one floor per floor, solo and co-op take the identical
      path, and the counting is visible in one function. `call_local` stays on
      the declaration (it is the spec's convention and it is what makes the
      late-joiner `rpc_id` path symmetric), but nothing depends on it firing.
    - *The broadcast hangs off `run_started` and `floor_changed`, not off a new
      signal.* Floor 1 is ready when the run starts and never before, so
      `run_started` is the exact moment; every later floor is already announced
      by `floor_changed` (W3-B1c's threshold seam emits it). Listening to those
      two means no new `Events` signal and no lane-B owner of the floor-advance
      decision — the host's run state is the only trigger, which is the
      host-only rule for free.
    - *A peer that joins mid-run is sent the floor again.* Deterministic
      generation means the floor is fully described by
      `(seed, floor_index, biome_id, modifiers)`, so `_send_floor_to_late_joiner`
      re-sends rather than making the joiner wait for the next floor. This was
      not speculative: the first two-process `--smoke-floor` run failed exactly
      here — the client connected after the host had broadcast and logged no
      `[floor]` line at all.
    - *`apply_remote_floor` is client-only.* On a client, `floor_changed` is how
      the rest of the game (HUD, world) learns which floor it is on, and a
      client has no `RunState` to emit it. Letting the host accept a remote floor
      would mean a client's `floor_changed` could reach the host's own
      `_on_floor_changed` and echo the floor back out; refusing on the host
      makes that loop impossible rather than merely unlikely, and the test
      asserts the refusal.
    - *The generator seam skips a real `FloorGenerator` while its biome argument
      is still a `BiomePlaceholder`.* The spec's signature takes `BiomeData`; DEV
      A's `BiomeData` does not exist yet (W3-A1/A6), so calling the real
      `generate` with the placeholder would fail its typed signature. The seam
      therefore resolves the script *and* checks the biome type, logging the
      blocker once per process — so the moment both land, generation switches
      over with no edit here. Until then a lane-B `FloorLayoutPlaceholder`
      carries the same `layout_hash` field, derived from the same four inputs
      through a seeded `RandomNumberGenerator` with integer-only seed arithmetic
      (`absi(run_seed * 2654435761 + floor * 40503) + 1`, no engine `hash()`),
      sampling 8–14 room rects in the spec's size ranges. It is a stand-in for
      the *layout*, not a fake of Dev A's algorithm: what it proves is that one
      seed reaches every peer and every peer derives the same hash from it.
      **blocked on Dev A (W3-A1)** for the real generator, and the swap-in is
      `GameState.biome_for_index` returning `BiomeData`.
    - *Modifiers travel as `[]` for now.* `roll_modifiers` is Dev A's
      (`FloorGenerator.roll_modifiers`), so the seam returns an empty array with
      a test pinning that. The field is in the payload and in
      `last_floor_modifiers` from day one so the wire shape does not change when
      the roll lands — but an empty list today must not be read as "no modifiers
      rolled".
    - *`--smoke-floor[=<sec>]` is a new launch arg.* The two-instance proof needs
      a run to start on its own in a headless process, and the existing `--smoke`
      / `--smoke3` drivers only walk and shoot. It follows the `--smoke3` pattern
      exactly (default seconds, `=value` form, one test per branch), and its 5 s
      client wait is the fix for the failure above: at 3 s the host was starting
      the run before the client had connected. Both peers logged
      `layout_hash 3525914442204165144` for `--seed=20261020`.

30. **The floor-hash smoke check is an equality assertion, and it carries its own
    negative control (W3-B3a-2/G7b).** Judgment calls, each chosen so the proof
    cannot pass for the wrong reason.
    - *Equality, not presence.* The existing `check()` helper greps for a
      pattern, which would pass if both peers logged *different* hashes — the
      exact failure the check exists to catch. The floor phase therefore extracts
      each peer's `layout_hash` with `floor_hash <file> <seed>` and compares the
      two strings, failing when either is empty. `check()` is still used for the
      presence facts (both drivers armed, the host started the run with the
      client in it).
    - *A third pair on a different seed.* Two equal numbers prove agreement only
      if the number is capable of differing. A constant hash would satisfy the
      same-seed comparison forever, so the phase also runs a pair on
      `--seed=987654321` and asserts its hash differs from the first pair's
      (`3525914442204165144` → `708545516277063756`). That pair's own host/client
      agreement is asserted too, so it is a second independent two-process proof
      rather than only a difference check.
    - *The seed is part of the extraction pattern.* `floor_hash` anchors
      `ready seed <seed> floor 1`, so a client that generated from some other
      seed — or a run where the host's `forced_seed` never reached the broadcast —
      produces an empty hash and fails, instead of matching on the number alone.
    - *Cost and flakiness.* The phase adds ~28 s (two 12 s host / 9 s client
      pairs plus a socket-release beat), taking the smoke from ~35 s to ~55 s.
      That is accepted because the smoke is the only place two real processes
      meet, and no pair retries: a peer that never connects leaves an empty hash
      and fails loudly. `FLOOR_SEED_A`, `FLOOR_SEED_B`, `FLOOR_HOST_SECONDS` and
      `FLOOR_CLIENT_SECONDS` are overridable from the environment, following the
      script's existing `PORT` / `HOST_SECONDS` convention.
    - *A negative control is recorded alongside the pass.*
      `.goals/evidence/g7b-smoke/negative-control.log` runs the same helper and
      the same branch over fabricated logs and shows the `FAIL` path for
      divergent hashes and for a peer on another seed. A check whose failing path
      was never observed is an assumption, not an assertion.
    - *Only floor 1 is proven here.* The driver starts the run once the client is
      in, so the pair proves the `run_started` broadcast end to end. The
      `floor_changed` re-broadcast is covered by `tests/unit/test_floor_sync.gd`
      and is not claimed as a two-process result: advancing a floor headlessly
      needs a smoke driver that presses `skip`; at this writeup `skip` itself was
      still a stub (**W3-B5a landed it 2026-10-20**, so only the driver is
      missing) and it stays on the manual-check list.
    - **Blocked on Dev A (W3-A1)**: the proof ran against the lane-B placeholder
      layout, because `scripts/generation/floor_generator.gd` still does not
      exist. Nothing in the check names the generator — it reads the `layout_hash`
      the seam produced — so the same command re-runs the proof against the real
      generator once it lands.

31. **Smoke tooling: `--port` on both peers, and an explicit `--join` port wins
    (W3-B3a-3/G7c).** The two findings W3-B3a-2 recorded and left unowned, fixed
    as one task because each one makes a *different* invocation of the smoke
    silently meaningless.
    - *`mkdir -p "$OUT"` in the script, not a rule for the caller.* The DoD asks
      for the smoke's output to be copied to `.goals/evidence/…`, and a copied
      run is exactly the case where `OUT` points somewhere new; making the
      caller responsible for a directory the script then writes into is the
      defect, not the convention. One line, no change when `OUT` already exists.
    - *`--port=<n>` added to `LaunchArgs` rather than refusing a non-default
      `PORT`.* The asymmetry was never intentional: `main.gd` already hands
      `options.port` to both `NetworkManager.host()` and `…join()`, so the only
      missing piece was a way for a *host* to state its port. Adding the arg is
      smaller than deleting `PORT` from the script and leaves the smoke able to
      run on a free port alongside anything else (two-instance runs, CI
      machines, a second smoke). It is parsed like `--seed` / `--smoke3`, with
      the range validated (`1..65535`) because `is_valid_int()` alone accepts
      `0` and negatives.
    - *An explicit `--join=ip:port` beats `--port`, order-independently.* The
      join's own port is the more specific statement about *that* connection, and
      order-dependent parsing would make `--port=7800 --join=127.0.0.1:7900`
      mean two different things depending on which came first. Resolution
      therefore happens after the whole argv is read.
    - *Both peers get `--port` in the smoke, the client keeps its explicit join
      port.* Belt and braces on purpose: the pair is now symmetric
      (`--host --port=$PORT` / `--join=127.0.0.1:$PORT --port=$PORT`) so a reader
      sees one port value, and the client's connect target cannot silently
      diverge from the host's bind.
    - *The pre-fix failures are committed as negative controls.*
      `.goals/evidence/g7c-smoke/negative-control-prefix-{out,port}.log` show the
      old script exiting 1 for a missing `OUT` and for `PORT=7901` — in the port
      case the host printed `hosting on port 7777` and ran a **one-player** run
      to completion, which is the silent degradation the fix removes. A check
      whose failing path was never observed is an assumption (decision 30), and
      the same rule applies to a tooling claim.

32. **The hash assertion is its own broadcast, and the fallback carries the
    layout's content (W3-B3b/G8).**
    - *`layout_asserted(layout_hash)` is a separate RPC, not a fifth field on
      `floor_ready`.* The spec fixes `floor_ready(seed, floor_index, biome_id,
      modifiers)`, and a test in this file asserts exactly those four argument
      names; the hash is a statement about the layout the host *produced*, which
      is a different fact from the inputs every peer generates from. It is sent
      immediately after `floor_ready` on the same reliable, ordered channel, so
      the client always has a floor to compare against.
    - *The assertion is split RPC / plain method, like `floor_ready` /
      `apply_floor_ready`.* `layout_asserted` is the sender-validated RPC;
      `apply_layout_assertion` is the plain client-side check the unit tests
      drive directly, because a single process cannot fake a client's sender id
      (LESSONS). Same for `floor_layout` / `apply_host_layout`.
    - *One sender rule for every floor broadcast.* `can_accept_floor_ready` now
      forwards to `can_accept_floor_broadcast`, which the assertion and the
      layout reply also use: the host accepts only its own local call (sender 0),
      a client accepts only the host's. `request_floor_layout` is
      `any_peer`/`call_remote` and validates the sender through the new
      `can_serve_floor_layout_request`, which refuses sender 0 exactly like
      `can_apply_rope_request` — a direct local call is not a client's request.
    - *The fallback sends the host's layout, not its inputs.* Regenerating on the
      client from `(seed, floor_index, biome_id, modifiers)` would reproduce the
      same wrong layout, so `FloorLayoutPlaceholder.to_wire()` carries the rooms
      and the hash. Rooms go over as a flat `PackedInt32Array` of `(x, y, w, h)`
      quadruples rather than an `Array[Rect2i]`: no typed-array or Rect2i
      encoding question on the wire, and no process-local value anywhere in it.
    - *The wire form is the seam for Dev A's layout.* `FloorGeneratorSeam.
      serialize_layout` calls the layout's own `to_wire()` and
      `deserialize_layout` rebuilds from the class named in `source`; when
      `FloorLayout` lands (blocked on Dev A W3-A1) it declares those two methods
      and nothing on the networking side changes. An unknown source rebuilds
      nothing and the caller reports the fallback as failed rather than
      pretending it worked.
    - *New public API beyond the declared signatures* (recorded here per the
      BRIEF's rule): `NetworkManager.layout_asserted`, `request_floor_layout`,
      `floor_layout`, `apply_layout_assertion`, `apply_host_layout`,
      `can_accept_floor_broadcast`, `can_serve_floor_layout_request`,
      `last_floor_hash`, `last_floor_index`, the `floor_layout_requested`
      signal, `GameState.note_floor_divergence` / `has_floor_divergence` and the
      three divergence fields, `FloorGeneratorSeam.serialize_layout` /
      `deserialize_layout`, `FloorLayoutPlaceholder.to_wire` / `from_wire`.
      Additions only — nothing existing was renamed or removed, and
      `can_accept_floor_ready` keeps its signature and behaviour.
    - *The divergence is a value, not just a log line.* `GameState` records the
      floor and both hashes, because the SPEC calls for a fallback and a fallback
      that leaves no trace is indistinguishable from a silent one; the week-5
      end-of-run summary and the HUD's debug panel are the readers.
    - *`floor_layout_requested` is emitted before the RPC travels.* It is how a
      single-process test proves the request was triggered (`can_send_request()`
      is false in a fake client, so the RPC is deliberately not sent), and it
      mirrors `Rope.interaction_forwarded`'s role at W3-B2a.

33. **Downed sync: where the flag is registered, and how a broadcast differs from
    a replicated value (W3-B4a/G2).** SPEC-networking says "downed and revive
    synced" and lists the downed state among what StateSync carries; it does not
    say which of the two mechanisms is authoritative, how the two `Events`
    signals reach the other peers, or what a client does with a downed player it
    did not simulate. Six calls:
    - *The flag is replicated **and** broadcast, and the replicated flag is the
      one of record.* StateSync already carries the host's per-player state
      (`synced_position`, `acked_input_tick`), so `is_downed` joins it: the host
      is the authority either way, and `ON_CHANGE` + `spawn` means a late joiner
      is told without a special case. The broadcast is what makes the *event*
      reliable and immediate — a `MultiplayerSynchronizer` replicates a value,
      not a moment — which is what `Events.player_downed` /
      `player_revived` are for, and what `GameState`'s defeat check already
      listens to. Wiring only the broadcast would have left a joining peer with
      no idea anyone was down; wiring only the synchronizer would have made the
      defeat check wait for a state poll.
    - *Both routes converge on one setter.* The replicated write and
      `apply_player_downed` both go through `is_downed`'s setter, so
      `refresh_authority()` and the player's own `downed` signal happen once,
      whichever way the news arrived — and a redundant write (the broadcast
      landing after the synchronizer already moved it) is a no-op rather than a
      second emission. The alternative, applying the two routes separately, is
      how a client ends up with a downed player that is still simulating.
    - *A downed player stops simulating everywhere, not just on the host.*
      `simulates` and `refresh_authority` now both subtract `is_downed`, so a
      client's remote copy of a downed player does not run states either. A
      downed player cannot move, so predicting or interpolating one is work that
      can only produce a wrong pose.
    - *`revived(by)` is not emitted by `_apply_downed_state`.* The setter knows
      only that the flag flipped; who did the reviving is a fact of the revive
      path (`request_revive`, W3-B4b, blocked on Dev A W3-A5), so the player's
      own `revived(by: Player)` signal keeps its one emitter. The bus event
      `Events.player_revived(player, by)` is emitted by `apply_player_revived`,
      which carries the reviver's peer id — `0` meaning "nobody", which is the
      wipe path.
    - *The host guard is `is_host and multiplayer.is_server()`, not
      `multiplayer.is_server()`.* In a single process the offline peer reports
      `is_server() == true` however the test fakes a client, so guarding on that
      alone made `_become_client()`'s router call `rpc_id` back to itself
      (`call_local`) → `apply_player_downed` → `Events.player_downed` → the same
      handler → an unbounded recursion, which GUT reported as a stack overflow.
      `_announces_player_state()` is the guard the router and both handlers read,
      and it is the same shape `TimeManager` already uses. This is a test-seam
      bug that would have been a real echo in a two-process run where the client
      is also `call_local` for its own call.
    - *New public API beyond the declared signatures* (recorded here per the
      BRIEF's rule): `NetworkManager.broadcast_player_downed`,
      `broadcast_player_revived`, `apply_player_downed`, `apply_player_revived`,
      `route_player_downed`, `route_player_revived`, `remote_peer_ids`,
      `can_accept_host_broadcast`. Additions only — nothing renamed or removed,
      `can_accept_floor_broadcast` keeps its signature, and `Player.is_downed`
      keeps its name and its meaning (it now has a setter, which no existing
      call site can observe).
    - *The `player.tscn` StateSync registration is a cross-lane edit taken
      deliberately.* `player.tscn` is nominally Dev A's, and the BRIEF's ask-first
      rule names `.tscn` files owned by the other lane. It was still the only
      place the flag can be replicated, PLAN G2 names it as this task's
      deliverable, and the test file's own header already declares this
      ownership ("PR into player.tscn, Dev A reviews") — so it is recorded here
      for review instead of being skipped. Three lines inside the `StateSync`
      sub-resource; no node, no `InputSync` field, and no other `.tscn` changed.

34. **Revive: who owns the rule, where the numbers live, and what a refusal says
    (W3-B4b/G3).** SPEC-player-controller declares `request_revive` (client → host)
    and SPEC-run-economy says a client never revives on its own authority, but
    neither says where the validation lives, what the host checks, or how a
    refused ask is reported. Six calls:
    - *The rule lives on `NetworkManager`, and `Player.request_revive` only
      forwards.* Distance, the downed flag and the sender are all facts about the
      session — which peer is where, and who is allowed to ask — so they belong
      with the rest of the session rules rather than on the player object. The
      player keeps the spec's entry point (`request_revive(target)`) and adds two
      lines that hand it to `send_revive_request(target.peer_id)`; a client that
      calls it in solo changes nothing locally and is *told* so, rather than
      appearing to revive.
    - *Validation is two functions, not one.* `can_apply_revive_request(sender,
      target)` is the boolean seam PLAN G3 asked for (the shape `can_apply_*` has
      everywhere else in the autoload); `revive_refusal_reason(sender, target)`
      is the reason behind it, kept in `last_revive_refusal`. Collapsing them
      would have made "it was refused" the only thing a caller could ever know —
      and the debug console (W3-B5) and the refusal log line both need the why.
    - *Every refusal is a `push_warning`.* A refused request is the authority
      doing its job, not a fault, and GUT scores engine errors as failures — so
      a refusal that used `push_error` would make the refusal tests fail for the
      wrong reason (LESSONS, the same call the Rope and floor paths made).
    - *The range check reads local `position`.* In the running game every player
      is a direct child of `World/Players`, so local positions are comparable and
      a global transform is not needed; outside the tree a player double has no
      global transform, and reading `global_position` on one raises an engine
      error. The rule is `<= REVIVE_RANGE`, asserted with a teammate standing at
      exactly the range (revives) and just outside it (does not).
    - *The revive constants live on `NetworkManager` with the swap point named.*
      `REVIVE_RANGE` / `REVIVE_SECONDS` / `REVIVE_HP_FRACTION` /
      `REVIVE_SPEED_MULT_MIN` are the host's numbers, and PLAN G3 places them
      here. What uses them is Dev A's: the hold-to-revive input, the `Downed` /
      `Dead` states and the bleed-out timer are **blocked on Dev A (W3-A5)**, and
      `revive_hp_for`'s result is written to `Health`, **blocked on Dev A
      (W2-A1)**. `revive_seconds_for` clamps `revive_speed_mult` at
      `REVIVE_SPEED_MULT_MIN` so a zero or negative multiplier cannot make the
      hold infinite or backwards, and `revive_hp_for` floors at 1 HP so a revive
      never leaves a player standing with 0.
    - *New public API beyond the declared signatures* (recorded here per the
      BRIEF's rule): `NetworkManager.request_revive`, `send_revive_request`,
      `can_apply_revive_request`, `apply_revive_request`, `revive_refusal_reason`,
      `revive_distance`, `revive_seconds_for`, `revive_hp_for`, the
      `revive_requested` signal, `last_revive_refusal` and the `REVIVE_*` /
      `REVIVE_REFUSAL_*` constants; plus `GameState._on_player_revived` (private,
      the slice-clearing route) and the two-line body of the existing
      `Player.request_revive`. Additions only — nothing renamed or removed, and
      no existing signature changed. The cross-lane edit is `scenes/player/player.gd`
      (Dev A's module, the stub's own comment reads "Filled in by networking week
      3"); it is flagged for Dev A's review rather than asked about, because the
      stub is this task's deliverable. No `.tscn`, no `project.godot`, no Input
      Map, no `Events` signal, no `scripts/data/` Resource, no save schema, no CI
      and no addon was touched.

35. **Debug floor advance: `skip` reports the authority's reason, and `floor <n>`
    walks rather than teleporting (W3-B5a/G4).** SPEC-debug-tools lists
    `skip` / `floor <n>` as "advance / jump floor" and says commands execute on
    the host; it does not say what a refused advance reports, or how a
    multi-floor jump should behave. Five calls:
    - *`skip` calls `GameState.next_floor()` and then reads
      `last_advance_refusal`, instead of pre-checking the run itself.*
      `GameState` already refuses the advance for four distinct reasons
      (not host / no run / exit shut / last floor) and records which one in
      `last_advance_refusal`. If the console pre-checked the run and short-
      circuited, it would have to duplicate that rule and the two copies could
      disagree the day one changes. There is one implementation of "may the floor
      advance", and the console is a reporter of it.
    - *`floor <n>` walks to the target by calling `next_floor()` once per floor.*
      Assigning `run.floor_index` directly would be shorter and wrong: it would
      step over a shut exit, skip the `floor_changed` broadcast every follower
      depends on, and leave `floors_cleared` lying. Walking means the debug jump
      is subject to exactly the rules a player's walk to the Exit is, which is
      what makes it useful for testing Shrines and loot headlessly.
    - *A target behind the current floor is refused, not implemented.* Nothing in
      the project can move a run backwards (no rewind, no floor-set API), and
      inventing one in a debug command would put run state on a second write
      path. The refusal names the current floor and points at `skip`.
    - *The refusal wording lives in the console, not in `GameState`.* PLAN G4
      asked for `last_advance_refusal`; `GameState` stays a reason **code**
      (`StringName`) so the HUD, the console and any future screen can each say
      it their own way. `_advance_refusal_text` is the console's table, and an
      unknown code falls through to a readable "unknown refusal" rather than
      reading as "nothing was refused".
    - *New public API* (recorded here per the BRIEF's rule): the
      `floor` command registration, `DebugCommands.MAX_FLOOR_JUMPS`, and the
      private `_cmd_floor` / `_advance_refusal_text`. Additions only — `skip`
      keeps its name and signature, and nothing was renamed or removed. No
      `project.godot`, Input Map, autoload public API, `scripts/data/` Resource,
      `Events` signal, save schema, CI or addon was touched — the Input Map is
      untouched because both commands are typed, not bound.

36. **`net_lag`'s placeholder shape, and what `seed` is proven against
    (W3-B5b/G5).** SPEC-debug-tools lists `net_lag <ms> [loss%]` as the simulated
    latency command and explicitly defers the implementation ("Decide
    implementation in week 4; the API is just `net_lag`"), while the Week 3 task
    list asks only for the placeholder. Four calls:
    - *The placeholder stores its arguments on `NetworkManager`, not on the
      console.* A `DebugCommands` instance lives inside the `DebugConsole`, which
      is lazily created behind `OS.is_debug_build()` and absent in a release
      export. The setting has to outlive the console for W4-B11's proxy and for
      the `dump` command to read, so the fields sit with the rest of the network
      state (`floor_seed`, `last_floor_hash`, `last_revive_refusal`) and their
      names are the contract W4-B11 fills in.
    - *Their units are fixed now:* `net_lag_ms` is whole milliseconds (0 = off),
      `net_lag_loss` is a percentage in 0.0–100.0. Recording "150" and "5" as
      bare numbers would let W4-B11 read loss as a fraction and silently drop
      5% of nothing; naming the units in the types and the doc comment costs
      nothing today.
    - *The command says out loud that it does nothing yet.* Every result line
      carries "placeholder, the real delay proxy lands in W4-B11". A debug
      command that quietly accepts an argument and changes no observable
      behaviour is the kind of thing that gets trusted and then blamed; the
      spec's own deferral is written into the output.
    - *`seed` is asserted against a real run, not only against the field.* The
      W3-B1 rule (`forced_seed` → caller seed → host roll) is the thing other
      tests and the smoke rely on, so the case runs `seed 4242` through the
      console and then starts a run with a **different** caller seed, asserting
      the run starts on 4242 — and the same for `seed 0`, where the caller's
      999 must come through. New public API beyond the declared signatures
      (recorded per the BRIEF's rule): `NetworkManager.net_lag_ms` /
      `NetworkManager.net_lag_loss` and the private `_cmd_net_lag`. Additions
      only; nothing renamed or removed. No `project.godot`, Input Map, autoload
      public API, `scripts/data/` Resource, `Events` signal, save schema, CI or
      addon was touched.

37. **Week 3 gate verdict and the withheld `week-3` tag (2026-10-20).**
    Verdict: **partial**. Re-verified from the tree at `84395b4` rather than from
    memory, as this decision is written:

    - The design doc's Week 3 "Done when" line — "Procedural floors with Start,
      Combat, Elite Combat, Treasure, Rope, Exit rooms, locking combat rooms,
      seed sync for co-op, downed/revive" — is **unmet**, and the reason is the
      same one that withheld `week-2`: Dev A's lane. `scripts/generation/` holds
      only `.gdkeep` (no `FloorGenerator`, no `Floor` scene, no room types, no
      locking rooms, no populator registry), `scenes/dungeon/` holds only
      `interactables/rope.tscn`, and `scripts/combat-core/`, `scripts/enemies-ai/`,
      `scripts/weapons/`, `scripts/abilities/` and `scripts/classes-characters/`
      do not exist. **W3-A1 .. W3-A7 are all unlanded.**
    - **Seed sync for co-op is met** — and met the hard way, with a two-process
      proof rather than a signal count: `tools/smoke_two.sh` launches host/client
      pairs on a shared `--seed` and compares each peer's `layout_hash` for
      **equality** (35 `ok` lines, 0 FAIL, exit 0; `20261020` →
      `3600649381522393848`, `987654321` → `536024383148136417`), plus a
      different-seed pair so two equal numbers cannot pass by being constant, and
      a committed negative control showing the helper's FAIL path.
    - **Downed/revive is met on Dev B's half only**: the replicated `is_downed`
      flag, the `player_downed`/`player_revived` broadcasts and the host revive
      rule (`request_revive`, range, eight refusal reasons) are in and tested.
      The states that *cause* a revive are Dev A's W3-A5, so nothing in a
      launched game can down a player yet.
    - Dev B's Week 3 lane is **complete**: W3-B1 (a/b/c), W3-B2 (a/b), W3-B3
      (a-1/a-2/a-3/b/c), W3-B4 (a/b) and W3-B5 (a/b) are all ticked in
      `tasks/todo.md` with their evidence. **W3-B6** (`[art-audio]` rope vote
      prompt, floor label pieces, downed/revive HUD icons, death/extract summary
      theme, and the rope/revive/downed/menu SFX) is **open and out of this
      run's scope** — it is an art-audio task, not a systems task, and the raw
      goal's task list does not include it; the placeholder rule stands
      (SPEC's "coloured square with the first letter", generated 5×7 font).
    - Verified on this machine at `84395b4`, logs in `.goals/evidence/g6/`:
      `--headless --path . --import` exit 0 with 0 error lines
      (`g6/import.log`); full GUT **35 scripts / 554 tests / 554 passing /
      54 115 asserts, exit 0** in 9.8 s (`g6/gut-full.log`, up from the 529-test
      baseline recorded at the last reflect); `tools/smoke_two.sh` **35 `ok`, 0
      FAIL, exit 0** (`g6/smoke-run.log`).
    - **`week-3` is NOT created.** A milestone tag claims the whole design-doc
      "Done when" line, not one lane's task list — that is the precedent this
      run set at decision 22 for `week-2`, and the raw goal's own `week-4`
      condition ("once *my* tasks are done and all tests are green") is the
      Week 4 line's wording, not a licence to tag a Week 3 whose headline
      deliverable (procedural floors) does not exist. Creating it would claim a
      milestone that did not happen. The gap is stated in `specs/WEEKLY.md`, in
      this decision, and in `.goals/LOG.md` instead.

    **Smoke steps.** Steps 1–3 pass in two processes, plus the floor-sync phase
    (shared-seed agreement and the client's own layout assertion). Step 4 (client
    picks a relic at a Shrine) has **no driver** — the Shrine is week 4's W4-B5
    and no Shrine exists to walk to. Step 5 (client goes down, host revives) has
    **no driver and no emitter** — Dev A's W3-A5 states are what down a player.
    Both are recorded as blocked rather than skipped, and their drivers are the
    post-week-3 smoke goals.

    **Stale-claim sweep performed as part of this verdict.** Every "still a
    stub" / "not yet landed" / "lands in week N" sentence in the files a reader
    consults for the *current* state was checked against the tree and corrected
    or dated: `HANDOFF.md`'s `Player.request_revive`-is-still-a-stub note in the
    downed-sync manual check (G3 filled it in), the same claim inside the W3-B4a
    writeup, the W3-B3a-3 note calling W3-B5's console work untouched, decision
    25's "Handle for G12" prescription that W3-B5 must jump through
    `RunState.floor_index` (W3-B5a deliberately walks through `next_floor()`
    instead), the header/edit bar's test and smoke counts, and the footer. The
    retrospective writeups for W3-B1a/b/c and W3-B3c — recorded as owed when
    W3-B3b shipped — are written in this pass.

    **What this does not change.** Nothing in `scripts/`, `scenes/`, `data/`,
    `tests/` or `tools/` is touched by this goal: it is the checkpoint's records.
    Week 4 proceeds on the standing premise that every Dev A dependency is
    unlanded, with each cross-lane seam built against the spec interface plus a
    `tests/helpers/` double and recorded `blocked on Dev A (W4-Ax)`.

### Week 4 decisions

38. **`Events` signal arguments move to the spec's own names and types, and the
    remaining placeholders get a machine-parsed owner line (2026-10-20).**
    W4-B1's deliverable is the spec's signal set with the exact parameter names
    and count, so the two drifts the new conformance test found were fixed rather
    than tolerated. Sanctioned by `SPEC-effect-system.md` "Events bus" — the
    signal table is that spec's own text — and recorded here because an `Events`
    signal signature is on the project's Ask-first list (BRIEF C9: such a change
    is made only where a task or spec clause requires it, and each gets a numbered
    decision naming the sanctioning clause).

    - `run_started(run_seed: int)` → `run_started(seed: int)`. The spec writes
      `seed`. A pure parameter rename: every emit and connect site is positional,
      and `GameState.run_started(run_seed)` is a *different* signal on the
      autoload, untouched by this.
    - `hit_landed`, `crit_landed`, `player_damaged`, `enemy_killed`, `elite_killed`:
      `hit: RefCounted` → `hit: HitData`; `run_ended(result: RefCounted)` →
      `result: RunResult`. The spec names `HitInfo` and `RunResult`. `RunResult`
      exists in this repo, and `HitData` is the week-2 mirror of `HitInfo` whose
      field names match by design (`scripts/components/hit_data.gd`: "When Dev A's
      `HitInfo` lands, `compute` can be re-pointed at it — the field names match").
      Retyping to the mirror is exactly what W4-B1 asks for; the eventual swap to
      `HitInfo` is one rename in the bus plus one line of `TYPE_MAP` in the test.
    - The remaining placeholders keep their base class and gained a strict,
      test-parsed `## TODO(<module>): <SpecType> <- <Placeholder> (blocked on
      Dev X, <task-id>)` line in place of the old free-text TODO block. A comment
      format change only — no signature moves.
    - Nothing else on the Ask-first list was touched: no `project.godot`, no Input
      Map, no autoload public API beyond these signal arguments, no
      `scripts/data/` Resource, no save schema, no CI, no `addons/`.

---

## Running the game

Godot 4.7.2 is **not** on `PATH` by default and **not** at the `C:\Godot` path
the docs reference. Either add the folder to PATH, or use the real path below:

```
C:\Users\Dsedg\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
```

In the blocks below, `godot` means "whatever invocation gives you 4.7.2". From
the repo root (`C:\Users\Dsedg\OneDrive\Documents\GitHub\terra-project`):

### Solo

```powershell
godot --path .                 # shows the placeholder menu -> Play Solo
godot --path . -- --host       # straight into a host session (playable solo too)
```

### Co-op on one machine (two or more windows)

```powershell
.\tools\run_two.ps1              # host + 1 client, windows side by side
.\tools\run_two.ps1 -Clients 2   # host + 2 clients
# if `godot` is not on PATH, point at the real binary:
.\tools\run_two.ps1 -Godot "C:\Users\Dsedg\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
```

Or launch by hand (POSIX or PowerShell):

```powershell
godot --path . -- --host
godot --path . -- --join=127.0.0.1
```

`--join=127.0.0.1:7777` also works; the port defaults to 7777.

### Headless two-instance smoke (required before any sync PR)

```bash
GODOT=/c/Users/Dsedg/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe bash tools/smoke_two.sh
```

Expect 35 `ok` lines (steps 1 + 2 + 3, then the floor-sync phase) and exit 0. On
Linux/macOS, `tools/run_two.sh` is the
windowed launcher and `smoke_two.sh` needs `GODOT` pointing at a 4.7.2 binary.
The floor-sync phase launches two extra host/client pairs on `--seed=20261020`
and `--seed=987654321` and compares each pair's `layout_hash` for equality; the
seeds and the pair durations are overridable with `FLOOR_SEED_A`, `FLOOR_SEED_B`,
`FLOOR_HOST_SECONDS` and `FLOOR_CLIENT_SECONDS`.

The script creates `OUT` if it does not exist, so
`OUT="$(mktemp -d)/nested" bash tools/smoke_two.sh` works and every log lands
there. `PORT` (default 7777) is passed to **both** peers — `--port=$PORT` on the
host and on the client, plus the client's `--join=127.0.0.1:$PORT` — so
`PORT=7901 bash tools/smoke_two.sh` is a real two-peer session on 7901 rather
than a one-player host on 7777 that nobody can join.

### Tests and import (what CI runs)

```powershell
godot --headless --path . --import                                                         # must exit 0, no errors
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit   # 564 tests, exit 0 (36 scripts; 554 was the week-3 close-out figure)
```

---

## Manual checks still open (non-blocking)

These were not blockable from a headless run or from this machine. They are a
short checklist for Dev A and the human; none of them block week 4.

- **Viewport / integer scaling** — run the game windowed at 1920x1080 and
  confirm the 960x540 base renders crisp nearest-neighbor pixels with no
  shimmer on a placeholder sprite (W1-B1 manual verification).
- **Controller icons** — open the Input Map panel in the editor and confirm a
  controller icon appears next to each gameplay action (W1-B2 manual
  verification).
- **3-instance run** — `.\tools\run_two.ps1 -Clients 2`: a third instance
  joining sees both earlier players moving, and its own movement reaches the
  other two (W1-B9 / W1-AB1 manual verification).
- **Editor multi-instance (F5)** — set Debug > Run Multiple Instances to 2 with
  args `-- --host` and `-- --join=127.0.0.1`; the setting lives in `.godot/`
  and is per machine, so Dev A sets it once on their machine (W1-B10).
- **Dev A walkabout feel checks** — movement/facing feel, camera smoothing and
  co-op zoom-out, wall collision and Y-sort against a moving sprite, and the
  "no visible rubber-banding at 0 ms" visual check from W1-AB1.
- **CI live run** — push to `main` and watch the Actions run complete green
  under 5 minutes (see decision 14 for why it isn't visible from here).
- **Debug console feel** — in a windowed run press backtick to open/close the
  console, type `help`, `spawn grub 3`, `seed 7`, `timestop 2` and see the
  scrollback respond; in a two-instance co-op, issue `gold 50` from the client
  window and confirm the host grants it to that peer (W2-B4 manual
  verification; the headless suite covers the parser, registry, and every
  command's logic, but not the visual toggle or the cross-window RPC round
  trip).
- **In-game defeat** — in a windowed co-op run, down both players (once Dev A's
  `Downed`/`Dead` states exist, W3-A5) and confirm the run ends with `DEFEAT`,
  the printed summary names both players, and the HUD clears. The headless test
  drives the same events from doubles; only the real states and emitters are
  unverified (W3-B2b, decision 27).
- **Crit-roll reproducibility in a live run** — no production path calls
  `Damage.compute` yet (Dev A's combat core, W2-A1), so the seeded-generator
  seam is exercised only by its tests and a headless launch. When
  `Hurtbox.receive` lands, thread the run's generator into `compute` and
  confirm two instances on the same `--seed` roll the same crit sequence
  (G13a, decision 28).
- **Downed flag crossing the wire, two processes** — the downed/revived
  broadcast and the replicated `is_downed` are proved in one process through the
  fake-client seam (W3-B4a, decision 33). The two-instance proof — down a player
  on one peer and observe the flag and the HUD on the other — needs a smoke
  driver and a launch arg, which are the post-week-3 smoke goals, with the green
  run after them. Nothing emits a real down yet in any case (Dev A W3-A5). The
  client half is no longer missing: **`Player.request_revive` was filled in by
  W3-B4b on 2026-10-20** (decision 34) and the host revive rule behind it is
  tested; what remains open is only the hold-to-revive input and the
  `Downed`/`Dead` states that start the sequence, both Dev A's W3-A5.
- **Floor-sync smoke steps 4 and 5** — step 4 (a client picks a relic at a
  Shrine) needs the Shrine of W4-B5, and step 5 (a client goes down and the host
  revives) needs Dev A's W3-A5 down/emitter path. Both are recorded as blocked
  rather than skipped in decision 37; `tools/smoke_two.sh` drives steps 1–3 and
  the floor-sync phase today.
- **Advanced-floor two-process proof** — only floor 1 is proven across two
  processes (the driver starts the run once the client is in, which is the
  `run_started` broadcast). The `floor_changed` re-broadcast is unit-tested;
  walking a floor advance through the smoke needs a driver that presses `skip`,
  which now exists as a real command (W3-B5a) but is not yet wired into the
  smoke.
- **The real-generator floor soak** — `tests/integration/test_floor_generation_seeds.gd`
  soaks the lane-B `FloorLayoutPlaceholder` (the layout every peer generates
  today) over 500 seeds, but SPEC-floor-generation's own soak — over
  `FloorGenerator.generate()`, with flood-fill reachability, Exit reachable,
  exactly one `ROPE` on floor 2, no overlapping rooms and 3-wide corridors — is
  **blocked on Dev A (W3-A3)**. The soak's last case asserts the seam's source so
  it cannot silently keep soaking the placeholder once the real generator lands.

---

Everything above was verified on this machine: week 1 and week 2 on 2026-10-18 /
2026-10-19 (import exit 0, 338/338 GUT, 28/28 smoke, `main` @ `ee62cb7`), and the
**Week 3 close-out on 2026-10-20** at `84395b4` — import exit 0 with 0 error
lines, **35 scripts / 554 tests / 554 passing / 54 115 asserts, exit 0**, and
`tools/smoke_two.sh` **35 `ok` / 0 FAIL / exit 0** (logs in
`.goals/evidence/g6/`). The week-1 close-out (WEEKLY entry, SPEC-foundation
write-backs, `week-1` tag) is done. The week-2 checkpoint is **partial** and the
`week-2` tag is withheld (decision 22); the week-3 checkpoint is **partial** and
the `week-3` tag is withheld (decision 37) — in both cases because Dev A's lane
for that week has not landed. Week 4 records, the perf numbers and the `week-4`
tag decision are tracked in `.goals/PLAN.md` and `specs/WEEKLY.md`.
