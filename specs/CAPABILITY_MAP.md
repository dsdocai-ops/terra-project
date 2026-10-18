# Capability Map: Sinkhole

Source of truth for *what* the game is: [SINKHOLE_SPEC.md](../SINKHOLE_SPEC.md) (design doc v3, locked; only change from v3 is Godot 4.7 instead of 4.4).
This map decomposes that design into modules with stable ids. Every module spec (`specs/SPEC-<module-id>.md`), task, branch, and PR names a module id from this table. Ids are kebab-case, chosen once, never renamed.

Cross-cutting engineering rules (stack, commands, structure, code style, testing, boundaries, git) live in [SPEC-project.md](SPEC-project.md).

## Modules

Owner is the developer lane from design doc section 19. **Which person is Dev A and which is Dev B is TBD**; fill in [SPEC-project.md, Ownership](SPEC-project.md#ownership) when decided. Weeks are from design doc section 20; a module listed as `4, 8, 11` ships its system in week 4 and its content batches in weeks 8 and 11.

| Module id | Responsibility | Depends on | Owner | Weeks | Design doc |
|---|---|---|---|---|---|
| `foundation` | Project settings (960x540, canvas_items, nearest, integer scale, Compatibility), Input Map, folder skeleton, autoload stubs (GameState, Events, TimeManager, etc.), isometric 64x32 TileSet, Y-sort world root, GUT + CI setup, `--host` / `--join` launch args | none | Both | 1 | 5, 17, 18, 20 |
| `networking` | NetworkManager: ENet host/join, peer tracking, player spawn via MultiplayerSpawner, MultiplayerSynchronizer conventions, RPC conventions, host-authority rules, seed broadcast, enemy HP scaling by player count, ping system | foundation | B | 1, 3, 12 | 12 |
| `player-controller` | 8-direction isometric movement, dodge roll with i-frames and perfect-dodge window, player state machine, 8-dir sprite handling, Camera2D (smoothing, shake, co-op framing), downed state and hold-F revive | foundation, networking | A | 1, 3 | 5, 6, 12 |
| `time-manager` | TimeManager autoload: enemy-side time multiplier, per-entity override, hit-stop by animation pause, rewind hook. Never `Engine.time_scale` | foundation | B | 2, 4 | 12 |
| `stats-status` | StatBlock (base + flat + percent, 11 stats), damage and crit formula, StatusEffects component, 7 statuses, 6 element combos, depth scaling constants | foundation | B | 2, 4 | 6, 9.5 |
| `combat-core` | Health, Hitbox, Hurtbox components; light combo, heavy charge, weapon swap input; hit-stun, knockback, post-hit i-frames; hit feedback (flash, shake, hit-stop, pooled damage numbers); enemy attack contract windup, active, recovery | player-controller, stats-status, time-manager | A | 2 | 6 |
| `enemies-ai` | EnemyData, enemy state machine, telegraph system, AStarGrid2D pathfinding, projectile pooling, elites (outline, +100% HP, 6 affixes), spawn director, 60-unit performance budget | combat-core, networking | A | 2, 4 | 6, 9.5, 23 |
| `floor-generation` | Seeded grid generation onto TileMapLayer, 8 to 14 rooms with corridors and loops, 15 room types placed, door locking, floor modifiers, hazard placement hooks, 500-seed reachability test | foundation, networking | A | 3, 6, 11 | 10 |
| `run-economy` | GameState run data; run start/end; rope points and all-living-players vote; death vs extract rules per currency; Ascension timing on Map Room shortcuts; Gold, Ore, Echo Shard, Class XP drops and pickups; chests, breakables, mining nodes; Shop rooms and Vesper; shared vs per-player loot | floor-generation, networking, stats-status, save-system | B | 3, 4, 5 | 3, 9.5, 12 |
| `save-system` | SaveManager: `user://save.json`, `save_version` and migrations, what persists, when it saves, per-player progress in co-op | foundation | B | 5 | 18 |
| `effect-system` | Events bus signal set; effect script base class listening to `on_hit`, `on_kill`, `on_dodge`, etc.; tag system; proc depth cap (3) and no self-retrigger; host-only execution with spawner replication; shared by relics, mutations, synergies, class passives, Ascensions, tree nodes | stats-status, networking, time-manager | B | 4 | 18 |
| `relics` | RelicData, 70 passive + 10 active + 8 cursed, rarity, tags, 12 synergies with HUD display, Shrine choose-1-of-3, Cursed Altars, active relic slots C and B, Relic Vault codex data | effect-system, run-economy | B | 4, 8, 11 | 9 |
| `weapons` | WeaponData for 20 weapons (19 + Leviathan's Tooth), light combo / heavy / weapon skill on perfect-dodge window, 2-slot carry, affinity hooks, MutationData for 120 mutations, Anvil rooms, Blacksmith unlock data | combat-core, effect-system | A | 2, 7, 9, 11 | 7 |
| `abilities` | AbilityData, 30 abilities in 9 schools, Rune Stone pickups, slots Q/R/V, 3 upgrade ranks via duplicates, Shrine swap, ultimate charge meter, 8 ultimates (4 character + 3 alternate + Spore Bloom), class twists on ultimates | effect-system, combat-core, stats-status | A | 5, 9 | 8 |
| `classes-characters` | ClassData for 7 classes (role, affinity, passive, class skill, alternate skill at mastery 5), AscensionData 14 Tier 1 + 14 Tier 2, class pair bonuses, CharacterData for 4 characters (passive, ultimate, unlock), pre-run character/class/weapon select, Class XP earn hooks | abilities, weapons, effect-system, story-dialogue | A | 5, 7, 9, 11 | 4, 8 |
| `story-dialogue` | StoryManager and flags; DialogueData loaded from JSON; dialogue UI with portraits and conditions; 8 NPC dialogue sets that change with progress; 3 acts; 3 endings; 40+ lore pages and codex; rescue missions (trapped miner, escort follower, unlock on rope); 3 personal events per character | save-system, run-economy, enemies-ai | B | 6, 7, 10 | 11 |
| `town` | Town scene with 11 buildings at 3 visible levels, pit edge shrinking with story, NPC placement, Blacksmith, Alchemist and potions, Map Room shortcuts, Shrine of Echoes entry, Tavern lobby board, Relic Vault and Rune Library starting picks, Training Grounds DPS dummies, Rescue Camp bonuses, Bounty Board, Wardrobe | run-economy, save-system, story-dialogue | B | 5, 6, 11 | 13 |
| `progression-trees` | Skill tree: 5 branches, 38 nodes, Echo Shard costs scaled to 25 to 40 runs, node graph UI, daily free respec; class trees and mastery 1 to 10 UI and data; Abyss unlock after The Foreman | save-system, effect-system, classes-characters | B | 7, 11 | 14 |
| `biomes` | BiomeData for 6 biomes; 24 base enemies + 3 Heart-only (Veinling, Heart Guard, Echo) + corrupted variants; per-biome hazards; palette, PointLight2D and CanvasModulate lighting; per-biome ore; music hook | enemies-ai, floor-generation | A | 6, 8, 9, 10 | 10, 17 |
| `bosses` | BossData, boss phase state machine, 6 mini-bosses, 5 biome bosses, The Sinkhole 3-phase final boss, 4 secret bosses and their triggers, The Hollow You build mirror, arena scenes | enemies-ai, biomes, classes-characters | A | 6, 8, 9, 10, 11 | 10 |
| `ui-hud` | Main menu, HUD (HP bars, potions, abilities, ult, active relic, floor, currencies, relic icons, synergies, minimap), pause, run/inventory screen, choice popups, rope vote prompt, death and victory screens, settings with rebinding, screen shake toggle | foundation, run-economy, relics, abilities | B | 2, 4, 5, 12 | 16 |
| `art-audio` | Pixel art pipeline (8-dir sheets, import presets, naming), GPUParticles2D library per element, AudioManager (music crossfade, SFX), per-biome tracks and boss themes, final art and audio pass | foundation | Both | 1, 6, 12 | 17 |
| `debug-tools` | Debug console (spawn enemy, give relic by name, give gold, skip floor, unlock all skills, set seed, god mode), simulated latency, 60-unit perf test scene, two-instance launcher | foundation, networking | Both | 2, 4 | 23 |
| `endgame` | Deep Mode (new boss attacks, Keeper dark version), 10 stackable Heat levels with Echo Shard multipliers, Daily Dive seeded run and leaderboard, 50+ achievements and cosmetic unlocks, codex completion tracking | bosses, story-dialogue, progression-trees, save-system | B | 11 | 15 |

## Dependency direction

Arrows point one way, no cycles. Checked chains:

- `foundation` feeds `networking`, `time-manager`, `stats-status`, `save-system`, `art-audio`
- `networking` feeds `player-controller`, then `combat-core`, then `enemies-ai`, then `biomes`, then `bosses`
- `stats-status` + `networking` + `time-manager` feed `effect-system`, which feeds `relics`, `weapons`, `abilities`, `progression-trees`
- `floor-generation` + `save-system` feed `run-economy`, which feeds `relics`, `story-dialogue`, `town`, `ui-hud`
- `abilities` + `weapons` + `story-dialogue` feed `classes-characters`, which feeds `progression-trees`, `bosses`
- `bosses` + `story-dialogue` + `progression-trees` feed `endgame`

Interfaces live at the boundary and are defined in the **provider's** spec. Examples: the Events signal list is in `SPEC-effect-system.md`; StatBlock API is in `SPEC-stats-status.md`; host-authority and RPC rules are in `SPEC-networking.md`; story flag API is in `SPEC-story-dialogue.md`. Consumers reference, never redefine.

## Cross-owner seams

Places where the design doc's lane split cuts through one feature. The owning module is listed; the other lane contributes via PR into it.

| Feature | Owning module | Contributor |
|---|---|---|
| Room types: placement and doors | `floor-generation` (A) | Each room's interactable comes from its system: Shrine from `relics` (B), Anvil from `weapons` (A), Rune Room from `abilities` (A), Shop and Rope from `run-economy` (B), Lore Room from `story-dialogue` (B) |
| Downed and revive | `player-controller` (A) | Vote and run-end rule in `run-economy` (B); Field Medic and Sanctuary effects in `effect-system` (B) |
| Rescue missions | `story-dialogue` (B) | Escort follower AI in `enemies-ai` (A) |
| Class trees and mastery | `progression-trees` (B) owns UI and purchase | Node effects and Class XP earn hooks in `classes-characters` (A) |
| Ultimates | `abilities` (A) | Alternate ultimate unlocks in `progression-trees` (B) |
| Elites | `enemies-ai` (A) | Loot and Echo Shard payout in `run-economy` (B) |
| Hazards | `biomes` (A) | Element interaction (gas + Fire, Storm + water) in `stats-status` (B) |
| The Hollow You | `bosses` (A) | Build snapshot API from `relics`, `abilities`, `weapons` |

## Build order (by week, design doc section 20)

```
Week 1   foundation -> networking, player-controller, art-audio (pipeline only)
Week 2   time-manager, stats-status (StatBlock) -> combat-core -> enemies-ai (3 enemies), weapons (2 starters), debug-tools (console), ui-hud (HUD v0)
Week 3   floor-generation -> run-economy (rope, downed rule), networking (seed sync)
Week 4   effect-system -> relics (20), stats-status (statuses, combos), enemies-ai (elites), run-economy (currencies), ui-hud (choice popups)
Week 5   abilities (10), classes-characters (Warrior, Ranger, Mage), save-system, run-economy (votes, death rules), town (v1), ui-hud (town menus)
Week 6   biomes (Biome 1), bosses (Boomer Jack, The Foreman), story-dialogue (system, first NPCs), town (Shop, Rest hooks)
Week 7   progression-trees (full skill tree), weapons (10, mutations, Anvil), classes-characters (Ascensions T1 x3, Class XP), story-dialogue (rescue missions)
Week 8   biomes (2, 3), bosses (4), relics (40, synergies)
Week 9   biomes (4, 5), bosses (4), weapons (all 19), abilities (all 30), classes-characters (chars 2 to 4, Rogue, Necromancer, Engineer, Lightbearer)
Week 10  biomes (6), bosses (Hollow You, The Sinkhole), story-dialogue (all dialogue, endings, lore)
Week 11  classes-characters (T2, class trees), relics (88, Cursed Altars), weapons (120 mutations), floor-generation (Challenge, Secret rooms), bosses (secret), endgame, town (all buildings)
Week 12  art-audio (final pass), ui-hud (settings, achievements UI), networking (co-op bug fix), balancing, external playtests
```

Each week ends with a playable build tagged `week-N` on `main`.

## Scope rule

Nothing in the design doc is cut by this map. The cut list (design doc section 21) is executed only by explicit human decision, in the listed order, and recorded here with a date when it happens.

## Status

Map approved 2026-10-18. All 24 module specs written 2026-10-18. Status moves to `planned` when `tasks/plan.md` covers the module, `in progress` on first merged PR, `done` when its success criteria are checked.

| Module | Spec | Status |
|---|---|---|
| `foundation` | [SPEC-foundation.md](SPEC-foundation.md) | spec written |
| `networking` | [SPEC-networking.md](SPEC-networking.md) | spec written |
| `player-controller` | [SPEC-player-controller.md](SPEC-player-controller.md) | spec written |
| `time-manager` | [SPEC-time-manager.md](SPEC-time-manager.md) | spec written |
| `stats-status` | [SPEC-stats-status.md](SPEC-stats-status.md) | spec written |
| `combat-core` | [SPEC-combat-core.md](SPEC-combat-core.md) | spec written |
| `enemies-ai` | [SPEC-enemies-ai.md](SPEC-enemies-ai.md) | spec written |
| `floor-generation` | [SPEC-floor-generation.md](SPEC-floor-generation.md) | spec written |
| `run-economy` | [SPEC-run-economy.md](SPEC-run-economy.md) | spec written |
| `save-system` | [SPEC-save-system.md](SPEC-save-system.md) | spec written |
| `effect-system` | [SPEC-effect-system.md](SPEC-effect-system.md) | spec written |
| `relics` | [SPEC-relics.md](SPEC-relics.md) | spec written |
| `weapons` | [SPEC-weapons.md](SPEC-weapons.md) | spec written |
| `abilities` | [SPEC-abilities.md](SPEC-abilities.md) | spec written |
| `classes-characters` | [SPEC-classes-characters.md](SPEC-classes-characters.md) | spec written |
| `story-dialogue` | [SPEC-story-dialogue.md](SPEC-story-dialogue.md) | spec written |
| `town` | [SPEC-town.md](SPEC-town.md) | spec written |
| `progression-trees` | [SPEC-progression-trees.md](SPEC-progression-trees.md) | spec written |
| `biomes` | [SPEC-biomes.md](SPEC-biomes.md) | spec written |
| `bosses` | [SPEC-bosses.md](SPEC-bosses.md) | spec written |
| `ui-hud` | [SPEC-ui-hud.md](SPEC-ui-hud.md) | spec written |
| `art-audio` | [SPEC-art-audio.md](SPEC-art-audio.md) | spec written |
| `debug-tools` | [SPEC-debug-tools.md](SPEC-debug-tools.md) | spec written |
| `endgame` | [SPEC-endgame.md](SPEC-endgame.md) | spec written |

Supporting: [SPEC-project.md](SPEC-project.md), [WEEKLY.md](WEEKLY.md), [content/README.md](content/README.md).
