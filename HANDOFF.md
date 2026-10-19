# HANDOFF — Weeks 1 and 2 (W1-B1 .. W1-B10, W2-B1 .. W2-B6)

A plain-language rundown of what the Dev B (Surface + Systems) lane shipped in
week 1 and week 2, how each piece works, every decision that was made without a
human in the loop, and how to run the build solo and in co-op. Written for Dev
A and the human who review this handoff; the task list is `tasks/todo.md`.

**Verified baselines:**

- Week 1 (2026-10-18) on `main` @ `75ed7c2`: import exit 0; 18 GUT scripts /
  204 tests green in ~7 s; `tools/smoke_two.sh` 15/15 (steps 1 + 2).
- Week 2 (2026-10-19) on `main` @ `ee62cb7`: import exit 0 with no errors;
  27 GUT scripts / 338 tests green in ~14 s; `tools/smoke_two.sh` 28/28
  (steps 1 + 2 + 3). `week-2` tag held off until Dev A's W2 tasks land (see
  `specs/WEEKLY.md`).

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
`gold <n>`, `skip` (stub), `seed <n>`, `god`, `kill`, `heal`, `timestop <s>`,
`timeslow <factor> <s>`, `fps`, `dump`. Commands run on the **host**: a client's
console sends the line through `NetworkManager.request_debug(cmd, peer_id)`
(a validated `any_peer`/`call_remote`/`reliable` RPC that emits
`debug_command_requested`); the host's console executes and targets the issuing
peer (spawn at that player, gold/heal/god on that player).

Where a command touches a system that has not landed yet it validates its input
and reports the deferral rather than failing: `give`/`heal` wait on
weapons/abilities/relics/run-economy/combat-core (weeks 4-5), `skip` on
floor-generation (week 3), and `spawn`/`kill` work today against the W2-B3
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
    `skip` needs floor-generation, `god` is debug-local state until Health
    consumes it.
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

Expect 28 `ok` lines (steps 1 + 2 + 3) and exit 0. On Linux/macOS, `tools/run_two.sh` is the
windowed launcher and `smoke_two.sh` needs `GODOT` pointing at a 4.7.2 binary.

### Tests and import (what CI runs)

```powershell
godot --headless --path . --import                                                         # must exit 0, no errors
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit   # 338 tests, exit 0
```

---

## Manual checks still open (non-blocking)

These were not blockable from a headless run or from this machine. They are a
short checklist for Dev A and the human; none of them block week 2.

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

---

Everything above was verified on this machine on 2026-10-18 (week 1) and
2026-10-19 (week 2): import exit 0 with no errors, 338/338 GUT tests green
(~14 s), 28/28 smoke checks green, on `main` @ `ee62cb7`. The week-1 close-out
(WEEKLY entry, SPEC-foundation write-backs, CI confirmation, `week-1` tag) and
the week-2 checkpoint (smoke steps 1–3, feel-pass checklist, WEEKLY entry, the
`week-2` tag once Dev A's tasks land) are tracked in `.goals/PLAN.md` and
`specs/WEEKLY.md`.
