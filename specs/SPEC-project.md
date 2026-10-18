# Spec: Sinkhole, project-wide engineering contract

Applies to every module in [CAPABILITY_MAP.md](CAPABILITY_MAP.md). Module specs add objective, interfaces, and success criteria on top of this; they never override it. Design content comes from [SINKHOLE_SPEC.md](../SINKHOLE_SPEC.md) and is locked at v3 (Godot 4.7 instead of 4.4 is the only change).

## Objective

Ship the full Sinkhole design in 12 weeks with two developers using Claude Code heavily: 2D isometric action roguelike, 7 classes with Ascensions, 4 characters, 20 weapons with 120 mutations, 30 abilities, 88 relics, 6 biomes with 30 floors and 16 bosses, extraction loop, town meta-progression, skill tree, story with 3 endings, and 1 to 4 player online co-op built in from week 1.

Success for the project as a whole:

- Every week ends with a build that launches, enters a run, and reaches the "Done when" line of that week in design doc section 20.
- Co-op works every week: two instances on one machine connect and play; two physical machines connect weekly.
- 60 FPS with 60+ units on screen on the Compatibility renderer (design doc section 23).
- Nothing in the design doc is silently narrowed. Cuts follow section 21 and only on explicit human decision.

## Tech stack

| Concern | Choice |
|---|---|
| Engine | Godot 4.7.2 stable, GDScript only |
| Renderer | Compatibility (`gl_compatibility`), desktop and mobile methods both set |
| Resolution | 960x540 base viewport, `canvas_items` stretch, `keep` aspect, integer scale where possible, nearest texture filter, 2D pixel snap on |
| Tiles | Isometric 2:1, 64x32 base, `TileMapLayer` nodes |
| Multiplayer | ENet high-level multiplayer, host-authoritative, `MultiplayerSpawner` + `MultiplayerSynchronizer` + RPCs. Local co-op only as fallback if online fails (cut list item 5) |
| Data | Custom `Resource` classes saved as `.tres` for all content (weapons, relics, abilities, enemies, classes, bosses, biomes, skills, mutations, synergies). JSON for dialogue and lore, loaded into `DialogueData` at runtime |
| Save | `user://save.json`, Godot `JSON`, `save_version` field, migrations |
| Tests | GUT 9.x (latest 4.x-compatible release) under `addons/gut/` |
| CI | GitHub Actions on every PR: headless import + GUT tests. No export check yet |
| Platform | Windows export only for 12 weeks. Web and others are stretch |
| Language | English only, no `tr()` |

## Commands

Godot lives at `C:\Godot\Godot_v4.7.2-stable_win64.exe` on both machines (moved there from Downloads; the Godot MCP `GODOT_PATH` points at it). Commands below assume that path is on `PATH` as `godot`; otherwise use the full path. Run from the repo root.

```powershell
# Open the editor (also runs import)
godot --path . --editor

# Headless import only (what CI does first; also surfaces parse errors)
godot --headless --path . --import

# Run the game
godot --path .

# Run two networked instances on one machine (required before any sync PR)
godot --path . -- --host
godot --path . -- --join=127.0.0.1

# Run all tests (what CI does second; must exit 0)
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

# Run one test file
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_stat_block.gd -gexit

# Floor generator soak (500 seeds, part of the normal test run but can be run alone)
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_floor_generation_seeds.gd -gexit
```

Launch args `--host` and `--join=<ip>` are read with `OS.get_cmdline_user_args()` in `NetworkManager` (see `SPEC-networking.md`). The Godot MCP (`launch_editor`, `run_project`, `get_debug_output`) is the preferred way for Claude Code to open the editor and read runtime errors; use the CLI for tests and CI.

## Project structure

Design doc section 18 layout, made concrete. Every file is snake_case.

```
res://
  project.godot
  icon.svg
  addons/gut/                 GUT test framework (vendored, never edited)
  scenes/
    main/                     main.tscn (entry), world.tscn (Y-sort root, camera)
    town/                     town.tscn, buildings/, npcs/
    dungeon/                  floor.tscn, rooms/, hazards/, interactables/
    player/                   player.tscn, states/
    enemies/                  enemy_base.tscn, <biome>/<enemy>.tscn
    bosses/                   <boss>.tscn, arenas/
    abilities/                one scene per ability that spawns something
    projectiles/              pooled projectile scenes
    pickups/                  gold, ore, echo shard, rune stone, relic, potion
    ui/                       hud/, menus/, popups/, dialogue/, skill_tree/
    dialogue/                 dialogue box, portraits
    network/                  lobby, join screen
  scripts/
    autoload/                 game_state.gd, save_manager.gd, events.gd, audio_manager.gd,
                              network_manager.gd, story_manager.gd, time_manager.gd
    components/               health.gd, hitbox.gd, hurtbox.gd, state_machine.gd, state.gd,
                              status_effects.gd, stat_block.gd
    data/                     Resource class definitions, one per file:
                              character_data.gd, class_data.gd, class_pair_data.gd, ascension_data.gd,
                              class_tree_node_data.gd, weapon_data.gd, mutation_data.gd, ability_data.gd,
                              relic_data.gd, synergy_data.gd, enemy_data.gd, boss_data.gd, biome_data.gd,
                              skill_node_data.gd, dialogue_data.gd
    effects/                  effect.gd (base), relic effects, mutation effects, synergy effects,
                              class passive and Ascension effects, skill node effects
    generation/               floor_generator.gd, room_templates, modifiers
    debug/                    debug_console.gd, perf_test scene script
  data/
    characters/  classes/  ascensions/  class_trees/  weapons/  mutations/  abilities/
    relics/  synergies/  enemies/  bosses/  biomes/  skills/      (.tres files)
    dialogue/  lore/                                               (.json files)
  assets/
    sprites/  tilesets/  vfx/  audio/music/  audio/sfx/  fonts/
  tests/
    unit/                     mirrors scripts/: test_stat_block.gd, test_status_effects.gd, ...
    integration/              test_floor_generation_seeds.gd, test_relic_triggers.gd, test_save_migration.gd, ...
    helpers/                  test doubles, fixture builders
  specs/                      this folder
  .github/workflows/ci.yml
```

Rules:

- A content `.tres` and its effect script sit together by id: `data/relics/ember_boots.tres` references `scripts/effects/relics/ember_boots.gd`. One relic, one data file, at most one script.
- Scenes own their script: `scenes/player/player.tscn` has `scenes/player/player.gd` next to it. Shared logic goes in `scripts/components/`.
- `tests/` mirrors `scripts/` paths. A new pure-logic file gets a test file in the same commit.
- `.godot/` is never committed. `.uid` files and `.import` files are committed.

## Code style

Official GDScript style guide, plus strict typing. One snippet shows all of it:

```gdscript
class_name Health
extends Node
## Tracks hit points for players, enemies, and bosses. Emits signals; never
## decides what happens on death. Owned by combat-core.

signal damaged(amount: int, source: Node)
signal died(source: Node)

const MIN_HP: int = 0

@export var max_hp: int = 100
@export var invulnerable: bool = false

var current_hp: int:
	set(value):
		current_hp = clampi(value, MIN_HP, max_hp)

var _last_source: Node = null

@onready var _stat_block: StatBlock = get_parent().get_node("StatBlock")


func _ready() -> void:
	current_hp = max_hp


func apply_damage(amount: int, source: Node) -> void:
	if invulnerable or current_hp <= MIN_HP:
		return
	_last_source = source
	current_hp -= amount
	damaged.emit(amount, source)
	if current_hp <= MIN_HP:
		died.emit(source)


func _is_dead() -> bool:
	return current_hp <= MIN_HP
```

Conventions:

- **Strict typing everywhere.** Every variable, parameter, and return value is typed. `debug/gdscript/warnings/untyped_declaration` is set to Error in `project.godot`. `inferred_declaration` stays a warning (`:=` is allowed when the right side is obviously typed). Untyped `Array` and `Dictionary` are allowed only at JSON boundaries and are converted to typed arrays or Resources immediately.
- **Naming.** Files and folders snake_case. Classes PascalCase via `class_name`. Functions and variables snake_case. Constants and enum members UPPER_SNAKE. Private members prefixed `_`. Signals are past tense (`died`, `room_cleared`), never imperative.
- **Order inside a script.** `class_name`, `extends`, doc comment, signals, enums, constants, `@export` vars, public vars, private vars, `@onready` vars, built-in overrides (`_init`, `_ready`, `_process`), public methods, private methods. Two blank lines between functions. Tabs for indentation.
- **Doc comments.** Every `class_name` script starts with a `##` block stating what it does and which module owns it. Non-obvious public methods get a `##` line.
- **Composition over inheritance.** Player, enemies, and bosses share `Health`, `Hitbox`, `Hurtbox`, `StatusEffects`, `StatBlock` as child nodes. Inheritance is used only for `State` subclasses and `Effect` subclasses.
- **Signals over references.** Cross-module communication goes through `Events` (global bus) or node-local signals. No module reaches into another's scene tree by path.
- **Resources are data.** `Resource` subclasses hold `@export` fields and at most trivial helper methods. Behavior lives in effect scripts and components.
- **Stats.** Nothing edits a base stat. All modifiers go through `StatBlock.add_modifier()` and are removed with the handle it returns.
- **Time.** Nothing touches `Engine.time_scale`. Slow and stop effects multiply `TimeManager` values.
- **Multiplayer.** Every script that holds game state answers "who owns this, how does it sync" in its doc comment. Gameplay decisions (damage, loot rolls, generation, effect procs) run only where `multiplayer.is_server()` is true. Clients send inputs and play presentation.
- **Magic numbers** live in `const` or `@export`, never inline.
- **Content ids** are the snake_case file name (`ember_boots`), used for save data, debug console, and codex. Display names live in the Resource.

## Testing strategy

Framework: GUT 9.x. Tests live in `tests/`, run headless by the command above, and gate every PR in CI.

| Level | What | Where | Rule |
|---|---|---|---|
| Unit | Pure logic: StatBlock math, damage and crit formula, status stacking and combos, currency rules on death and extract, save migrations, proc depth cap, skill tree cost scaling, dialogue condition evaluation, floor grid algorithms | `tests/unit/` | Required for every pure-logic script. Written in the same PR |
| Integration | Floor generator 500-seed soak (every room reachable, exit reachable, rope rooms where the design says), relic trigger harness (instantiate relic, fire Events signal, assert spawn or stat change), save round trip, dialogue JSON schema validation over every file in `data/dialogue/` and `data/lore/`, every `.tres` in `data/` loads and has required fields | `tests/integration/` | Required. Content batches extend the data-driven tests, not hand-written per item |
| Scene smoke | Headless instantiate of every `.tscn` under `scenes/` to catch broken references | `tests/integration/test_scenes_load.gd` | Required |
| Manual, per PR | Two-instance co-op smoke on one machine for any PR touching sync (spawn, synchronizer, RPC, host-only logic, time effects). Checklist in `SPEC-networking.md` | PR description | Required, recorded in the PR |
| Manual, weekly | Two-machine co-op session, simulated latency, perf scene at 60 units, each class and Ascension solo and co-op | Weekly build notes in `specs/WEEKLY.md` | Required before tagging `week-N` |

Coverage is defined by rules, not a percentage, since GDScript has no coverage tooling worth the setup cost: every file under `scripts/components/`, `scripts/data/`, `scripts/generation/`, `scripts/autoload/` has a test file; every content item passes the data-driven tests; every relic, mutation, and ability has at least one trigger-harness case.

CI (`.github/workflows/ci.yml`): checkout, set up Godot 4.7.2 headless (pin the exact version; verify the setup action supports 4.7.2 in week 1), run import, run GUT, fail on non-zero exit. Target under 5 minutes.

## Boundaries

**Always**

- Run the full test command locally before opening a PR. Run the two-instance smoke for sync changes.
- Follow the file layout and naming above. New content is a `.tres` plus optional effect script, never a new system.
- Type everything. Treat `untyped_declaration` errors as build failures.
- Add or extend tests in the same PR as the code they cover.
- Keep PRs scoped to one module id and name it in the title: `[relics] add On Dodge relics 1 to 6`.
- Pull `sinkhole` before starting work. Small commits, conventional messages (`feat(relics): ...`, `fix(networking): ...`).
- Write "who owns this, how does it sync" in the doc comment of any script with game state.
- Keep every week's build playable. If a PR breaks the run loop, revert first, fix second.

**Ask first** (the other developer, or the human if Claude Code is driving)

- Changing `project.godot` settings, the Input Map, or autoload list.
- Adding or updating an addon or any dependency, including GUT version bumps.
- Changing a `Resource` class definition in `scripts/data/` (field add, rename, type change). These are shared contracts and break every `.tres` of that type.
- Adding, removing, or changing the signature of an `Events` signal.
- Changing `StatBlock`, `TimeManager`, or `NetworkManager` public API.
- Changing save schema (requires a migration and a `save_version` bump).
- Editing a `.tscn` owned by the other lane.
- Changing CI config.
- Anything on the cut list (design doc section 21). Cuts are a human decision, recorded in `CAPABILITY_MAP.md` with a date.

**Never**

- Commit `.godot/`, exported builds, or secrets.
- Edit `addons/` vendored code.
- Use `Engine.time_scale` for gameplay time effects.
- Edit base stat values at runtime.
- Run gameplay logic (damage, loot, procs, generation) on a client.
- Remove or skip a failing test to get CI green.
- Edit the same `.tscn` as the other developer in parallel.
- Narrow, simplify, or defer design doc scope without an explicit human decision.
- Hand-write content that a data-driven test could validate; add the test instead.

## Git workflow

- `main` holds the archived previous game until the team decides otherwise. `sinkhole` is the integration branch for this project.
- Feature branches off `sinkhole`: `feat/<module-id>-<short-desc>`, `fix/<module-id>-<short-desc>`.
- Merge via PR into `sinkhole`. CI must pass.
- **Required review** from the other developer for shared systems: anything under `scripts/autoload/`, `scripts/components/`, `scripts/data/`, `project.godot`, `.github/`, `addons/`.
- **Self-merge allowed** for content and scenes inside your own lane's modules once CI passes.
- Each week's playable build is tagged `week-N` on `sinkhole` after the weekly checklist passes.
- Never force-push `sinkhole`. Never rebase a branch someone else has checked out.

## Ownership

Lanes from design doc section 19. Names to be filled in when decided.

| Lane | Developer | Modules |
|---|---|---|
| **Dev A: The Pit** | TBD | `player-controller`, `combat-core`, `enemies-ai`, `floor-generation`, `weapons`, `abilities`, `classes-characters`, `biomes`, `bosses` |
| **Dev B: The Surface + Systems** | TBD | `networking`, `time-manager`, `stats-status`, `save-system`, `run-economy`, `effect-system`, `relics`, `story-dialogue`, `town`, `progression-trees`, `ui-hud`, `endgame` |
| **Both** | | `foundation`, `art-audio`, `debug-tools`, bulk content data files, balancing, playtesting |

Cross-owner seams are listed in [CAPABILITY_MAP.md](CAPABILITY_MAP.md#cross-owner-seams). The owning module's developer reviews contributions from the other lane.

## Success criteria

Project-level, checked at week 12:

- [ ] Every module in the capability map is at status "done" or has a dated cut-list entry.
- [ ] All 12 weekly tags exist and each matched its "Done when" line.
- [ ] CI green on `sinkhole`; test command exits 0 locally on both machines.
- [ ] 500-seed floor soak passes for all 6 biomes.
- [ ] Every content count from the design doc is met and verified by the data-driven tests: 4 characters, 7 classes, 28 Ascensions, 20 weapons, 120 mutations, 30 abilities, 8 ultimates, 88 relics, 12 synergies, 6 biomes, 30 floors, 16 bosses, 11 buildings, 38 skill nodes, 3 endings, 40+ lore pages, 50+ achievements.
- [ ] 4-player online co-op completes a full 30-floor run on two or more machines.
- [ ] 60 FPS with 60+ units in the perf scene on the Compatibility renderer.
- [ ] At least 5 external playtesters from week 9 on, with notes in `specs/WEEKLY.md`.

## Open questions

- Which developer is Dev A and which is Dev B. Fill in Ownership when decided.
- Exact GUT release to vendor (latest 9.x compatible with 4.7 at week 1).
- GitHub Actions Godot setup action and whether it already publishes 4.7.2; verified in week 1 during `foundation`.
