# Implementation Plan: Sinkhole, 12 weeks

## Overview

Build the full Sinkhole design (SINKHOLE_SPEC.md v3, Godot 4.7.2) in 12 weeks with two developers: Alex (Dev A, The Pit) and Daniel (Dev B, Surface + Systems). Each week ends with a playable build tagged `week-N` on `main` that meets the "Done when" line in design doc section 20. Nothing from the design doc is cut; the cut list (section 21) is only executed by explicit human decision recorded in `specs/CAPABILITY_MAP.md`.

This plan covers all 12 weeks. Week 1 is broken into implementable tasks with acceptance criteria and verification in `tasks/todo.md`. Weeks 2 to 12 are listed as lane-split tasks with brief acceptance lines; each is expanded into full task detail at the start of its week (same format as week 1) so the detail reflects what actually shipped the week before.

Sources: `specs/CAPABILITY_MAP.md` (modules, dependencies, build order), `specs/SPEC-project.md` (engineering contract), `specs/SPEC-<module>.md` (scope per week), design doc section 20 (milestones).

## Architecture decisions (from the specs, restated for planning)

- **Host-authoritative ENet co-op from week 1.** Inputs up via `InputSync`, state down via `StateSync`, spawns via `MultiplayerSpawner`, requests as `request_*` RPCs. Solo is a host with one peer. Every stateful script documents "Sync:". No single-player code path exists to retrofit later.
- **Composition over inheritance.** `Health`, `Hitbox`, `Hurtbox`, `StatusEffects`, `StatBlock`, `StateMachine` are child nodes shared by players, enemies, bosses, minions.
- **One effect system.** Relics, mutations, synergies, class passives, Ascensions, skill nodes, heat modifiers are all `Effect` subclasses on an `EffectHost`, listening to the `Events` bus, with a proc depth cap of 3 and no self-retrigger. Content weeks are data files plus small scripts on top of this.
- **Data-driven content.** `.tres` Resources for every content type, JSON for dialogue and lore. Data-driven tests check counts, ids, required fields, and that every synergy tag appears on at least 4 relics.
- **TimeManager, never `Engine.time_scale`.** Enemy-side time multiplier so time effects never freeze another player.
- **Deterministic floors.** Seeded `RandomNumberGenerator` per floor, every peer generates locally, host hash asserts equality, 500-seed soak in CI.
- **Strict typing, GUT, CI on every PR.** `untyped_declaration` is an error; headless import + GUT gate every merge.
- **960x540 base, 64x32 isometric tiles, Compatibility renderer, nearest filter, integer scaling.**
- **Ownership lanes.** Dev A owns Pit modules, Dev B owns Surface + Systems modules; cross-owner seams listed in the capability map are PRs into the owning module with the owner's review.

## Dependency graph (modules)

```
foundation
 ├─ networking ─────────┐
 ├─ time-manager ───┐   │
 ├─ stats-status ─┐ │   │
 ├─ save-system   │ │   │
 └─ art-audio     │ │   │
                  ▼ ▼   ▼
player-controller ◄─────┘            (needs networking)
   │
combat-core ◄── stats-status, time-manager
   │
enemies-ai ◄── networking
   │           floor-generation ◄── foundation, networking
   │                │
   │           run-economy ◄── floor-generation, networking, stats-status, save-system
   │                │
   │   effect-system ◄── stats-status, networking, time-manager
   │      ├─ relics ◄── run-economy
   │      ├─ weapons ◄── combat-core
   │      ├─ abilities ◄── combat-core, stats-status
   │      └─ progression-trees ◄── save-system, classes-characters
   │
   │   story-dialogue ◄── save-system, run-economy, enemies-ai
   │      └─ town ◄── run-economy, save-system
   │
   │   classes-characters ◄── abilities, weapons, effect-system, story-dialogue
   │
biomes ◄── enemies-ai, floor-generation
   │
bosses ◄── enemies-ai, biomes, classes-characters
   │
endgame ◄── bosses, story-dialogue, progression-trees, save-system

ui-hud, debug-tools: cross-cutting, grow every week
```

No cycles. Build order follows weeks in the capability map.

## Phases (one per week)

Every week has the same checkpoint shape, from `specs/WEEKLY.md`: CI green on `main`, two-machine co-op session, perf scene numbers (from week 4), classes and Ascensions tested solo and co-op, time effects tested in co-op (from week 4), new content trigger-tested and co-op checked, external playtest notes (from week 9), then tag `week-N`.

| Week | Phase | Dev A (Alex) | Dev B (Daniel) | Done when (design doc section 20) |
|---|---|---|---|---|
| 1 | Foundation + networking | Iso helper, TileSet, world scene, player scene, state machine, movement, camera | project settings, Input Map, autoload stubs, GUT, CI, main scene + launch args, NetworkManager, spawner, sync, launcher | Isometric TileSet, Y-sort, player movement, camera. 2 players connect and see each other move |
| 2 | Combat core | Health/Hitbox/Hurtbox, attacks, hit reactions, feedback, telegraphs, projectiles, dodge + perfect dodge, enemy base + 3 enemies, Pickaxe + Crossbow | TimeManager, StatBlock + damage formula, debug console, HUD v0, enemy sync | Light/heavy, dodge, swap, components, 3 enemies with telegraphs, all synced |
| 3 | Floor generation | generator, 6 room types, doors, painting, astar, 500-seed test, basic room fill, downed/revive, Interactable | GameState/RunState, rope room + run end, seed sync + hash, downed sync | Procedural floors, locking rooms, seed sync, downed/revive |
| 4 | Effect system + loot | elites + affixes, spawn director, pooling, perf budget, Shrine room placement | Events bus, Effect/EffectHost, proc caps, harness, statuses + combos, 20 relics + Shrine + active slot, currencies + pickups + chests, choice popup + HUD icons + minimap, time stop/slow/rewind, perf scene + net_lag + overlay | Events, StatBlock, TimeManager, statuses, combos, 20 relics, Shrine, elites, drops |
| 5 | Abilities + classes v1 + extraction | ability system + 10 abilities + Rune rooms + ultimates + Cave-In, ClassData/CharacterData, Warrior/Ranger/Mage, Wren, affinity hooks | SaveManager, votes, death/extract rules, banking, Map Room, shops, potions, town v1 + RunSetup, main menu, pause, inventory, vote prompt, death screen | 10 abilities, Rune rooms, ultimates, 3 classes, rope votes, death rules, town v1, save/load |
| 6 | Biome 1 + story base | Biome 1 enemies + hazards + lighting, boss framework, Boomer Jack, The Foreman, Shop/Rest/Rune/Anvil/Lore placement | dialogue system + UI + flags, 6 NPCs Act 1, lore pickup, town NPCs + Alchemist + Map Room, Shop/Rest populators; both: first real art + Biome 1 track + SFX set | All Biome 1 enemies, both bosses, dialogue, first NPCs, Shop, Rest |
| 7 | Skill tree + weapons + Ascensions | 10 weapons + skills, Anvil + 60 mutations, T1 Ascensions x3, Class XP, Ascension choice, EscortNpc | 38 skill nodes data + effects + graph UI + respec + Abyss gate, rescue missions + Cage | Full skill tree, 10 weapons, Anvil, Ascensions x3, Class XP, rescue system |
| 8 | Biomes 2 and 3 | Fungal Caverns + Crystal Hollows enemies/hazards, Sporelord Twins, Bloom Mother, Gem Collector, Prism Queen, Lost Lanterns | relics to 40, 12 synergies + tracker + HUD, Bomb Bag + Healing Totem, codex data | Biomes 2 and 3 complete, 40 relics, synergies |
| 9 | Biomes 4 and 5 | Drowned City + Ember Forge, 4 bosses, all 19 weapons, all 30 abilities, 4 character ultimates, Rogue/Necro/Engineer/Lightbearer T1, chars 2 to 4, minions/turrets/companions | class miner rescue data, Act 2 beats, external playtest round 1, co-op soak | Biomes 4 and 5, 19 weapons, 30 abilities, chars 2 to 4, 4 classes |
| 10 | Biome 6 + final boss + story | The Heart + corrupted pool + 3 new enemies, The Hollow You, The Sinkhole 3 phases | all NPC dialogue, Act 3, 3 endings + scenes, 40+ lore, codex UI, 12 character events, victory screen | Biome 6, Hollow You, Sinkhole, 3 endings, all dialogue, lore |
| 11 | Content and endgame | 14 T2 Ascensions, class trees data, alt class skills, pair bonuses, Leviathan's Tooth, 120 mutations, alt ultimates + Spore Bloom, Challenge/Secret/Cursed Altar rooms + all modifiers, 4 secret bosses | relics to 88 + Cursed Altars + second slot + Relic Vault, class tree UI + mastery, all 11 buildings x3, Rescue Camp, Bounty Board, Wardrobe, Deep Mode, Heat, Daily Dive, achievements, codex % | Everything in the week 11 line of section 20 |
| 12 | Polish | balancing (damage golden, weapons feel), co-op bug fix, final enemy/boss art | settings + rebinding, achievements UI, release export without debug tools, tree/town economy tuning; both: final art/audio/VFX, 4-player 30-floor run, external playtests | Final pass, balancing, co-op fixes, achievements, settings, external playtests |

## Week 1 in detail

Goal: two instances connect, both players spawn and move on an isometric floor with a following camera, CI green, every autoload and component name that later weeks compile against exists.

Dependency order within the week:

```
W1-B1 project settings + folders ──► W1-B2 Input Map
                                 ──► W1-B3 autoload stubs + ContentData ──► W1-B7 NetworkManager
                                 ──► W1-B4 GUT + test skeleton ──► W1-B5 CI
                                 ──► W1-B6 main scene + launch args
W1-A1 Iso helper (independent)
W1-A2 TileSet + placeholder generator ──► W1-A3 world scene
W1-A3 ──► W1-A4 player scene skeleton ──► W1-A5 StateMachine + Idle/Move ──► W1-A6 movement + facing
W1-A3 ──► W1-A7 camera
W1-A4 + W1-B7 ──► W1-B8 spawner ──► W1-B9 sync config ──► W1-AB1 prediction + smoke
W1-A6 + W1-A7 + W1-B9 ──► W1-AB2 weekly checkpoint + tag
```

Parallel from day 1: Alex on A1 to A3 while Daniel does B1 to B5. Contract that lets them not block each other: `player.tscn` node layout (A4) and `NetworkManager` API (B7) are both fixed by the specs, so each side codes against the spec shape before the other side's file exists.

Shared-file rule for week 1: Daniel owns `project.godot` entirely this week (settings, Input Map, autoloads, main scene). Alex sets nothing in `project.godot`; if the TileSet or world scene needs a setting, Alex asks and Daniel adds it.

Full task text in `tasks/todo.md` under Week 1.

## Verification checkpoints

- **Week 1 day 2:** project imports with zero warnings, folder tree complete, CI runs on an empty-content PR, `Iso` tests pass. Both developers pull and confirm the editor opens clean.
- **Week 1 day 4:** `--host` and `--join=127.0.0.1` connect; both players spawn under `World/Players`; placeholder sprites visible on both screens.
- **Week 1 end:** movement synced with prediction, camera follows, 8-direction facing, `test_iso`, `test_player_facing`, `test_scenes_load`, `test_data_loads`, `test_network_manager` pass, WEEKLY.md entry written, tag `week-1`.
- **Every later week:** the WEEKLY.md checklist, then tag. From week 4, perf numbers recorded. From week 9, external playtest notes.
- **Mid-project gate (end of week 6):** Biome 1 playable end to end in co-op with relics, abilities, 3 classes, town, save. If this gate slips by more than 3 days, the team meets to decide whether any cut-list item is invoked; the decision is recorded in the capability map.

## Parallelization

- Lanes are parallel by design. Within a lane, tasks are sequential along the dependency arrows above.
- Cross-lane seams (capability map) are PRs into the owning module: Alex's floor-generation room populators are registered by Daniel's relics/run-economy; Daniel's `effect-system` harness is used by Alex's weapons/abilities tests; Daniel's `progression-trees` UI consumes Alex's class tree data.
- Content weeks (8 to 11) parallelize further: Claude Code writes `.tres` and effect scripts in batches per module; the data-driven tests catch count and id mistakes.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Client prediction + host correction feels rubber-bandy at real latency | High (design pillar 5) | Week 1 ships prediction for the local player only; weekly two-machine test with `net_lag` from week 4; accept dodge i-frame lag as documented |
| Effect system performance with 4 players x 30 relics | High | Proc depth cap, per-frame spawn cap, perf scene in week 4 before relic count grows; `Effect extends Node` profiled in week 4 |
| Compatibility renderer light and particle limits | Medium | Cap 16 lights / 128 emitters, pooled; faked shadows; perf scene measures weekly |
| Floor determinism drift between peers | High | Single RNG per floor, no engine randomness, hash assertion with host fallback, 500-seed soak |
| Content volume (88 relics, 120 mutations, 30 abilities, 27 enemies, 16 bosses) | High | Everything is data + small script on finished systems; harness tests make each item a 10-minute task; weeks 8 to 11 are content-only by design |
| Two developers editing the same scene | Medium | Ownership lanes, `.tscn` rule, week 1 `project.godot` owned by Daniel, Ask-first list |
| GitHub Actions Godot 4.7.2 availability | Low | Fall back to downloading the official headless zip by URL |
| Design doc edits by one developer desync the specs (happened once: Reaper's Chain) | Medium | Design doc changes go through a PR that also touches the affected specs; data-driven tests assert counts |
| Week 6 gate slips | High | Explicit mid-project gate; cut list order is pre-agreed in the design doc |
| Art time in week 12 | Medium | Placeholder generator from week 1 keeps builds playable; priority list in SPEC-art-audio |

## Open questions

- GUT exact release and the Actions setup action for 4.7.2 (resolved in W1-B4 / W1-B5, written back to SPEC-foundation).
- `AStarGrid2D` vs `NavigationAgent2D` for enemies (week 2, SPEC-enemies-ai).
- Art source (hand-drawn, commissioned, CC0) by week 6 (SPEC-art-audio).
- Latency simulation implementation (week 4, SPEC-debug-tools).
- Online Daily Dive leaderboard endpoint (week 11, local is the commitment).

## Task list

Tracked in `tasks/todo.md` (default target; no external tracker designated). Task ids are `W<week>-<lane><n>` with lane `A` (Alex), `B` (Daniel), `AB` (both), and double as branch names: `feat/<module-id>-w1-a6-movement`.
