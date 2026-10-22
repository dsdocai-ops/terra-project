# Spec: stats-status

| | |
|---|---|
| Module id | `stats-status` |
| Owner | Dev B |
| Weeks | 2 (StatBlock, damage formula), 4 (statuses, element combos, depth scaling) |
| Design doc | section 6 (stats, elements, combos), section 9.5 (depth scaling, elite HP) |
| Depends on | `foundation` |
| Depended on by | `combat-core`, `effect-system`, `enemies-ai`, `player-controller`, `relics`, `weapons`, `abilities`, `classes-characters`, `progression-trees` |

## Objective

The math layer: a `StatBlock` every entity carries, the single damage formula, seven status effects with stacking rules, six element combos, and the scaling constants. Every relic, skill node, class passive, and Ascension changes numbers only through this module.

## Scope

### StatBlock

11 stats from design doc section 6. Value = `(base + sum(flat)) * (1 + sum(percent))`, clamped per stat (crit chance 0 to 1, cooldown reduction max 0.6, attack speed min 0.2).

```gdscript
class_name StatBlock extends Node
enum Stat { MAX_HP, ATTACK, DEFENSE, MOVE_SPEED, ATTACK_SPEED, DODGE_COOLDOWN,
            CRIT_CHANCE, CRIT_DAMAGE, ABILITY_POWER, COOLDOWN_REDUCTION, LUCK }
signal stat_changed(stat: Stat, value: float)

@export var base: Dictionary          # Stat -> float, filled from CharacterData/ClassData/EnemyData

func get_value(stat: Stat) -> float
func add_modifier(stat: Stat, flat: float, percent: float, source: StringName) -> int   # returns handle
func remove_modifier(handle: int) -> void
func remove_source(source: StringName) -> void      # all modifiers from one relic/node/status
func snapshot() -> Dictionary                        # Stat -> value, for Hollow You and debug
```

Base values are never written after `_ready` except by `set_base(stat, value)` used only during spawn setup. MAX_HP changes keep the current HP ratio.

### Damage formula

Single function, `Damage.compute(attacker: StatBlock, target: StatBlock, hit: HitInfo) -> int`, used by every hit in the game:

```
raw        = hit.base_damage * (attacker.ATTACK / 100.0) * hit.ability_power_scale(attacker.ABILITY_POWER)
crit       = roll(attacker.CRIT_CHANCE + hit.bonus_crit_chance)   # forced true when target has MARK
crit_mult  = 1.5 + attacker.CRIT_DAMAGE if crit else 1.0
status_mult= 1.0 (+0.25 Kindling on BURN) (+1.0 Permafrost on FREEZE, once) (+UNRAVEL stacks * 0.1)
defense    = target.DEFENSE after armor shred
mitigation = 100.0 / (100.0 + max(defense, 0))
final      = round(raw * crit_mult * status_mult * hit.multiplier * mitigation)
```

Rolls use the host's `RandomNumberGenerator` seeded per run for reproducibility. `hit.multiplier` is where effects like Backstab (+75%), Far Shot (up to +40%), Revenge Pact (x3) land; they are composed multiplicatively by the caller. Minimum 1 damage on a connecting hit.

### Status effects

`StatusEffects` component on every damageable entity.

| Status | Element | Stacking | Behavior |
|---|---|---|---|
| `BURN` | Fire | refresh duration, stacks add DPS, max 5 | 4% of max HP per second per stack for 4 s, host ticks on scaled time |
| `CHILL` | Frost | stacks to 5 | -12% move and attack speed per stack. At 5 converts to `FREEZE` |
| `FREEZE` | Frost | single | Immobile 2 s, can't act, next hit double damage once (Permafrost makes it always), then clears all Chill |
| `SHOCK` | Storm | refresh | On apply, chains 30% of trigger damage to up to 2 enemies within 96 px; Lightning Rod +2 chains |
| `TOXIN` | Poison | unlimited stacks, 6 s each | 1.5% max HP per second per stack; healing received -50%; Plague Doctor's Mask disables expiry |
| `MARK` | Shadow | single | Next damaging hit is a guaranteed crit, then consumed |
| `BLEED` | Blood | stacks to 10 | While the target moves, 2% max HP per second per stack |
| `UNRAVEL` | Void | stacks to 5 | +10% all damage taken per stack |

Statuses are applied via `apply_status(status, stacks, source: Node)`. Bosses have `status_resistance` in `BossData` (duration multiplier, Freeze becomes heavy Chill). Players can receive BURN, CHILL, TOXIN, BLEED from enemies and hazards, never MARK/UNRAVEL/FREEZE.

### Element combos

When a status is applied to a target that already has another element's status, the combo fires once, consumes the listed stacks, and emits `Events.combo_triggered`.

| Combo | Trigger | Effect |
|---|---|---|
| `SHATTER` | Fire on Frost or Frost on Fire | Burst 200% of trigger damage in 64 px, consumes Chill/Freeze |
| `CONDUCT` | Storm on a `wet` target (standing in water tile or Drowned enemy) | Shock spreads to every enemy touching the connected water area |
| `BLIGHT_EXPLOSION` | Fire on Toxin | Explosion 40% per Toxin stack, consumes Toxin |
| `HEMORRHAGE` | Shadow (Mark) on Bleed | Bleed ticks crit for 4 s |
| `SUPERCONDUCT` | Frost on Storm or Storm on Frost | -30% Defense for 8 s |
| `COLLAPSE` | Void on any other status | Pull enemies within 128 px to the target |

Reactive skill node (+40%) and Elementalist synergy (x2) multiply combo damage. Mage Arcane Flow listens to `combo_triggered`.

### Scaling constants

`Scaling` static class: `enemy_hp_mult(biome_index) = 1.12 ** (biome_index - 1)`, same for damage; `enemies_per_room(floor)`, `elite_chance(floor)`; elite base `+100% HP`; co-op HP multiplier comes from `NetworkManager`.

## Interfaces provided

- `StatBlock`, `Stat` enum, `Damage.compute()`, `HitInfo` (defined in combat-core but its damage-relevant fields are read here: `base_damage`, `element`, `multiplier`, `bonus_crit_chance`, `is_heavy`, `from_behind`, `tags`). Until W2-A1 lands, `scripts/components/hit_data.gd` (`HitData`) is the payload `Damage.compute` reads; decision 2026-10-21 (Dev A and Dev B): `HitInfo` replaces `HitData`, see SPEC-combat-core "HitInfo". `HitData` is renamed, not kept beside it.
- `StatusEffects`: `apply_status()`, `has(status)`, `stacks(status)`, `clear(status)`, `clear_all()`, signals `status_applied(status, stacks)`, `status_expired(status)`.
- `Element` enum: `NONE, FIRE, FROST, STORM, SHADOW, POISON, EARTH, BLOOD, VOID`. Earth has no status; it is a school for abilities only.
- `Combo` enum and `Scaling`.

## Interfaces consumed

- `foundation`: `ContentData`.
- `time-manager`: scaled ticking for enemy-side statuses.
- `effect-system` (week 4): emits through `Events`.

## Data model

No `.tres` content. Constants in `scripts/components/status_effects.gd` and `scripts/scaling.gd`, all `const`.

## Multiplayer ownership

All computation on the host. `StatusEffects` stacks are replicated by the entity's `StateSync` so clients can render icons and tints. Modifier lists are host-only; the HUD reads `get_value()` from the local player's replicated snapshot (the host sends the 11 values in `StateSync`).

## Testing

- Unit `test_stat_block.gd`: flat then percent ordering, handles, `remove_source`, clamps, MAX_HP ratio preservation.
- Unit `test_damage.gd`: formula table against hand-computed values, Mark forcing crit, mitigation at 0 / 50 / 100 defense, minimum 1.
- Unit `test_status_effects.gd`: every row of the status table, Chill to Freeze conversion, Toxin healing penalty, Bleed only while moving.
- Unit `test_combos.gd`: every combo row triggers once and consumes; no combo when same element reapplied; Elementalist and Reactive multipliers.
- Golden file `tests/unit/damage_table.json` so balance changes are explicit diffs.

## Success criteria

- [ ] No script outside `StatBlock` writes a base stat (CI grep for `.base[` outside the component).
- [ ] All 7 statuses and 6 combos implemented and covered by tests.
- [ ] Damage golden file reviewed by both developers in week 4.
- [ ] Statuses visible on clients (tint and icon) within one sync tick.

## Open questions

- Exact per-stack numbers above are starting values; balance pass in week 12 updates this table and the golden file together.
