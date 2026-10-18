# Spec: time-manager

| | |
|---|---|
| Module id | `time-manager` |
| Owner | Dev B |
| Weeks | 2 (multiplier, hit-stop), 4 (stop and slow effects, rewind hook) |
| Design doc | section 12 "Time effects in co-op", section 6 (hit-stop), relics Clockwork Heart and Time Hourglass, Perfect Dodge skill node, Sharpshooter Deadeye |
| Depends on | `foundation` |
| Depended on by | `combat-core`, `enemies-ai`, `effect-system`, `bosses`, `abilities`, `weapons` |

## Objective

One place that answers "how fast does time move for this entity right now" so that time stop, time slow, hit-stop, and rewind work in co-op without `Engine.time_scale`. Enemies and enemy projectiles freeze; players keep moving; the network keeps flowing.

## Scope

- **Global enemy scale**: a stack of active slow/stop effects, each `{source: StringName, factor: float, until: float}`. Effective scale is the minimum factor. Factor 0 is a stop.
- **Per-entity override**: `set_entity_scale(node, factor, duration, source)` for single-target effects (Frozen Clone taunt target, Umbral Grasp root uses status instead, Crimson Leech slows its target).
- **Per-player exemption**: time effects apply to the `ENEMY` time group. Players are in the `PLAYER` group and ignore enemy-side effects. Deadeye slows enemies while *one* player charges; other players are unaffected and keep normal speed, which matches the design doc rule that time effects never freeze another player.
- **Hit-stop**: `hit_stop(a: Node, b: Node, frames: int)` pauses the `AnimationPlayer`/`AnimatedSprite2D` and movement of exactly those two nodes for N physics frames (3 for light hits, 6 for heavy, 10 for boss kills). Implemented by setting a per-entity scale of 0 for N frames on both. The camera, the HUD, and other entities continue.
- **Rewind hook** (Time Hourglass): `register_rewindable(node, sampler: Callable, restorer: Callable)`. The manager records samples every 0.1 s for the last 3 s for each registered node. `rewind(node, seconds)` restores the newest sample older than N seconds. Only the using player registers; nothing else rewinds.
- **Clockwork Heart** (every 10 s, stop enemies 1 s), **Perfect Dodge node** (slow enemies 1 s), **Deadeye** (slow while charging) all call the public API from their effect scripts in `effect-system` / `classes-characters`.
- Audio pitch is not changed by time effects (AudioManager decision, keeps co-op consistent).

How entities use it: every enemy, boss, and enemy projectile multiplies its `delta` by `TimeManager.scale_for(self)` in `_physics_process` and sets `sprite.speed_scale` to the same value. The `StateMachine` passes scaled delta to states. `StatusEffects` ticks on scaled delta for enemies. Pure engine timers (`Timer` nodes, `await get_tree().create_timer`) are forbidden on enemies for anything gameplay-relevant; use `TimeManager.timer(node, seconds)` which returns a signal that respects scale.

## Interfaces provided

`TimeManager` autoload:

```gdscript
enum Group { PLAYER, ENEMY }

signal enemy_time_changed(scale: float)

func scale_for(node: Node) -> float
func set_group(node: Node, group: Group) -> void          # called in _ready by player/enemy scripts
func slow_enemies(factor: float, seconds: float, source: StringName) -> void
func stop_enemies(seconds: float, source: StringName) -> void
func clear_source(source: StringName) -> void             # cancel early (Deadeye release)
func set_entity_scale(node: Node, factor: float, seconds: float, source: StringName) -> void
func hit_stop(a: Node, b: Node, frames: int) -> void
func timer(node: Node, seconds: float) -> Signal          # scaled timer, fires once
func register_rewindable(node: Node, sampler: Callable, restorer: Callable) -> void
func unregister_rewindable(node: Node) -> void
func rewind(node: Node, seconds: float) -> void
```

## Interfaces consumed

- `foundation`: autoload registration (second, after `Events`).

## Data model

Internal only: arrays of active effects, dictionary node to per-entity stack, ring buffers for rewind samples.

## Multiplayer ownership

Host decides every time effect and broadcasts `time_effect_applied(group, factor, seconds, source)` and `entity_time_applied(path, factor, seconds, source)` as reliable RPCs so clients render frozen enemies locally; gameplay (hit detection, AI) only runs on the host anyway. Hit-stop is broadcast too so clients see the freeze frame. Rewind is a host operation on the requesting player's state, then synced like any position/HP change.

Sync: host-authoritative, reliable RPC broadcast of start events; expiry is computed locally from the same duration.

## Testing

- Unit `test_time_manager.gd`: min-of-stack math; expiry; `clear_source` removes only that source; per-entity overrides group; `hit_stop` restores after N frames; `rewind` picks the right sample; players unaffected by enemy slow.
- Integration: a scripted enemy with scaled delta moves 0 px during a 1 s stop and resumes.
- Two-instance smoke: time stop triggered on host via debug console; client's own player keeps moving on both screens; enemies frozen on both.
- Grep check in CI: no `Engine.time_scale` anywhere in `scripts/` or `scenes/`.

## Success criteria

- [ ] Clockwork Heart, Perfect Dodge slow, Deadeye slow, Time Hourglass rewind, and hit-stop all work in a 2-player session with no effect on the non-using player.
- [ ] No `Engine.time_scale` in the repo.
- [ ] Hit-stop on a heavy kill freezes exactly attacker and target for 6 frames; the HUD timer keeps counting.
- [ ] Enemy projectiles in flight freeze during a stop and resume on the same trajectory.

## Open questions

- None.
