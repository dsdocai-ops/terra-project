# Week 6 Dev B Plan: Story, Town, and Art

**Module focus:** `story-dialogue` (W6-B1-B3, B6 art), `run-economy` (W6-B5), `town` (W6-B4, B6 art)

**Scope:** Story system foundation with JSON dialogue loader and condition evaluator; Act 1 NPC dialogue and progression flags; Run-economy polish (currency scaling, Shop/Rest); Town NPCs with dialogue and menus (Alchemist, Map Room); Art asset generation for NPCs, portraits, UI themes, and building states through Python generators.

**Dependencies:** W5-B1-B8 (town v1, run-economy, shop/rest placeholders). No dependencies on Dev A for this week's start.

**Acceptance:** All 15 goals deliver their checklist items; GUT tests green; `build_all.py --check` clean; review sheet generated and pending approval in `docs/asset-review/week-6/`.

---

## Goals

- [x] G1: StoryManager flags and acts
  - Why: Enables condition-based dialogue and act transitions; per-player progress tracking
  - Success: `StoryManager` has namespaced flag storage (`story.*`, `rescue.*`, `char.*`, `ending.*`, `town.*`, `secret.*`, `boss.*`, `lore.*`), `flags.json` declares all reserved flags, `act()` returns 1-3 derived from story flags, `set_flag()` persists to save, full unit test coverage
  - Sub-tasks:
    1. Read SPEC-story-dialogue flag namespace rules and SINKHOLE_SPEC story beats (section 11)
    2. Extend `StoryManager` with `_flags` as `Dictionary[StringName, bool]` keyed by namespace
    3. Write `data/dialogue/flags.json` with all 20+ reserved flag names grouped by namespace
    4. Implement `set_flag(flag)` with idempotent behavior and save-on-UNLOCK_FLAGS hook
    5. Implement `act()` to return 1 if no `story.foreman_defeated`, 2 if it's set but not `story.vulkar_journals`, 3 if all set
    6. Write `tests/unit/test_story_flags.gd` with 8+ assertions covering namespaces, acts, idempotence, and JSON loading

- [x] G2: DialogueData JSON loader and schema
  - Why: Defines the contract between dialogue JSON and the runtime; schema validation catches editor errors at test time
  - Success: `DialogueData` resource class loads from JSON with full schema validation, every schema error (missing `id`, bad `priority`, undeclared flag, circular `goto`, missing speaker) caught and reported by tests, deterministic errors prevent bad data from entering the game
  - Sub-tasks:
    1. Write `specs/content/dialogue-schema.md` documenting NPC structure, entry structure, lines, choices, conditions, `on_end` actions (set_flags, give rewards)
    2. Create `scripts/data/dialogue_data.gd` as a `Resource` with fields for `id`, `portrait`, and `entries` (array of dialogue entries)
    3. Implement JSON loader in `DialogueManager` or a static helper that parses `data/dialogue/<npc>.json` and validates against schema
    4. For each schema rule, add a validation check that fails the test if violated
    5. Write `tests/integration/test_dialogue_data.gd` with 12+ test cases covering valid files, each schema violation, goto resolution, and portrait path existence

- [x] G3: Condition language evaluator
  - Why: Dialogue priority selection depends on evaluating conditions; 12 operators must be complete and tested
  - Success: `StoryManager.evaluate(condition: Dictionary) -> bool` handles all 12 operators (`all`, `any`, `not`, `flag`, `flag_not`, `character`, `class`, `town_level`, `ore_min`, `deepest_floor_min`, `rescued`, `act_min`, `random_chance`), highest-priority passing entry selected by dialogue lookup, fallback to stub response on no match
  - Sub-tasks:
    1. Study condition language examples from SPEC-story-dialogue and design doc section 11
    2. Implement `evaluate(cond: Dictionary)` using recursive descent for `all`/`any`/`not` and dispatch for leaf operators
    3. Test each operator independently: `test_story_conditions.gd` with 14+ cases (one per operator, plus true/false edge cases)
    4. Implement entry priority selection: scan entries in descending priority order, return first passing conditions entry
    5. Implement fallback: if no entry passes, return a stub `{id: "fallback", lines: [{speaker: npc_name, text: "..."}]}` entry
    6. Write integration test: given a dialogue set and a flag state, verify the highest-priority matching entry is chosen

- [x] G4: LorePage pickup and floor populator hook
  - Why: Lore collection is a design pillar (40+ pages, required for true ending); LORE room placer needs a hook
  - Success: `LorePage` interactable spawns on `LORE` room floor, collecting sets flag in `StoryManager.unlock_lore()` and saves, floor-generation placement hook calls `LORE` populator with biome context
  - Sub-tasks:
    1. Create `scripts/world/lore_page.gd` as an `Area2D` with a static sprite, collision, and trigger callback
    2. On `body_entered(player)`, call `StoryManager.unlock_lore(page_id)` and queue_free
    3. Write a `LORE` room populator function in `floor_generation` that finds the lowest-order unread lore page for the biome and spawns a `LorePage` instance
    4. Register populator in floor-generation's placement hooks
    5. Write integration test: generate a floor, spawn a lore page, pick it up, verify flag is set and save includes it

- [x] G5: DialogueBox mock-up
  - Why: Town and pit dialogue both need a UI; mock-up allows design approval before real implementation
  - Success: `DialogueBox` scene shows portrait, name, typewriter text, choices list, all styled with placeholder visuals, marked in code as "awaiting design review"; gameplay-safe (pauses local input, not game), per-player in town
  - Sub-tasks:
    1. Create `scenes/dialogue/dialogue_box.tscn` with placeholder hierarchy: portrait `TextureRect`, name `Label`, text `Label` (with typewriter effect stub), choices `VBoxContainer` with `Button` placeholders
    2. Write `scripts/dialogue/dialogue_box.gd` with `show_dialogue(dialogue_data, entry)` that populates and signals on choice selection
    3. Implement typewriter effect: reveal text char-by-char over 0.05s per char, skip on Space/click
    4. Implement choice buttons: create `Button` per choice, connect to `choice_selected` signal with choice id
    5. Add pause on show: `get_tree().paused = true` for the local player only (per spec: co-op sees all, but local input is paused)
    6. Write `tests/unit/test_dialogue_box.gd` with 4+ cases: show, typewriter timing, choice click, resume on close

- [x] G6: Act 1 dialogue content as JSON
  - Why: Content is the proof that the system works; Act 1 NPCs + forum topics drive early story beats
  - Success: All 8 NPC JSON files have intro and Act 1 lines with `priority` and `conditions` set, every required entry (intro, act_1, act_2_stub, act_3_stub, endings_stub) present, all flags referenced are declared in `flags.json`, no undeclared `goto` references
  - Sub-tasks:
    1. For each of 8 NPCs (Hilde, Gruff, Moss, Pip, Sister Ash, Old Tom, Vesper, rescued miner v1), write `data/dialogue/<npc>.json` with intro and Act 1 dialogue trees
    2. Intro entry: triggered first time (e.g., `flag_not: story.met_hilde`), sets the flag on end
    3. Act 1 entry: triggered after `story.foreman_defeated` is set, reacts to defeat with character voice
    4. Each dialogue tree branches via `goto` into follow-up lines, using `text` with character flavor
    5. Every referenced flag in `conditions` must exist in `flags.json`
    6. Run data validation test: assert all 8 files parse, have required entries, match schema, resolve all gotos

- [x] G7: Act 1 progression flags and hooks
  - Why: Story beats must trigger on key events; Foreman defeat should immediately affect town dialogue
  - Success: `story.foreman_defeated` flag set when The Foreman boss dies, `story.miners_possessed` and `story.pit_calls` set on return to town after that event, town NPC dialogue changes next time player talks
  - Sub-tasks:
    1. Add hook in `bosses.gd` or boss-death callback: when The Foreman dies, `StoryManager.set_flag("story.foreman_defeated")`
    2. Add hook in town load or NPC dialogue start: when town loads after `story.foreman_defeated` is set, call `StoryManager.set_flag("story.miners_possessed")` and `set_flag("story.pit_calls")`
    3. Verify NPC entries have conditions: Gruff, Hilde, Pip, etc. have Act 1 lines with `condition: {act_min: 1}` which is now true
    4. Test: mock a game state with The Foreman killed, load town, verify dialogue changes
    5. Test: mock return-to-town flow with flag set, verify subsequent NPC lines use Act 1 entries

- [x] G8: Run-economy currency scaling
  - Why: Difficulty progression requires deeper biomes to yield more currency; pure rules separate from UI
  - Success: Static `CurrencyScaler` class with `biome_multiplier(biome_index: int) -> Dictionary` returning `{gold, ore, echo}` scaling factors (e.g., biome 4 = x1.2 gold, x1.4 echo), tests cover co-op splits and all biomes
  - Sub-tasks:
    1. Create `scripts/run-economy/currency_scaler.gd` as a static class
    2. Implement `biome_multiplier(biome: int) -> Dictionary` returning scaling factors; design curve so biome 1 = 1.0x, biome 6 = 1.5x gold / 2.0x echo
    3. Apply scaling in gold/ore drop rolls and echo shard payouts during runs
    4. Write `tests/unit/test_currency_scaling.gd` with 10+ cases: each biome, solo vs co-op (splits evenly), rarity + luck interaction
    5. Verify in `test_death_rules.gd` that co-op split math still holds with scaling applied

- [x] G9: Shop and Rest room polish
  - Why: W5-B3 left Shop/Rest as interactables; they need refactoring for clarity and UX; currency scaling (G8) now requires prices to be biome-aware
  - Success: `Shopkeeper` and `RestPoint` scripts refactored, shop purchase flow uses static `Shop` class (prices scaled by biome, filtering by rarity), rest point heal uses `PotionController`, both interactables have clear prompts and feedback; PotionController.use() wiring decision documented in commit
  - Sub-tasks:
    1. Review W5-B3 shop and rest code; identify UX pain points (unclear prompts, missing feedback)
    2. Create `scripts/run-economy/shop.gd` as a static utility with `item_price(rarity: int, biome: int) -> int` (applies G8 scaling) and `filtered_items(rarity_cap)` methods
    3. Refactor `scenes/rooms/shop_interactable.gd` to use `Shop` class with biome context, add purchase feedback (sound, visual confirmation)
    4. Refactor `scenes/rooms/rest_interactable.gd` to call `PotionController.heal_one()` or equivalent, add heal feedback
    5. Inspect player.tscn ownership and PotionController.use() interface; if wiring potion action → `PotionController.use()` requires editing Dev A's scene, document decision as "wired pending W6-A" in commit message; otherwise wire it and test
    6. Test: verify shop purchases correctly use static prices + biome scaling, rest heals to expected value, co-op both players see same shop stock
    7. Full GUT suite green before commit

- [ ] G10: NPC town nodes
  - Why: NPCs are the story anchor in town; they need to be placeable and dialogue-triggerable
  - Success: 8 `NPC` nodes placed in `town.tscn` (one per building), each a `CharacterBody2D` with sprite and collision, interaction triggers `StoryManager.start_dialogue()` with correct `dialogue_id`, dialogue respects per-player flag state in co-op
  - Sub-tasks:
    1. Create `scripts/town/npc.gd` as a `CharacterBody2D` with `dialogue_id: StringName` property and `interact()` method
    2. In `interact()`, call `StoryManager.start_dialogue(dialogue_id, self)`; in co-op, local player sees their own view
    3. Place NPC nodes in `town.tscn` at appropriate positions (Hilde in town center, Gruff near Blacksmith, etc.)
    4. Set each node's `dialogue_id` property (e.g., `"mayor_hilde"`)
    5. Add collision trigger: Area2D overlap or `F` key press calls `interact()`
    6. Write integration test: load town, press F on NPC, verify dialogue shows with correct entry for that player's flags

- [ ] G11: Alchemist and Map Room menus
  - Why: Alchemist (potions) and Map Room (start floor shortcuts) are core town loops; they need UI
  - Success: `AlchemistMenu` scene for potion slot selection, `MapRoomMenu` scene for rope-shortcut selection with next-floor modifiers preview, both integrate into town flow, selections feed into `RunSetup`
  - Sub-tasks:
    1. Create `scenes/town/alchemist_menu.tscn`: 3 slot selections, potion type picker, confirm/cancel buttons
    2. Write `scripts/town/alchemist_menu.gd`: populate slots from building level (1/2/3 = 1/2/3 potion slots), track `selected_potions: Array[StringName]`, emit on confirm
    3. Create `scenes/town/map_room_menu.tscn`: rope list (floor 2, biome bosses up to deepest reached), next-floor modifier preview text, confirm/start
    4. Write `scripts/town/map_room.gd`: list reached ropes, fetch next-floor modifiers from `FloorGenerator`, show preview, emit `run_requested(start_floor)`
    5. Hook both into town's `RunSetup` flow: Alchemist choice → Map Room choice → dive
    6. Write integration test: select potions in Alchemist, start floor in Map Room, verify `RunSetup` receives selections

- [ ] G12: NPC and portrait generators
  - Why: 8 NPCs with walk/idle + 8 portraits must be generated; Python generators enable palette edits
  - Success: `tools/art/gen_npcs.py` generates 8-direction walk and idle sheets (48x48) for 8 humanoid NPCs, `tools/art/gen_portraits.py` generates 96x96 portraits for 8 NPCs + 1 rescued miner variant, registered in `build_all.py`, `--check` verifies on-palette
  - Sub-tasks:
    1. Write `tools/art/gen_npcs.py <id>` that takes a character id and outputs `assets/sprites/npcs/<id>.png` with walk/idle rows
    2. Use `tools/art/pixel.py` canvas and per-frame descriptions from `tools/art/chars/<npc_id>.py` (body parts, colors)
    3. Write `tools/art/gen_portraits.py <id>` that outputs `assets/portraits/<id>.png` 96x96 portrait
    4. Register both in `tools/art/build_all.py` with `subprocess` calls and pattern matching
    5. Run `build_all.py` to generate 8 NPC sheets + 8 portraits + 1 rescued miner variant into `assets/`
    6. Verify `build_all.py --check` passes (all colors on-palette)

- [ ] G13: DialogueBox and lore UI generators
  - Why: DialogueBox theme (frame, nameplate, choice buttons) and lore page UI (collection, reading page) need generated assets
  - Success: `tools/art/gen_dialogue_ui.py` generates 9-patch frame, nameplate bar, choice button sprites; `tools/art/gen_lore_ui.py` generates lore page background, codex list theme; registered in `build_all.py`, on-palette
  - Sub-tasks:
    1. Write `tools/art/gen_dialogue_ui.py` generating: portrait frame (9-patch 24x24 with palette border), nameplate bar (variable width, palette base + accent), choice button (up/down/hover states, palette highlight)
    2. Write `tools/art/gen_lore_ui.py` generating: lore page background (parchment, palette-based), codex list item frame (with read/unread indicator), page turner buttons
    3. Register both in `build_all.py`
    4. Run `build_all.py` to output to `assets/ui/`
    5. Verify `build_all.py --check` clean

- [ ] G14: Building state generators
  - Why: W5-B7 left buildings at L0 states; L1 states for Alchemist and Map Room need generation
  - Success: `tools/art/gen_town.py` extended to generate Alchemist L1 and Map Room L1 sprites (128x128 each, 4 states), all 11 buildings have L1 states committed, on-palette
  - Sub-tasks:
    1. Review `tools/art/gen_town.py` structure and `palette.py` town palette
    2. Add Alchemist L1 definition: visible counters, cleaner, more potion bottles visible
    3. Add Map Room L1 definition: more detailed floor map visible, charts and tables
    4. Run generator to output new L1 states
    5. Verify L0, L1 in `assets/sprites/buildings/` and on-palette

- [ ] G15: Art review sheet and submission
  - Why: Mid-project gate requires visual approval of all dialogue/town art before proceeding
  - Success: `docs/asset-review/week-6/` contains `dialogue-town-npcs-1x.png` and `-4x.png` with all NPC sheets, portraits, UI themes, building states labeled by direction and animation, palette strip at bottom; `docs/asset-review/INDEX.md` lists as `pending`; PR ready for review
  - Sub-tasks:
    1. Run `tools/art/review_sheet.py` on `assets/sprites/npcs/*.png`, `assets/portraits/*.png`, `assets/ui/dialogue_*.png`, `assets/sprites/buildings/alchemist_l1.png`, `assets/sprites/buildings/map_room_l1.png`
    2. Output to `docs/asset-review/week-6/dialogue-town-npcs-1x.png` and `-4x.png` with labels per direction and animation
    3. (Optional) Run in-engine screenshot of DialogueBox mock-up with all UI elements visible; save as `dialogue-box-capture.png`
    4. Add entry to `docs/asset-review/INDEX.md`: `| Week 6 | dialogue-town-npcs | pending | — |`
    5. Build PR description listing asset ids, generators, palettes used, no CREDITS.md rows (all generated)
    6. DO NOT mark as approved yet; wait for human review

---

## Dependency chain

- G1 enables G3, G4 (evaluate), G6, G7
- G2 enables G6 (JSON validation)
- G3 enables G6 (dialogue branching)
- G4 enables `LORE` room populator in floor-generation (parallel to G8-G11)
- G5 enables G10 (NPC dialogue UI)
- G6 enables G10 (content to display)
- G7 enables test verification of flag-based dialogue
- G8, G9 independent; can run parallel to story work
- G10 depends on G5, G6
- G11 independent; can run parallel
- G12-G15 can run mostly parallel; G15 depends on G12-G14 completion

## Success criteria per goal

Each goal's "Success" section lists what the judge checks:
- GUT suite runs `tests/` subset and expects green
- `build_all.py --check` runs for art goals and expects no diffs
- Manual: run the game to a relevant scene and verify expected behavior
