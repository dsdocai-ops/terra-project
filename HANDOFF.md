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
touching the bank. Tests: `tests/unit/test_audio_manager.gd` (22; 21 until
G15a, below).

**G15a, 2026-10-20 — the pool-cap test's timing flake is gone (fixture change,
no production code).** `test_plain_pool_respects_the_cap` filled the pool with
16 real `ui_click` plays and then asserted the pool had grown to the cap. A
pooled player is `playing` only while the audio thread has not mixed past the
end of its stream, and the bank's `ui_click.wav` is **1448 bytes ≈ 16 ms**, so
under load the fill loop outlived the first click: `_acquire_plain()` handed
back a finished player and the pool reached 15 (`[15] expected to equal [16]`),
1 run in 3 at `785bf63`. Reproduced on the real binary at that revision — a
500-trial probe of the same loop under CPU load failed 15 trials, sizes
including 15 (`.goals/evidence/g15a/red-flake.log`). The fix is in the fixture:
`_looping_click()` builds a `LOOP_FORWARD` `AudioStreamWAV`, `_fill_plain_pool()`
fills through the real acquire path and asserts each acquire grew the pool by
one, and `test_plain_pool_reclaims_a_stopped_player` (new) pins the rule the
flake depended on — a stopped player is reclaimed, the pool does not grow. Both
original cap/steal assertions stay, plus the oldest-player identity and the new
stream on the stolen player. Verified: 20× the file alone green, 20× green under
the 32-way load that reproduced the flake, and 5 full-suite runs green (3 clean +
2 under load) at **43 scripts / 694 tests / 694 passing / 55 558 asserts**;
negative control forced and kept (`.goals/evidence/g15a/negative-control.log` —
a non-looping click with a 30 ms stall between acquires fails the fixture
assertion and the cap assertion `[3] expected to equal [16]`, and stopping no
player fails the reclaim case; exactly 2 tests red, 20 green).

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

### W4-B2 — `Effect` base, `EffectHost`, event dispatch (`effect-system`) — in progress

W4-B2 is the system every relic, mutation, class passive, Ascension and skill
node attaches through, so it landed as several goals (G9–G15). This section
records what has shipped so far and grows as the rest lands. Task line in
`tasks/todo.md` stays unticked until `Effect`/`EffectHost` are complete.

#### G9 — `Tags` vocabulary and `ProjectileSpec` (2026-10-20)

Two interfaces every other Week 4 module imports: the closed tag vocabulary
`ContentData.tags` is drawn from, and the value object `Effect.fire_projectile`
hands the projectile spawner.

**`scripts/effects/tags.gd`** — `class_name Tags extends RefCounted`, the spec's
19 tags as `StringName` constants (`FIRE` … `ACTIVE`), a typed
`ALL: Array[StringName]` in the spec's order, and `is_valid(tag) -> bool`. It
carries no state and no methods beyond that check; it is a vocabulary, not a
registry.

**`scripts/effects/projectile_spec.gd`** — `class_name ProjectileSpec extends
RefCounted` with exactly the spec's six fields: `scene: PackedScene`,
`speed: float`, `damage: float`, `element: HitData.Element`, `pierce: int`,
`bounce: int`. A convenience `_init` takes them in that order.
`to_dict()`/`from_dict()` are the plain-type form the spawner path uses — the
scene travels as its resource path, the element as its enum int, everything else
as a float/int — matching the `EnemySpawnInfo` / `ProjectileSpawnInfo`
convention. A missing or non-scene path leaves `scene` null and an element
outside the enum degrades to `NONE`, so a spec that only carries numbers (or an
older payload) is still usable rather than raising.

**`tests/unit/test_tags.gd`** (15 tests / 258 asserts) parses the tag set out of
the spec's own "Tags and synergies" sentence at run time (`test_events_bus.gd`'s
precedent) and asserts: the spec lists 19 unique tags; the script's constant map
contains exactly those 19 `StringName` constants and nothing else besides `ALL`;
every constant is the uppercased tag name; `ALL` is the full, deduplicated
vocabulary; `is_valid` accepts every vocabulary tag and rejects an invented tag,
the wrong case and the empty name. The content cross-link walks every `.tres`
under `data/relics`, `data/mutations`, `data/synergies` and `data/ascensions`,
loads the `ContentData` ones and reports any tag outside the vocabulary, with the
helper's failing path forced in its own case (`&"lifesteal"` is reported,
`Tags.ALL` produces nothing). `ProjectileSpec` is asserted for its six declared
variables and no more, its neutral defaults, a full dictionary round trip through
the placeholder projectile scene, the plain wire types, the absent-scene path and
the unknown-element degradation.

**Verified:** `-gtest=res://tests/unit/test_tags.gd` 15/15 green / 258 asserts
(`.goals/evidence/g9/test-tags.log`); red run first — GUT refused the file with a
parse error because neither class existed
(`.goals/evidence/g9/red-test-tags.log`); full suite **38 scripts / 589 tests /
589 passing / 55 116 asserts** exit 0 (`g9/gut-full.log`, up from the 574
baseline); `--import` exit 0 with **0** error or warning lines (`g9/import.log`);
headless `-- --host --debug-tools --smoke=6` exit 0 with 0 script/parse errors
(`g9/launch-host.log`); `grep -rn "Engine.time_scale" scripts/ scenes/` and the
global-RNG grep both empty. Negative controls forced and kept: an invented
constant fails the exact-set assertion and a dropped tag fails six assertions
(`g9/negative-control-invented-tag.log`, `g9/negative-control-missing-tag.log`),
both reverted before the green run.

**Judgment calls.** (1) The vocabulary is read from the spec rather than
transcribed, so a spec edit that adds or renames a tag fails the test instead of
leaving a second list to rot. (2) The test asserts the constant map *exactly*
apart from `ALL`, which is what makes "exactly the 19 tags" checkable; a future
non-tag constant would need to live in its own script. (3) `ProjectileSpec`'s
wire form carries a resource path and an int rather than Resource objects, per
the repo's existing spawn-info convention. (4) `_element_from` is a `match`
rather than an int cast: an unknown value becomes `NONE` explicitly, and the
conversion raises no int-to-enum warning.

**Blocked / not claimed.** `ProjectileSpec.element` consumes stats-status's
`HitData.Element`, the field-matching mirror of combat-core's `HitInfo.Element`
(**blocked on Dev A W2-A1**); when the real class lands the swap is the same
rename HANDOFF decision 38 recorded for the bus. Nothing in this goal calls a
spawner: `spawn`/`fire_projectile` are G15, and the projectile spawner itself is
Dev A's W2-A6. The round trip proves the spec's own dictionary form, not a
two-process transmission. No file on the "Ask first" list was touched — both new
scripts are additions under `scripts/effects/`, and `ContentData` is unchanged —
so no new numbered decision is required.

#### G10 — the `Effect` skeleton: attach, detach and total cleanup (2026-10-20)

The base every relic, mutation, synergy, class passive, Ascension and skill node
is written as, and the class whose whole purpose is `detach()`: a relic dropped
at a Shrine, or an effect torn down on room exit, must leave no modifier, no
timer and no connection behind, or it keeps changing the game after it is gone.

**`scripts/effects/effect.gd`** — `class_name Effect extends Node`, opening with
the ownership line (`## Sync: host only.`) and the "clients hold no `Effect`
instances" note. The spec's members are declared with the spec's names and types:
`player: Player`, `source: ContentData`, `stacks: int = 1`, `_handles:
Array[int]`, `_timers: Array[Timer]`. `attach(player, source, stacks)` keeps the
spec's parameter names (no shadowing warning is raised for a parameter that
shares a member's name — checked in the import log, which stays at zero warnings)
and floors `stacks` at 1, so a rank of 0 cannot make a scaling helper divide by
zero. It refuses a second attach without an intervening detach with a warning:
an effect belongs to exactly one player at a time, and a second `_on_attach()`
would double every modifier it added.

`detach()` is one ordered teardown — `_release_handles()` → `_free_timers()` →
`_disconnect_all()` → `_attached = false` → `_on_detach()` — and is a safe no-op
on an unattached effect (the early return is what keeps `_on_detach()` from
running for a cycle that never started). The base cleanup runs *before*
`_on_detach()` so a subclass tears its own state down against a state that
already holds no handles, timers or connections; the doc comment says so
explicitly, because the one thing a subclass can still get wrong is registering
something new inside `_on_detach()`.

Modifiers are removed **by handle**, never by `remove_source()`: two effects on
one player must not be able to take each other's modifiers down, even if they
were built from the same content id. `modify(stat, flat, percent)` appends
`stat_block.add_modifier(stat, flat, percent, source_id())` to `_handles`, and
`source_id()` is `source.id` — the id that W4-B3 also uses as the tag that
blocks self-retriggering, so the two rules cannot drift apart. *(As of G10; from
G19b `source_id()` builds through `EffectHost.suffixed_id()`, which returns
`source.id` unchanged for every effect that is not a Mimic Crown copy.)* Timers are
`queue_free()`d rather than freed outright, so a `detach()` from inside a signal
handler is safe. `_connections` is the `{signal, callable}` pair list
`PLAN.md` G10 asked for: a connection made through a wrapper cannot be found
again by name, and a lambda can never be disconnected at all, so `listen()`
records the exact `Callable` it connected and `_disconnect_all()` disconnects
that same one.

**`tests/unit/test_effect_base.gd`** (14 tests / 64 asserts) covers the spec
surface (the script declares `class_name Effect extends Node`, every spec member
and method, and each method carries a `##` doc line — a method that loses its doc
comment fails rather than passing on its name), `attach` carrying
player/source/stacks, `_on_attach`/`_on_detach` each running exactly once per
cycle, a second attach being refused, the full cleanup (modifier values back to
base, `_handles` empty, timer freed and out of the tree, listener disconnected
and the pair list empty), an unattached `detach()` being a no-op, and the
`source_id()`-as-modifier-source link. Two negative-control-shaped cases are
permanent: a second effect's modifier survives the first one's detach, and an
effect on a player with no `StatBlock` component warns and records no handle
instead of crashing. The player double is the real player scene with the
`StatBlock` component hung on its bare `StatBlock` node, the same shape
`test_hud_model.gd` uses for Dev A's missing `Health`.

**Verified:** `-gtest=res://tests/unit/test_effect_base.gd` 14/14 green /
64 asserts (`.goals/evidence/g10/test-effect-base.log`); written red first — GUT
refused the file with a parse error because `Effect` did not exist
(`g10/red-test-effect-base.log`) — and the failing path of the cleanup assertion
was forced and kept: with `_release_handles()`'s removal loop stubbed out,
exactly the two modifier-cleanup tests fail and nothing else, exit 1
(`g10/negative-control-release-handles.log`), then reverted. Full suite
**39 scripts / 603 tests / 603 passing / 55 180 asserts** exit 0
(`g10/gut-full.log`, up from the 589 / 55 116 baseline); `--headless --path .
--import` exit 0 with **0** error or warning lines and `Effect` registered as a
global class (`g10/import.log`); headless `-- --host --debug-tools --smoke=6`
exit 0 with 0 script/parse errors (`g10/launch-host.log`); two-instance smoke
`GODOT=… OUT=… bash tools/smoke_two.sh` exit 0 with **35 `ok` / 0 FAIL**
(`g10/smoke-run.log`, per-peer logs in `g10/smoke/`) with the standing layout
hashes `3600649381522393848` and `536024383148136417` unchanged;
`grep -rn "Engine.time_scale" scripts/ scenes/`, the `.base[` grep under
`scripts/effects/` and the global-RNG grep all print nothing.

**Judgment calls (HANDOFF decision 39).** (1) The `StatBlock` is resolved from
the player by node name and **cast-checked** (`player.get_node_or_null(^
"StatBlock") is StatBlock`), not written into the player scene: the player
scene's component nodes (`StatBlock`, `Health`, `Hurtbox`, `StatusEffects`) are
still bare `Node`s — `player.gd:159` carries the `TODO(stats-status)` that
retypes them — so this goal supplies the component the way every other Week 2–4
test does (a component hung on the node by the double) and leaves the scene
alone. A player without the component gets one warning per dropped modifier
rather than a crash or a silent no-op. (2) `_on_detach()` runs last (above).
(3) Handles, not `remove_source()` (above). (4) `queue_free()` for timers
(above). (5) `_start_timer()` is plain engine time and is documented as such:
`every_seconds()` (G13) is the `TimeManager`-scaled loop, and the split is
deliberate — a 30 s "invisible for 2 s" is not a time-stop-affected clock, a
relic's "every 10 s" is.

**New public surface beyond the declared spec signatures** (recorded per the
BRIEF's rule; additions only, nothing renamed or removed): `stat_block`,
`is_attached()`, `source_id()`, `_start_timer()`, `_resolve_stat_block()`,
`_release_handles()`, `_free_timers()`, `_disconnect_all()`, `_connections`,
`_attached`, `STAT_BLOCK_NODE`. `Effect` is a brand-new script, so no existing
signature changed and nothing on the "Ask first" list was touched.

**Blocked / not claimed.** This goal ships the skeleton and the cleanup only.
`chance`/`apply_status`/`deal_damage` are G12, `every_seconds` is G13,
`EffectHost` is G14, `spawn`/`fire_projectile` are G15, and the proc limits are
W4-B3 — so nothing here says anything about dispatch, depth or the per-frame
cap. There is no client path because there is nothing for a client to do:
clients hold no `Effect` instances, and this class reads no input and writes no
replicated field, so no two-process behaviour is claimed. Nothing yet *attaches*
an effect in the game (no relic content exists until W4-B5/B6); what is proved
is that the attach/detach cycle is complete when they do. (G11 then added
`listen`'s player filter and `once_per_room`; this paragraph is as G10 left it.)

#### G11 — `listen`, the player filter, and `once_per_room` (2026-10-20)

The two helpers the whole relic batch will be written against: `listen` will be
how every one of the 20 Week 4 relics subscribes to the bus, and `once_per_room`
will be the base of every "once per room" relic (Second Wind, Cracked Shell,
Panic Button). None of the 20 exist yet — W4-B6 builds them, and `data/relics/`
holds only `.gdkeep` at this commit.

**`listen(sig, callable)`** (`scripts/effects/effect.gd`) now filters where the
signal gives it something to filter on. Where `sig` declares a `Player`
argument, the connection goes through a bound forwarder instead of the raw
callable, and `_forward()` calls the handler only when the event's `Player`
argument **is** this effect's own `player` — so an effect on player 1 never
reacts to player 2's dodge, hit, pickup or room entry. Where the signal has no
`Player` argument (`enemy_killed`, `hit_landed`, `floor_entered`, …) the named
method itself is connected, untouched: `hit_landed` carries the attacker inside
`HitData`, and filtering every effect on every hit is the effects' own job, not
the base class's. The `Player` argument is located from the signal's
**declaration**, read off the `Events` autoload's own script
(`get_script_signal_list()`, the `test_events_bus.gd` precedent), not sniffed
off a call: `player_dodged` carries it at index 0 and `room_entered(room,
player)` at index 1, and both are covered.

`Callable.bind()` appends its arguments *after* the signal's own — verified
against the engine before this was written (`two.connect(Callable(self,
"_dispatch").bind("CTX1", "CTX2"))` reaches `_dispatch(SIGA, SIGB, CTX1,
CTX2)`) — so a single forwarder cannot receive a variable number of event
arguments ahead of its bound pair. `DISPATCH_METHODS` therefore holds one tiny
forwarder per signal arity (`_dispatch0` … `_dispatch4`), which is the widest
signal on the bus (`status_applied`), and the arity is taken from the same
declaration the player index came from. A signal wider than that is connected
unfiltered with a warning rather than dropped. Every connect in the class now
goes through `_connect_tracked()`, which records the pair for `detach()`, so a
filtered connection is disconnected exactly like an unfiltered one — asserted,
including that `Events.player_dodged.is_connected(effect._on_player_dodged)` is
false after `detach()`.

**`once_per_room(key)`** returns true the first time a key is asked for in a
room and false on every later ask, and every key is granted again when
`room_entered` fires. The base subscribes to `room_entered` itself in
`attach()` — **directly, not through `listen()`**, because the reset is the
room's rather than the entering player's (decision 40) — and clears the key set
in `detach()` as well, so a re-attach cycle never inherits the previous one's
budget. Keys are per-effect and per-name: two effects, and two things on one
effect, never share a budget by accident.

**Verified:** `-gtest=res://tests/unit/test_effect_base.gd` 24/24 green /
98 asserts (`.goals/evidence/g11/test-effect-base.log`); written red first — 10
failing tests, every failure for the right reason (`Nonexistent function
'once_per_room'`, `Invalid access to property '_on_room_entered'`, and the
three way short `_connections` count, `g11/red-test-effect-base.log`). Both
failing paths were forced and kept: with the player filter removed from
`_forward()`, exactly the two filter cases fail (`[1] expected to equal [0]:
player 2's dodge never reaches player 1's effect`, and the same for the
index-1 `room_entered` case) and nothing else —
`g11/negative-control-player-filter.log`; with the `room_entered` subscription
stubbed out, exactly four tests fail (the round-up of recorded connections, the
two reset cases and the detach/disconnect case) and nothing else —
`g11/negative-control-room-reset.log`; both reverted before the green run. Full
suite **39 scripts / 613 tests / 613 passing / 55 214 asserts** exit 0
(`g11/gut-full.log`, up from the 603 / 55 180 baseline); `--headless --path .
--import` exit 0 with **0** error or warning lines (`g11/import.log`);
two-instance smoke `GODOT=… OUT=… PORT=… bash tools/smoke_two.sh` exit 0 with
**35 `ok` / 0 FAIL** (`g11/smoke-run.log`, per-peer logs in `g11/smoke/`), run
even though this commit adds no RPC, as the standing two-process proof. No
`Engine.time_scale`, no global RNG, no base-stat write, no Dev A file, no
`.tscn`, and nothing on the "Ask first" list touched.

**Blocked / not claimed.** `listen` proves the bus delivers a filtered event to
a named method; it says nothing about proc depth, self-retriggering or the
per-frame spawn cap, which are W4-B3 (G16–G18) and land in this same wrapper.
*(All three landed on 2026-10-20; this section is the G11 record.)*
Nothing in the game attaches an effect yet (no relic content until W4-B5/B6), so
the filter is exercised against the test doubles only; and `once_per_room`'s
"room" is whatever the room-populator emits `room_entered` for — Dev A's
`floor-generation` (W3-A2) is still unlanded, so the reset is tested by
emitting the bus directly.

#### G12 — `modify`, `chance`, `apply_status`, `deal_damage` (2026-10-20)

The four data helpers a relic's effect script actually calls. `modify` shipped
in G10; this goal pins its contract and adds the other three.
`tests/unit/test_effect_helpers.gd` is new: **22 tests / 57 asserts**, green
(`g12/test-effect-helpers.log`), written red first — 17 of 22 failing, every
failure for the right reason (`Nonexistent function 'chance' in base 'Nil'`,
`'apply_status'`, `'deal_damage'`, `Invalid access to property or key 'rng'` —
`g12/red-test-effect-helpers.log`).

**`chance(p)`** rolls on the host's own generator and never on a global roll
function. The two extremes short-circuit *without drawing* — `p <= 0.0` is
false, `p >= 1.0` is true — so a guaranteed or impossible proc does not advance
the run's stream and one effect's certainty cannot desynchronise another's
rolls. Everything between them draws `_resolve_rng().randf() < p`. The
generator is `Effect.rng`: `EffectHost` (G14, landed 2026-10-20) hands every
effect its player's generator on attach, and an effect with no host makes its
own, seeded from
`GameState.run.seed` (or the fixed `DEFAULT_RNG_SEED` when no run is live). Two
consequences are asserted: the same seed replays the same sequence, and the
fallback is a named seed rather than clock entropy, so the draws are
reproducible without a live run. The "no draw at the extremes" claim is proven
by the stream, not by the return value: a control generator at the same seed
supplies the next two values, and the effect's generator is still exactly there
after both extremes were asked.

**`apply_status(target, status, stacks = 1)`** reaches the target's
`StatusEffects` component (stats-status) and passes the effect itself as the
`source`, so `Events.status_applied(target, status, stacks, source)` names the
relic that applied it. `status` is an `int` today — `StatusEffects.Status` is
W4-B4's (G20) and does not exist — and the parameter is retyped to the enum
when it lands, with no call-site change. The component is found by node name
and a `has_method("apply_status")` check rather than a typed cast, for the same
reason; a target with no component is a warned no-op.

**`deal_damage(target, hit)`** stamps `hit.proc_depth = trigger_depth + 1`, tags
the hit `proc` (once — an already-tagged hit keeps one tag), and hands it to the
target's `Hurtbox`, which is what computes the damage and announces it. It
deliberately does **not** emit `hit_landed` itself: the spec's emitters are the
owning modules, and combat-core's hurtbox is the one that owns that signal
(`SPEC-combat-core`: "`receive(hit)` on the host: ... emit `Events.hit_landed`"),
so the chain continues through the hurtbox and the hit is stamped before it gets
there. `trigger_depth` is the depth of the event this effect is handling; the
dispatch wrapper that sets it, the depth-3 gate and the self-retrigger check are
W4-B3 (G16–G17). Until then it stays 0, which is the depth of a hit a weapon
landed, so an effect's own damage lands one link deep. *(The wrapper landed on
2026-10-20; this paragraph is the G13 record.)*

`HitData` gained `proc_depth: int = 0` (`scripts/components/hit_data.gd`) — the
field G16's gate reads and the one G12's helper writes. It is additive with a
zero default, so every existing `Damage.compute` test is unaffected (re-run: the
full suite is green).

**Test doubles.** `StatusEffects` and `Hurtbox` are other modules' and do not
exist yet, so the two call sites are asserted against `tests/helpers/`
doubles carrying the specs' own signatures: `StatusEffectsStub`
(`apply_status(status, stacks, source: Node)`, `blocked on Dev B (W4-B4)`) and
`HurtboxStub` (`receive(hit)`, `blocked on Dev A (W2-A2)`). Both are test-only,
never game scenes.

**Verified:** `-gtest=res://tests/unit/test_effect_helpers.gd` 22/22 green /
57 asserts, exit 0 (`g12/test-effect-helpers.log`); full suite **40 scripts /
635 tests / 635 passing / 55 271 asserts**, exit 0 (`g12/gut-full.log`, up from
the 39 / 613 / 55 214 baseline); `--headless --path . --import` exit 0 with 0
error or warning lines (`g12/import.log`); headless `-- --host --debug-tools
--smoke=6` exit 0 with 0 script/parse errors (`g12/launch-host.log`);
two-instance smoke `GODOT=… OUT=… PORT=… bash tools/smoke_two.sh` exit 0 with
**35 `ok` / 0 FAIL** and the standing hashes `3600649381522393848` /
`536024383148136417` (`g12/smoke-run.log`, per-peer logs in `g12/smoke/`), run
even though this commit adds no RPC, as the standing two-process proof;
`grep -rn "Engine.time_scale" scripts/ scenes/` empty; `grep -rn "\.base\["
scripts/effects/` empty; the only RNG draw under `scripts/effects/` is
`_resolve_rng().randf()`, a method call on the effect's own seeded generator —
no bare global `randf()`/`randi()`/`randf_range()`/`randi_range()` call exists
there. Three failing paths were **forced and kept**
(`g12/negative-controls.log`): dropping `chance`'s extremes short-circuit fails
exactly `test_chance_draws_nothing_at_the_extremes`; dropping the `+ 1` on the
proc depth fails exactly the two depth tests; and writing `stat_block.base[stat]
= flat` from an effect fails the base-stat rules — all three reverted before the
green run.

**Blocked / not claimed.** `apply_status` is asserted against a double, not the
real component: `StatusEffects` (W4-B4 / G20) is where the seven statuses,
their stacking rules and the scaled ticking land. `deal_damage` is asserted
against a double too: Dev A's `Hurtbox` (W2-A2) is still a bare `Area2D`, so
what is proven is the stamping and the delivery call, not a real damage number
reaching `Health` or a real `hit_landed` on the bus. The proc-depth **gate**
(depth 3), the self-retrigger check and the 64-spawns-per-frame cap are W4-B3
(G16–G18); `trigger_depth` is the seam they will drive. *(All three landed on
2026-10-20; this paragraph is the G12 record.)* `chance`'s
Luck-aware sibling `chance_lucky()` is named in the spec's annotation but is
loot-side (W4-B8, G40) and is not implemented here.

#### G14 — `EffectHost`: attach lifecycle, lookup, `list_tags` (2026-10-20)

The node every player carries and the only place an effect is attached.
`scripts/effects/effect_host.gd` is `class_name EffectHost extends Node`, with
the spec's four methods (`add(source, stacks)`, `remove(source)`,
`get_effect(id)`, `list_tags() -> Dictionary`) each carrying its own `##` line,
and the `## Sync: host only` ownership line: the host exists on the host for
every player, clients hold no `Effect` instances.

**Attach lifecycle.** `add(source, stacks)` resolves the host's player from its
parent, refuses with a warning when the source is null, has no id, has no
`effect_script`, has a script that does not extend `Effect`, or whose id is
already attached, then instantiates `source.effect_script` as a child of the
host, injects the host's generator and calls `Effect.attach(player, source,
stacks)`. It returns the live effect (or null on a refusal), which is what the
pick flow (G30) and the harness will use. The effect is parented before
`attach()`, so an `_on_attach()` may use the tree. `remove(source)` erases the
key, calls `detach()` **while the node is alive** (so its modifiers, timers and
`Events` connections are released) and then `queue_free()`s it; it returns
whether there was anything to remove and warns on an unknown source.
`get_effect(id)` returns the live effect or null, `has_effect`/`effect_count`/
`effects` expose the set in attach order.

**The generator is the host's.** `EffectHost.rng` is created on first use and
seeded from `GameState.run.seed` (or `Effect.DEFAULT_RNG_SEED` when no run is
live) — never clock entropy — and every effect added is handed the same object,
which is what G12's decision 41 promised the host would do. One stream per
player means one seed replays that player's procs.

**`list_tags()` counts by stacks.** Every tag on every attached effect's
`source.tags`, with each occurrence weighting by that effect's `stacks`
(`fire` on a 3-stack relic counts 3), an empty `Dictionary` when nothing is
attached and no zero entries for tags nothing carries. That is the exact shape
`SynergyTracker` (W4-B5's consumer) evaluates `SynergyData.required_count`
against on `relic_picked`/`relic_removed`.

**Event dispatch.** Effects subscribe to the `Events` bus themselves through
`Effect.listen()`, whose player filter (G11) already keeps an event from
reaching another player's effects; the host is therefore the single place the
effects' lifetime is enforced rather than a second bus. The dispatch case in
the test proves the path end to end with two hosts on two players: a
`player_dodged` for one player reaches exactly that player's effect, the other
player's effect sees nothing, and a removed effect stops receiving events. The
proc-ruled wrapper (depth 3, self-retrigger and the 64-per-frame cap) is W4-B3
(G16–G18) and lands in this same subscription path. *(It landed on 2026-10-20;
this section is the G14 record.)*

**Player installation.** `player.tscn` is Dev A's scene and is not edited, so
the host is installed by `tests/helpers/effect_host_player.gd`
(`EffectHostPlayer.install(player)`, idempotent, node named `EffectHost` from
`EffectHost.NODE_NAME`), the `fake_health.gd` pattern. When the player scene
gains its composition the child moves into `player.tscn` and the helper keeps
working unchanged; recorded as **blocked on Dev A (W2-A1, player.tscn)** in the
helper's doc comment.

**Verified:** new `tests/unit/test_effect_host.gd` **17/17 green / 85 asserts**
(`.goals/evidence/g14/test-effect-host.log`), written red first (GUT refused the
file with a parse error — `EffectHost` and its helper did not exist,
`g14/red-test-effect-host.log`). The failing path was forced and kept for the
tag weighting: counting each tag once instead of by stacks failed exactly the
two `list_tags` cases (`[2] expected to equal [4]: fire: 1 + 3 stacks`) and
nothing else (`g14/negative-control-tag-stacks.log`), then reverted. Full suite
**42 scripts / 668 tests / 668 passing / 55 411 asserts** exit 0
(`g14/gut-full.log`, up from 41 / 651 / 55 326); `--headless --path . --import`
exit 0 with 0 error or warning lines (`g14/import.log`); two-instance smoke
35 `ok` / 0 FAIL (`g14/smoke-run.log`), run even though this commit adds no RPC.
`grep -rn "Engine.time_scale" scripts/ scenes/` empty; no Dev A file and no
`.tscn` touched.

**Blocked / not claimed.** `add()` is a container operation: it does not emit
`relic_picked`, update `RunPlayerState` or roll anything — the pick flow is
G30's. Nothing calls `add()` in the game yet because no relic content exists
until W4-B5/B6, so what is proved is that the lifecycle is correct when it
does. There is no client path: clients hold no `Effect` instances. The proc
caps, the harness and Mimic Crown's id-suffixed duplicate are W4-B3. *(As of
this section; all three landed under W4-B3 on 2026-10-20 — see G16, G18, G19a
and G19b below.)*

#### G15 — `spawn` and `fire_projectile` through the spawner seam (2026-10-20)

The "my dodge spawns lightning clones that explode" half of the effect system:
the two helpers an effect script calls when it wants a node in the world rather
than a number changed.

**The seam.** New `scripts/effects/effect_spawner.gd` —
`class_name EffectSpawner extends Node` — is the one place an effect's spawn
request lands. It is *not* reached by path: SPEC-project forbids cross-module
tree-path reach-through, so the world hands the player's `EffectHost` one
(`EffectHost.spawner`, with `spawner_path` resolved once on `_ready()` for a
world that would rather wire a node path), and `EffectHost.spawn_proc()` /
`fire_proc_projectile()` forward to it. `Effect.host` is set by
`EffectHost.add()`, so `Effect.spawn()` and `Effect.fire_projectile()` reach the
host without walking the tree either.

`EffectSpawner.spawn_node(scene, pos, setup, source_id, depth)` instantiates,
stamps, positions, runs the caller's `setup` callable **and only then parents**
the instance under `container` — so a spawner can still configure a node that
has not entered the tree, and before any `_ready()` on it could run.
`EffectSpawner.spawn_projectile(spec, from, dir, source_id, depth)` hands the
`ProjectileSpec` to the shipping `ProjectileSpawner` whole — scene, speed,
damage, element, pierce and bounce are exactly the spec's fields — and then
stamps the same numbers onto the projectile that came back, so the result
carries what the spec described.

**Provenance.** Every result carries `proc_source_id` (the effect's `source.id`)
and `proc_depth`, which is SPEC-effect-system's "Visual language" rule: the VFX
library colours by element and the debug overlay (W4-B11) says which relic made
what. A root that declares the field gets it as a property (the
`ProjectileSpawner.synced_position` convention); one that does not gets it as
metadata, so an art-audio scene can never silently lose the value. The one
reader for both is `EffectSpawner.read_stamp(node, key)`.

**Proc depth.** Both helpers pass `trigger_depth + 1` — SPEC-effect-system,
"Proc chain limits": "`deal_damage`, `spawn`, and `fire_projectile` from an
effect create results with `proc_depth = trigger.proc_depth + 1`". A spawned
node therefore carries *the depth the trigger produced*, one link past the event
that caused it, which is the same rule `deal_damage` applies to a hit and the
depth G16's gate will read. The test asserts `deal_damage`'s result and
`fire_projectile`'s result side by side so the two cannot drift.

**The client gate has exactly one home.** `EffectHost.can_spawn()` (over the
`_can_spawn()` seam, defaulting to `multiplayer.is_server()`, the shape
`EnemySpawner`/`ProjectileSpawner` already use) refuses before the seam is
reached. Putting a second check inside `EffectSpawner` was rejected: two gates
means a spawner reached another way is *hidden* rather than reported, and one
gate is one thing to test.

**Verified:** new `tests/unit/test_effect_spawn.gd` **25/25 green / 93 asserts**
(`.goals/evidence/g15/test-effect-spawn.log`), written first and run red for the
right reason — against an `Effect` without the two helpers, 23 of the 25 cases
fail with `Nonexistent function 'spawn'` (`g15/red-test-effect-spawn.log`). Full
suite **43 scripts / 693 tests / 693 passing / 55 504 asserts** exit 0
(`g15/gut-full.log`, up from 42 / 668 / 55 411). `--headless --path . --import`
exit 0 with 0 error lines. Two-instance smoke **35 `ok` / 0 FAIL / exit 0**
(`g15/smoke-run.log`, `PORT=28901`), run even though this commit adds no RPC.
The failing path was forced and kept: dropping the `+ 1` on `spawn`'s depth
failed exactly the four depth cases and nothing else
(`g15/negative-control.log`), then reverted. The whole seam is exercised for
real as well as through the spy — `test_fire_projectile_through_the_real_projectile_spawner`
fires through the shipping `ProjectileSpawner` and its placeholder scene.

**Blocked / not claimed.** The FX-with-gameplay spawner does not exist (Dev A's
W4-A4, and `World/Entities` has only the enemy and projectile spawners today),
and neither does combat-core's real `Projectile`, so `EffectSpawner` is not yet
wired into `world.tscn` and the game drops effect spawns with a warning —
**blocked on Dev A (W4-A4)** in the seam's doc comment and `tasks/todo.md`. The
swap-in is a wiring change on the world, not a change to any helper: a
`ProjectileSpawner` reference and a container node are all the seam needs.
Nothing here is replicated yet — the seam's results reach clients when the real
spawners do — so the two-instance smoke was run as insurance, not as proof of a
sync path. The per-frame 64-spawn cap is G18 and lands inside this seam.

### W4-B3 — proc depth gate (`effect-system`) — complete 2026-10-20

**All four of SPEC-effect-system's "Proc chain limits" rules are in** — depth cap
(G16), no self-retrigger (G17), the per-frame spawn cap (G18) and the Mimic Crown
duplication rule (G19b) — plus the trigger-test harness (G19a). The sections
below are the section-per-goal record in the order they landed; this heading said
"in progress" from G16 until G19b, and `tasks/todo.md`'s W4-B3 tick went with the
last of them.

The first of SPEC-effect-system's three hard caps is in: **a proc chain stops at
depth 3**. The rule is enforced in exactly one place — `Effect._forward()`, the
dispatch wrapper `listen()` puts in front of every handler it connects — so a
relic author cannot forget it and a new effect script cannot bypass it.

**What changed.** `scripts/effects/effect.gd` gained
`const MAX_PROC_DEPTH: int = 3` (with the spec sentence that fixes the number in
its doc comment) and the gate itself:

- `listen()` used to decide between "wrap" and "connect untouched" purely on
  whether the signal declared a `Player` argument. `hit_landed` declares none, so
  the busiest event in the game was connected **raw** and could never be gated.
  A signal now also routes through the wrapper when it carries a hit —
  `_carries_a_hit()` reads the signal's own declaration and matches the payload
  against `HIT_CLASSES` (`HitData` today, `HitInfo` accepted already so
  combat-core's landing is a type rename and not a second list to keep in step).
  A signal with neither a `Player` nor a hit is still connected untouched:
  nothing is wrapped that has nothing to look at.
- `_forward()` reads the event's own depth (`_event_proc_depth()` — the maximum
  `proc_depth` across the event's `HitData` arguments) and returns early when it
  has reached `MAX_PROC_DEPTH`. The hit itself is untouched: it was already
  delivered to the hurtbox and already announced on `Events.hit_landed` by
  combat-core, so "its hits still damage" holds by construction rather than by a
  second decision in the wrapper.
- `_forward()` also publishes the event's depth as `trigger_depth` for the
  duration of the handler and restores what it found, so `deal_damage`/`spawn`/
  `fire_projectile`'s shipped `+ 1` is now a step in a chain instead of a
  constant. That assignment is what the pre-G16 code was missing: the field
  existed and the `+ 1` was asserted, but nothing ever raised the depth above 0.

`tests/unit/test_proc_limits.gd` (10 cases / 59 asserts) is the acceptance
evidence. It pins the four clauses of the spec sentence separately — the depth
travels on `HitData` defaulting to 0; depth-0/1/2 events reach a handler and
depth-3/4 ones do not (each boundary asserted on its own); the depth-3 hit is
still announced on `Events.hit_landed` and still reaches the damage sink; and the
chain therefore stops — plus the `+ 1` stamps on all three helpers, the gate on
**every** hit-carrying signal (not `hit_landed` alone), and the negative control
that the gate reads the event rather than a stale field on the effect.

Two chain shapes are covered on purpose, because a chain that stops can stop for
the wrong reason. One self-triggering effect is given a **five-link budget** and
uses three; a chain of five *different* effects stops with a named link (`link_3`)
never reacting. The probe's own budget is longer than the spec's limit
everywhere, so a stop is the gate's doing and not the fixture running out.

The chain advances through the real path: `ProcHurtboxStub` records the hit and
then does what SPEC-combat-core says the real hurtbox does — announce
`Events.hit_landed` — so `Effect.deal_damage` deliberately still does not emit the
signal (HANDOFF decision 41) and the chain is driven by the module that owns the
event. The double is **blocked on Dev A (W2-A2)** for combat-core's real
`Hurtbox`.

**Accept.** `-gtest=res://tests/unit/test_proc_limits.gd` exit 0, 10/10, 59
asserts; the five other effect files unchanged and green (`test_effect_base`
25/103, `test_effect_host` 17/85, `test_effect_helpers` 22/57, `test_effect_spawn`
25/93, `test_effect_timers` 16/53); full suite **44 scripts / 705 tests / 705
passing / 55 620 asserts** exit 0 (up from 43 / 693 / 55 504); `--import` exit 0
with zero error lines; two-instance smoke 0 `FAIL`. The failing path was forced
once and kept: with `MAX_PROC_DEPTH` temporarily 5 the chains ran all five links
and only the gate assertions failed (`.goals/evidence/g16/negative-control.log`).

**Not claimed (at G16).** No self-retrigger rule (G17), no 64-spawns-per-frame
cap (G18), and no Mimic Crown duplication (G19a/G19b) — all three landed in this
same wrapper later the same day, 2026-10-20 (see below). The gate is host-only
logic like the rest of `Effect`; there is no
client half to replicate, so the smoke run is insurance rather than proof of a
sync path.

#### G17 — an effect never reacts to a hit tagged with its own id (2026-10-20)

SPEC-effect-system, "Proc chain limits", rule 2: "An effect never reacts to a hit
whose `tags` already contain its own id (no self-retrigger)." The check is the
second thing `Effect._forward()` does, in the same wrapper as G16's depth gate and
for the same reason — one place that knows the proc rules, which no effect script
can forget and no new effect script can bypass.

**What changed.** `scripts/effects/effect.gd` only:

- `_is_own_hit(values)` returns true when any hit the event carries has
  `source_id()` in its `tags`; `_forward()` returns early on it, before the depth
  gate. The comparison is against the **content id** the effect was attached
  with, never the class name, so two effects built from one script (a Mimic
  Crown copy, two relics sharing an effect script) are suppressed independently,
  each by its own id only; an effect attached with no source reads `&""` and has
  no id to match, so the check passes everything through instead of matching an
  empty tag.
- `_event_hits(values)` was factored out and now backs both rules — the
  self-tag check and the depth gate read the same list, so "what counts as a hit"
  is one decision rather than two that can drift apart
  (`.goals/evidence/g16/` and `g17/` both still pass unchanged after the
  refactor).
- Only the *reaction* is suppressed. The hit was already delivered to the hurtbox
  and already announced on `Events.hit_landed` by combat-core, so it still
  damages — the same "its hits still damage" clause rule 1 is written around.

**Who stamps the tag.** The reacting side is the wrapper's; the *producing* side
is the caller's. `deal_damage()` stamps `proc` and the depth and leaves `tags`
alone, because a hit's tag list is also a weapon's, a status's and a hazard's.
Stamping the source id here was considered and rejected: it would make
`deal_damage` uncallable from an effect that legitimately self-triggers (G16's
self-triggering chain shape stops being expressible at all), which trades a
backstop for a single mechanism. An effect that wants rule 2 to protect it
appends `source_id()` to the tags of every hit it deals; `listen()`'s doc comment
states this, and W4-B6's relic batch will do it (`ember_boots` and friends) once
W4-B6 lands — no relic content exists yet, `data/relics/` holds only `.gdkeep`.
The two rules therefore compose instead of overlapping: rule 2 catches the tagged
self-reference, rule 1 is the backstop for a chain that carries no id.

**Accept.** `-gtest=res://tests/unit/test_proc_limits.gd` exit 0, **18/18, 111
asserts** (10 cases / 59 asserts at G16 — 8 new cases, all red first, six failing
for the right reason under `.goals/evidence/g17/red-test-proc-limits.log`); full
suite **44 scripts / 713 tests / 713 passing / 55 672 asserts** exit 0 (up from
44 / 705 / 55 620); `--import` exit 0 with zero error lines; the five other effect
files run individually and unchanged (`test_effect_base` 25/103,
`test_effect_host` 17/85, `test_effect_helpers` 22/57, `test_effect_spawn` 25/93,
`test_effect_timers` 16/53 — the same counts as G16, so no depth or cleanup case
moved); headless `-- --host --debug-tools --smoke=6` exit 0 with zero error and
zero parse-error lines. The failing path was forced once and kept: with
`_is_own_hit()` short-circuited to `false`, **exactly the five rule-2 cases fail**
and no other case in the file moves (`.goals/evidence/g17/negative-control.log`,
13 passing / 5 failing). The first attempt at that control patched the wrong
occurrence of the shared loop and took the depth gate down with it, failing 13
cases — the log it produced was discarded rather than kept, and the working
control is scoped to `_is_own_hit()` alone.

**Judgment calls (HANDOFF decision 46).** (1) The rule lives in the shared
wrapper and not in a per-signal wrapper, which is what makes it hold on
`enemy_killed` and `elite_killed` as well as `hit_landed` — asserted on all five
hit-carrying signals. (2) The mutual-reference case is asserted on a *derived*
number: two effects that each tag their hits with the other's id produce six
reactions — each effect three times, at depths 0, 1 and 2, and never for the hit
tagged with its own id — against fourteen for the same pair with nothing
tagged. The fourteen is the control that makes the six mean "the rule removed
them"; the per-effect depth lists are asserted rather than the interleaved log
order, so the count does not depend on which connection fired first. (3) The
G16 chain-of-five fixture used the effect's **own id** as its routing tag, which
rule 2 makes un-routable by construction; its routing tag moved to a separate
`hop_N` namespace so the two rules are asserted separately, and every assertion
in that case (the named stop at `link_3`, the depths `[0, 1, 2]`, the dealt
depths) is byte-for-byte unchanged. (4) `ProcChainProbe.handler_calls` counts
events the wrapper let through *before* the probe's own tag filter, so a
suppressed event is proven never to reach a handler rather than inferred from a
log that the probe's filter could also have left empty.

**Not claimed.** The 64-spawns-per-frame cap (G18), the trigger harness (G19a)
and the Mimic Crown duplication rule (G19b). Still **blocked on Dev A (W2-A2)**
for the real `Hurtbox` the chain advances through. *(Scope of this section, as of
G17; all three landed on 2026-10-20 — the cap at G18, the harness at G19a and the
duplication rule at G19b, all below.)*

#### G18 — the 64-spawns-per-player-per-frame cap (2026-10-20)

SPEC-effect-system, "Proc chain limits", rule 3: "Per-frame cap: at most 64
effect-spawned nodes per player per frame; the rest are dropped and counted in a
debug stat." The cap is enforced on `EffectHost` — the one boundary every effect
reaches to spawn — and not in an effect script, which is what makes it
unbypassable by a new relic.

**What changed.** `scripts/effects/effect_host.gd` only (plus the tests):

- `MAX_SPAWNS_PER_FRAME: int = 64`, doc-commented with rule 3 quoted verbatim.
- `_spend_spawn_budget(source_id)` is called by both `spawn_proc()` and
  `fire_proc_projectile()` and by nothing else, in one shared per-host budget —
  the spec's unit is "effect-spawned nodes", so a relic cannot buy a second 64
  by firing projectiles instead of spawning clones.
- Three public, frame-keyed counters: `spawns_this_frame` (allowed),
  `spawns_dropped` (refused) and `drop_reports` (lines written about them, at
  most one per frame). These are the "debug stat" rule 3 requires and what the
  debug overlay (W4-B11, G55) will read.
- The frame is `Engine.get_physics_frames()`. The counters are *computed* from
  the frame they belong to rather than reset in a process callback, so a read in
  a new frame is 0 whether or not this node has been processed yet, and a host
  that is paused or out of the tree for a tick cannot spend or read last frame's
  budget. The budget is refreshed lazily in `_spend_spawn_budget()`.

**Accept.** `-gtest=res://tests/unit/test_proc_limits.gd` exit 0, **26/26, 158
asserts** (18 cases / 111 asserts at G17 — 8 new cases, all written and run red
first, failing with `Cannot find member "MAX_SPAWNS_PER_FRAME" in base
"EffectHost"`, `.goals/evidence/g18/red-test-proc-limits.log`); full suite **44
scripts / 721 tests / 721 passing / 55 719 asserts** exit 0 (`g18/gut-full.log`,
up from 713 / 55 672 at `67d9bbe`); `--headless --path . --import` exit 0 with
zero error and zero warning lines (`.goals/evidence/g18/import.log`); the five
other effect test files run individually and unchanged (`test_effect_base`
25/25, `test_effect_host` 17/17, `test_effect_helpers` 22/22,
`test_effect_spawn` 25/25, `test_effect_timers` 16/16 — the same counts as G17,
so no depth, self-tag or cleanup case moved, `g18/effect-files.log`). The failing
path was forced once and kept: with `MAX_SPAWNS_PER_FRAME` set to 5, **exactly
the eight cap cases fail** (18 passing / 8 failing) and no depth or self-tag case
in the file moves (`g18/negative-control.log`), then reverted and `grep`-confirmed
back to 64. The single announcement per frame is also observable in the real
output, not only through `drop_reports`: `grep -c` on the run log finds the
warning **9 times for 9 host-frames that capped out** — one per host per frame,
never one per dropped node (`g18/test-proc-limits.log`).

**Judgment calls (HANDOFF decision 47).** (1) One shared budget for both spawn
helpers rather than one each — see above; the case spends 60 on nodes and 4 on
projectiles to prove it. (2) The counters are computed from the frame key, so
"resets on the next physics frame" holds by construction and there is no
`_physics_process` on `EffectHost` at all. (3) The refusal is a `push_warning`,
not an error: reaching the cap is a designed outcome for a pathological build,
not a fault, and the suite must stay engine-error free. (4) The cap is checked
*after* the client gate and the seam-wiring check, so only requests that would
otherwise have spawned are counted as capped-drops, and an unwired seam (Dev A
W4-A4) still shows up as its own refusal rather than as cap pressure.

**Not claimed (at G18).** The trigger-test harness `tests/helpers/effect_harness.gd`
and the Mimic Crown duplication rule (G19a/G19b) were not implemented at that
commit — **both landed the same day, 2026-10-20: the harness as G19a and the
Mimic Crown rule as G19b (see below), and `data/relics/` still holds only
`.gdkeep`.** The chain
still advances through `ProcHurtboxStub`, **blocked on Dev A (W2-A2)** for
combat-core's real `Hurtbox`, and the FX spawner the cap guards is **blocked on
Dev A (W4-A4)**.

#### G19a — the trigger-test harness and its template test (2026-10-20)

SPEC-effect-system, "Interfaces provided": the module ships "Trigger test harness
`tests/helpers/effect_harness.gd`: creates a headless player with `EffectHost`,
attaches an effect, fires any `Events` signal with fake arguments, asserts
spawns, stat changes, statuses, and damage via a `SpyWorld`." This goal is that
instrument plus the template case a content author copies; the Mimic Crown
duplication rule was split off to G19b because it is a production rule rather
than a test instrument.

**What shipped.** Four files under `tests/helpers/` and one under `tests/unit/`
— **no production file changed at all**:

- `tests/helpers/effect_harness.gd` (`class_name EffectHarness`) — the
  instrument. `setup()` builds one autofreed root; `make_player()` gives that
  root the real `player.tscn` with a `StatBlock` component, a `StatusEffects`
  double, a `SpyHurtbox` and an `EffectHost`; `make_target()` builds a node with
  the same two components for damage and statuses to land on; `attach()` goes
  through the real `EffectHost.add()`; `detach()` through the real `remove()`;
  `fire(sig, args)` emits any `Events` signal by its own signal object after
  checking the name is on the bus and the argument count matches; `source()`
  builds a `ContentData` in memory and `marker_scene()` a one-node scene, so a
  case needs neither content nor art to exist yet.
- `tests/helpers/spy_world.gd` (`class_name SpyWorld`) — the recorder the spec
  names. It **extends `EffectSpawnerSpy`** rather than duplicating it, so the
  spawn half is the shipped double (which records *and* runs the real
  `EffectSpawner` base) and this class adds the damage half plus
  `spawn_count`/`spawns_for`/`damage_count`/`damage_hits`/`damage_total`.
- `tests/helpers/spy_hurtbox.gd` (`class_name SpyHurtbox`) — the target's
  hurtbox double: it reports every `receive(hit)` to the world and, when the
  world asks, announces it on `Events.hit_landed` exactly as the real hurtbox
  does (off by default, so a case asserting a relic's damage is not surprised by
  its own hit echoing back; `ProcHurtboxStub` is the announce-always shape the
  proc-limit tests use).
- `tests/helpers/harness_sample_effect.gd` (`class_name HarnessSampleEffect`) —
  the sample relic the template drives: on `player_dodged` it spawns, modifies
  `MOVE_SPEED`, applies a status and deals a hit, each part switched off until
  the case sets its field, so one double also serves as the deliberately broken
  relic.
- `tests/unit/test_effect_template.gd` — the template and its self-test.

**Two ways to assert, and why.** Every one of the four categories has a pure
predicate (`check_spawned`, `check_stat`, `check_status`, `check_damage`, plus
`check_attached`/`check_no_spawns`) and a GUT-reporting wrapper
(`assert_spawned`, `assert_stat`, `assert_status`, `assert_damage`,
`assert_attached`, `assert_no_spawns`). The predicates exist so a case can assert
the **negative** — that is how the self-test proves the harness's own assertion
would have caught a broken relic, which `assert_*` alone cannot express without
failing the run it is trying to test.

**Accept.** `-gtest=res://tests/unit/test_effect_template.gd` exit 0, **7/7, 49
asserts** (`g19a/test-effect-template.log`), written and run red first — the file
was authored before any helper existed and the red is the parse error, "Identifier
`EffectHarness` not declared in the current scope"
(`g19a/red-test-effect-template.log`). Full suite **45 scripts / 728 tests / 728
passing / 55 768 asserts** exit 0 (`g19a/gut-full.log`, up from 44 / 721 / 55 719
at `799646c`), the delta being exactly this file's 7 tests and 49 asserts.
`--headless --path . --import` exit 0 with **zero error lines**
(`g19a/import.log`); the seven effect test files re-run in one loop, the six
pre-existing counts byte-for-byte unchanged so no depth, self-tag, spawn-cap or
cleanup case moved (`g19a/effect-files.log`); `git status --porcelain` clean
apart from `.goals/`/`.claude/`. No smoke run: this commit touches no RPC,
replication or spawner wiring (BRIEF C17) — it adds test-only files.

**Judgment calls (HANDOFF decision 48).** (1) The failing path was forced once
and kept: with the self-test's `assert_false(check_spawned(1))` flipped to
`assert_true`, **exactly that case fails** (6 passing / 1 failing) and nothing
else moves (`g19a/negative-control.log`), then reverted and `grep`-confirmed —
so `check_spawned` is proven able to report "the relic did not fire" rather than
merely observed to be true. (2) `fire()` takes the bus's own `Signal`
(`Events.player_dodged`) rather than a `StringName`, so the compiler catches a
signal that does not exist and the name is still read back off the object to
check the bus's own declaration — the guard is asserted in three ways (unknown
name, one argument, three arguments). (3) A refusal in `fire()`/`attach()` is a
`push_warning` returning `false`/`null`, never a GUT failure: a harness that
kills the run it is diagnosing is worse than one whose case then fails on the
consequence in its own words. (4) `attach()` defaults to the **first** player
made (`primary_player`), not the most recent, so a case that builds a second
player to prove the player filter still attaches to the one it means. (5)
`SpyWorld` announces hits only when asked, because the real hurtbox always
announces and a content case asserting a relic's damage should not silently run
the relic again. (6) The harness is typed against `GutTest` and is
`tests/`-only; nothing under `scripts/` imports it, so the game is untouched.

**Not claimed (at G19a).** The Mimic Crown duplication rule was G19b's and is not
implemented at that commit — it landed the same day, 2026-10-20 (see below), and
`tasks/todo.md`'s W4-B3 tick went with it. No relic or mutation case exists yet:
`data/relics/` still holds only `.gdkeep`, and the 20 relics of W4-B6 are the
harness's first real users (G32 onward). The player composition the harness
assembles by hand is **blocked on Dev A (W2-A1, player.tscn)**; the harness
returns the scene's existing host when that composition lands, so the swap-in is
mechanical.

#### G19b — the Mimic-Crown duplication rule, and W4-B3's tick (2026-10-20)

SPEC-effect-system, "Proc chain limits", rule 4: "Mimic Crown copies the last
picked relic's effect; the copy is a second `Effect` instance with its own id
suffix so rule 2 still applies." The last of the four proc rules and the last
goal of W4-B3: rules 1–3 (depth cap, no self-retrigger, spawn cap) each added a
gate to one wrapper, and this one adds the *second instance* those gates have to
tell apart. The design doc's no. 58 says only "**Mimic Crown:** copies the effect
of your last picked relic"; the spec sentence is what makes it implementable, and
the clause that decides the whole shape is "**so rule 2 still applies**" — a copy
that shared its original's id would suppress its own hits and be suppressed by
its original's, which is not a copy at all.

**What changed.** Two production files, two test files:

- `scripts/effects/effect.gd` — `Effect` gains `id_suffix: StringName` and
  `source_id()` now returns `EffectHost.suffixed_id(source.id, id_suffix)`
  instead of `source.id`. The copy holds the **same `ContentData`** as the relic
  it copies (there is one `.tres` per relic; a second resource would be a second
  thing to keep in sync), so the suffix is the only thing separating the two
  instances: the host's key, the node's `name`, and — through rule 2's check,
  which keys on `source_id()` — the tag that suppresses it.
- `scripts/effects/effect_host.gd` — `MIMIC_CROWN_SUFFIX` (`&"__crown"`),
  `static suffixed_id()`, `add_mimic_copy(copied, owner_id, stacks)`,
  `has_mimic_copy_of(id, owner_id)` and the private `_mimic_owners` dictionary
  that ties each copy to the effect that made it. `add()` gains an `id_suffix`
  parameter (defaulting to `&""`, so every existing caller and every existing
  call site is unchanged) and is the **only** place an effect script is
  instantiated — the copy is an ordinary `add()`, so it inherits the lifecycle,
  the RNG injection and the ownership `add()` already establishes rather than
  going through a parallel attach path that could drift from them. `remove()`
  now calls `_drop_mimic_copies_going_with()`, so a removed effect takes its own
  copy with it and a removed crown takes the copy it made.
- `tests/helpers/mimic_crown_stub.gd` (`class_name MimicCrownStub`) — the
  week-8 relic's double, `blocked on Dev B (W8-B?, the Mimic Crown relic)`. On
  attach it finds the most recently attached effect that is not itself and calls
  `host.add_mimic_copy()`. The real `mimic_crown.gd` differs only in how it
  resolves "last picked" (the shipped relic will read the replicated
  `RunPlayerState`; this double reads host attach order), and the duplication
  rule itself is the host's — rule 4 is one of the rules the spec requires to be
  "enforced in the helpers, not in each effect".
- `tests/unit/test_mimic_crown.gd` — 13 cases, built on G19a's `EffectHarness`,
  `EffectHostPlayer` and `ProcChainProbe`, so the effects under test listen
  through the real `Effect.listen()` wrapper and are attached through the real
  `add()`. Run red first (see below).

**Accept.** `-gtest=res://tests/unit/test_mimic_crown.gd` exit 0, **13/13, 107
asserts** (`g19b/gut-full.log` carries the file's run inside the suite), written
and run red first: the file was authored before `MIMIC_CROWN_SUFFIX` existed and
the red is "Cannot find member \"MIMIC_CROWN_SUFFIX\" in base \"EffectHost\""
(`g19b/red-test-mimic-crown.log`). Full suite **46 scripts / 741 tests / 741
passing / 55 875 asserts** exit 0 (`g19b/gut-full.log`, up from 45 / 728 / 55 768
at `013ab25`), the delta being exactly this file's 13 tests and 107 asserts.
`--headless --path . --import` exit 0 with **zero error and zero warning lines**
(`g19b/import.log`); the nine effect-family files re-run in one loop with every
pre-existing count byte-for-byte unchanged — `test_effect_base` 25/103,
`test_effect_host` 17/85, `test_effect_helpers` 22/57, `test_effect_spawn` 25/93,
`test_effect_timers` 16/53, `test_effect_template` 7/49, `test_proc_limits`
26/158, `test_tags` 15/258, all passing (`g19b/effect-files.log`) — so no depth,
self-tag, spawn-cap or cleanup case moved, and the new file's own 13/107 is
recorded beside them. No two-instance smoke run: the commit touches no RPC,
replication or spawner wiring (BRIEF C17) — the duplication path is host-only
logic, like every other effect path — but the game itself was run headless for
insurance, `--headless --path . -- --host --smoke=6` exit 0 with zero error
lines (`g19b/host-smoke.log`), so the build still boots and plays a solo session
with the new `add()` signature in it.

**Judgment calls (HANDOFF decision 49).** (1) The suffix is `&"__crown"` and is
named in **two** places on purpose: `EffectHost.MIMIC_CROWN_SUFFIX` (what the
code uses) and a `SUFFIX` const in the test (what the id must look like), so a
copy whose id silently changed shape fails the suite instead of making every
store that looks a copy up by id — the HUD, the debug overlay, a save — miss it.
(2) The failing path was forced once and kept: with `Effect.source_id()`
returning the unsuffixed id — the one line rule 4 turns on — **6 of 13 cases
fail** (7 passing, 94/107 asserts) and the six are exactly the suffix-dependent
ones (the copy reports the wrong id; the original and its copy stop reacting
separately; each suppresses the wrong one of the pair; the crown's removal takes
the *relic* out instead of the copy, so "the copied relic stays attached" fails;
the copy outlives the relic it copies), while the spec-quote, suffix-form,
one-attach-path, refusal, empty-crown and tag-count cases do not move
(`g19b/negative-control.log`), then reverted and `grep`-confirmed — so the
suffix's effect on identity, suppression and cleanup is proven to be tested
rather than merely observed. (3) "Removing Mimic Crown detaches only the copy" reads as **removing
the crown removes the crown and its copy and leaves the copied relic attached**:
the relic the player still holds must keep working, and a copy whose owner is
gone is of nothing. The other direction is asserted too — removing the *copied*
relic takes its copy with it, so a copy can never outlive what it copies. (4)
The copy's own `Effect` is not a second content entry, so **`list_tags()` counts
a copied relic's tags twice while the crown is held**; the case that pins this is
explicitly a policy pin, not a spec claim, with the one-line alternative
(exclude copies from the count) noted for the week-8 balance pass. (5)
`has_mimic_copy_of()` and `add_mimic_copy()` are new public surface on a
module's own class rather than an autoload, so nothing on the Ask-first list
moved; `add()`'s new parameter is additive with a default, so no existing caller
changed. (6) SPEC-effect-system's Testing section names `test_tags.gd` for
"counts, Mimic Crown duplication"; the counts half lives there (G9) and the
duplication half is its own file, `tests/unit/test_mimic_crown.gd`, which the
goal's own sub-task allows in as many words ("Extend
`tests/unit/test_effect_template.gd` (or add `tests/unit/test_mimic_crown.gd`)
first"). The duplicate-counting case that would have gone in `test_tags.gd` is
instead the last case of the new file, so the "counts" the spec's bullet pairs
with duplication are asserted beside it; `test_tags.gd` itself is unchanged, and
`g19b/effect-files.log` is the proof its 15 cases still pass.

**Not claimed.** The real `mimic_crown.gd` and its `.tres` do not exist — the
week-8 relic batch (W8-B, G-when-it-arrives) ships them and deletes
`MimicCrownStub`, re-pointing its case at `data/relics/mimic_crown.tres`;
`data/relics/` still holds only `.gdkeep`. A copy is not yet reachable in the
game: nothing calls `add()` in a running build, because no relic content exists
until W4-B5/B6 (G32 onward). The crown copies **one** relic — the last picked —
and there is no re-copy when the player picks a later relic, no un-copy when the
crown is stacked, and no stacking interaction beyond the `stacks` argument
`add_mimic_copy()` already forwards; those are the week-8 relic's business, not
the duplication rule's. The copy carries no client half: clients hold no
`Effect` instances. The player composition the test assembles by hand is still
**blocked on Dev A (W2-A1, player.tscn)**.

---

#### G20 — the `StatusEffects` core, and ticking on scaled time (2026-10-20)

The first goal of W4-B4 and the component the whole stats-status module hangs
off. SPEC-stats-status's "Statuses" section fixes the API in as many words —
`apply_status()`, `has()`, `stacks()`, `clear()`, `clear_all()`, plus the two
signals — and its table fixes eight rows (seven statuses, with FREEZE listed as
a row of its own), each with a stacking rule and a duration. Its last line fixes
the one gate the component has to carry: "Players can receive BURN, CHILL,
TOXIN, BLEED from enemies and hazards, never MARK/UNRAVEL/FREEZE." And its
"Multiplayer ownership" paragraph fixes the sync story: "All computation on the
host", with the stacks "replicated by the entity's `StateSync` so clients can
render icons and tints."

The one piece of the goal that is not a table entry is the ticking rule, and it
is the piece that decides the component's shape: a status tick must advance on
**scaled** time. `_physics_process` multiplies its delta by
`TimeManager.scale_for(entity())`, so a time stop aimed at the enemies freezes a
burning enemy's damage with it — not `Engine.time_scale`, which the project
forbids, and not a raw delta, which would have a stopped enemy keep burning.

**What changed.** Two production files, three test files:

- `scripts/components/status_effects.gd` (new, `class_name StatusEffects extends
  Node`) — the deliverable. `enum Status { BURN, CHILL, FREEZE, SHOCK, TOXIN,
  MARK, BLEED, UNRAVEL }`, the two signals (`status_applied(status, stacks)`,
  `status_expired(status)`), the API above, and the reads the rest of the game
  needs (`active_statuses()`, `remaining()`, `allows()`, `max_stacks()`,
  `duration()`, `status_name()`, `damage_per_second()`, `max_hp()`). Every
  number in the spec's table is a **named constant** (`BURN_MAX_STACKS` = 5,
  `BURN_DURATION` = 4.0, `BLEED_MAX_STACKS` = 10, `TOXIN_MAX_STACKS` =
  `UNLIMITED_STACKS`, …) and the four tables the component keys off
  (`STATUS_NAMES`, `STATUS_ELEMENT`, `STATUS_MAX_STACKS`, `STATUS_DURATION`,
  `STATUS_DAMAGE_PER_SECOND`) are built from those constants, so a status that
  the spec adds or renumbers is one edit and no literal.
- `scripts/effects/effect.gd` — `apply_status()`'s `status` parameter is
  **retyped to `StatusEffects.Status`**, which is the retype its own doc comment
  promised ("an int until W4-B4's component lands, at which point this parameter
  is retyped to the enum"), and the `_status_component()` comment now says why
  the duck-typed lookup stays a duck-typed lookup now that the class exists.
- `scripts/network/player_spawner.gd` — one line,
  `player.add_to_group(StatusEffects.PLAYER_TAG)`, in `_spawn_from_data()`.
- `tests/unit/test_status_effects.gd` (new) — 26 cases, 192 asserts, written and
  run red first.
- `tests/helpers/status_health_stub.gd` (new) — the double for Dev A's `Health`
  (combat-core, W2-A1), which records every hit so a tick's damage is assertable
  without a real component.
- `tests/unit/test_player_spawner.gd` — one case, written and run red first, that
  a spawned player carries the tag.
- `tests/helpers/status_effects_stub.gd` — doc comment only: the real component
  now exists, so the stub is no longer "the component, which does not exist yet"
  but the effect tests' recorder.

**Accept.** `-gtest=res://tests/unit/test_status_effects.gd` exit 0, **26/26,
192 asserts** (`g20/test-status-effects.log`). Full suite **47 scripts / 768
tests / 768 passing / 56 069 asserts, exit 0** (`g20/suite.log`, up from 46 / 741
/ 741 / 55 875 at `8948af4`), the delta being exactly this file's 26/192 plus the
spawner case's 1 test and 2 asserts. `--headless --path . --import` exit 0 with
zero error and zero `Parse Error` lines (`g20/import.log`). The three touched
files re-run in one loop with the pre-existing counts unchanged —
`test_effect_helpers` 22/57 (the effect-family call site still applies a status
through the stub after the retype), `test_status_effects` 26/192,
`test_player_spawner` 17/55 (`g20/touched-*.log`). `tools/smoke_two.sh` **exit 0,
every check `ok`**, because the spawner tag is spawner wiring and spawner wiring
is sync (BRIEF C17): two real peers still spawn, move, cross the wire, run the
step-3 enemy path and agree on both floor hashes (`g20/smoke-two.log`, raw pair
logs in `g20/smoke/`). Red first: the component's file was authored before the
class existed and the red is "Parse Error: Could not find base class
\"StatusEffects\"" (`g20/red-test-status-effects.log`), and the tag case was
authored before the tag was applied and the red is 16/17 with the one failure
being "a spawned player joins player" (`g20/red-test-player-tag.log`).

**Judgment calls (HANDOFF decision 50).** (1) The player gate reads a **group**,
not a class: `PLAYER_TAG` = `&"player"` and `is_player()` is
`entity().is_in_group(PLAYER_TAG)`, which is what "guarded on the entity's tag
rather than a hard-coded class" means in this engine, and an untagged entity is
treated as an enemy — the permissive default, so an enemy double or a bare
fixture behaves as the spec's table says. The tag is applied by
`PlayerSpawner`, the module that *composes* a player, so the player scene and
`player.gd` stay the other lane's. (2) Stacking is **one uniform rule** — stacks
add to the cap, the duration is refreshed, never accumulated — which is the
spec's own wording for BURN ("refresh duration, stacks add DPS") read across
every row; the rows' individual behaviour (CHILL→FREEZE, MARK's consumption,
SHOCK's chaining, TOXIN's healing penalty, UNRAVEL's taken-damage rule) is G21
and G22 — **both landed on 2026-10-20, see their sections below; every row of the
table now has its behaviour, and this file pins the core they extend**. (3) A tick
is handed to
`Health` as a **finished `HitData`**, through `apply_damage()` and never by
writing HP, which is SPEC-combat-core's one entry point; it deliberately bypasses
`Hurtbox`, because damage over time is not a connecting attack — it takes no
i-frames, rolls no crit and wakes no on-hit proc. (4) The tick's damage is a
fraction of the entity's **`StatBlock` max HP** (BURN 4 % per stack per second,
TOXIN 1.5 %, BLEED 2 %), read from the StatBlock rather than from `Health`, so
the fraction stays correct when a modifier moves max HP and a status tick needs
no component but this one. (5) The client half is the seam, not a `StateSync`
property: `_resolves_statuses()` returns `multiplayer.is_server()` and gates both
`apply_status()` and the tick, so a client applies nothing and deals nothing
while still *tracking* the stacks it is told about; the replicated-stacks
property itself is the HUD's work (W4-B10, G51). (6) `Events.status_applied`'s
`status` parameter stays a plain `int` — the enum now exists, so A4 would allow
the retype, but no Week 4 goal needs it and it would touch the bus and the
emitter tests for no gain; it is left for whoever first needs a typed bus read.

**Not claimed.** The component is **not on the player scene yet** — the
`StatusEffects` node there is a bare `Node`, and wiring it (plus the stacks
property on `StateSync`) is **blocked on Dev A (W2-A1, player.tscn)**; nothing in
a running build carries a status today, and no enemy scene carries the component
either, because enemy composition is Dev A's. The `Health` a tick hands its
`HitData` to is `StatusHealthStub`, not the real component — **blocked on Dev A
(W2-A1, combat-core `Health`)** — and the swap-in is a type rename, since
SPEC-combat-core's `HitInfo` and the week-2 `HitData` already agree on the
damage-relevant field names. CHILL's slow, FREEZE's immobility, SHOCK's chain,
TOXIN's healing penalty, MARK's consumption and UNRAVEL's taken-damage bonus were
**not** implemented at this goal's commit: G20 shipped the core and its tables,
and G21/G22 add the rows' own behaviour on top. **CHILL, FREEZE and MARK landed
in G21 on 2026-10-20** — the `#### G21` section immediately below — **and SHOCK,
TOXIN, BLEED and UNRAVEL landed in G22 the same day** (the `#### G22` section
below it), so all eight rows of the table are implemented together with the core. The week-12 balance pass
(SPEC-stats-status, "Open questions") owns CHILL, SHOCK, BLEED and UNRAVEL's
durations and TOXIN's and BLEED's rates; they are starting values here, named so
the pass has one place to edit. No status is yet applied by any content — no
relic, weapon or hazard calls `Effect.apply_status()` in a build.

---

#### G21 — BURN, CHILL → FREEZE, and MARK (2026-10-20)

The second goal of W4-B4, and the four rows of SPEC-stats-status's status table
the Week 4 relics actually drive: "Ember Boots burns, Storm Sandals shocks,
Frostwalkers chills", and Assassin's Mark in week 8. G20 shipped the component
core and the tables every row is looked up in; this goal gives these four rows
the behaviour their own line of that table specifies, including the two clauses
that are easiest to get subtly wrong — Chill's conversion at five stacks and
Freeze's one-shot double.

**What changed.** One production file and one test file, and nothing else:

- `scripts/components/status_effects.gd` (+153) — the deliverable.
- `tests/unit/test_status_effects.gd` (+175 / −2) — 14 new cases (26 → 40),
  written and run red first. The two removed lines are the fixture's `block.base`
  literal (MAX_HP only), which now also sets `BASE_MOVE_SPEED` and
  `BASE_ATTACK_SPEED` because a zero base reads 0 with or without a penalty and
  these rows are stated as reads "through `StatBlock` values", plus the file's
  missing trailing newline. No assertion was deleted, weakened or `pending`-ed.

**BURN** — the core's tick, now pinned by cases of its own rather than the one
proportionality case G20 wrote. `damage_per_second(BURN, 1)` is 4 % of the
`StatBlock` max HP and five stacks are five times that; the stacks stop at
`BURN_MAX_STACKS` (5); a re-apply **refreshes** the 4 s clock rather than adding
a second one; and the status expires on 4 s of **scaled** time, which is G20's
`_physics_process` multiplying its delta by `TimeManager.scale_for(entity())`.

**CHILL** — the spec's "-12% move and attack speed per stack" as `StatBlock`
**percent** modifiers on `MOVE_SPEED` and `ATTACK_SPEED`, `CHILL_SLOW_PER_STACK`
= 0.12, under the new per-status source `CHILL_SOURCE` (`status:chill`).
`_sync_speed_modifiers()` removes the source and re-adds it on every stack
change, so four stacks read `base * (1 - 0.48)` rather than four stacked copies
of the penalty, and a clear lifts it; `base` is never written. The fifth stack is
**never held as Chill**: `apply_status()` routes it to `_freeze_from_chill()`,
which clears the Chill and its slow first and applies FREEZE at one stack for
`FREEZE_DURATION`, announced like any other application. A **player** caps at
five Chill and never converts, because the same table's last line forbids FREEZE
to players — the gate is re-used from G20's `PLAYER_FORBIDDEN`, not
re-implemented.

**FREEZE** — move speed pinned to 0 by `FREEZE_IMMOBILE_PERCENT` (-1.0) under
`FREEZE_SOURCE` ("can't act" is the separate read `can_act()`, false only while
frozen, because `StatBlock` clamps attack speed at 0.2 and a zero there would be
unreachable and wrong); a one-shot double armed when the freeze lands and spent
by `consume_freeze_double()`, which also clears all Chill — the row's last
clause, and the only reason that clause is reachable at all is that an entity can
be chilled *again* while frozen. `_release_modifiers()` drops the freeze's
modifier and an unspent double however the status leaves — expiry, `clear`,
`clear_all` or a conversion. Permafrost's "always" is documented here as the
attacker-side `status_mult` term G23 owns, not a second flag in this component.

**MARK** — a single stack, re-application neither stacks nor re-arms, read by
`mark_forces_crit()` and spent by `consume_mark()`, so G23's `Damage.compute`
can force the crit without this component computing damage.

**Accept.** `-gtest=res://tests/unit/test_status_effects.gd` exit 0, **40/40,
249 asserts** (`g21/test-status.log`, up from 26/192 at `1216c11`). Full suite
**47 scripts / 782 tests / 782 passing / 56 126 asserts, exit 0**
(`g21/gut-full.log`, up from 47 / 768 / 768 / 56 069 — the delta is exactly this
file's 14 tests and 57 asserts). `--headless --path . --import` exit 0 with zero
error lines (`g21/import.log`). `GODOT=… OUT=… PORT=28921 bash tools/smoke_two.sh`
exit 0 with **35 `ok` / 0 FAIL** (`g21/smoke-run.log`, raw pair logs in
`g21/smoke/`) — run as insurance, though the commit adds no RPC, replication or
spawner wiring. `--headless --path . -- --host --debug-tools --smoke=6` exit 0
with zero error lines (`g21/host-smoke.log`), and `grep -rn "Engine.time_scale"
scripts/ scenes/` finds only the doc comment that forbids it.

Red first: the 14 cases were written before the constants existed and the run is
"Could not find member `CHILL_SLOW_PER_STACK` in base `StatusEffects`"
(`g21/red-test-status.log`). Two failing paths were then forced, kept, reverted
and the suite re-greened:

- The Chill-to-Freeze branch replaced by `if false:` → **exactly** the two
  conversion cases fail
  (`test_the_fifth_chill_converts_the_entity_to_freeze_instead` and
  `test_five_chill_applied_at_once_converts_the_same_way`; 38/40,
  `g21/negative-control.log`), and no slow, burn, freeze or mark case moves.
- The Chill percent zeroed → **exactly** the two slow cases fail
  (`test_chill_slows_move_and_attack_speed_by_twelve_percent_per_stack` and
  `test_chill_slow_follows_the_stack_count_and_lifts_with_the_status`; 38/40,
  245/249 asserts, `g21/negative-control-2.log`), with the freeze's own -100 %
  untouched by that change.

**Judgment calls (HANDOFF decision 51).** (1) The conversion **clears** the Chill
rather than keeping five hidden stacks, because the row reads "At 5 converts to
`FREEZE`" and the FREEZE row's "then clears all Chill" is only meaningful if
Chill can exist beside a freeze — which it can, and does, when an entity is
chilled again while frozen. (2) A **player is exempt from the conversion**, since
the same table forbids FREEZE to players and leaving it ungated would have made
`apply_status()` the one place that contradiction was reachable. (3) The freeze
double is a **flag on this component**, spent through `consume_freeze_double()`,
not a `Damage` behaviour: this goal owns the rule and G23 owns the formula that
reads it. (4) "Cannot act" is the `can_act()` read rather than a zero attack
speed, because `StatBlock` clamps ATTACK_SPEED at 0.2, so a zero there is
unreachable and would have been the wrong instrument. (5) Each status's penalty
lives under its **own modifier source** (`status:chill`, `status:freeze`), so
`remove_source()` releases exactly one status's modifiers — which is what makes a
conversion, an expiry, a consumption and a `clear_all()` the same code path
rather than four. (6) The fixture's `StatBlock` gained MOVE_SPEED and
ATTACK_SPEED bases, for the reason given under "What changed".

**Not claimed.** Nothing calls any of this yet: no relic, weapon, hazard or enemy
applies a status in a running build (the 20 relics are W4-B6), and the component
is still not composed onto the player scene — **blocked on Dev A (W2-A1,
player.tscn)** — so these rows are proven by the component's own tests and not by
a live run. SHOCK's chain, TOXIN's healing penalty and per-stack tick, BLEED's
move-gated tick and UNRAVEL's taken-damage bonus are **still not implemented**;
they are G22, on this same file. G23 (`Damage.compute`'s `status_mult` terms,
MARK's forced crit, `status_resistance`) and G24-G26 (the six combos, the two
multiplier hooks, `Scaling`) are unlanded too, so `mark_forces_crit()` and
`consume_freeze_double()` have no production caller yet and "next hit double
damage" is armed and spendable but read by nothing.

---

#### G22 — SHOCK, TOXIN, BLEED, and UNRAVEL (2026-10-20)

The second half of W4-B4's status table, and the four rows the Week 4 relics in
W4-B6 drive from the other side: Storm Sandals shocks, the three toxin relics
apply TOXIN, the bleed relics open a wound, and UNRAVEL is the enemy-side row
`Damage.compute` has to read. Together with G21 this closes the eight rows of
SPEC-stats-status's table; G23 keeps the formula terms and the golden table.

**What changed.** Four existing files and two new test doubles, and nothing else:

- `scripts/components/status_effects.gd` (+228 / −11) — the deliverable.
- `scripts/components/damage.gd` (+16 / −4) — one optional parameter and the
  UNRAVEL term it feeds.
- `tests/unit/test_status_effects.gd` (+282 / −1) — **14 new cases** (40 → 54),
  written and run red first. The one removed line is the file's **missing trailing
  newline** — the last `assert_true(_status.consume_mark(), …)` line, re-added
  with one — the same tidy-up G21 recorded. No assertion was deleted, weakened or
  `pending`-ed; the BLEED case was **edited**, not shortened (it measures its
  moving window at the 10-stack cap it had just proved, rather than the 5-stack
  figure it was written with).
- `tests/helpers/relic_marker_effect.gd` (18, new) — a no-op `Effect` whose only
  job is to exist under an id, so a test can hold Lightning Rod or Plague
  Doctor's Mask **before W4-B6's `.tres` files exist**. The relics stay data:
  `has_relic()` reads an id off an `EffectHost`, and the marker is what the test
  attaches to it.
- `tests/helpers/status_enemy_stub.gd` (44, new) — a `CharacterBody2D` in the
  `enemy` group with a `Health` double, so the chain has something to find,
  measure and damage.
- `tests/helpers/status_health_stub.gd` (+28) — the `heal()` entry point that
  routes through `healing_multiplier()`.

**SHOCK.** The row is "on apply chains 30 % of trigger damage to up to 2 enemies
within 96 px; Lightning Rod +2 chains", so the application needs the hit that
caused it: `apply_status()` gained a trailing optional
`trigger_damage: int = 0`, and a SHOCK application calls `_chain_shock(source,
trigger_damage)`. An application carrying none — a bare `apply_status(SHOCK, 1)`
— lands the status and chains **nothing**, because `chain_damage()` returns 0 and
`_chain_shock()` returns before it looks for targets. `chain_targets()` reads the
`ENEMY_TAG` group, keeps the `Node2D`s within `SHOCK_CHAIN_RADIUS` that are not
the entity itself, sorts them nearest-first by squared distance and truncates to
`chain_count()`, which is `SHOCK_CHAIN_TARGETS` (2) **plus**
`LIGHTNING_ROD_CHAIN_BONUS` (2) when Lightning Rod is held — the relic adds to
the count rather than replacing it, so a build without the relic chains exactly
what the table says. The hit each chained enemy receives is the tick's shape (the
status's element, the `status` tag, the status's name) plus `CHAIN_TAG`, so a
listener or the W4-B11 overlay can tell a shock that travelled from a burn that
did not; there is no proc depth and no crit, because a chain is a status result
and not a link of effects. Re-applying SHOCK **refreshes** — G20's refresh path,
which sets `remaining` back to the 4 s duration — and each application chains
once: the row's chain is per application, so a second shock does not stack the
first one's chain nor chain twice for one hit.

**TOXIN.** Unlimited stacks, six seconds each and 1.5 % max HP/s/stack all fall
out of G20's core: `UNLIMITED_STACKS` was already `-1` for this row and the tick
was already proportional. New here is the healing penalty, exposed as
`healing_multiplier()` — `TOXIN_HEALING_MULTIPLIER` (0.5) while TOXIN is held,
1.0 otherwise — and applied **where the healing lands**, on the heal path, so a
caller cannot forget it and the test asserts the HP that arrived rather than the
number on the component. "Plague Doctor's Mask disables expiry" is read off the
`EffectHost` governing the application: when TOXIN's clock runs out and
`has_relic(PLAGUE_DOCTORS_MASK_ID, entry["source"])` is true, `_tick` **re-arms**
the window instead of expiring, so the status persists, its stacks keep their
meaning and the HUD's duration bar stays sane; drop the mask and the re-armed
window runs out naturally. That is why `_entry()` now records `source` — the same
effect that applied the status is the one a later tick asks.

**BLEED.** Two clauses, both already carrying their numbers from G20: it stacks
to `BLEED_MAX_STACKS` (10) and does not stack past it, and it ticks only while
the target is moving — `is_moving()` gates the `_tick`, so 60 physics frames
standing still deal exactly 0 damage and the same 60 frames moving deal
`2 % × stacks` of max HP. At the cap on a 100 HP entity that is 20 damage a
second, which is what the case asserts; the read `damage_per_second(BLEED, 10)`
is asserted on its own so the arithmetic and the delivered tick are two claims.

**UNRAVEL.** Stacks to 5 and reads `1.0 + 0.10 × stacks` through
`damage_taken_multiplier()`. `Damage.compute` gained the trailing optional
`target_statuses: StatusEffects = null` and folds that read into the formula's
`status_mult` term — the parameter is optional so every week-2 caller and the
golden table keep their exact behaviour, and so G23 can add Kindling's BURN term
and Permafrost's FREEZE term beside it without a second signature change. This
goal landed **only** the UNRAVEL term: the doc header now says which of the three
terms are G23's, so the split is written down rather than inferred.

**Relic lookup.** `has_relic(id, source)` consults both `EffectHost`s that
govern an entity's statuses — the applier's first, the entity's own second — so
lightning that a player applies to an enemy reads the **player's** Lightning Rod
and a status an entity applies to itself reads that entity's own host, without
either reading being hard-coded. The relic is never a number in this file; it is
an id asked of a host, which is what keeps it an attachment instead of a code
path. Both halves are covered by cases of their own: the applier's by
`test_lightning_rod_adds_two_chains_read_off_the_effect_host`, and the **target's
own** — the criterion's own wording, "read from the target's effect host" — by
`test_the_targets_own_effect_host_is_read_for_the_lightning_rod`, which applies
the shock with **no applier at all** (`source` null, so the entity's own host is
the only place the rod can be found) and still expects four chained enemies.

**Accept.** `-gtest=res://tests/unit/test_status_effects.gd` exit 0, **54/54,
314 asserts** (`g22/test-status.log`, up from 40/249 at `247839f`). Full suite
**47 scripts / 796 tests / 796 passing / 56 191 asserts, exit 0**
(`g22/full-suite.log`, up from 47 / 782 / 782 / 56 126 — the delta is exactly
this file's 14 tests and 65 asserts). `--headless --path . --import` exit 0 with
zero error lines (`g22/import.log`). `test_damage.gd` re-run beside it at 15/15,
45 asserts. The two-instance smoke test was **not** run: this commit adds no RPC,
no replication and no spawner wiring, which is the condition SPEC-project's rule
and the LESSONS evidence bound both state. A single-process
`--headless --path . -- --host --debug-tools --smoke=6` boot was run instead —
exit 0, zero error lines, one player spawned and moved (`g22/host-boot.log`) — to
confirm the game still launches; it is not the two-instance test and is not
offered as one.

Red first: the cases were written before the constants existed and the run names
exactly what was missing — the six new constants, `apply_status()` "expected at
most 3 but received 4" and `compute()` "expected at most 4 but received 5"
(`g22/red-test-status.log`). Thirteen of the fourteen cases were in that red run;
the fourteenth — the target's-own-host reading, added once the implementation was
in — had its failing path observed in the forced negative control below rather
than in the red log, so it is not an assertion whose failure was never seen. One
failing path was then forced, kept, reverted and the suite re-greened:
`SHOCK_CHAIN_DAMAGE_FRACTION` zeroed → **exactly** the five cases that assert the
chain's damage fail (49/54, 300/314 asserts, `g22/negative-control.log`), no
toxin, bleed or unravel case moves. The revert is byte-exact — `sha1sum`
`e31884b3…` before and after (`g22/negative-control-before.sha1`,
`g22/negative-control-after.sha1`), and that is the same hash the 54/54 run above
was made against.

**Judgment calls (HANDOFF decision 52).** (1) The trigger damage arrives as a
**trailing optional parameter** on `apply_status()`, so the signature the spec
fixes (`apply_status(status, stacks, source: Node)`) is unchanged for every caller
that does not need it, and a relic that applies a shock passes the hit's damage
while one that applies a burn ignores it. (2) `has_relic()` reads **both** the
applier's and the entity's own `EffectHost`, because a relic can govern an
application from either side and neither reading is more "correct" than the
other; the applier's is consulted first. (3) A mask-holding entity's TOXIN
**re-arms its clock** rather than pinning a sentinel duration, so the status
persists through the same expiry path every other status uses and the duration
bar can still be read. (4) `Damage.compute` gains `target_statuses` as an
optional fifth argument, rather than G22 reaching into `Damage` for the whole
`status_mult` term or G23 being forced to re-open the signature. (5) The heal
path this penalty is asserted through lives on the **`StatusHealthStub`** double,
**blocked on Dev A (W2-A1, combat-core `Health`)**: SPEC-combat-core fixes
`apply_damage(hit: HitInfo)` and the real `Health.heal()` is
host-authoritative, so the double is the swap-in and the type rename is the
migration. (6) `ENEMY_TAG`'s real registrant is **blocked on Dev A (W4-A1,
enemies-ai)** — `scripts/generation/` is still empty and no enemy scene exists —
so the group is whatever the world or a test double puts in it, and the swap-in
is Dev A's `add_to_group` line. (7) A chain target that carries no `Health` is a
**silent skip**, not a warning: a chain lands on whatever the group put in range,
and the missing component is W2-A1's gap to report, not this one's.

**Not claimed.** Nothing calls any of this yet: no relic, weapon, hazard or enemy
applies a status in a running build (the 20 relics are W4-B6), and the component
is still not composed onto the player scene — **blocked on Dev A (W2-A1,
player.tscn)** — so all four rows are proven by the component's own tests and not
by a live run. The chain looks for enemies in a group the real enemy base does not
yet join, so in a running build it would find nobody. G23 (`Damage.compute`'s
remaining `status_mult` terms, MARK's forced crit, `status_resistance`) and G24–G26
(the six combos, the two multiplier hooks, `Scaling`) are unlanded, so
`healing_multiplier()` and `damage_taken_multiplier()` have one production reader
between them and no producer of a status at all.

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

39. **`Effect`'s stat block is resolved from the player by name and cast-checked,
    its modifiers are removed by handle, and its `_on_detach` runs last
    (2026-10-20).** W4-B2's `Effect` base is the class every content item changes
    the game through, and `detach()` is its whole point. Sanctioned by
    `SPEC-effect-system.md` "Effect base class" (which declares `player`,
    `source`, `stacks`, `_handles: Array[int]`, `_timers: Array[Timer]`,
    `attach`, `detach`, `_on_attach`, `_on_detach`) and its "Proc chain limits"
    rule 2, which reuses the effect's id as the self-retrigger tag. `Effect` is a
    new script, so no existing signature changed and nothing on the Ask-first
    list was touched; the decision is recorded for the additions and the two
    choices a reader would otherwise have to reverse-engineer.

    - **The `StatBlock` comes from `player.get_node_or_null(^"StatBlock")`,
      cast-checked, with a settable `stat_block` override.** The player scene's
      component nodes (`StatBlock`, `Health`, `Hurtbox`, `StatusEffects`) are
      still bare `Node`s — `player.gd:159` carries the `TODO(stats-status)` that
      retypes them — so writing the component into `player.tscn` would be a
      cross-lane scene edit this goal does not need, and reading it untyped would
      crash every relic the moment one attached. A player with no component gets
      one warning per dropped modifier and an inert effect. The tests supply the
      component on the node, the same shape `test_hud_model.gd` uses for Dev A's
      missing `Health`; when stats-status retypes the node the swap is mechanical
      and the tests keep passing.
    - **Modifiers are removed by handle, never by `remove_source()`.** Two
      effects on one player must not be able to take each other's modifiers down,
      even if they were built from the same content id (Mimic Crown's copy carries
      a suffixed id — landed at G19b, 2026-10-20 — but a bug elsewhere should not
      be able to make one relic's teardown erase another's buff). `modify()` records the handle
      `add_modifier` returns; `detach()` removes exactly those.
    - **`_on_detach()` runs after the base cleanup** (handles, timers,
      connections), so a subclass tears its own state down against a state that
      already holds nothing. The alternative order would let a subclass see
      handles it is about to lose, at the cost of a base cleanup that never runs
      if `_on_detach()` errors; the doc comment states the order and the one
      thing a subclass can still get wrong (registering something inside
      `_on_detach`).
    - **Timers are `queue_free()`d, not freed outright**, so a `detach()` from
      inside a signal handler is safe; they leave the tree at the end of the
      frame, which is what the cleanup test awaits. `_start_timer()` is plain
      engine time and is documented as such — `every_seconds()` (G13) is the
      `TimeManager`-scaled loop, and the split is deliberate.
    - **New public surface beyond the declared signatures** (additions only,
      nothing renamed or removed): `stat_block`, `is_attached()`, `source_id()`,
      `_start_timer()`, `_resolve_stat_block()`, `_release_handles()`,
      `_free_timers()`, `_disconnect_all()`, `_connections`, `_attached`,
      `STAT_BLOCK_NODE`.

40. **`listen` filters by the `Player` argument the signal declares, and
    `once_per_room` resets on any player's room entry (2026-10-20).** W4-B2's
    `listen`/`once_per_room` are the helpers all 20 Week 4 relics will be
    written against once W4-B6 lands; none of them exists yet at this commit
    (`data/relics/` holds only `.gdkeep`). Sanctioned by `SPEC-effect-system.md` "Effect base class"
    (`listen … auto-disconnect on detach, filters to this player where the
    signal has one`; `once_per_room(key) # returns true the first time per
    room`) and its unit-test line (`listen` filters by player; `once_per_room`
    resets on `room_entered`). `Effect` is a script this run created, so no
    existing signature changed and nothing on the Ask-first list was touched;
    the decision is recorded for the additions and the three choices a reader
    would otherwise have to reverse-engineer.

    - **The filter is driven by the signal's declaration, not by sniffing a
      call.** `_signal_arguments()` reads the `Events` autoload's own
      `get_script_signal_list()` and `_player_argument_index()` takes the first
      argument declared `Player`, so `player_dodged(player, perfect)` filters on
      index 0 and `room_entered(room, player)` on index 1, and every emit of the
      same signal is treated the same way. Reading the values instead would make
      the filter depend on whether a given emit carried a player, which is how a
      null-argument event slips past a filter meant to stop it. A signal the bus
      does not declare is connected unfiltered, which is the safe direction for a
      signal nobody has classified yet.
    - **One forwarder per signal arity.** `Callable.bind()` appends its
      arguments after the signal's, so the bound `(player_argument_index,
      callable)` pair always lands last and a single method cannot receive a
      variable number of event arguments ahead of it. `DISPATCH_METHODS` holds
      `_dispatch0` … `_dispatch4` (the widest bus signal, `status_applied`,
      carries four). A hypothetical wider signal is connected unfiltered with a
      warning rather than silently dropped — a new bus signal must be handled,
      not ignored.
    - **`once_per_room`'s reset is subscribed directly, never through
      `listen()`.** `room_entered` fires once per player who walks in, so the
      player filter would make a teammate's entry miss the reset and leave a
      class passive spent from the previous room; the spec's own wording is
      "resets on `room_entered`", with no qualifier. The cost, stated plainly: a
      teammate entering first resets this effect's budget slightly early. Keys
      are cleared by `attach()` and `detach()` as well, so no cycle inherits
      another's budget.
    - **New surface beyond the declared signatures** (additions only, nothing
      renamed or removed): `once_per_room()`'s backing `_room_keys`,
      `DISPATCH_METHODS`/`PLAYER_CLASS`/`NO_PLAYER_ARGUMENT`,
      `_connect_tracked()`, `_on_room_entered()`, `_signal_arguments()`,
      `_player_argument_index()`, `_forward()` and `_dispatch0`–`_dispatch4`.
      Every connect in the class now goes through `_connect_tracked()` so no
      subscription can escape `detach()`.

41. **`deal_damage` stamps and delivers but never emits, `chance` owns its own
    seeded generator, and `proc_depth` lands on `HitData` a goal early
    (2026-10-20).** W4-B2's four data helpers (`modify`, `chance`,
    `apply_status`, `deal_damage`) are the whole surface a relic's effect script
    changes the game through. Sanctioned by `SPEC-effect-system.md` "Effect base
    class" (the helper block: `deal_damage … increments proc depth, tags
    "proc"`; `chance(p) # host RNG, Luck-aware for loot-type procs via
    chance_lucky()`; `apply_status(target, status, stacks)`) and "Proc chain
    limits" (`proc_depth = trigger.proc_depth + 1`). `Effect` is a script this
    run created and `HitData` is Dev B's own stats-status component, so no
    existing signature changed and nothing on the Ask-first list was touched;
    the decision is recorded for the choices a reader would otherwise have to
    reverse-engineer.

    - **`deal_damage` does not emit `hit_landed`.** It stamps the hit and hands
      it to the target's `Hurtbox`, which owns that signal — `SPEC-effect-system`
      "Events bus" says the emitters are the owning modules and names combat for
      `hit_landed`, and `SPEC-combat-core` names `Hurtbox.receive` as the place
      it is emitted. An effect emitting a combat event would make two emitters
      for one signal and would let a chain recurse without a hurtbox in it. The
      consequence, stated plainly: the proc chain only continues through a real
      hurtbox, which is Dev A's (W2-A2) and does not exist yet.
    - **`chance` short-circuits at both extremes without drawing.** A guaranteed
      or impossible proc must not consume a value from the run's generator: the
      draw is shared state, and one effect's certainty silently shifting every
      other effect's rolls is the kind of desync a seed cannot replay. The
      spec's signature says only "host RNG"; this is the reading that keeps one
      seed replaying one run.
    - **The generator is `Effect.rng`, owned per effect and injected by
      `EffectHost` when it lands (landed as G14 on 2026-10-20: the host now
      creates one generator per player and hands the same object to every
      effect it adds; the per-effect fallback stays for effects attached
      outside a host).** The plan's sub-task named `_rng` on
      `EffectHost` (G14), which did not exist at G12, so the generator lived on the
      effect with a documented injection seam rather than the goal inventing an
      `EffectHost` API ahead of the goal that owns it. An effect with no host
      seeds itself from `GameState.run.seed`, or the fixed `DEFAULT_RNG_SEED`
      when no run is live — never clock entropy, because a clock-seeded draw is
      un-reproducible and this is the helper the relic harness asserts against.
    - **`HitData.proc_depth` lands here, one goal before the gate that reads
      it.** W4-B3's G16 owns the depth rule, but G12's own success criterion is
      that `deal_damage` increments `hit.proc_depth`, which needs the field to
      exist. It is additive with a zero default and the existing damage suite is
      unchanged. `Effect.trigger_depth` is the second half of the same seam: it
      is the field G16's dispatch wrapper will set, and until then it stays 0.
    - **New surface beyond the declared signatures** (additions only, nothing
      renamed or removed): `Effect.rng`, `Effect.trigger_depth`,
      `Effect.DEFAULT_RNG_SEED`, `STATUS_NODE`/`HURTBOX_NODE`/
      `DAMAGE_SINK_METHOD`/`STATUS_METHOD`/`PROC_TAG`, `_status_component()`,
      `_resolve_rng()`, `_host_seed()`, and `HitData.proc_depth`. The two new
      `tests/helpers/` doubles are test-only.

42. **`every_seconds` loops on `TimeManager`'s scaled timer, in the player's own
    time group, and `detach()` disarms the pending tick (2026-10-20).** W4-B2's
    periodic helper will be the clock every "every N seconds" relic is written
    against once those relics land (Clockwork Heart is the named case; none of
    them exists yet at this commit). Sanctioned by
    `SPEC-effect-system.md` "Effect base class" — `func every_seconds(interval:
    float, callable: Callable) -> void # uses TimeManager.timer loop, PLAYER
    group so time stops don't pause it` — read together with
    `SPEC-time-manager.md` "Interfaces provided" (`func timer(node: Node,
    seconds: float) -> Signal # scaled timer, fires once`) and its rule that
    pure engine timers are forbidden for anything gameplay-relevant. `Effect` is
    a script this run created, and `TimeManager`'s public surface was **not**
    changed: the loop calls the spec's `timer()` and `set_group()` exactly as
    declared, so nothing on the Ask-first list was touched. The decision is
    recorded for the five choices a reader would otherwise have to
    reverse-engineer.

    - **One armed tick at a time; each tick re-arms itself.** `TimeManager.timer`
      is a one-shot signal, so a loop is a chain, not a repeating timer. The
      re-arm happens *after* the callable runs and only *if* the loop still
      exists, so a relic that spends its last tick tearing itself down (Second
      Wind, Panic Button) does not resurrect its own loop — re-arming first
      would leave a detached effect ticking until someone noticed.
    - **The player joins `TimeManager`'s PLAYER group at the point of use.** The
      spec's parenthetical ("PLAYER group so time stops don't pause it") is the
      behaviour, not a detail: an unregistered node also reads the default scale
      today, which would make the exemption an accident of `scale_for`'s
      fallback rather than a declared property — and `player-controller` does
      not register the player itself yet, so the loop has to. `set_group` is an
      idempotent assignment, so a player that already registered is unaffected.
      The measured consequence: with `stop_enemies` live the clock still ticks
      (the spec's negative control), while an override aimed at the player's own
      node — hit-stop — does pause it. That second case is the one a plain
      engine `Timer` would fail.
    - **`detach()` disconnects the pending tick instead of cancelling the
      manager's timer.** Stopping the loop is the effect's job and takes one
      disconnect: the armed tick is `TimeManager`'s own `RefCounted`, expires on
      its own, and after the disconnect holds no reference to the effect. No
      method was added to `TimeManager` for this, because the spec's `timer()`
      has no cancel and C9 says anything a spec does not require is left alone —
      so "stops the loop and frees the timer" is discharged as *no further
      callback, nothing holding the effect*. The residual, stated plainly: an
      armed one-shot still sits in the manager's list until its interval
      expires, and does nothing when it lands.
    - **No engine timer is opened for a loop.** `_start_timer()` (plain engine
      time, G10) stays what it is and is not used by `every_seconds`; the test
      asserts `_timers` stays empty, because a plain `Timer` would ignore every
      time effect — exactly the bug this goal exists to prevent.
    - **New surface beyond the declared signatures** (additions only, nothing
      renamed or removed): `_periodic`, `_next_periodic_id`, `_arm_periodic()`,
      `_on_periodic_timeout()`, `_stop_periodic()`. All private; the only public
      addition is the spec's own `every_seconds()`.
    - **What is *not* claimed.** The loop is host-only local logic with no
      replicated field and no RPC, so nothing here is asserted in two processes
      beyond the standing smoke (35 `ok` / 0 FAIL, re-run in this goal's commit
      even though no sync path changed). Nothing yet *attaches* a loop in the
      game: no relic content exists until W4-B5/B6, so what is proved is that
      the clock is correct when it does.

43. **`EffectHost` keys one effect per source id, refuses rather than
    reconciles, and hands out its own seeded generator (2026-10-20).** W4-B2's
    container node — the attach/lookup/tag path `relics`, `weapons`,
    `abilities` and `progression-trees` all go through. Sanctioned by
    `SPEC-effect-system.md` "Effect base class" (`EffectHost` … "holds attached
    effects, keyed by source id, and exposes `add(source, stacks)`,
    `remove(source)`, `get_effect(id)`, `list_tags() -> Dictionary` (tag ->
    count) for synergies") and "Tags and synergies" (`list_tags()` counts tags
    across attached relics). `EffectHost` is a script this run created; the
    only existing surface it touches is `Effect` (also this run's) and
    `ContentData`'s already-declared `tags`/`effect_script` fields, which are
    read, not changed — so nothing on the Ask-first list was touched. The
    decision is recorded for the four choices a reader would otherwise have to
    reverse-engineer.

    - **One effect per id; a duplicate is refused, not stacked.** The spec keys
      the host's dictionary by source id and gives `stacks` as `Effect`'s
      duplicate counter, so a second `add()` of the same id would be two
      `Effect` instances with one key — one of them unreachable and both adding
      modifiers. The pick flow raises `stacks` on the existing effect (or, for
      Mimic Crown, adds an id-suffixed copy, W4-B3 — landed at G19b,
      2026-10-20) instead. A refusal is a
      `push_warning` and a null return, not an error: a caller asking twice is
      a bug to surface, not a reason to take the host down.
    - **A source without a usable `effect_script` is refused, and a non-`Effect`
      script is freed rather than parented.** `ContentData.effect_script` is
      optional on the base type, so `add()` has to answer for null; and because
      `GDScript.new()` will happily build any script, the result is
      `is Effect`-checked before `add_child()`. The refused instance is freed so
      a bad data file cannot leak a node per attempt.
    - **The host owns one generator per player and injects the same object into
      every effect.** Decision 41 left `Effect.rng` as the injection seam and
      said the host would fill it. A per-effect fallback remains for effects
      attached outside a host (tests, tools), but in the game every effect on a
      player draws from the host's stream, seeded from `GameState.run.seed` or
      the fixed fallback — never clock entropy — so one seed replays one
      player's procs and a host can be rebuilt deterministically.
    - **`remove()` detaches before freeing, and returns whether it removed
      anything.** `queue_free()` alone would leave the effect's modifiers,
      timers and bus connections live until the end of the frame, which is a
      window in which a relic dropped at a Shrine still buffs its old owner;
      `detach()` runs first and `queue_free()` then takes the node out safely
      even when `remove()` is called from inside a signal handler. The boolean
      lets the pick/removal flow distinguish "removed" from "was not there"
      without reading a warning out of the log.
    - **New surface beyond the declared signatures** (additions only, nothing
      renamed or removed): `EffectHost.NODE_NAME`, `player`, `rng`,
      `has_effect()`, `effect_count()`, `effects()`, `_resolve_player()`,
      `_resolve_rng()`, `_host_seed()`. The player is installed by
      `tests/helpers/effect_host_player.gd` rather than in Dev A's
      `player.tscn`, which is the recorded swap-in (**blocked on Dev A (W2-A1,
      player.tscn)**).
    - **What is *not* claimed.** `add()` is a container operation: no
      `relic_picked`, no `RunPlayerState` write, no roll (G30 owns the pick
      flow). Nothing in the game calls it yet — there is no relic content until
      W4-B5/B6 — and there is no client path, because clients hold no `Effect`
      instances. *(As of this decision; the proc caps and Mimic Crown all landed
      under W4-B3 on 2026-10-20 — see G16, G18 and G19b below.)*

44. **The spawn seam is a handed-over reference on `EffectHost`, the client gate
    lives only there, and a spawned node carries the depth its trigger produced
    (2026-10-20, W4-B2 / G15).** `spawn` and `fire_projectile` had to reach the
    world's spawners without an effect naming a node path, and without adding a
    second place that decides whether this peer may spawn at all.
    - **The seam is `EffectSpawner` (a new `Node` under `scripts/effects/`),
      handed to `EffectHost.spawner` rather than looked up by path.** SPEC-project
      forbids cross-module tree-path reach-through, and SPEC-networking puts the
      spawners under `World/Entities`, which is not `effect-system`'s subtree. An
      exported `spawner_path` is resolved once on `_ready()` for a world that
      would rather wire a path; an explicitly assigned `spawner` always wins, so
      a test or a later world can hand one over. Nothing on the "Ask first" list
      changed: `EffectSpawner` is a new script, `EffectHost.spawner` /
      `spawner_path` / `spawn_proc()` / `fire_proc_projectile()` / `can_spawn()`
      are additions, and `Effect.host` / `spawn()` / `fire_projectile()` are
      additions to a class this lane owns. `world.tscn` is **not** edited (it is
      foundation, both lanes) — the seam's wiring is the Dev A W4-A4 swap-in.
    - **One client gate, on `EffectHost`.** The spawner classes in this repo each
      carry their own `_can_spawn()`, and copying that onto `EffectSpawner` as
      well was rejected: two checks in series means a spawner reached another way
      is silently *covered* rather than reported, and the criterion "refused on a
      client" then has two possible authors. `EffectHost.can_spawn()` is over
      `_can_spawn()` (default `multiplayer.is_server()`), so the client half is
      testable in one process by the same subclass override
      `test_entity_spawners.gd` uses.
    - **`proc_depth` on a spawned node is the trigger's depth + 1.** SPEC-
      effect-system, "Proc chain limits" — "`deal_damage`, `spawn`, and
      `fire_projectile` from an effect create results with `proc_depth =
      trigger.proc_depth + 1`" — and G16 restates the same rule for all three.
      `.goals/PLAN.md`'s G15 line phrases it as "the trigger depth"; it is read
      here as *the depth the trigger produced* (the trigger's own depth plus
      one), because the spec and G16 both say `+ 1` and because `deal_damage`
      already ships that rule and is asserted side by side with
      `fire_projectile` so they cannot drift. Reading it the other way would make
      G16 change this behaviour and break this goal's test.
    - **Provenance is stamped as a property where the scene declares one and as
      metadata otherwise.** The repo's spawners use `set()` on a name the scene is
      required to keep (`ProjectileSpawner`'s `synced_position`), but the nodes
      `spawn` produces are FX scenes whose ownership is `art-audio`'s, and a
      silent no-op `set()` would drop the one value the debug overlay (W4-B11)
      needs. `EffectSpawner.read_stamp(node, key)` is the single reader for both
      branches, so no consumer has to know which one a scene took.
    - **`setup` runs before `add_child()`, and it is host-local.** The criterion
      requires it, and it is the only way a caller can still shape a node before
      its `_ready()` could run; a `Callable` cannot be replicated, so anything
      that must reach clients travels in the seam's payload, not in `setup`.
    - **Absence is a warning, never an error.** The FX-with-gameplay spawner and
      combat-core's `Projectile` are unlanded (Dev A W4-A4), so with nothing
      wired the game drops spawns and logs; the suite stays engine-error free, and
      the swap-in is a wiring change, not a code change. Recorded as
      **blocked on Dev A (W4-A4)** in `scripts/effects/effect_spawner.gd` and
      `tasks/todo.md`.

45. **`Effect.listen` now routes a hit-carrying signal through its dispatch
    wrapper even when the signal declares no `Player`, and the wrapper both gates
    on the event's depth and publishes it as `trigger_depth` for the handler
    (2026-10-20, W4-B3 / G16).** SPEC-effect-system's "Proc chain limits", rule 1,
    is explicit about *where* the limit lives — "`Effect.listen` wrappers skip
    events with `proc_depth >= 3`" — so this goal was always going to change
    `listen()`'s behaviour on one signal: `hit_landed(hit: HitData)` declares no
    `Player` argument, and the pre-G16 `listen()` connected any signal without one
    **untouched**. That made the spec's gate unreachable on the busiest event in
    the game, which is the one event a proc chain actually runs through.
    - **The change is `Events`-signal routing plus wrapper behaviour, and it is
      sanctioned by the spec, not invented here.** The alternative — a second
      wrapper installed on `hit_landed` alone — was rejected because it would be a
      second place that knows the limit, and the goal's own sub-task says the gate
      is "not in each effect script". Asked about in this lane's own terms: no
      `Events` signal was added, renamed, retyped or given a new parameter; the
      autoload's public API is unchanged; nothing in `project.godot`, the Input
      Map, `scripts/data/`, the save schema, CI or `addons/` moved.
    - **`HIT_CLASSES` accepts `HitInfo` as well as `HitData`.** These are
      different things: `listen()` has to *recognise* a payload from the signal's
      declaration (a `StringName` class name read off `Events`'s script), while
      the signature `Events` declares is still `HitData` — combat-core's `HitInfo`
      does not exist yet (Dev A W2-A1). Listing both now means the swap-in is a
      type rename in `Events` and not a second place to remember the rule.
    - **The gate reads the event, never the effect's stored state.** An effect
      that is somehow carrying a stale `trigger_depth` at or past the limit must
      still react to a depth-0 event, so the check is on the event's own payload
      and `trigger_depth` is written and restored *around* the handler call. The
      restore also makes nested procs correct: a handler that synchronously causes
      another event sees its own depth, and the outer handler's depth is back in
      place when the inner one returns. `test_the_gate_reads_the_event_and_not_the_effects_own_state`
      is that negative control.
    - **`trigger_depth` is set rather than incremented, and that is the `+ 1`'s
      other half.** `deal_damage`/`spawn`/`fire_projectile` already shipped
      `trigger_depth + 1` (W4-B2, G12/G15), but nothing ever raised
      `trigger_depth` above its default, so every effect result was depth 1
      regardless of the chain it came from. The wrapper is the only writer
      because the event is the only thing that knows how deep a hit is.
    - **`Effect.MAX_PROC_DEPTH` is public and the test reads it instead of
      writing 3 twice.** The spec sentence that fixes the number is quoted in the
      const's doc comment and asserted verbatim against `specs/SPEC-effect-system.md`
      in the suite, so the constant and the spec cannot drift apart silently.
    - **A pre-existing test's contract was deliberately changed, and its intent
      was kept.** `test_effect_base.gd` had `test_listen_leaves_a_signal_without_a_player_argument_unfiltered`
      asserting `Events.enemy_killed.is_connected(effect._on_enemy_killed)` — the
      property *at the time* was "connected directly", but the property the test
      was protecting is "a non-`Player` argument must not gate the event", and
      that still holds (asserted, with a hit at the limit as the counter-case).
      The "connected directly" half was re-pinned on `room_cleared(room)` — a
      signal with no player **and** no hit, which is genuinely connected
      untouched. `LISTENERS_PER_EFFECT` went 4 → 5 because the tracking effect
      now also listens to that signal. No assertion was deleted or weakened; the
      file's other 24 cases are unchanged.
    - **What is *not* claimed.** Rule 2 (no self-retrigger, G17), rule 3 (64
      spawned nodes per frame, G18) and rule 4 (Mimic Crown's id suffix, G19a/G19b)
      were not implemented at this decision. *(They landed on 2026-10-20 — rules 2
      and 3 in this same wrapper, rule 4 in the same wrapper plus the copy it keys
      apart; see G17, G18 and G19b below.)* The cap on total chain length per event is this goal;
      a per-key cooldown, a spawn budget and a duplication rule are separate
      decisions and land in this same wrapper on their own goals' evidence.

46. **The no-self-retrigger rule matches the attached content id, in the shared
    dispatch wrapper, and the *producer* stamps the tag (2026-10-20, W4-B3 /
    G17).** SPEC-effect-system "Proc chain limits", rule 2: "An effect never
    reacts to a hit whose `tags` already contain its own id (no self-retrigger)."
    This is an `Events`-routing behaviour change on the busiest signal in the
    game, so it is recorded here even though no signal was added, renamed,
    retyped or given a parameter, and no other Ask-first item moved.
    - **The spec pins the reacting side, and that is the side that changed.**
      Rule 1's parenthetical says exactly what the wrapper does for the depth
      gate ("`Effect.listen` wrappers skip events with `proc_depth >= 3`"); rule 2
      names only the condition. `_is_own_hit()` therefore lives in the same
      `Effect._forward()` wrapper — one place that knows the proc rules, so no
      effect script can forget it and a new one cannot bypass it — and holds on
      every hit-carrying signal, not on `hit_landed` alone (asserted on all
      five).
    - **`deal_damage()` does not stamp `source_id()` on the hit it deals.**
      Stamping there was the obvious way to make the rule self-enforcing, and it
      was rejected on a concrete cost: G16's accepted acceptance evidence
      includes a *self-triggering* chain shape (one effect that reacts to its own
      hits until the depth gate stops it, `test_a_five_link_self_triggering_chain_stops_at_depth_three`),
      and stamping every `deal_damage` hit with the dealing effect's id makes
      that shape inexpressible — the probe would be suppressed on link one and
      the depth rule would lose the case that exercises it. It would also be
      wrong on the merits: a hit's `tags` are the caller's (the same payload is a
      weapon's, a status's and a hazard's), and `deal_damage` already owns the
      two fields that are its business (`proc_depth`, the `proc` tag). The two
      rules therefore compose rather than overlap — rule 2 catches the tagged
      self-reference, rule 1 is the backstop for a chain carrying no id — and
      `listen()`'s doc comment plus `deal_damage()`'s state the producer's half
      of the contract. W4-B6's relics will be the first content to exercise it
      once that batch lands (`data/relics/` holds only `.gdkeep` today).
    - **The check keys on `source_id()`, never on the class name.** Two effects
      built from one script (a Mimic Crown copy, two relics sharing an effect
      script) must be suppressed independently, each by its own id; the suite's
      per-id case uses two probes of the *same* class so the class name cannot
      be the discriminator, and a third case pins the id against the display
      name. An effect attached with no source reads `&""` and has no id to match,
      so it suppresses nothing rather than matching an empty tag.
    - **The mutual-reference case is asserted on a derived count, with a
      control.** Rule 2's real risk is a pair of effects that each tag their hits
      with the *other's* id: nothing suppresses the other's chain on its own, so
      the shape must converge. It converges at six reactions (each effect three
      times, at depths 0, 1 and 2, and never for the hit tagged with its own id)
      against fourteen for the same pair with nothing tagged — the control is
      what makes the six mean "the rule removed them" instead of "the fixture is
      small". The per-effect depth lists are asserted rather than the interleaved
      log order, so the count does not depend on which connection fired first;
      `ProcChainLog.depths_for_source()` exists for that.
    - **A G16 fixture's routing tag moved off the effect's own id, and this is
      the honest record of it.** `test_a_chain_of_five_effects_stops_at_the_depth_three_link`
      routed by tagging each link's hit with the *next link's id* — which rule 2
      now suppresses by construction, so the chain became un-routable and the
      case failed the moment the rule landed. The routing tag moved to a separate
      `hop_N` namespace so the two rules are asserted separately. Every assertion
      in that case is byte-for-byte unchanged (the named stop at `link_3`, the
      depths `[0, 1, 2]`, the dealt depths `[0, 1, 2, 3]`), no assertion was
      deleted or weakened, and a `LONG_LINK_BUDGET = 20` const was added so the
      new rule cases cannot run out of links and pass for the wrong reason.
      `ProcChainProbe.handler_calls` counts events the wrapper let through
      *before* the probe's own `react_tag` filter, so "the handler never ran" is
      observed rather than inferred.
    - **What is *not* claimed.** Rule 3 (the 64-spawn-per-frame cap, G18) and
      rule 4 (Mimic Crown's id suffix, G19a/G19b) were not implemented at this
      decision. *(Both landed on 2026-10-20: the cap at G18, the duplication rule
      at G19b, below.)* The chain still
      advances through `ProcHurtboxStub`, **blocked on Dev A (W2-A2)** for
      combat-core's real `Hurtbox`.

47. **The per-frame spawn cap is one shared per-player budget on `EffectHost`,
    refreshed lazily off the physics frame key (2026-10-20, W4-B3 / G18).**
    SPEC-effect-system "Proc chain limits", rule 3: "Per-frame cap: at most 64
    effect-spawned nodes per player per frame; the rest are dropped and counted
    in a debug stat." `EffectHost` gains `MAX_SPAWNS_PER_FRAME`, the
    `_spend_spawn_budget()` gate both spawn paths call, and the three public
    frame-keyed counters `spawns_this_frame`, `spawns_dropped` and
    `drop_reports`. This adds public API to a module's own class (not an
    autoload), so nothing on the Ask-first list moved; it is recorded here
    because the counter is the interface the debug overlay (W4-B11, G55) reads
    and because the budget's shape is a choice, not a spec number.
    - **The spec says "effect-spawned nodes", so `spawn_proc()` and
      `fire_proc_projectile()` spend one budget.** Two budgets would leave the
      cap half-bypassable by choosing the other helper, and there is no reading
      of "64 effect-spawned nodes per player per frame" under which a projectile
      is free. The case spends 60 on nodes and 4 on projectiles, then asserts the
      65th request of either kind is refused.
    - **The counters are computed from `Engine.get_physics_frames()`, not reset
      in a process callback.** The stored counts carry the frame they belong to
      and a getter returns 0 when that frame is not the current one, so "the
      counter resets on the next physics frame" is a property of the read rather
      than of a callback having run first. This is why `EffectHost` has no
      `_physics_process` at all: a host that is paused, out of the tree for a
      tick, or read before its own processing in a frame can neither spend nor
      observe last frame's budget. The budget is refreshed lazily in
      `_spend_spawn_budget()`.
    - **The first drop of a frame warns; the rest only count.** Rule 3 says the
      excess is "dropped and counted", and a build that caps out can drop
      hundreds per frame — 936 lines of log in one frame is not a debug stat. The
      announcement is a `push_warning` and never an error, because capping is a
      designed outcome for the pathological build the Week 4 checkpoint names,
      not a fault. `drop_reports` is the readable proof it happened once, and the
      run log is grepped for the same line in the evidence.
    - **The cap is checked after the client gate and the seam check.** A request
      refused because this peer is not the host, or because no spawner is wired
      (Dev A's W4-A4), is not a capped-drop and must not inflate
      `spawns_dropped` — otherwise the debug stat would report cap pressure that
      the cap did not cause.

48. **The trigger-test harness is test-only, takes the bus's own `Signal`, and
    reports refusals as warnings rather than failures (2026-10-20, W4-B3 /
    G19a).** SPEC-effect-system "Interfaces provided" specifies
    `tests/helpers/effect_harness.gd`: "creates a headless player with
    `EffectHost`, attaches an effect, fires any `Events` signal with fake
    arguments, asserts spawns, stat changes, statuses, and damage via a
    `SpyWorld`." Every file this goal added lives under `tests/`, so nothing on
    the project's Ask-first list moved and the game is untouched; it is recorded
    here because the instrument's shape is a choice every content module inherits
    (G32 onward, and weeks 8, 11 and 12 after them).
    - **`fire()` takes the bus's own `Signal` object, not a `StringName`.** The
      caller writes `_harness.fire(Events.player_dodged, [_player, false])`, so
      a signal that does not exist is a compile-time error and not a test that
      silently fires nothing; the harness still reads the name back off the
      object and checks it against `Events`' own script, so an argument count
      that does not match the declaration is refused at run time too.
    - **A refusal is a `push_warning` returning `false`/`null`, never a GUT
      failure.** `fire()` and `attach()` are the harness's own plumbing; if a
      case misuses them, the case's own `assert_*` reports the consequence in the
      case's own words, which is more useful than an assertion failure raised
      from inside the fixture. The guard is itself asserted (unknown signal,
      one argument, three arguments), so the warning path is not dead code.
    - **Every assertion exists twice: a pure `check_*` predicate and a
      GUT-reporting `assert_*` wrapper.** The predicates are what make the
      *negative* expressible — the self-test proves the harness's own assertion
      would have failed for a relic wired to the wrong player without failing the
      run that proves it, which is BRIEF C13's "force the failing path once and
      keep it" done inside the suite rather than in a throwaway run.
    - **`attach()` defaults to the first player made, not the most recent.** A
      case that builds a second player to prove the player filter must not have
      its `attach()` silently follow that player; `primary_player` is set on the
      first `make_player()` and stays.
    - **`SpyWorld` extends `EffectSpawnerSpy` and announces hits only on
      request.** Extending reuses the shipped spawn double (which records *and*
      runs the real `EffectSpawner` base, so the production path is exercised);
      `announce_hits` is off by default because a content case asserting a
      relic's damage should not have that damage re-fed to the relic that
      produced it. `ProcHurtboxStub` remains the announce-always shape for the
      proc-limit tests.

49. **The Mimic Crown copy is a second `Effect` on the same `ContentData` under
    a suffixed id, and it goes when its owner goes (2026-10-20, W4-B3 / G19b).**
    SPEC-effect-system "Proc chain limits", rule 4: "Mimic Crown copies the last
    picked relic's effect; the copy is a second `Effect` instance with its own id
    suffix so rule 2 still applies." `EffectHost` gains `MIMIC_CROWN_SUFFIX`
    (`&"__crown"`), `static suffixed_id()`, `add_mimic_copy()`,
    `has_mimic_copy_of()` and the private `_mimic_owners` map; `Effect` gains
    `id_suffix` and `source_id()` now builds through `suffixed_id()`; `add()`'s
    `id_suffix` parameter is additive with a default of `&""`. This adds public
    API to a module's own class (not an autoload) and changes no existing
    signature's meaning, so nothing on the project's Ask-first list moved; it is
    recorded here because the copy's identity, its ownership and the
    tag-counting policy are choices, not spec numbers.
    - **The copy holds the *same* `ContentData`, and the suffix is the whole
      difference.** A second `.tres` per copied relic would be a second thing to
      keep in sync with the first, and `ContentData` is the *content* — the
      relic's name, tags and script — while "which instance of it is this" is
      the host's business. So `Effect.id_suffix` is what separates the two, and
      it flows into the host key, the node's `name` and (through rule 2, which
      keys on `source_id()`) the tag that suppresses it. This is the clause "so
      rule 2 still applies": a copy that shared its original's id would be
      suppressed by its original's hits *and* suppress its own, which is not a
      copy.
    - **The duplication path is `EffectHost.add()` with the constant named, not
      a second attach mechanism.** The copy is an ordinary `add()` call, so it
      inherits the attach lifecycle, the host's RNG injection and the
      parenting/naming that `add()` establishes. The suite asserts this
      structurally as well as behaviourally: `effect_script.new()` occurs exactly
      once in `effect_host.gd`, so a future second instantiation path fails the
      test rather than silently bypassing the lifecycle.
    - **`remove()` cascades in both directions, and that is the reading of
      "removing Mimic Crown detaches only the copy".** Removing the crown
      removes the crown *and* the copy it made, leaving the copied relic
      attached and still reacting — the relic the player still holds must keep
      working, and a copy whose owner is gone is a copy of nothing. The other
      direction is asserted too: removing the *copied* relic takes its copy with
      it, so a copy can never outlive what it copies. `_mimic_owners` is the
      ownership that makes both possible; without it a copy would be an orphan
      keyed under an id no one can look up. Its read side is public
      (`has_mimic_copy_of(id, owner_id)`, and `has_mimic_copy_of()` answers
      false for a wrong owner and for an id that was never copied), and the
      suite asserts the record is **erased** when the copy goes, so the map
      cannot accumulate an entry per crown ever attached in a run. (An
      alternative reading — the crown
      leaves its copy behind as a permanent, ownerless effect — was rejected: it
      gives a player a way to pay the crown's cost once and keep its benefit
      after dropping it.)
    - **A copy is a second attached `Effect`, so `list_tags()` counts the copied
      relic's tags twice while the crown is held.** `list_tags()` answers "what
      does this build carry", and a copied effect is carried. This is pinned by
      an explicit policy case rather than left implied; excluding copies from
      the count is a one-line change in the getter if the week-8 balance pass
      prefers the other reading, and the case that would fail is named in its own
      comment.
    - **The suffix is a `StringName` constant asserted in two places.** The host
      names it for the code to use; the test names its exact form too, so a copy
      whose id changed shape fails the suite instead of making every store that
      looks a copy up by id — the HUD, the debug overlay, a save — miss it. And
      `suffixed_id(id, &"")` returning `id` unchanged is asserted as well, which
      is what keeps every existing non-copy id byte-for-byte what it was.
    - **The relic itself is `MimicCrownStub` under `tests/helpers/`, `blocked on
      Dev B (W8-B?, the Mimic Crown relic)`.** Rule 4 is one of the rules the
      spec requires to be "enforced in the helpers, not in each effect", so the
      duplication lives on `EffectHost` and the relic double only has to find
      "the last picked" — which it reads off host attach order in the test and
      the shipped relic will read off the replicated `RunPlayerState`. Week 8
      deletes the double and re-points its case at `data/relics/mimic_crown.tres`.
50. **`StatusEffects` reads an entity's kind off a group, applies one uniform
    stacking rule, and hands a tick to `Health` as a finished hit (2026-10-20,
    W4-B4 / G20).** SPEC-stats-status fixes the component's API, its eight rows
    and its "All computation on the host" ownership, but not the four things
    below; they are choices, so they are recorded here. `StatusEffects` gains
    `PLAYER_TAG`, `PLAYER_FORBIDDEN`, the per-status constant tables, the
    `_resolves_statuses()` seam and the `STATUS_TAG` a tick carries, all of it
    new surface on the module's own component rather than on an autoload, so
    nothing on the project's Ask-first list moved. The one signature outside the
    module that changed is `Effect.apply_status`'s `status` parameter (int ->
    `StatusEffects.Status`), which is the retype that method's own comment
    promised and is not a change of meaning: every caller passes an enum member
    or an int literal, and the effect suite is unchanged at 22/57.
    - **The player gate is a group, not a class.** `is_player()` is
      `entity().is_in_group(PLAYER_TAG)`, which is what the goal's "guarded on
      the entity's tag rather than a hard-coded class" comes to here; an entity
      with no tag is treated as an enemy, the permissive default, so an enemy
      double or a bare fixture behaves exactly as the spec's table says and no
      test has to know how a player is built. The tag is applied by
      `PlayerSpawner` — the module that composes a player — so `player.tscn` and
      `player.gd` stay the other lane's. This is the one thing in G20 that
      touches sync, which is why the two-instance smoke ran before the commit.
    - **Stacking is one rule for every row: add to the cap, refresh the
      duration, never accumulate it.** The spec gives BURN's rule in those words
      ("refresh duration, stacks add DPS") and is silent on the rest, so the same
      reading is applied to all eight rows rather than inventing a per-row rule
      the table does not state. `UNLIMITED_STACKS` (`-1`) is TOXIN's cap, and a
      cap of `1` (MARK, FREEZE, SHOCK) is what makes re-application a refresh
      only. If a later row needs different treatment, it is G21/G22's to add
      where its own case can see it.
    - **A tick is a finished `HitData` handed to `apply_damage()`, and it
      bypasses `Hurtbox` on purpose.** SPEC-combat-core makes `apply_damage()`
      the one entry point and says HP is never written directly, so a tick is a
      hit whose damage is already decided (both `base_damage` and `final_damage`
      set to it, so whichever the real `Health` reads, the number is the tick's).
      The `Hurtbox` is skipped deliberately: damage over time is not a connecting
      attack, so it must not take i-frames, roll a crit or wake an on-hit effect.
      The hit carries `STATUS_TAG` and the status's own name, so a listener can
      tell a tick from a connecting hit — `Effect`'s `proc` tag is the precedent
      for a hit tag outside the `Tags` vocabulary, and the tag answers "what
      carried this" rather than "what is it".
    - **The tick's rate is a fraction of the `StatBlock`'s max HP, not of
      `Health`'s.** BURN 4 % per stack per second, TOXIN 1.5 %, BLEED 2 %, read
      through `StatBlock.get_value()` so a modifier that moves max HP moves the
      tick with it and a status tick needs no component but this one. It also
      means the component never needs to know how much HP is left — it is a
      damage *rate*, and the health bar is `Health`'s business.
    - **The client half is the `_resolves_statuses()` seam, and the replicated
      stacks are left to the HUD.** `_resolves_statuses()` returns
      `multiplayer.is_server()` and gates **both** application and ticking, so a
      client deals no damage and applies nothing while still tracking the stacks
      it is told about — "what a client displays is its own business". It is a
      method rather than an inline `is_server()` call for the reason
      `EffectHost._can_spawn()` is: one process can flip it, so the client half
      is unit-tested here instead of only in the smoke. The property that
      actually replicates the stacks belongs to the entity's `StateSync` and
      lands with the HUD status icons (W4-B10, G51).
    - **The duration and rate constants the spec does not fix are starting
      values, named so the week-12 balance pass has one place to edit.** BURN
      (4 s), FREEZE (2 s) and TOXIN (6 s) are the spec's; CHILL, SHOCK, BLEED and
      UNRAVEL durations and TOXIN's and BLEED's rates come from
      SPEC-stats-status's "Open questions" and are marked as such in the
      component's comments. MARK's duration is `NO_EXPIRY` (0.0), which is how
      the code says "consumed, not timed" without a second flag.
    - **`Events.status_applied`'s `status` parameter stays a plain `int`.** The
      enum now exists, so the A4 rule that permits retyping to a real type would
      allow it, but no Week 4 goal needs a typed bus read and the change would
      touch the bus and its emitter tests for no behavioural gain. Whoever first
      needs it can do it with A4 in hand.
51. **The Chill-to-Freeze conversion clears its own Chill, a player is exempt,
    and every status's speed penalty owns a modifier source (2026-10-20, W4-B4 /
    G21).** SPEC-stats-status fixes the four rows' numbers but not how a status
    leaves, who may hold it, or where its penalty lives; those are choices, so
    they are recorded here. `StatusEffects` gains `CHILL_SLOW_PER_STACK`,
    `FREEZE_IMMOBILE_PERCENT`, `CHILL_SOURCE`, `FREEZE_SOURCE`,
    `_freeze_from_chill()`, `_sync_speed_modifiers()`, `_release_modifiers()`,
    `can_act()`, `freeze_double_ready()`, `consume_freeze_double()`,
    `mark_forces_crit()` and `consume_mark()` — all new surface on the module's
    own component, so nothing on the project's Ask-first list moved: no `Events`
    signal changed, no autoload's public API, no `scripts/data/` Resource and no
    `.tscn`.
    - **The conversion clears the Chill it converts.** The CHILL row reads "At 5
      converts to `FREEZE`" and the FREEZE row's last clause is "then clears all
      Chill"; clearing on conversion is what gives that clause something to do,
      because Chill can and does exist beside a freeze when an already-frozen
      entity is chilled again. Keeping five hidden Chill stacks under the freeze
      would make the clause dead text and would re-apply the slow the freeze had
      just replaced.
    - **A player never converts.** The same table's last line lists FREEZE among
      the statuses players may not receive, so a player simply sits at five
      Chill. The conversion is gated on `allows(Status.FREEZE)`, re-using G20's
      `PLAYER_FORBIDDEN` rather than testing for a player a second way.
    - **Each status's penalty has its own `StatBlock` source.** `status:chill` and
      `status:freeze` are separate `StringName`s, so `remove_source()` on a clear,
      an expiry, a stack change or a conversion releases exactly the modifiers
      that status added, and a second status cannot take the first one's penalty
      away with it. `_sync_speed_modifiers()` is the only place a speed penalty
      is computed — called from `apply_status()` and from the conversion — and
      `_release_modifiers()` is its only counterpart, called from `clear()`, so
      every exit from a status is one code path. Every write is a modifier and
      `base` is never touched (SPEC-project, "Never edit base stats").
    - **The freeze double is a flag on the component, not a `Damage` behaviour.**
      `consume_freeze_double()` returns true once and false after, and clears all
      Chill as it spends — which is how "next hit double damage once ... then
      clears all Chill" is discharged. Permafrost's "makes it always" is instead
      the attacker-side `status_mult` term SPEC-stats-status's formula names
      ("+1.0 Permafrost on FREEZE, once"), which is G23's to implement; as a
      second flag here it would put half of one rule in each of two modules.
    - **"Can't act" is a read, not a stat.** `can_act()` is false only while
      FREEZE is active. Attack speed is clamped at 0.2 by `StatBlock`, so a zero
      there is unreachable and would have been the wrong instrument. The entity's
      own controller asks before it moves or attacks, so a frozen enemy keeps its
      AI and its cooldowns and simply produces nothing.
    - **The test fixture's `StatBlock` gained MOVE_SPEED and ATTACK_SPEED
      bases.** A zero base reads 0 with or without a penalty, and these rows are
      stated as reads "through `StatBlock` values". Those two lines are the whole
      of the test file's deletions; no assertion was removed, weakened or
      `pending`-ed.
52. **SHOCK's trigger damage is an optional trailing argument, a relic is asked of
    both governing effect hosts, and Plague Doctor's Mask re-arms TOXIN's clock
    (2026-10-20, W4-B4 / G22).** SPEC-stats-status fixes the four rows' numbers
    but not how a chain is fed its trigger, who owns a relic that rescued a
    status, or where a relic-driven exemption lives; those are choices, so they
    are recorded here. `StatusEffects` gains `ENEMY_TAG`, `EFFECT_HOST_NODE`,
    `CHAIN_TAG`, `SHOCK_CHAIN_DAMAGE_FRACTION`, `SHOCK_CHAIN_TARGETS`,
    `SHOCK_CHAIN_RADIUS`, `LIGHTNING_ROD_ID`, `LIGHTNING_ROD_CHAIN_BONUS`,
    `TOXIN_HEALING_MULTIPLIER`, `PLAGUE_DOCTORS_MASK_ID`,
    `UNRAVEL_DAMAGE_TAKEN_PER_STACK`, `healing_multiplier()`,
    `damage_taken_multiplier()`, `has_relic()`, `chain_count()`,
    `chain_damage()`, `chain_targets()`, `chain_hit()`, `_chain_shock()`,
    `health_of()`, `_deliver_to()`, `_effect_hosts()`, `_entity_position()` and
    `_nearer_first()`, and one trailing optional parameter each on
    `apply_status()` and `Damage.compute()` — all new surface on the two modules'
    own scripts, so nothing on the project's Ask-first list moved: no `Events`
    signal changed, no autoload's public API, no `scripts/data/` Resource and no
    `.tscn`.
    - **The trigger damage is a trailing optional parameter on
      `apply_status()`.** SHOCK's row is stated in terms of "trigger damage",
      which only the caller knows, so `apply_status(status, stacks, source,
      trigger_damage)` carries it. Additive and defaulted: the signature the spec
      fixes for every other status is unchanged, a relic that applies a burn
      ignores the argument, and an application with no trigger damage chains
      nothing rather than chaining a zero-damage hit.
    - **`has_relic()` asks both effect hosts that govern an entity's statuses.**
      A relic can govern an application from either side — a player's Lightning
      Rod shocks an enemy, an enemy's own attachment could shock itself — so the
      applier's `EffectHost` is consulted first and the entity's own second, and
      each has a case: the applier's is the ordinary one, and the target's own is
      asserted with **no applier at all**, so its host is the only place the rod
      can be found. The relic is read as an **id off a host**, never as a number
      or a branch in this file, which is what keeps Lightning Rod and Plague
      Doctor's Mask content (W4-B6) rather than code.
    - **Plague Doctor's Mask re-arms TOXIN's clock instead of pinning it.** When
      TOXIN's `remaining` reaches zero and the source holds the mask, `_tick`
      resets the window to the full duration rather than expiring. Pinning a
      sentinel duration would have made the status unreadable to the HUD's
      duration bar and would have hidden it from every code path that asks "is
      this about to fall off"; re-arming keeps the status inside the same expiry
      path every other status uses, and dropping the mask lets the re-armed window
      run out naturally.
    - **`Damage.compute` takes the target's `StatusEffects` as an optional fifth
      argument.** The formula's `status_mult` term is the formula's to own, so
      UNRAVEL's read lives on the component and the multiply lives in `Damage`.
      Optional and defaulted to `null`, so every week-2 caller and the golden
      table keep their exact behaviour and G23's attacker-side terms (Kindling's
      BURN bonus, Permafrost's FREEZE bonus) can be added beside it without a
      second signature change. Only the UNRAVEL term is landed here; the doc
      header names the two G23 owns.
    - **The heal path the TOXIN penalty is asserted through is the
      `StatusHealthStub` double — blocked on Dev A (W2-A1, combat-core
      `Health`).** The real `Health.heal()` is host-authoritative and emits
      `Events.player_healed`, and does not exist yet; the row is therefore proven
      by a strip-in double whose `heal()` multiplies the incoming amount by
      `StatusEffects.healing_multiplier()`, so the assertion is on the HP that
      landed and not on the multiplier alone. SPEC-combat-core's
      `apply_damage(hit: HitInfo)` fixes the shape, so the swap-in is a type
      rename.
    - **`ENEMY_TAG` has no real registrant yet — blocked on Dev A (W4-A1,
      enemies-ai).** `scripts/generation/` is still empty and no enemy scene
      exists, so the group the chain reads is whatever the world or a test double
      puts in it. The constant is named and documented so the swap-in is Dev A's
      `add_to_group` line and nothing in this component changes. A chain target
      that carries no `Health` is a **silent skip** rather than a warning: a chain
      lands on whatever the group put in range, and a missing `Health` is W2-A1's
      gap to report, not this component's.

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
