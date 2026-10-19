# Implementation Plan: Sinkhole, 12 weeks

## Overview

Build the full Sinkhole design (SINKHOLE_SPEC.md v3, Godot 4.7.2) in 12 weeks with a small team. Each week ends with a playable build and a milestone gate. This plan covers all 12 weeks. Week 1 is broken into implementable tasks with acceptance criteria and verification in `tasks/todo.md`. Weeks 2 to 12 are listed as lane-split tasks with brief acceptance criteria and dependencies.

Sources: `specs/CAPABILITY_MAP.md` (modules, dependencies, build order), `specs/SPEC-project.md` (engineering contract), `specs/SPEC-<module>.md` (scope per week), design doc section 20 (milestones and completion criteria).

## Architecture decisions (from the specs, restated for planning)

- **Host-authoritative ENet co-op from week 1.** Inputs up via `InputSync`, state down via `StateSync`, spawns via `MultiplayerSpawner`, requests as `request_*` RPCs. Solo is a host with one peer.
- **Composition over inheritance.** `Health`, `Hitbox`, `Hurtbox`, `StatusEffects`, `StatBlock`, `StateMachine` are child nodes shared by players, enemies, bosses, minions.
- **One effect system.** Relics, mutations, synergies, class passives, Ascensions, skill nodes, heat modifiers are all `Effect` subclasses on an `EffectHost`, listening to the `Events` bus, with deterministic order.
- **Data-driven content.** `.tres` Resources for every content type, JSON for dialogue and lore. Data-driven tests check counts, ids, required fields, and that every synergy tag appears on at least one relic or class.
- **TimeManager, never `Engine.time_scale`.** Enemy-side time multiplier so time effects never freeze another player.
- **Deterministic floors.** Seeded `RandomNumberGenerator` per floor, every peer generates locally, host hash asserts equality, 500-seed soak in CI.
- **Strict typing, GUT, CI on every PR.** `untyped_declaration` is an error; headless import + GUT gate every merge.
- **960x540 base, 64x32 isometric tiles, Compatibility renderer, nearest filter, integer scaling.**
- **Ownership lanes.** Lane A owns Pit modules, Lane B owns Surface + Systems modules; cross-owner seams listed in the capability map are PRs into the owning module with the owner's review.

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

Every week has the same checkpoint shape, from `specs/WEEKLY.md`: CI green on `main`, two-machine co-op session, perf scene numbers (from week 4), classes and Ascensions tested solo and co-op, time effects tested, and content counts validated.

| Week | Phase | Dev A | Dev B | Done when (design doc section 20) |
|---|---|---|---|---|
| 1 | Foundation + networking | Iso helper, TileSet, world scene, player scene, state machine, movement, camera | project settings, Input Map, autoload stubs, GUT, CI, main scene + launch args, networking and sync hook-up | Two instances connect and move locally; project imports cleanly |
| 2 | Combat core | Health/Hitbox/Hurtbox, attacks, hit reactions, feedback, telegraphs, projectiles, dodge + perfect dodge, enemy base + 3 enemies, starting weapons | TimeManager, StatBlock + damage formulas, spawn sync, debug console, HUD v0 | Basic combat loop and 3 enemy types work in co-op |
| 3 | Floor generation | generator, room types, doors, painting, pathfinding, 500-seed tests, downed and revive states | GameState, rope room + end-of-run logic, seed sync, deterministic floor validation | Procedural floors with room logic and co-op rope state |
| 4 | Effect system + loot | elites + affixes, spawn director, perf budget, shrine placement | Events bus, Effect framework, proc caps, statuses + combos, 20 relics, shrine flow, currencies | Relics and effect hooks work in co-op |
| 5 | Abilities + classes v1 + extraction | ability system, class data, Warrior/Ranger/Mage, ultimates | SaveManager, vote rules, town v1, menu flow, run setup | Full town-to-run loop with save and class selection |
| 6 | Biome 1 + story base | Biome 1 enemies + hazards + lighting, boss framework, first bosses | dialogue system + UI + flags, six NPCs, lore + town hooks | The first biome and start of narrative are playable |
| 7 | Skill tree + weapons + Ascensions | 10 weapons, mutations, Ascension flow, class XP | skill tree nodes and UI, rescue data, town and progression flow | Progression systems are functional and testable |
| 8 | Biomes 2 and 3 | Fungal Caverns + Crystal Hollows, bosses, encounter flows | relics to 40, synergies + HUD, co-op soak | Mid-game content is in and passes co-op smoke |
| 9 | Biomes 4 and 5 | Drowned City + Ember Forge, all weapons, all abilities, 4 characters | story dialogue, boss UI, playtest notes, co-op soak | Mid-to-late game content is complete |
| 10 | Biome 6 + final boss + story | The Heart, The Hollow You, final boss phases | all NPC dialogue, endings, lore codex | Full run loop to ending content is functioning |
| 11 | Content and endgame | Tier 2 Ascensions, class trees, 120 mutations, secret content, deep mode setup | relic count, progression screens, town upgrades, final endgame systems | All design counts are represented in data tests |
| 12 | Polish | balance, final art/audio pass, co-op bug fixing | settings, economy tuning, release export, playtests | Final release-ready build and weekly tag |

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

Parallel from day 1: Lane A on A1 to A3 while Lane B does B1 to B5. Contract that lets them not block each other: `player.tscn` node layout (A4) and `NetworkManager` API (B7) are both fixed by the shared spec and verified through smoke tests.

Shared-file rule for week 1: Lane B owns `project.godot` entirely this week (settings, Input Map, autoloads, main scene). Lane A sets nothing in `project.godot`; if the TileSet or world scene needs a project-level setting, it is handled by the platform owner and reviewed before merge.

Full task text in `tasks/todo.md` under Week 1.

## Verification checkpoints

- **Week 1 day 2:** project imports with zero warnings, folder tree complete, CI runs on an empty-content PR, `Iso` tests pass. Both contributors pull and confirm the editor opens clean.
- **Week 1 day 4:** `--host` and `--join=127.0.0.1` connect; both players spawn under `World/Players`; placeholder sprites visible on both screens.
- **Week 1 end:** movement synced with prediction, camera follows, 8-direction facing, `test_iso`, `test_player_facing`, `test_scenes_load`, `test_data_loads`, `test_network_manager` pass, weekly notes updated.
- **Every later week:** the WEEKLY.md checklist, then tag. From week 4, perf numbers recorded. From week 9, external playtest notes.
- **Mid-project gate (end of week 6):** Biome 1 playable end to end in co-op with relics, abilities, 3 classes, town, save. If this gate slips by more than 3 days, the team meets to decide whether to thin planned content or extend the milestone.

## Parallelization

- Lanes are parallel by design. Within a lane, tasks are sequential along the dependency arrows above.
- Cross-lane seams (capability map) are PRs into the owning module: floor-generation room populators are registered by relics/run-economy; effect-system harness is used by content modules; scenes and shared data contracts are reviewed by the owning lane.
- Content weeks (8 to 11) parallelize further: Claude Code writes `.tres` and effect scripts in batches per module; the data-driven tests catch count and id mistakes.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Client prediction + host correction feels rubber-bandy at real latency | High | Week 1 ships prediction for the local player only; weekly two-machine test with simulated latency and drift checks |
| Effect system performance with 4 players x 30 relics | High | Proc depth cap, per-frame spawn cap, perf scene in week 4 before relic count grows |
| Compatibility renderer light and particle limits | Medium | Cap 16 lights / 128 emitters, pooled; faked shadows; perf scene measures weekly |
| Floor determinism drift between peers | High | Single RNG per floor, no engine randomness, hash assertion with host fallback, 500-seed soak |
| Content volume (88 relics, 120 mutations, 30 abilities, 27 enemies, 16 bosses) | High | Everything is data + small script on finished systems; harness tests make each item a 10-minute task |
| Two developers editing the same scene | Medium | Ownership lanes, `.tscn` rule, week 1 `project.godot` owned by the platform lane; Ask-first list |
| GitHub Actions Godot 4.7.2 availability | Low | Fall back to downloading the official headless zip by URL |
| Design doc edits by one developer desync the specs | Medium | Design doc changes go through a PR that also touches the affected specs; data-driven tests assert counts and ids |
| Week 6 gate slips | High | Explicit mid-project gate; cut list order is pre-agreed in the design doc |
| Art time in week 12 | Medium | Placeholder generator from week 1 keeps builds playable; priority list in SPEC-art-audio |

## Open questions

- GUT exact release and the Actions setup action for 4.7.2 (resolved in the initial setup tasks, written back to the spec files).
- `AStarGrid2D` vs `NavigationAgent2D` for enemies (week 2, SPEC-enemies-ai).
- Art source (hand-drawn, commissioned, CC0) by week 6 (SPEC-art-audio).
- Latency simulation implementation (week 4, SPEC-debug-tools).
- Online Daily Dive leaderboard endpoint (week 11, local is the commitment).

## Task list

Tracked in `tasks/todo.md` (default target; no external tracker designated). Task ids are `W<week>-<lane><n>` with lane `A`, `B`, `AB`, and double as branch names: `feat/<module-id>-<task-id-lowercase>-<short-desc>`.
