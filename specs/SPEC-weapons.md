# Spec: weapons

| | |
|---|---|
| Module id | `weapons` |
| Owner | Dev A |
| Weeks | 2 (WeaponData, WeaponController, Pickaxe, Crossbow), 7 (10 weapons, weapon skills, Anvil rooms, mutations for those 10), 9 (all 19), 11 (all 120 mutations, Leviathan's Tooth) |
| Design doc | section 7, section 4.2 (affinities, starting weapons rule), section 13 (Blacksmith), section 14 (Armory, Dual Wielder, Weapon Master) |
| Depends on | `combat-core`, `effect-system` |
| Depended on by | `classes-characters` (affinity), `town` (Blacksmith), `bosses` (Hollow You, Leviathan reward), `ui-hud` |

## Objective

20 weapons across 5 types (19 main + the secret Leviathan's Tooth), each with a light combo, a heavy attack, and a weapon skill that fires on heavy-after-perfect-dodge, plus 120 mutations offered at Anvil rooms. Weapons are data plus per-weapon attack scenes; mutations are `Effect`s.

## Scope

### Weapon list (locked, design doc section 7)

| Type | Weapons | Signature summary |
|---|---|---|
| Blades | Pickaxe, Longsword, Twin Daggers, Grave Scythe | ground crack line; spinning pull slash; 5th hit Mark + teleport skill; soul orbs |
| Heavy | Sledgehammer, Greataxe, Rust Anchor | shockwave ring; continuous spin; throw and yank |
| Ranged | Crossbow, Shortbow, Hand Cannon, Throwing Knives | piercing charged bolt; arrow rain at cursor; recoil dash shotgun; stick and recall |
| Magic | Lantern Staff, Spore Tome, Tide Orb, Blood Grimoire | charged beam + light bonus; growing toxic clouds; water puddles + wave; HP cost spells |
| Exotic | Chain Whip, Drill Gauntlets, Saw Boomerang, Reaper's Chain | tip triple damage; drill through, shred armor; bouncing saw; wide chain-scythe arcs, heavy hooks and pulls an enemy, kills drop souls |
| Secret | Leviathan's Tooth | from The Leviathan; design is Dev A's call, must have light, heavy, skill, 6 mutations |

Unlock state: Pickaxe, Crossbow, Lantern Staff unlocked at start. Class unlock grants Twin Daggers (Rogue), Hand Cannon (Engineer), Grave Scythe (Necromancer), Longsword (Lightbearer). Everything else bought at the Blacksmith (`town`) or found as a rare drop in the pit (`run-economy` loot table, 2% on legendary chests). Pickaxe always selectable by any class.

### WeaponData

```gdscript
class_name WeaponData extends ContentData
enum Type { BLADE, HEAVY, RANGED, MAGIC, EXOTIC }
@export var type: Type
@export var description: String
@export var icon: Texture2D
@export var light_combo: Array[AttackSpec]       # 2 to 4 steps
@export var heavy: AttackSpec
@export var heavy_charge_seconds: float = 0.8
@export var charge_move_factor: float = 0.3       # share of move speed while holding a heavy (combat v2 C3)
@export var weapon_skill: PackedScene             # WeaponSkill node, instanced on equip
@export var weapon_skill_cooldown: float = 6.0
@export var mutations: Array[MutationData]        # exactly 6
@export var move_speed_while_attacking: float     # 0.5 light default, type-specific
@export var unlock_cost_gold: int                 # Blacksmith
@export var unlocked_at_start: bool
@export var attack_scene: PackedScene             # the per-weapon node that implements attacks
```

`AttackSpec` (Resource): `animation`, `active_frames`, `hitbox_shape`, `base_damage`, `knockback`, `element`, `statuses`, `is_projectile`, `projectile: ProjectileSpec`, `hit_stop_frames`, `sfx`. Combat v2 adds `poise_damage` (light 10, finisher 20, heavy 30, a heavy adds 30 x charge on top), `combo_cancel_at` (fraction of recovery, default 0.4) and `dodge_cancel_at` (fraction of recovery, default 0.0, the end of active). Hit-stop frames come from the one tier table in `CombatFeedbackConstants`, not from the spec.

### WeaponController

Node on the player under `WeaponPivot`. Holds 2 `WeaponData` slots, instances the active weapon's `attack_scene` (a `WeaponAttack` subclass with `light(step)`, `heavy(charge)`, `skill()`), handles swap with 0.2 s lockout, applies affinity bonuses from `ClassData` by tagging `HitInfo` (`"affinity"`) so class effects can react. Weapon damage tiers from Blacksmith add percent to weapon `base_damage`.

Weapon skill rule: `attack_heavy` pressed while `Player.is_perfect_dodge_window()` and skill cooldown ready triggers `skill()` and consumes the window; cooldown 6 s (Weapon Master node +10% damage per rank, not cooldown). If on cooldown, a normal heavy happens.

### Per-weapon mechanics that need engine support

- Charged attacks (Crossbow, Lantern Staff, Sledgehammer): `heavy(charge)` scales damage and size.
- Hold attacks (Greataxe spin, Shortbow rain, Drill Gauntlets): `heavy` enters a `Channel` state while held; `WeaponAttack.channel_tick(delta)`.
- Thrown-and-recall (Rust Anchor, Throwing Knives, Saw Boomerang): `Projectile` with `return_to_owner`, sticking (`stick_to_wall`), recall path through enemies.
- Hand Cannon recoil: applies an impulse to the player opposite the aim; usable as a dash (no i-frames).
- Blood Grimoire: `heavy` costs HP via `Health.apply_damage` with `self_inflicted` tag, bypassing i-frames and not triggering on_damaged relics.
- Tide Orb puddles: spawns `WaterTile` areas that set `wet` on enemies for Conduct.
- Lantern Staff light: a `PointLight2D` cone; enemies inside have the `lit` flag (+bonus damage; Ivy passive uses the same flag).
- Chain Whip tip: hitbox split into shaft and tip, tip hits tagged `tip` for triple damage.
- Twin Daggers skill: teleport behind nearest Marked enemy.
- Grave Scythe souls: on kill spawns `SoulOrb` pickup (heal 3%, +5% damage 5 s); Necromancer affinity makes every kill drop one.
- Reaper's Chain (added 2026-10-18, Necromancer affinity, may be adjusted by the team): light combo is wide 180-degree arcs at mid-long range with a `tip` segment like Chain Whip; heavy throws the blade, hooks the first enemy hit, and pulls it to the player (reuses Rust Anchor's yank path, enemy-to-player direction only); kills drop `SoulOrb` like Grave Scythe. Weapon skill: spin the chain in a full circle pulling every hooked enemy inward.
- Blood Grimoire has no class affinity (changed 2026-10-18); it remains a Magic weapon bought at the Blacksmith.

### Mutations

`MutationData extends ContentData`: `weapon: WeaponData`, `description`, `effect_script` (extends `Effect`, has access to the player's `WeaponController` and the weapon's attack node), `icon`. Exactly 6 per weapon, 20 x 6 = 120. The 6 examples in design doc section 7 are mandatory names (Thunderhead, Phantom Pair, Wrecking Ball, Grapeshot, Twin Saws, Reaper's Harvest); the remaining 114 are authored by Dev A in weeks 7, 9, 11 and listed in `specs/content/mutations.md` as they are designed so both devs and Claude Code have the canonical list.

Anvil rooms: `ANVIL` populator spawns an `Anvil` interactable; offers 1 of 3 mutations for the *current* weapon not already applied (Armory node +1 choice). A weapon can hold any number of mutations within a run; they are lost at run end. Mutations are `Effect`s attached with `source = MutationData`, so proc caps apply.

### Class affinity hooks

`ClassData.affinity_weapon_ids` and `affinity_effect_script`; `WeaponController` emits `affinity_active_changed(bool)` on equip so the class effect (Warrior faster heavy charge, Ranger +1 pierce, Mage double element, Rogue backstab crit, Necromancer soul drops, Engineer Scrap rate, Lightbearer ally heal) attaches or detaches. Class effects are owned by `classes-characters`.

## Interfaces provided

`WeaponData`, `AttackSpec`, `MutationData`, `WeaponController` (`equip(slot, data)`, `swap()`, `active: WeaponData`, `slots`, `mutations_of(slot)`, `skill_cooldown_fraction()`), `WeaponAttack` base, `Anvil`, `SoulOrb`, `WaterTile`, `lit` flag convention, build snapshot `weapons_of(player)` for Hollow You. Events: `heavy_attack_released`, `weapon_swapped`, `mutation_applied`, `projectile_fired`.

## Interfaces consumed

- `combat-core`: `AttackController` states, `Hitbox`, `Projectile`, `HitInfo`.
- `effect-system`: `Effect`, `EffectHost`.
- `player-controller`: perfect dodge window, `WeaponPivot`, facing.
- `floor-generation`: `ANVIL` populator.
- `town`: Blacksmith purchase writes `profile.weapons_unlocked`, `weapon_damage_tiers`.

## Data model

`data/weapons/<id>.tres`, `scenes/player/weapons/<id>.tscn` + `.gd`, `data/mutations/<weapon_id>/<mutation_id>.tres` + `scripts/effects/mutations/<weapon_id>/<mutation_id>.gd`.

## Multiplayer ownership

Attack intent from the input-owning client; hitboxes, damage, projectile spawn, skill cooldown, mutation attach: host. Clients play attack animations immediately on input. Swap is a `request_swap_weapon` validated by host (slot index only).

Sync: host-authoritative, client-predicted animation.

## Testing

- Data-driven `test_weapon_data.gd`: 20 weapons, each with light combo 2 to 4, heavy, skill scene, exactly 6 mutations, type set, attack scene instantiates; mutation ids unique; 120 total.
- Unit `test_weapon_controller.gd`: swap lockout, skill only in perfect window and off cooldown, affinity signal on equip.
- Harness `test_mutation_triggers.gd`: one case per mutation (120 by week 11) asserting its documented effect.
- Integration: Anvil offers 3 distinct unapplied mutations for the active weapon; Armory adds a 4th.
- Manual: feel pass per weapon on the Training Grounds dummies (DPS readout) each content week.
- Two-instance: client swaps, attacks with each weapon type, uses a weapon skill; host results visible on both.

## Success criteria

- [ ] Week 2: Pickaxe and Crossbow with light, heavy, swap.
- [ ] Week 7: 10 weapons with skills, Anvil rooms, 60 mutations.
- [ ] Week 9: all 19 main weapons.
- [ ] Week 11: Leviathan's Tooth, 120 mutations, all with harness tests.
- [ ] Every weapon has a distinct feel per the "Feel" column; checked in weekly playtest notes.

## Open questions

- Leviathan's Tooth design (Dev A, before week 11). Recorded in `specs/content/mutations.md` with its 6 mutations.
- Reaper's Chain mechanics above are a first pass from 2026-10-18; the team may adjust before week 9. Its 6 mutations go in `specs/content/mutations.md` with the others.
