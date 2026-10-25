# Spec: effect-system

| | |
|---|---|
| Module id | `effect-system` |
| Owner | Dev B |
| Weeks | 4 |
| Design doc | section 18 "Effect / trigger system", design pillar 2 "Wild builds", section 23 (proc caps) |
| Depends on | `stats-status`, `networking`, `time-manager` |
| Depended on by | `relics`, `weapons` (mutations), `abilities`, `classes-characters` (passives, Ascensions, pair bonuses), `progression-trees` (node effects), `bosses` (Hollow You), `endgame` (heat modifiers) |

## Objective

The reason relics are "my dodge spawns lightning clones that explode" instead of +5% damage: a global `Events` bus, an `Effect` base class that listens to those events and spawns things, a tag system for synergies, and hard proc caps so no build freezes the game. Relics, mutations, synergies, class passives, Ascensions, and skill nodes are all `Effect`s, so they stack automatically.

## Scope

### Events bus

`Events` autoload, signals only, no logic. Emitters are the owning modules named in parentheses. All `player` arguments are the attributing `Player` (minion and turret hits attribute to their owner).

```gdscript
# combat (combat-core)
signal hit_landed(hit: HitInfo)                         # after damage applied, hit.source / hit.owner_player / target in hit
signal crit_landed(hit: HitInfo)
signal player_damaged(player: Player, hit: HitInfo)
signal player_healed(player: Player, amount: int, source: Node)
signal heavy_attack_released(player: Player, charge: float)
signal weapon_swapped(player: Player, slot: int)
signal projectile_fired(player: Player, projectile: Projectile)
# movement (player-controller)
signal player_dodged(player: Player, perfect: bool)
signal player_downed(player: Player)
signal player_revived(player: Player, by: Player)
signal player_died(player: Player)
# enemies (enemies-ai)
signal enemy_spawned(enemy: Enemy)
signal enemy_killed(enemy: Enemy, hit: HitInfo)         # hit.owner_player is the killer, may be null (hazard)
signal elite_killed(enemy: Enemy, hit: HitInfo)
signal enemy_staggered(enemy: Enemy, hit: HitInfo)         # poise broke (or a 0-poise enemy was hit); hit.staggered is true
signal boss_defeated(boss_id: StringName)
# status (stats-status)
signal status_applied(target: Node, status: StatusEffects.Status, stacks: int, source: Node)
signal combo_triggered(target: Node, combo: Combo, source: Node)
# abilities (abilities)
signal ability_cast(player: Player, ability: AbilityData, rank: int)
signal ultimate_used(player: Player, ultimate: AbilityData)
signal class_skill_used(player: Player)
# rooms and run (floor-generation, run-economy)
signal room_entered(room: Room, player: Player)
signal room_cleared(room: Room)
signal floor_entered(floor_index: int)
signal floor_cleared(floor_index: int)
signal run_started(seed: int)
signal run_ended(result: RunResult)
signal rope_vote_updated(votes: Dictionary)
# loot (run-economy, relics, weapons, abilities)
signal currency_gained(player: Player, currency: StringName, amount: int)
signal pickup_collected(player: Player, pickup: Pickup)
signal relic_picked(player: Player, relic: RelicData)
signal relic_removed(player: Player, relic: RelicData)
signal synergy_activated(player: Player, synergy: SynergyData)
signal mutation_applied(player: Player, weapon: WeaponData, mutation: MutationData)
signal ascension_chosen(player: Player, ascension: AscensionData, tier: int)
# story (story-dialogue)
signal story_flag_set(flag: StringName)
signal lore_unlocked(page_id: StringName)
signal miner_rescued(miner_id: StringName)
```

Adding or changing a signal is "Ask first". Signals are emitted on the host; the ones the HUD and VFX need are also emitted on clients from replicated state (`hit_landed`, `enemy_killed`, `relic_picked`, `room_cleared`, `currency_gained`). An effect script never runs on a client (see ownership).

### Effect base class

```gdscript
class_name Effect extends Node
## Base for relic, mutation, synergy, class passive, Ascension, and skill node effects.
## Sync: host only. Visible results are spawned through spawners.

var player: Player              # the player this effect belongs to
var source: ContentData         # RelicData, MutationData, etc.
var stacks: int = 1             # duplicates (relic picked twice), rank (skill node), upgrade rank (ability)
var _handles: Array[int]        # StatBlock handles to remove on detach
var _timers: Array[Timer]

func attach(player: Player, source: ContentData, stacks: int) -> void   # calls _on_attach
func detach() -> void                                                     # removes modifiers, disconnects, frees timers
func _on_attach() -> void: pass
func _on_detach() -> void: pass

# helpers
func listen(sig: Signal, callable: Callable) -> void          # auto-disconnect on detach, filters to this player where the signal has one
func every_seconds(interval: float, callable: Callable) -> void   # uses TimeManager.timer loop, PLAYER group so time stops don't pause it
func once_per_room(key: StringName) -> bool                   # returns true the first time per room
func modify(stat: StatBlock.Stat, flat: float = 0.0, percent: float = 0.0) -> void
func spawn(scene: PackedScene, pos: Vector2, setup: Callable = Callable()) -> Node   # through the FX/entity spawner, tagged with proc depth
func deal_damage(target: Node, hit: HitInfo) -> void          # increments proc depth, tags "proc"
func apply_status(target: Node, status, stacks: int) -> void
func chance(p: float) -> bool                                  # host RNG, Luck-aware for loot-type procs via chance_lucky()
func fire_projectile(data: ProjectileSpec, from: Vector2, dir: Vector2) -> Projectile
```

`EffectHost` node on each player holds attached effects, keyed by source id, and exposes `add(source, stacks)`, `remove(source)`, `get_effect(id)`, `list_tags() -> Dictionary` (tag -> count) for synergies.

### Proc chain limits

Every `HitInfo` carries `proc_depth`. `deal_damage`, `spawn`, and `fire_projectile` from an effect create results with `proc_depth = trigger.proc_depth + 1`. Rules enforced in the helpers, not in each effect:

1. A proc at depth 3 does not trigger further effects (its hits still damage, but `hit_landed` from it is emitted with `hit.proc_depth = 3` and `Effect.listen` wrappers skip events with `proc_depth >= 3`).
2. An effect never reacts to a hit whose `tags` already contain its own id (no self-retrigger).
3. Per-frame cap: at most 64 effect-spawned nodes per player per frame; the rest are dropped and counted in a debug stat.
4. Mimic Crown copies the last picked relic's effect; the copy is a second `Effect` instance with its own id suffix so rule 2 still applies.

### Tags and synergies

`ContentData.tags: Array[StringName]`. Tag vocabulary (closed set, `Tags` enum-like constants): `fire, frost, storm, shadow, poison, earth, blood, void, dodge, on_hit, on_kill, on_damaged, crit, ability, movement, economy, transformation, cursed, active`. `EffectHost.list_tags()` counts tags across attached relics; `relics` evaluates `SynergyData` requirements against it on every `relic_picked`/`relic_removed`.

### Shared by everything

Class passives, class skills' passive parts, Ascensions, pair bonuses, skill tree nodes, class tree nodes, heat modifiers, and weapon mutations are all `Effect` subclasses attached to the `EffectHost`. One system, one test harness.

### Visual language

`spawn()` tags spawned nodes with `proc_source_id` so the VFX library (`art-audio`) can color by element and the debug overlay can show which relic made what.

## Interfaces provided

`Events` signal set, `Effect`, `EffectHost`, `Tags`, `ProjectileSpec` (RefCounted: scene, speed, damage, element, pierce, bounce), the proc depth rules. Trigger test harness `tests/helpers/effect_harness.gd`: creates a headless player with `EffectHost`, attaches an effect, fires any `Events` signal with fake arguments, asserts spawns, stat changes, statuses, and damage via a `SpyWorld`.

## Interfaces consumed

- `stats-status`: `StatBlock`, `Damage`, statuses.
- `networking`: FX/entity spawner, host check.
- `time-manager`: `timer`, `stop_enemies` etc. for time relics.
- `combat-core`: `HitInfo`, `Projectile`.

## Data model

No `.tres` of its own. `ContentData` gains `tags` and `effect_script: GDScript` fields (defined in `foundation`'s `content_data.gd` and extended here under "Ask first").

## Multiplayer ownership

Effects attach and run on the host for every player, including remote ones. Clients hold no `Effect` instances; they see spawned results via spawners and HUD state via replicated `RunPlayerState`. Local-feel exceptions (none in 12 weeks; if a relic needs instant client feedback, spawn a cosmetic-only preview locally and let the host result replace it).

Sync: host-only logic, spawner-replicated results.

## Testing

- Unit `test_effect_base.gd`: attach/detach cleans every handle, timer, and connection; `listen` filters by player; `once_per_room` resets on `room_entered`.
- Unit `test_proc_limits.gd`: a chain of 5 self-triggering fake effects stops at depth 3; self-retrigger blocked; per-frame cap drops and counts.
- Unit `test_tags.gd`: counts, Mimic Crown duplication.
- Harness tests: every relic, mutation, passive, Ascension, and node effect has at least one harness case in its owning module's tests. This module ships the harness and a template test.
- Perf: perf scene with Hydra Heart + Splitting Shot + Rune of Ricochet + Volatile Core + Chain Lightning procs on 60 enemies stays above 60 FPS thanks to depth cap and per-frame cap.

## Success criteria

- [ ] Week 4: 20 relics implemented against the bus with zero per-relic special casing in combat code.
- [ ] A deliberately pathological build (test above) cannot drop the host below 60 FPS or allocate unbounded nodes.
- [ ] Class passives (week 5) and skill nodes (week 7) attach through the same `EffectHost` with no new system.
- [ ] Debug overlay (from `debug-tools`) lists active effects and last 20 procs with depth.

## Open questions

- Whether `Effect` extends `Node` (easy timers, tree lifetime) or `RefCounted` (lighter). Start with `Node` under `EffectHost`; profile in week 4 with 30 relics attached per player x 4 players.
