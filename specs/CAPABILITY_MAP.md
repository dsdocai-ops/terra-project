# Capability Map: Sinkhole

Source of truth for *what* the game is: [SINKHOLE_SPEC.md](../SINKHOLE_SPEC.md) (design doc v3, locked; only change from v3 is Godot 4.7 instead of 4.4).
This map decomposes that design into modules with stable ids. Every module spec (`specs/SPEC-<module-id>.md`), task, branch, and PR names a module id from this table. Ids are kebab-case, chosen once and treated as the stable product contract.

Cross-cutting engineering rules (stack, commands, structure, code style, testing, boundaries, git) live in [SPEC-project.md](SPEC-project.md).

## Modules

Owner is the developer lane from design doc section 19: **Dev A and Dev B are designated lane owners** (see [SPEC-project.md, Ownership](SPEC-project.md#ownership)). Weeks are from design doc section 20; a module can span multiple weeks, and the weekly build order is the canonical milestone sequence.

| Module id | Responsibility | Depends on | Owner | Weeks | Design doc |
|---|---|---|---|---|---|
| `foundation` | Project settings (960x540, canvas_items, nearest, integer scale, Compatibility), Input Map, folder skeleton, autoload stubs (GameState, Events, TimeManager, etc.), isometric 64x32 tile conventions, common helper layout | — | Both | 1 | 1 |
| `networking` | NetworkManager: ENet host/join, peer tracking, player spawn via MultiplayerSpawner, MultiplayerSynchronizer conventions, RPC conventions, host-authority rules, seed broadcast, enemy sync, scene ownership rules | foundation | B | 1, 3 | 9 |
| `player-controller` | 8-direction isometric movement, dodge roll with i-frames and perfect-dodge window, player state machine, 8-dir sprite handling, Camera2D (smoothing, shake, co-op framing), downed logic | foundation, networking | A | 1, 2, 3 | 8 |
| `time-manager` | TimeManager autoload: enemy-side time multiplier, per-entity override, hit-stop by animation pause, rewind hook. Never `Engine.time_scale` | foundation | B | 2, 4 | 12 |
| `stats-status` | StatBlock (base + flat + percent, 11 stats), damage and crit formula, StatusEffects component, 7 statuses, 6 element combos, depth scaling constants | foundation | B | 2, 4 | 6, 13 |
| `combat-core` | Health, Hitbox, Hurtbox components; light combo, heavy charge, weapon swap input; hit-stun, knockback, post-hit i-frames; hit feedback (flash, shake, hit-stop, pooled damage numbers) | stats-status, player-controller | A | 2 | 6 |
| `enemies-ai` | EnemyData, enemy state machine, telegraph system, AStarGrid2D pathfinding, projectile pooling, elites (outline, +100% HP, 6 affixes), spawn director, 60-unit performance budget | networking, combat-core | A | 2, 4 | 8 |
| `floor-generation` | Seeded grid generation onto TileMapLayer, 8 to 14 rooms with corridors and loops, 15 room types placed, door locking, floor modifiers, hazard placement hooks, 500-seed reachability checks | foundation, networking | A | 3, 6, 11 | 15 |
| `run-economy` | GameState run data; run start/end; rope points and all-living-players vote; death vs extract rules per currency; Ascension timing on Map Room shortcuts; Gold, Ore, Echo Shard, Clarity currency rules | floor-generation, save-system | B | 3, 5 | 8, 18 |
| `save-system` | SaveManager: `user://save.json`, `save_version` and migrations, what persists, when it saves, per-player progress in co-op | foundation | B | 5 | 18 |
| `effect-system` | Events bus signal set; effect script base class listening to `on_hit`, `on_kill`, `on_dodge`, etc.; tag system; proc depth cap (3) and no self-retrigger; host-only execution with deterministic ordering | stats-status, networking, time-manager | B | 4 | 10 |
| `relics` | RelicData, 70 passive + 10 active + 8 cursed, rarity, tags, 12 synergies with HUD display, Shrine choose-1-of-3, Cursed Altars, active relic slots C and B, Relic Vault codex data | effect-system, run-economy | B | 4, 8, 11 | 10, 17 |
| `weapons` | WeaponData for 20 weapons, light combo / heavy / weapon skill on perfect-dodge window, 2-slot carry, affinity hooks, MutationData for 120 mutations, Anvil room flow | combat-core, effect-system | A | 2, 7, 9, 11 | 11 |
| `abilities` | AbilityData, 30 abilities in 9 schools, Rune Stone pickups, slots Q/R/V, 3 upgrade ranks via duplicates, Shrine swap, ultimate charge meter, 8 ultimates | combat-core, stats-status | A | 5, 9 | 11 |
| `classes-characters` | ClassData for 7 classes (role, affinity, passive, class skill, alternate skill at mastery 5), AscensionData 14 Tier 1 + 14 Tier 2, class pair bonuses, CharacterData for 4 characters | abilities, weapons, effect-system, story-dialogue | A | 5, 7, 9, 11 | 11, 15 |
| `story-dialogue` | StoryManager and flags; DialogueData loaded from JSON; dialogue UI with portraits and conditions; 8 NPC dialogue sets that change with progress; 3 acts; 3 endings; 40+ lore pages | save-system, run-economy, enemies-ai | B | 6, 10 | 16 |
| `town` | Town scene with 11 buildings at 3 visible levels, pit edge shrinking with story, NPC placement, Blacksmith, Alchemist and potions, Map Room shortcuts, Shrine of Echoes entry, Tavern lobby and dive flow | run-economy, save-system | B | 5, 10 | 16 |
| `progression-trees` | Skill tree: 5 branches, 38 nodes, Echo Shard costs scaled to 25 to 40 runs, node graph UI, daily free respec; class trees and mastery 1 to 10 UI and data; Abyss unlock after completion | save-system, classes-characters | B | 7, 11 | 17 |
| `biomes` | BiomeData for 6 biomes; 24 base enemies + 3 Heart-only variants; per-biome hazards; palette, PointLight2D and CanvasModulate lighting; per-biome mini-bosses | enemies-ai, floor-generation | A | 6, 8, 9, 10 | 13 |
| `bosses` | BossData, boss phase state machine, 6 mini-bosses, 5 biome bosses, The Sinkhole 3-phase final boss, 4 secret bosses and their triggers, The Hollow You build mirror, arena scenes | enemies-ai, biomes, classes-characters | A | 6, 8, 10, 11 | 14 |
| `ui-hud` | Main menu, HUD (HP bars, potions, abilities, ult, active relic, floor, currencies, relic icons, synergies, minimap), pause, run/inventory screen, choice popups, rope vote prompt, death and ending flow | run-economy, story-dialogue | B | 2, 4, 5, 12 | 14 |
| `art-audio` | Claude-made asset pipeline (Python/PIL generators, locked biome palettes, 8-direction sheets with every facing drawn (decision 2026-10-21), import presets, naming, `CREDITS.md` for sourced CC0/CC-BY assets), GPUParticles2D library per element, AudioManager (music crossfade, SFX), synthesized SFX, per-biome tracks and boss themes, weekly asset review sheets, week 12 polish | foundation | Both (Claude produces, lanes review) | 1 to 12 | 20 |
| `debug-tools` | Debug console (spawn enemy, give relic by name, give gold, skip floor, unlock all skills, set seed, god mode), simulated latency, 60-unit perf test scene, two-instance launcher | foundation, networking | B | 2, 12 | 21 |
| `endgame` | Deep Mode (new boss attacks, Keeper dark version), 10 stackable Heat levels with Echo Shard multipliers, Daily Dive seeded run and leaderboard, 50+ achievements and cosmetic unlocks, final release polish | bosses, story-dialogue, progression-trees, save-system | B | 11, 12 | 17 |

## Dependency direction

Arrows point one way, no cycles. Checked chains:

- `foundation` feeds `networking`, `time-manager`, `stats-status`, `save-system`, `art-audio`
- `networking` feeds `player-controller`, then `combat-core`, then `enemies-ai`, then `biomes`, then `bosses`
- `stats-status` + `networking` + `time-manager` feed `effect-system`, which feeds `relics`, `weapons`, `abilities`, `progression-trees`
- `floor-generation` + `save-system` feed `run-economy`, which feeds `relics`, `story-dialogue`, `town`, `ui-hud`
- `abilities` + `weapons` + `story-dialogue` feed `classes-characters`, which feeds `progression-trees`, `bosses`
- `bosses` + `story-dialogue` + `progression-trees` feed `endgame`

Interfaces live at the boundary and are defined in the **provider's** spec. Examples: the Events signal list is in `SPEC-effect-system.md`; StatBlock API is in `SPEC-stats-status.md`; host-authoritative net sync rules are in `SPEC-networking.md`.

## Cross-owner seams

Places where the design doc's lane split cuts through one feature. The owning module is listed; the other lane contributes via PR into it.

| Feature | Owning module | Contributor |
|---|---|---|
| Room types: placement and doors | `floor-generation` (A) | Each room's interactable comes from its system: Shrine from `relics` (B), Anvil from `weapons` (A), Rune Room from `abilities` (A), Shop from `town` (B) |
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
Week 12  art-audio (polish list and sign-off; real assets land weekly from week 2), ui-hud (settings, achievements UI), networking (co-op bug fix), balancing, external playtests
```

Each week ends with a playable build tagged `week-N` on `main`.

## Scope rule

Nothing in the design doc is cut by this map. The cut list (design doc section 21) is executed only by explicit human decision, in the listed order, and recorded here with a date when it happens.

## Status

Map approved for the current milestone. The active plan was written for the current milestone and tracked in `tasks/plan.md` and `tasks/todo.md`. Status is `planned` once the plan covers the module, `in progress` once implementation has started, and `done` when the module gate passes.

| Module | Spec | Status |
|---|---|---|
| `foundation` | [SPEC-foundation.md](SPEC-foundation.md) | planned |
| `networking` | [SPEC-networking.md](SPEC-networking.md) | planned |
| `player-controller` | [SPEC-player-controller.md](SPEC-player-controller.md) | planned |
| `time-manager` | [SPEC-time-manager.md](SPEC-time-manager.md) | planned |
| `stats-status` | [SPEC-stats-status.md](SPEC-stats-status.md) | planned |
| `combat-core` | [SPEC-combat-core.md](SPEC-combat-core.md) | planned |
| `enemies-ai` | [SPEC-enemies-ai.md](SPEC-enemies-ai.md) | planned |
| `floor-generation` | [SPEC-floor-generation.md](SPEC-floor-generation.md) | planned |
| `run-economy` | [SPEC-run-economy.md](SPEC-run-economy.md) | planned |
| `save-system` | [SPEC-save-system.md](SPEC-save-system.md) | planned |
| `effect-system` | [SPEC-effect-system.md](SPEC-effect-system.md) | planned |
| `relics` | [SPEC-relics.md](SPEC-relics.md) | planned |
| `weapons` | [SPEC-weapons.md](SPEC-weapons.md) | planned |
| `abilities` | [SPEC-abilities.md](SPEC-abilities.md) | planned |
| `classes-characters` | [SPEC-classes-characters.md](SPEC-classes-characters.md) | planned |
| `story-dialogue` | [SPEC-story-dialogue.md](SPEC-story-dialogue.md) | planned |
| `town` | [SPEC-town.md](SPEC-town.md) | planned |
| `progression-trees` | [SPEC-progression-trees.md](SPEC-progression-trees.md) | planned |
| `biomes` | [SPEC-biomes.md](SPEC-biomes.md) | planned |
| `bosses` | [SPEC-bosses.md](SPEC-bosses.md) | planned |
| `ui-hud` | [SPEC-ui-hud.md](SPEC-ui-hud.md) | planned |
| `art-audio` | [SPEC-art-audio.md](SPEC-art-audio.md) | planned |
| `debug-tools` | [SPEC-debug-tools.md](SPEC-debug-tools.md) | planned |
| `endgame` | [SPEC-endgame.md](SPEC-endgame.md) | planned |

Supporting: [SPEC-project.md](SPEC-project.md), [WEEKLY.md](WEEKLY.md), [content/README.md](content/README.md).
