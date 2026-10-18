# Spec: networking

| | |
|---|---|
| Module id | `networking` |
| Owner | Dev B |
| Weeks | 1 (connect, spawn, move), 3 (seed sync, downed sync), 12 (bug fix, latency) |
| Design doc | section 12, section 4.3 (co-op class rules), section 9.5 (shared loot) |
| Depends on | `foundation` |
| Depended on by | `player-controller`, `enemies-ai`, `floor-generation`, `run-economy`, `effect-system`, `debug-tools` |

## Objective

Online 1 to 4 player co-op that exists from week 1 and that every other module writes against. Host-authoritative: the host runs enemies, damage, loot rolls, effect procs, and floor generation; clients send inputs and play presentation. This spec is the contract every stateful script follows when it answers "who owns this, how does it sync."

## Scope

### Connection

- `ENetMultiplayerPeer`, default port 7777, max 4 peers including host.
- Host shares IP + port. Internet play without port forwarding uses playit.gg or Tailscale, documented in the Tavern lobby screen text (`ui-hud`). Steam lobbies are stretch.
- Reconnect is not supported in 12 weeks. A dropped client is removed; its loot stays with the host's shared pools; the run continues for the rest.
- Host disconnect ends the run for everyone with a "host left" screen.

### Player spawning

- `World/Players` has a `MultiplayerSpawner` with `spawn_path = World/Players` and the player scene registered. The host calls `spawn()` with `{peer_id, character_id, class_id, weapon_ids}` for every peer, including itself.
- Each player node has `set_multiplayer_authority(peer_id)` **only on its input and presentation**. Health, stats, position of record, and inventory are server-authoritative (authority 1). Concretely, the player scene has two `MultiplayerSynchronizer` nodes: `InputSync` (authority = peer, replicates input vector, aim, pressed actions, to host) and `StateSync` (authority = host, replicates position, velocity, animation state, HP, downed state, to all).
- Client-side prediction for the local player's movement only: client moves immediately from its own input, host simulates the same input and the `StateSync` position corrects drift with a small lerp. No prediction for attacks; attack animations start on client input but hits are decided by the host.

### Enemies, projectiles, pickups, effects

- Spawned only by the host through `MultiplayerSpawner`s under `World/Entities`. One spawner for enemies, one for projectiles, one for pickups, one for FX-with-gameplay (clones, zones, totems).
- Each has a `MultiplayerSynchronizer` for position, animation state, HP (enemies), and status stacks. Purely cosmetic particles are not synced; clients spawn them locally from synced events.
- Effect procs (`effect-system`) run on the host only. Their visible results are spawned via the spawners so clients see them.

### RPC conventions

- Input: client to host via `InputSync`, never raw RPC.
- Requests from client to host: `@rpc("any_peer", "call_remote", "reliable")` named `request_<verb>` (e.g. `request_pick_relic`, `request_vote_rope`, `request_use_potion`). Host validates (is it that player's choice, is the room state right) and applies. Never trust client values beyond ids and indices.
- Host to clients: `@rpc("authority", "call_local", "reliable")` named `<past_tense_event>` (e.g. `relic_picked`, `vote_updated`, `floor_ready`). Presentation-only updates can be `unreliable_ordered`.
- Every RPC method's first line validates `multiplayer.get_remote_sender_id()` where it matters.

### Seed sync

- Host picks `run_seed` at run start, sends with `floor_ready(seed, floor_index, biome_id, modifiers)` before each floor. Every peer runs `FloorGenerator.generate()` locally with the same inputs and must produce identical layouts (`floor-generation` guarantees determinism). Host hashes the layout and clients assert the same hash; mismatch logs an error and requests the host's layout as a fallback.

### Game rules owned here

- Enemy HP scaling by player count: `hp_mult = 1.0 + 0.5 * (player_count - 1)`. Constant lives here, applied by `enemies-ai` when spawning.
- Same class allowed twice, different Ascensions enforced at Ascension choice (host rejects a duplicate and offers the other).
- Ping: `request_ping(world_pos, kind)` relayed as `ping_shown(peer_id, world_pos, kind)`; `ui-hud` draws it.
- Progress is per player: Echo Shards, Class XP, story flags, unlocks are tracked per peer and sent to each client at run end so `save-system` on each machine saves its own. Gold and ore are shared pools on the host, split evenly at extraction. Town visited together is the host's town.

### Time effects

Nothing here uses `Engine.time_scale`. See `SPEC-time-manager.md`; this module guarantees a time stop on the host does not stall `MultiplayerSynchronizer` traffic (synchronizers keep ticking; frozen entities simply report the same values).

## Interfaces provided

`NetworkManager` autoload:

```gdscript
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal connection_failed(reason: String)
signal host_disconnected()

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4
const ENEMY_HP_PER_EXTRA_PLAYER: float = 0.5

var is_host: bool            # true when multiplayer.is_server(); also true in solo
var local_peer_id: int
var peer_ids: Array[int]     # includes host
var players: Dictionary      # peer_id -> Player node, filled as spawns complete

func host(port: int = DEFAULT_PORT) -> Error
func join(ip: String, port: int = DEFAULT_PORT) -> Error
func start_solo() -> void    # offline server, same code path as host
func disconnect_all() -> void
func get_player(peer_id: int) -> Player
func player_count() -> int
func enemy_hp_multiplier() -> float
```

Solo play is a host with one peer; there is no separate single-player code path.

Scene conventions (spawners, synchronizer split, `World/Players`) are part of this interface and are used by `player-controller`, `enemies-ai`, `effect-system`.

## Interfaces consumed

- `foundation`: world scene node layout, launch args, `GameState.world`.

## Data model

`PlayerSpawnInfo` (RefCounted, serialized to Dictionary for `spawn()`): `peer_id`, `character_id`, `class_id`, `weapon_ids: Array[StringName]`.

## Multiplayer ownership

This module *is* the ownership rule. Summary every other spec quotes:

> Host decides, clients present. Inputs go up through `InputSync`. State comes down through `StateSync`. Spawns go through spawners. Requests are validated RPCs named `request_*`; broadcasts are past-tense RPCs.

## Testing

- Automated: `tests/unit/test_network_manager.gd` for `enemy_hp_multiplier()` at 1 to 4 players and for `start_solo()` setting `is_host`.
- Two-instance smoke (required in every PR that touches sync, recorded in the PR):
  1. Launch `--host` and `--join=127.0.0.1`.
  2. Both players visible on both screens, moving, dodging.
  3. Client attacks an enemy; HP drops on both; kill registers once.
  4. Client picks a relic from a shrine; host confirms; HUD updates on client.
  5. Client goes down; host revives; both see the state.
  6. Trigger a time stop on host (debug console); client player keeps moving, enemies frozen on both screens.
  7. Close client; host run continues.
- Weekly two-machine test with simulated latency 100 ms and 2% loss (debug console `net_lag` command from `debug-tools`).

## Success criteria

- [ ] Week 1: two instances connect, both players spawn and move with no visible rubber-banding at 0 ms latency.
- [ ] Week 3: both peers generate identical floors from the broadcast seed (hash match in 100 of 100 floors in the automated soak run with two headless instances if feasible, otherwise 20 manual floors).
- [ ] Week 3: downed and revive synced.
- [ ] Every stateful script in the repo has the ownership line in its doc comment (grep check in CI: `scripts/**/*.gd` containing `signal` or `@export` with state must contain "Sync:").
- [ ] Week 12: a 4-player run of 30 floors completes on at least two physical machines.

## Open questions

- Whether to run the two-headless-instances floor hash soak in CI or keep it manual. Decide in week 3 based on how long it takes.
