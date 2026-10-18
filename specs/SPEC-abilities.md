# Spec: abilities

| | |
|---|---|
| Module id | `abilities` |
| Owner | Dev A |
| Weeks | 5 (AbilityData, controller, Rune Stones, Rune rooms, 10 abilities, ultimates framework + Wren's Cave-In), 9 (all 30 abilities, all 4 character ultimates), 11 (alternate ultimates, Spore Bloom) |
| Design doc | section 8, section 14 (Third Rune, Rune Finder, Ult Charge, Alt Ultimates, Archmage), relics 38 to 42 |
| Depends on | `effect-system`, `combat-core`, `stats-status` |
| Depended on by | `classes-characters` (ultimates per character, Mage passive), `relics` (ability relics read controller), `ui-hud`, `town` (Rune Library), `bosses` (Echo enemy copies abilities, Hollow You) |

## Objective

30 abilities in 9 schools found as Rune Stones, slotted on Q / R / V, upgradable to rank 3 by duplicates, swappable at Shrines, plus the ultimate meter and 8 ultimates.

## Scope

### Ability list (locked, design doc section 8)

| School | Abilities |
|---|---|
| Fire | Meteor Call, Flame Dash, Inferno Ring |
| Frost | Glacier Spike, Frozen Clone, Blizzard |
| Storm | Chain Lightning, Static Field, Thunder Step |
| Shadow | Shadow Clones, Vanish, Umbral Grasp |
| Poison | Toxic Cloud, Plague Swarm, Acid Rain |
| Earth | Boulder Roll, Stone Skin, Fault Line |
| Blood | Blood Pact, Crimson Leech, Hemoburst |
| Void | Black Hole, Rift Walk, Unmake |
| Utility | Grapple Hook, Turret Drop, Mine Field, Decoy Lantern, Smoke Bomb, Barrier Dome |

Week 5 ten: Meteor Call, Flame Dash, Glacier Spike, Chain Lightning, Thunder Step, Shadow Clones, Toxic Cloud, Stone Skin, Black Hole, Barrier Dome (covers every targeting type and the co-op dome).

### AbilityData

```gdscript
class_name AbilityData extends ContentData
enum School { FIRE, FROST, STORM, SHADOW, POISON, EARTH, BLOOD, VOID, UTILITY }
enum Targeting { SELF, CURSOR_POINT, CURSOR_DIRECTION, NEAREST_ENEMY, SCREEN }
@export var school: School
@export var element: Element
@export var targeting: Targeting
@export var cooldown: float
@export var charges: int = 1
@export var base_damage: float
@export var ranks: Array[AbilityRank]    # 3 entries: rank 1, 2, 3 values (damage mult, size mult, duration, extra)
@export var cast_scene: PackedScene      # the node that performs the ability
@export var description: String
@export var icon: Texture2D
@export var is_ultimate: bool
@export var hp_cost_percent: float       # Blood Pact, Infinity Loop path
```

### AbilityController

On the player. 2 slots (3 with Third Rune node). `ability_1/2/3` press: if the slot has an ability off cooldown with a charge, aim by `targeting`, spawn `cast_scene` on the host with `rank`, start cooldown `cooldown * (1 - COOLDOWN_REDUCTION)`, emit `ability_cast`. Charges: Overcharger +1. Archmage 20% no cooldown; Echo Rune 25% double cast; Rune Battery -0.5 s on kill; Mage Arcane Flow -1 s on combo; Infinity Loop no cooldown but 10% HP. Ability power scales damage: `base_damage * ability_power_scale`.

Rank up: picking a duplicate Rune Stone of a held ability raises rank to max 3; duplicates at rank 3 are converted to 25 gold. Shrine swap: `AbilitySwapStation` in Shrine rooms lets the player swap a slot for a stored rune (runes picked beyond slots are stored, 3 max).

Rune Library (`town`): a chosen ability slotted at run start at rank 1.

### Rune Stones

`RUNE` room populator spawns 1 of 3 Rune Stone pickups (choose one; the others vanish). Rune Finder node raises `RUNE` room chance. Rune Stones also drop from shops and rarely elites.

### Ultimates

`UltimateController`: meter 0 to 100 charged by damage dealt (0.5 per 1% of an enemy's max HP) and damage taken (2 per 1% of own max HP), Ult Charge node +10%/rank, Spite Totem x3 on taken. `ultimate` press at 100 casts the character's ultimate (or selected alternate) and resets. Ultimate is an `AbilityData` with `is_ultimate`.

| Ultimate | Owner | Base effect |
|---|---|---|
| Cave-In (Wren) | character | ceiling collapses on all enemies in the room: heavy damage, stun |
| Foreman's Fury (Brann) | character | giant for 10 s: +100% size and damage, knockback immunity |
| Sunrise (Ivy) | character | blinding light: stun all 3 s, enemies take double damage 6 s |
| Thousand Cuts (Kestrel) | character | dash through every enemy on screen, hit each, end at cursor |
| Pit's Embrace | alternate (Abyss tree) | tentacles from floor grab and damage in a wide area |
| Echo Storm | alternate | replays the player's last 5 s of attacks as ghost copies |
| Last Light | alternate | revive all downed teammates, heal everyone 50% |
| Spore Bloom | alternate (Mushroom Hermit) | giant mushrooms erupt across room, launch and poison |

Class twist: each `ClassData` has an `ultimate_twist_script` (`Effect`) that listens to `ultimate_used` and adds its flavor (Necromancer: Cave-In crushed enemies rise as minions; Mage: element applied; Engineer: Scrap refund; Warrior: Rage fill; Ranger: companion pounce; Rogue: Mark all; Lightbearer: heal pulse). Twists are owned by `classes-characters`.

### Cast scenes

`AbilityCast` base node: `setup(player, data, rank, aim_point, aim_dir)`, runs on host, spawns hitboxes/projectiles/zones via spawners, tags `HitInfo` with the ability id and `"ability"`, applies `element` statuses (Mage affinity doubles stacks), frees itself. Zones (Static Field, Toxic Cloud, Barrier Dome) are `Zone` areas with tick damage or blocking. Clones and companions use `FriendlyUnit` from `enemies-ai`. Unmake clears all enemy projectiles through `ProjectilePool.clear_team(ENEMY)`. Barrier Dome blocks enemy `Projectile`s crossing its edge and lets allies in. Rift Walk teleports to any walkable point in view; Thunder Step to cursor with a strike; Grapple Hook pulls self to walls or enemies to self. Fault Line instantly kills enemies with `EnemyData.size == SMALL`.

### Echo enemy (Biome 6)

Copies the player's last cast ability: `AbilityController.last_cast` is exposed for `biomes`/`enemies-ai`.

## Interfaces provided

`AbilityData`, `AbilityRank`, `AbilityController` (`slots`, `stored`, `cooldown_fraction(slot)`, `charges(slot)`, `last_cast`, `request_cast(slot)`), `UltimateController` (`meter`, `request_ultimate()`), `AbilityCast`, `Zone`, `RuneStone` pickup, `AbilitySwapStation`, build snapshot `abilities_of(player)`. Events: `ability_cast`, `ultimate_used`.

## Interfaces consumed

- `effect-system`: `Effect` for passive ability relics to hook, `spawn`, proc tagging.
- `combat-core`: `Hitbox`, `Projectile`, `ProjectilePool`, `HitInfo`.
- `stats-status`: `ABILITY_POWER`, `COOLDOWN_REDUCTION`, statuses.
- `player-controller`: `aim_position`, `AbilityCast` state.
- `enemies-ai`: `FriendlyUnit` for clones, turret, decoy.
- `floor-generation`: `RUNE` populator, Shrine room shared with `relics`.
- `progression-trees`: Third Rune, Alt Ultimates unlock flags.

## Data model

`data/abilities/<school>/<id>.tres`, `scenes/abilities/<id>.tscn` + `.gd`. Ultimates under `data/abilities/ultimates/`.

## Multiplayer ownership

Cast request from client (`request_cast(slot, aim_point)`), host validates cooldown and charges, spawns the cast, broadcasts `ability_cast` for VFX/SFX. Ultimate meter host-owned, replicated in `RunPlayerState`. Barrier Dome and Last Light affect allies on the host.

Sync: host-authoritative.

## Testing

- Data-driven `test_ability_data.gd`: 30 abilities + 8 ultimates, 3 ranks each, school and targeting set, cast scene instantiates.
- Unit `test_ability_controller.gd`: cooldown math with CDR, charges, rank-up by duplicate, rank 3 duplicate to gold, stored runes cap, Third Rune slot, Archmage/Echo Rune/Infinity Loop interactions through the harness.
- Unit `test_ultimate_meter.gd`: charge rates, nodes, reset.
- Harness `test_ability_casts.gd`: each ability spawns the documented thing with a fake aim (38 cases by week 11).
- Two-instance: client casts each targeting type; client sees host's Barrier Dome block projectiles; Last Light revives client.

## Success criteria

- [ ] Week 5: 10 abilities, Rune rooms, rank-up, ultimate meter, Cave-In.
- [ ] Week 9: all 30, all 4 character ultimates with class twists.
- [ ] Week 11: alternate ultimates and Spore Bloom.
- [ ] Every ability has a GPUParticles2D VFX per element by week 12 (`art-audio`).

## Open questions

- Rank 2 and 3 scaling per ability is Dev A's call in week 5/9, recorded in the `.tres` and in `specs/content/abilities.md`.
