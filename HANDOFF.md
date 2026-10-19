# HANDOFF — Week 1 (W1-B1 .. W1-B10)

A plain-language rundown of what the Dev B (Surface + Systems) lane shipped in
week 1, how each piece works, every decision that was made without a human in
the loop, and how to run the build solo and in co-op. Written for Dev A and the
human who review this handoff; the week-1 task list is `tasks/todo.md`.

**Verified baseline (2026-10-18)** on `main` @ `75ed7c2`:

- `godot --headless --path . --import` exits 0 with no warnings or errors.
- Full GUT suite: **18 scripts, 204 tests, all passing** in ~7 s.
- `tools/smoke_two.sh`: **15/15 checks pass**, exit 0.

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

---

## Decisions made without a human

These are the judgment calls taken during week 1 that were not dictated by a
spec, so the accountability contract is explicit. Where a decision is already
recorded in a spec or a comment, the location is given.

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

Expect 15 `ok` lines and exit 0. On Linux/macOS, `tools/run_two.sh` is the
windowed launcher and `smoke_two.sh` needs `GODOT` pointing at a 4.7.2 binary.

### Tests and import (what CI runs)

```powershell
godot --headless --path . --import                                                         # must exit 0, no errors
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit   # 204 tests, exit 0
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

---

Everything above was verified on this machine on 2026-10-18: import exit 0,
204/204 GUT tests green, 15/15 smoke checks green, on `main` @ `75ed7c2`.
Week 1's remaining close-out (WEEKLY entry, SPEC-foundation write-backs, CI
confirmation, `week-1` tag) is tracked in `.goals/PLAN.md` and the handoff to
week 2 continues from there.
