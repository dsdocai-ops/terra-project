# Spec: classes-characters

| | |
|---|---|
| Module id | `classes-characters` |
| Owner | Dev A |
| Weeks | 5 (ClassData, CharacterData, select screen data, Warrior/Ranger/Mage passives + class skills, Wren), 7 (Tier 1 Ascensions for 3 classes, Class XP hooks), 9 (Rogue, Necromancer, Engineer, Lightbearer with T1; Brann, Ivy, Kestrel), 11 (Tier 2 Ascensions all, class trees data, alternate class skills, pair bonuses) |
| Design doc | sections 4.1, 4.2, 4.3, 8 (ultimates per character), 9.5 (Scrap, Souls) |
| Depends on | `abilities`, `weapons`, `effect-system`, `story-dialogue` |
| Depended on by | `progression-trees` (class trees UI), `bosses` (Hollow You), `town` (select screen in Tavern/Shrine), `ui-hud` |

## Objective

7 classes and 4 characters, any combination (28 combos). Each class: role, weapon affinity, passive, class skill on Shift, alternate skill at mastery 5, 2 Tier 1 Ascensions each evolving into a Tier 2 form, a class tree, and pair bonuses. Each character: passive, ultimate, unlock condition, story thread. All implemented as `Effect`s and data on top of the shared systems.

## Scope

### Classes (locked, design doc 4.2)

| Class | Role | Affinity | Passive | Class skill | Ascensions T1 (T2) |
|---|---|---|---|---|---|
| Warrior | melee bruiser / tank | Blades, Heavy: heavy charge 25% faster | Rage: build on deal/take, full = cleave arc + 20% less damage | Battle Cry: taunt, armor, knockback small | Berserker (Blood Frenzy), Guardian (Bulwark) |
| Ranger | ranged DPS | Ranged: +1 pierce | Far Shot: up to +40% by distance | Tumble Volley: backflip + arrow fan | Beastmaster (Pack Leader), Sharpshooter (Deadeye) |
| Mage | elemental AoE | Magic: elements applied twice | Arcane Flow: combos cut cooldowns 1 s | Blink: teleport + last-element explosion | Pyromancer (Phoenix), Stormcaller (Eye of the Storm) |
| Rogue | burst assassin | Twin Daggers, Throwing Knives, Chain Whip: behind always crits | Backstab: +75% from behind + Mark | Smoke Step: dash + invisible 2 s | Assassin (Death Mark), Trickster (Master Thief) |
| Necromancer | summoner | Grave Scythe, Blood Grimoire, Spore Tome: kills always drop souls | Soul Harvest: 5 souls = skeleton (max 3) | Corpse Burst: detonate minion/corpse, minion returns in 10 s | Gravelord (Lord of the Dead), Plague Lord (Pestilence) |
| Engineer | zone control | Hand Cannon, Drill Gauntlets, Saw Boomerang, Crossbow: Scrap faster | Scrap: hits and kills generate | Deploy: turret (max 2), use on turret to upgrade | Mechanist (War Machine), Demolitionist (Chain Reaction) |
| Lightbearer | support / healer | Lantern Staff, Sledgehammer, Longsword: hits heal nearby allies | Radiance: aura heals allies, burns enemies | Sanctuary: zone -40% damage, faster revive | Paladin (Avatar of Light), Oracle (Foresight) |

Every Ascension effect text in design doc 4.2 is implemented literally (e.g. Phoenix: rise from death once per run; Foresight: once per room cancel a hit that would down an ally; War Machine: allies ride the mech; Master Thief: stolen buffs last the floor, chests can drop double).

Unlocks: Warrior, Ranger, Mage at start. Rogue/Engineer/Necromancer/Lightbearer on `rescue.sly_nettie` / `rescue.cogsworth` / `rescue.mortimer` / `rescue.elian`. Class unlock also unlocks its free weapon (`weapons`).

### Characters (locked, design doc 4.1)

| Character | Passive | Ultimate | Unlock flag |
|---|---|---|---|
| Wren | ore +25%, break marked walls (secret rooms) | Cave-In | default |
| Brann | armor stacks while still, lost when moving | Foreman's Fury | `story.foreman_defeated` |
| Ivy | lights dark rooms, enemies in her light +15% damage | Sunrise | `char.ivy_lanterns_5` (5 Lost Lanterns in Fungal Caverns, placed by `biomes`) |
| Kestrel | 30% dodge instant reset | Thousand Cuts | `story.reached_biome_4` |

### Data

```gdscript
class_name ClassData extends ContentData
@export var role: String
@export var affinity_weapon_ids: Array[StringName]
@export var affinity_effect: GDScript           # Effect, attached while affinity weapon equipped
@export var passive_effect: GDScript            # Effect, always attached
@export var class_skill: PackedScene            # ClassSkill node (Shift), own cooldown
@export var class_skill_alt: PackedScene        # unlocked at mastery 5, chosen in select screen
@export var ascensions: Array[AscensionData]    # exactly 2
@export var class_tree: Array[ClassTreeNodeData]
@export var ultimate_twist: GDScript            # Effect listening to ultimate_used
@export var base_stats: Dictionary              # Stat -> float
@export var unlock_flag: StringName             # empty = start
@export var free_weapon_id: StringName
@export var resource_name: StringName           # "scrap", "souls", or empty

class_name AscensionData extends ContentData
@export var class_id: StringName
@export var tier1_effect: GDScript
@export var tier2_effect: GDScript              # attached in addition at tier 2
@export var tier2_name: String
@export var description_t1: String
@export var description_t2: String
@export var replaces_class_skill: PackedScene   # Stormcaller Blink lightning, Mechanist etc. optional

class_name CharacterData extends ContentData
@export var passive_effect: GDScript
@export var ultimate: AbilityData
@export var unlock_flag: StringName
@export var portrait: Texture2D
@export var sprite_frames: SpriteFrames
@export var story_events: Array[StringName]     # 3 dialogue ids

class_name ClassPairData extends ContentData
@export var class_a: StringName
@export var class_b: StringName
@export var effect: GDScript                    # attached to both players when both classes present
```

Class trees: `ClassTreeNodeData` (`class_id`, `cost_class_xp`, `max_ranks`, `effect`, `requires`, `mastery_required`). Data authored here (highlights from design doc 4.2 become 6 to 8 nodes per class), UI and purchasing in `progression-trees`.

### Runtime

- `ClassController` on the player: attaches `passive_effect`, manages affinity attach/detach from `WeaponController.affinity_active_changed`, instances the chosen class skill on Shift with its own cooldown (`class_skill_used` event), tracks class resource (Rage 0 to 100, Scrap, Souls) exposed for HUD, attaches Ascension effects when chosen, attaches class tree node effects from the profile at run start.
- Ascension choice: after the first biome boss (`boss_defeated` for floor 5 kill, or run start if `RunState.start_floor > 5`), host offers both Ascensions; `request_choose_ascension(index)`; duplicates across players rejected (`networking` rule). Tier 2 attaches after the Biome 4 boss (or at start if `start_floor > 20`). `ascension_chosen` event.
- Mastery: `ClassXP` thresholds for mastery 1 to 10 (`[0, 100, 250, 500, 900, 1400, 2000, 2800, 3800, 5000]`); mastery 5 unlocks alternate skill, 10 unlocks cosmetics (`town` Wardrobe). Class XP earn amounts are in `run-economy`; this module emits `class_xp_gained` into `RunPlayerState`.
- Pair bonuses: at run start and on player join, for every pair of distinct classes present, attach the `ClassPairData` effect to both: Warrior+Lightbearer, Mage+Engineer, Rogue+Ranger, Necromancer+Warrior.
- Minions and turrets: Necromancer skeletons, Gravelord typed minions, bone golem merge, Plague zombies, Engineer turrets, mech suit, Ranger wolf and hawk, Trickster decoys all use `FriendlyUnit` from `enemies-ai`; mech suit is a player state (`Mech`) with its own attacks for 12 s. Ally riding: ally becomes a child of the mech while inside.
- Select screen data: `SelectionState {character_id, class_id, weapon_ids[2], class_skill_variant}` validated by host against unlocks; UI in `ui-hud`.

## Interfaces provided

`ClassData`, `AscensionData`, `CharacterData`, `ClassPairData`, `ClassTreeNodeData`, `ClassController` (`class_resource`, `ascension`, `tier`, `request_choose_ascension`), `SelectionState`, build snapshot `class_state_of(player)` for Hollow You, mastery thresholds. Events: `class_skill_used`, `ascension_chosen`.

## Interfaces consumed

- `effect-system`, `abilities` (ultimates, `UltimateController`), `weapons` (affinity signal, free weapon unlock), `story-dialogue` (unlock flags), `enemies-ai` (`FriendlyUnit`), `stats-status`, `player-controller` (states, dodge reset), `time-manager` (Deadeye), `networking` (duplicate Ascension rule), `save-system` (classes, characters_unlocked).

## Data model

`data/classes/<id>.tres`, `data/ascensions/<class>_<id>.tres`, `data/characters/<id>.tres`, `data/class_trees/<class>/<node>.tres`, `data/class_pairs/<a>_<b>.tres`; effects under `scripts/effects/classes/<class>/`.

## Multiplayer ownership

All class logic on the host. Class resource and Ascension replicated in `RunPlayerState`. Class skill is a `request_class_skill(aim)` RPC. Selection validated by host before spawn.

Sync: host-authoritative.

## Testing

- Data-driven `test_class_data.gd`: 7 classes with 2 Ascensions each (14 T1 + 14 T2), 4 characters with ultimates and 3 story events, 4 pair bonuses, every class tree has >= 6 nodes, unlock flags declared in `flags.json`.
- Harness: one case per passive, affinity, class skill, Ascension T1, T2, pair bonus, character passive, class tree node (expected ~90 cases by week 11).
- Unit `test_ascension_timing.gd`: choice after floor 5 boss, at start when start_floor > 5, tier 2 after floor 20 boss or start_floor > 20; duplicate rejection.
- Unit `test_mastery.gd`: thresholds, alt skill unlock.
- Two-instance: both players choose Ascensions (duplicate rejected), pair bonus attaches, Lightbearer heals client, Engineer turret visible to client, Necromancer minions synced.

## Success criteria

- [ ] Week 5: Warrior, Ranger, Mage playable with passive and class skill; Wren.
- [ ] Week 7: T1 Ascensions for those 3; Class XP flows to mastery.
- [ ] Week 9: all 7 classes with T1; all 4 characters; class unlock via rescues.
- [ ] Week 11: all 14 T2, class trees data, alt skills, 4 pair bonuses.
- [ ] 28 character + class combos selectable when unlocked; every class and Ascension tested solo and co-op (weekly notes).

## Open questions

- Class tree node lists (6 to 8 per class from the design doc highlights) are authored in week 7/11 and listed in `specs/content/class-trees.md`.
