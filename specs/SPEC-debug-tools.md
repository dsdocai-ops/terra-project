# Spec: debug-tools

| | |
|---|---|
| Module id | `debug-tools` |
| Owner | Both |
| Weeks | 2 (console with core commands, two-instance launcher), 4 (perf scene, simulated latency, effect overlay) |
| Design doc | section 23 |
| Depends on | `foundation`, `networking` |
| Depended on by | every module's manual testing |

## Objective

The tools the quality bar in design doc section 23 needs: a debug console, a two-instance launcher, simulated latency, a perf test scene, and a proc overlay, all stripped from release exports.

## Scope

### Debug console

Toggle with `debug_console` (backtick). A `LineEdit` + scrollback under a `CanvasLayer`. Commands registered via `DebugConsole.register(name, callable, help)` by owning modules; core set here:

| Command | Effect |
|---|---|
| `help [cmd]` | list / describe |
| `spawn <enemy_id> [count] [elite] [affix]` | at cursor |
| `boss <boss_id>` | spawn boss in current room |
| `give relic <id> [stacks]`, `give ability <id> [rank]`, `give weapon <id>`, `give mutation <id>` | to local player (host applies) |
| `gold <n>`, `ore <id> <n>`, `echo <n>`, `classxp <n>` | currencies |
| `skip` / `floor <n>` | advance / jump floor |
| `unlock all` / `unlock skills` / `unlock classes` / `unlock characters` | profile unlocks (saves) |
| `seed <n>` | set next run seed |
| `god`, `noclip`, `kill` (all enemies), `heal` | toggles and instants |
| `timestop <s>`, `timeslow <factor> <s>` | TimeManager |
| `flag <id>` / `flags` | story |
| `net_lag <ms> [loss%]` | simulated latency on this peer |
| `perf` | open perf scene |
| `fps`, `stats` | overlay toggles |
| `dump` | write profile and run state JSON to `user://debug_dump.json` |
| `save_reset` | wipe profile (confirm) |

Commands run on the host via `request_debug(cmd)`; clients can issue, host executes (so co-op testing from either side works). Console is only compiled in when `OS.is_debug_build()` or `--debug-tools` arg; release export excludes `scripts/debug/` via export filter.

### Two-instance launcher

Editor plugin menu item or `tools/run_two.ps1` / `.sh` that launches `--host` and `--join=127.0.0.1` with window positions side by side. Also configures Godot's "Run Multiple Instances" debug setting with these args so F5 works.

### Simulated latency

`net_lag` wraps `ENetMultiplayerPeer` host with ENet's built-in simulation (`ENetConnection.socket_send` lag not exposed; use `peer.host.set_bandwidth_limit` plus a delay queue around `MultiplayerSynchronizer` deltas via `SceneMultiplayer` custom packet delay) or, simpler, ENet's `enet_host_...` is unavailable in GDScript so implement a `DelayedPeer` proxy that buffers outgoing packets by N ms and drops a percentage. Decide implementation in week 4; the API is just `net_lag`.

### Perf scene

`scenes/debug/perf_test.tscn`: spawns 60 units (mix of enemies, skeletons, turrets), 4 fake players with a chosen set of proc-heavy relics, 128 VFX emitters, logs FPS min/avg over 30 s to the console and a file. Run weekly from week 4 on both machines; results in `specs/WEEKLY.md`.

### Overlays

- FPS and frame time graph.
- Effect overlay: active effects per player and last 20 procs with depth (from `effect-system`).
- Hitbox outlines (`debug/shapes` toggle), telegraph timings, AI state labels above enemies, room graph and types over the minimap.

### Seed soak runner

`tools/soak_floors.gd` headless script used by `test_floor_generation_seeds.gd` and runnable alone with a seed range argument.

## Interfaces provided

`DebugConsole.register`, overlays toggles, launcher scripts, perf scene, soak runner.

## Interfaces consumed

- `networking`: `request_debug` RPC, peer wrapping.
- Every module registers its commands.

## Data model

None persistent beyond `user://debug_dump.json`.

## Multiplayer ownership

Commands execute on the host; the issuing peer is passed so `give` targets the right player. Sync: host-authoritative.

## Testing

- Unit `test_console_parser.gd`: tokenizing, quoted args, unknown command, help.
- Integration: each registered command runs without error against a headless run (smoke).
- CI check: export preset excludes `scripts/debug/`.

## Success criteria

- [ ] Week 2: console with spawn, give relic, gold, skip, seed, god; two-instance launcher.
- [ ] Week 4: perf scene with 60 units logging FPS; `net_lag`; effect overlay.
- [ ] Release export contains no debug console (verified in week 12 export).

## Open questions

- Latency simulation implementation (week 4).
