# Week 6 Dev B: Story, Town Art, Run Economy Polish

## Objective

Implement Week 6 Dev B work across six modules (story-dialogue, town, run-economy, art-audio) in one branch `feat/week6-dev-b-story-town-art` off `main`. Ship with one PR, auto-fix enabled, CI green, all GUT and art tests passing, and two-instance smoke test green. Never merge the PR.

## Definition of Done

All checkable by command once the PR is open:

1. **W6-B1:** `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` exits 0; `test_story_manager.gd` covers all condition operators, priority selection, fallback, and act derivation; `test_dialogue_data.gd` validates all JSON against schema, resolves every `goto`, checks every NPC has required entries.

2. **W6-B2:** `DialogueBox` scene compiles with no errors; `ui-sign-off` mockup documented in `specs/SPEC-story-dialogue.md` as "week 6 mockup, ready for Dev A feedback" (no approval needed); all tests pass.

3. **W6-B3:** JSON files under `data/dialogue/` and `data/lore/` load without parse errors; `test_dialogue_data.gd` confirms all entries, `goto` refs, and story flags declared. Act 1 content present: early NPC lines, forum topics, boss-defeated reactions with story flags.

4. **W6-B4:** Town scene loads; NPC nodes call `start_dialogue`; Alchemist menu slots and heal potion work; Map Room shows start-at-reached-ropes; building level sprites exist for 4 states in `assets/sprites/buildings/`; pit edge staging nodes visible.

5. **W6-B5:** `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_run_economy_shops.gd -gexit` and `test_run_economy_rest.gd` exit 0; currency scaling by biome in a static class with tests; Shop and Rest interactables wired and functional in town without editing Dev A's scenes.

6. **W6-B6:** `cd tools/art && python build_all.py --check` exits 0; review sheets present in `docs/asset-review/week-6/` for all 8 NPC walk/idle sheets, 8 portraits, DialogueBox theme, lore page UI, codex list, and 2 building level states; sheets show palette names only, no placeholder; generators registered in `build_all.py`.

7. **CI green:** All tests pass; `godot --headless --path . --import` surfaces no errors.

8. **Smoke test green:** `tools/smoke_two.sh` exits 0 (headless two-instance: host and client connect, spawn, move, extract).

9. **One PR:** All work on one branch, commits after each step for reviewability. PR title under 70 chars. Body describes summary, test plan, and includes the Claude Code attribution line at the end.

## In Scope

- **W6-B1** `[story-dialogue]`: StoryManager with namespaced flags, `flags.json` declaration, `act()`, `evaluate()` condition language (all, any, not, flag, flag_not, character, class, town_level, ore_min, deepest_floor_min, rescued, act_min, random_chance), `unlock_lore`. DialogueData loader with schema validation. GUT tests for every condition case and every schema rejection.

- **W6-B2** `[story-dialogue]`: DialogueBox UI scene (portrait left, name, typewriter text, choices). `start_dialogue()` RPC. LorePage pickup + LORE room populator. Codex list stub (empty frame, no content yet). Per-player dialogue in town. **Mockup sign-off only:** documented in spec with structure and ready for refinement; no approval gate.

- **W6-B3** `[story-dialogue]`: Act 1 content as JSON only (early NPC lines for Hilde/Gruff/Moss/Pip/Ash/Tom, forum topics, boss-defeated reactions). Content is data; no new systems. Story flags and progression hooks. Dialogue conditions and `goto` refs validate in tests.

- **W6-B4** `[town]`: NPC nodes that call `start_dialogue`. Alchemist menu (potion slots 1 to 3, heal potion type). Map Room (start at reached ropes, next-floor modifier preview). Building level sprites 4 states. Pit edge staging with story act. No new building logic; data-driven from BuildingData.

- **W6-B5** `[run-economy]`: Shop and Rest room interactables polished. Currency (gold, ore) scaling by biome. Pure rules in static class with unit tests; thin interactable nodes on top. Wire PotionController.use() to potion action **only if no Dev A scene edits needed**; otherwise document as "wired pending W6-A" in the spec.

- **W6-B6** `[art-audio]`: 8 NPC walk/idle sheets (Hilde, Gruff, Moss, Pip, Sister Ash, Old Tom, Vesper, rescued miner v1), 8 portraits (same), DialogueBox theme (portrait frame, name plate, choice buttons, typewriter blip), lore page UI, codex list theme, Alchemist L1 and Map Room L1 building states (4 states total = 2 buildings). Generators under `tools/art/` with palette names, registered in `build_all.py`. Review sheets in `docs/asset-review/week-6/` but **not marked approved in INDEX.md**; leave at review-sheet stage.

## Out of Scope

- Dev A's work (W6-A1 to W6-A7): biome data, enemies, bosses, hazards, real art assets.
- Music (W6-B7): skipped per user instruction.
- Scene ownership violations: never edit Dev A's `.tscn` without asking.
- W6-B2 UI approval: mockup sign-off replaces "wait for yes"; refinement happens in feedback, not a gate.
- W6-B6 final approval: review sheet only; no "approved in INDEX.md" step.
- Interactive pauses or status reports during the run: automatic logging replaces them.

## Constraints

### Stack & Files
- **Engine:** Godot 4.7.2, GDScript, Compatibility renderer.
- **Tests:** GUT 9.x; all new code ships with unit or integration tests.
- **Code style:** Strict static typing; no `untyped_declaration`. Named method callbacks in GUT (never lambdas with `.connect()`).
- **Naming:** Dev A and Dev B only; no real names in code, commits, or PRs.
- **Data:** Content is JSON (dialogue, lore) under `data/dialogue/` and `data/lore/`; Resource classes under `scripts/data/`.
- **Sync:** Host-authoritative; every stateful script doc comment says who owns it.
- **Art:** Python generators under `tools/art/`, palette names only, palette locked for Biome 1 (collapsed_mines) as of this week.

### Commands (all must exit 0)
```powershell
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
cd tools/art && python build_all.py --check
tools/smoke_two.sh  # headless two-instance, 15+ checks
```

### Hard Rules
- **Tests ship with code:** Never skip or delete a failing test.
- **Never change without asking:** `project.godot`, Input Map, autoloads, `scripts/data/` Resource classes, Events signals, save schema, CI, addons, or Dev A's `.tscn`.
- **Strict ownership:** town.tscn is Dev B; player.tscn is Dev A. Never edit across boundaries without review.
- **No Engine.time_scale:** Use TimeManager.
- **No StatBlock base edits:** Use modifiers only.
- **GUT gotchas:** Named method callbacks (not lambdas); clear TimeManager between tests if global state leaks.

## Assumptions

1. **Branch base:** Current branch is `feat/run-economy-W5-dev-b-town-screens` (W5 PR 4 not yet merged). If `main` has PR 4 merged before work starts, branch off `main` instead.

2. **PR 4 dependencies:** W6 work assumes W5-B3 to W5-B5 are landed (town.tscn, RunSetup, MapRoom, PotionController exist).

3. **W6-B2 UI sign-off:** "Wait for yes" is replaced with a documented mockup and structure. The UI is functional but open to refinement feedback; no interactive approval gate during this run.

4. **W6-B6 art sign-off:** Review sheets created in `docs/asset-review/week-6/` but not marked approved in `INDEX.md`. The weekly review happens asynchronously; the automation stops before final sign-off.

5. **PotionController.use() wiring:** If wiring requires editing Dev A's player.tscn (W1-A4), skip it and document as "wired pending Dev A scene change" in commit message; otherwise wire it. Decision made by inspection.

6. **NPC dialogue ownership:** All 8 NPC dialogue files (Hilde, Gruff, etc.) are new JSON files under `data/dialogue/`; no existing files edited outside the dialogue system.

7. **Story flags namespace:** All flags follow the namespace convention: `story.*`, `rescue.*`, `char.*`, `ending.*`, `lore.*`, `town.*`, `secret.*`, `boss.*`. Declared in `flags.json`.

8. **Building level sprites:** Assume 4 visible states per building: level 0 (sign), level 1 (rebuilt), level 2 (upgraded), level 3 (fully rebuilt). Alchemist and Map Room only, not all 11.

9. **One PR total:** All six work items (W6-B1 to W6-B6) land in one branch, one PR, one review cycle. Auto-fix enabled for CI failures; never merge.

10. **Logging:** After each goal completes, append one line to `.goals/LOG.md` with timestamp, what changed, and how it was checked. Continue to the next goal without pausing.

## Removed from Request

- **W6-B2 UI approval gate** ("wait for my yes before writing the real UI"): Replaced with documented mockup. Refinement happens offline.
- **W6-B6 approval gate** ("wait for my approval before marking approved in docs/asset-review/INDEX.md"): Replaced with review sheet only. No INDEX.md entry added.
- **Per-task status updates:** Replaced with automatic LOG.md entries.
- **Prompt improvements:** Replaced with this brief; no further clarification needed.
- **Interactive decisions on PotionController wiring:** Make the best choice by inspection; document the decision in the commit.

---

## Execution Notes

- **Branch strategy:** One branch, one PR. Commit after each work item (W6-B1, W6-B2, etc.) so diffs are reviewable.
- **Testing cadence:** Run full test suite after W6-B1, W6-B3, W6-B5. Run art build after W6-B6. Run smoke test before PR.
- **Documentation:** Add schema file `specs/content/dialogue-schema.md` for dialogue JSON validation.
- **Logging:** Each work item logs to `.goals/LOG.md` with outcome and verification command.
