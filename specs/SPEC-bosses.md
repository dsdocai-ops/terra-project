# Spec: bosses

| | |
|---|---|
| Module id | `bosses` |
| Owner | Dev A |
| Weeks | 6 (BossData, phase framework, arena, Boomer Jack, The Foreman), 8 (Sporelord Twins, Bloom Mother, Gem Collector, Prism Queen), 9 (Captain Saltbones, Tide King, Iron Maiden, Old Vulkar), 10 (The Hollow You, The Sinkhole), 11 (Rat King, Mushroom Hermit, Leviathan, The Watcher) |
| Design doc | section 10 (bosses, secret bosses), section 11 (final boss phase 3 story choice), section 15 (Deep Mode extra attacks, Heat 4th phase) |
| Depends on | `enemies-ai`, `biomes`, `classes-characters` |
| Depended on by | `story-dialogue` (boss_defeated flags), `run-economy` (rope after boss, payouts), `endgame`, `art-audio` (themes) |

## Objective

16 bosses: 6 mini-bosses on floor 3, 5 biome bosses on floor 5, the 3-phase final boss on floor 30, and 4 secret bosses. Every boss is a phase state machine with telegraphed attacks and a readable arena, built on the enemy framework.

## Scope

### Boss list (locked, design doc section 10)

| Biome | Mini-boss (floor 3) | Boss (floor 5) |
|---|---|---|
| 1 | Boomer Jack: dynamite tosses, drops mines | The Foreman: ground slams, summons Rock Ticks, cave-ins at 50% |
| 2 | The Sporelord Twins: kill both within 10 s or the other revives | The Bloom Mother: rooted, spore fill, exposed core between attacks |
| 3 | The Gem Collector: crystal mech, steals gold on hit, drops it all on death | The Prism Queen: 3 mirror copies, only real takes damage, bouncing beams |
| 4 | Captain Saltbones: undead pirate with cannon crew | The Tide King: throne fight, water level rises and falls changing walkable area |
| 5 | The Iron Maiden: hammer / saw / flamethrower modes | Old Vulkar, the First Smith: forges weapons mid-fight and uses them |
| 6 | The Hollow You: dark copy with your current build | The Sinkhole: 3 phases (maw: bosses 1 to 3 attacks; heart: bosses 4 and 5 attacks, arena collapses; true form: story choice then final duel) |

Secret: The Rat King (Biome 1 hidden wall, Legendary relic + Rat companion cosmetic), The Mushroom Hermit (Biome 2 Golden Spore room, unlocks Spore Bloom), The Leviathan (Biome 4 fishing, Leviathan's Tooth), The Watcher (town well after any ending, true ending). 6 + 5 + 1 + 4 = 16.

### BossData

```gdscript
class_name BossData extends ContentData
@export var enemy: EnemyData                 # base stats, sprites
@export var arena: PackedScene               # arena room scene with spawn points, hazards, camera bounds
@export var phases: Array[BossPhase]         # ordered; each has hp_threshold, attack set, modifiers, intro
@export var status_resistance: float         # duration multiplier, Freeze downgraded to Chill
@export var stagger_windows: Array[String]   # attack ids after which the boss is staggerable
@export var is_mini: bool
@export var is_secret: bool
@export var echo_shards: int                 # 10 mini, 20 biome
@export var music: AudioStream               # unique for biome and final bosses, shared mini theme
@export var intro_dialogue: StringName       # optional, story-dialogue id
@export var deep_mode_phase: BossPhase       # extra attacks for Deep Mode
@export var heat_phase: BossPhase            # 4th phase for the heat modifier
@export var cosmetic_unlock: StringName
```

`BossPhase`: `hp_threshold` (enter at or below), `attacks: Array[AttackPattern]`, `attack_selector` (weighted / sequence / reactive), `adds: Array[EnemyData]`, `arena_event: StringName` (cave-in, water rise, collapse, mirror split), `on_enter` script hook.

### Framework

`Boss extends Enemy` with `BossStateMachine`: `Intro` (camera focus, name banner, 1.5 s, players can move), `Phase(n)` with `Attack(pattern)`, `Transition` (invulnerable, arena event), `Stagger` (after listed attacks, 2 s vulnerable, bonus damage), `Death` (slow-mo hit-stop 10 frames, loot burst, rope spawn for biome bosses, `boss_defeated`). Bosses use the same `AttackPattern`/`Telegraph` contract; windups >= 0.4 s. Health bar with phase markers in `ui-hud`.

Co-op scaling: HP via `NetworkManager.enemy_hp_multiplier()`, plus one extra add per extra player where the phase spawns adds. Aggro spreads across players; some attacks target a random living player, shown by a marker.

### Boss-specific systems

- Sporelord Twins: shared `TwinLink` component; death of one starts a 10 s revive timer unless the other dies.
- Bloom Mother: `WeakPoint` child hurtbox exposed between attacks; body takes 20% damage otherwise.
- Gem Collector: on hit steals `min(10% gold, 50)` into his pool; drops pool on death as pickups.
- Prism Queen: spawns 2 `Mirror` copies (no hurtbox damage) that swap positions with her on a pattern; beams `reflectable`.
- Tide King: arena `WaterLevel` controller toggles walkable tiles in rings; telegraphed by rising bubbles 1.5 s.
- Iron Maiden: `mode` state swaps attack set and sprite every 20 s or at thresholds.
- Old Vulkar: forges a weapon from the list of the players' equipped weapons (uses the `WeaponData` attack specs scaled as enemy attacks) every phase; weapon drops as a temporary pickup at death (cosmetic only).
- The Hollow You: at spawn, snapshots the *triggering* player's build via `relics_of`, `abilities_of`, `weapons_of`, `class_state_of`, `StatBlock.snapshot()`; attaches a subset of relic effects translated to enemy-side `Effect`s (only the ones flagged `hollow_safe` in `RelicData`, others become stat boosts), uses the player's weapon attack specs and 2 abilities. In co-op copies the player with the highest damage dealt.
- The Sinkhole: phase 1 attack set drawn from Foreman, Bloom Mother, Prism Queen patterns; phase 2 from Tide King and Vulkar with `arena_collapse` removing floor rings; phase 3 calls `StoryManager.final_choice()` which plays the chosen ending's dialogue, then a final duel with a small unique attack set (Seal: relics sacrificed as the duel starts; Keeper: player gains dark buffs; True: miners' ghosts assist).
- Rat King: swarm summoner, hidden wall needs Wren or Treasure Map or any explosion to reveal (wall is a breakable with `secret` flag).
- Mushroom Hermit: non-hostile until given the Golden Spore (rare drop in Biome 2 from Glow Moths); fight on acceptance.
- Leviathan: `FishingSpot` interactable in Drowned City requires the Fishing Rod (rare chest drop in Biome 4); fishing minigame is a timing press; success summons the boss in a flooded arena.
- The Watcher: town well interactable after any `ending.*`; fight in a special arena; drops `secret.watcher_defeated` enabling the true ending next victory.

### Rewards

Mini-boss: 10 Echo Shards, 3 ore, legendary-leaning chest. Biome boss: 20 Echo Shards, 6 ore, rope, Ascension choice trigger after Biome 1 and Tier 2 after Biome 4 (`classes-characters`), `boss_defeated` flag for story, cosmetic unlock. Final: ending sequence, Deep Mode unlock.

## Interfaces provided

`BossData`, `BossPhase`, `Boss`, `BossStateMachine`, `WeakPoint`, `TwinLink`, `WaterLevel`, arena scenes, `FishingSpot`, `boss_defeated` emission, `BossHealthBarData` for HUD (name, HP, phase markers).

## Interfaces consumed

- `enemies-ai`: `Enemy`, `EnemyData`, `SpawnDirector.spawn_one`, `FriendlyUnit` for miners' ghosts.
- `biomes`: arena tiles, hazards, `BiomeData.mini_boss` / `boss`.
- `classes-characters`, `relics`, `abilities`, `weapons`: build snapshot APIs for Hollow You; `WeaponData` attack specs for Vulkar.
- `story-dialogue`: `final_choice`, intro dialogue, flags.
- `run-economy`: payouts, rope spawn, Gem Collector gold.
- `time-manager`: death slow-mo via `hit_stop` and `slow_enemies`.
- `ui-hud`: boss bar, name banner.

## Data model

`data/bosses/<id>.tres`, `data/bosses/attacks/<id>/*.tres`, `scenes/bosses/<id>.tscn` + states, `scenes/bosses/arenas/<id>.tscn`.

## Multiplayer ownership

Boss AI, phases, arena events: host. Phase index and arena event state replicated so clients play the right visuals. Hollow You snapshot taken on the host from host-side state.

Sync: host-authoritative.

## Testing

- Data-driven `test_boss_data.gd`: 16 bosses, 6 mini, 5 biome, 1 final, 4 secret; every phase has >= 2 attacks with windup >= 0.4 s; thresholds descending; arena instantiates; every biome's `mini_boss` and `boss` set.
- Unit `test_boss_phases.gd`: threshold transitions, stagger windows, twin revive timer, Gem Collector steal math, water level ring toggling.
- Integration `test_hollow_you.gd`: snapshot of a fake build produces a boss with matching stats and allowed effects.
- Manual: every boss beaten solo and in 2-player co-op in its content week; no attack without telegraph (observed); fairness check per design pillar 3.

## Success criteria

- [ ] Week 6: Boomer Jack and The Foreman with phases, cave-in event, rope after Foreman, Ascension trigger.
- [ ] Week 8 and 9: 8 more bosses, each with its signature mechanic working.
- [ ] Week 10: The Hollow You mirrors a real build; The Sinkhole 3 phases with all 3 endings reachable.
- [ ] Week 11: 4 secret bosses with their triggers and rewards.
- [ ] Every boss has a unique theme hook (`art-audio`) and a readable arena.

## Open questions

- Fishing minigame scope: single timing press. Expand only if week 11 has slack.
