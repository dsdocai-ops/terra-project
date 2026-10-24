# Lessons

## Validation catches implementation bugs before they reach gameplay

**Why:** G2's comprehensive schema validation (36 test cases, each rule tested) caught two loader bugs (lines/choices not appended; not-composite form) that would have caused silent data loss at runtime. The bugs were fixed once and never regressed.

**How to apply:** For any system that loads data (dialogue, items, encounters), write the schema validator test cases BEFORE implementation. Make the validator check both structure (required fields, types, bounds) and references (goto resolution, flag declarations).

---

## Data validation must include content rules, not just schema structure

**Why:** G7 exposed a content bug the schema couldn't catch: act_2_stub entries shipped at priority 20, which is valid JSON but wrong gameplay (stubs shadowed act_1 reactions). Only integration tests evaluating the full dialogue flow caught the priority inversion. Schema checked bounds and required fields; it couldn't check relative priority based on conditions.

**How to apply:** For systems with semantic ordering (dialogue priority, loot rarity, skill cooldowns), add integration tests that exercise the full flow under multiple game states. Let tests verify not just "is this valid?" but "does this work correctly in context?"

---

## Sequential goals with full completion between steps prevent rework

**Why:** G1 (flags) → G2 (loader) → G3 (evaluator) each fully completed before dependents started. No goal needed to circle back; tests caught problems at the right layer. The flow was: "G1 done, G2 builds on G1, G3 builds on G1+G2", not "G1 partial, G2 partial, try G3, go back to G1".

**How to apply:** In PLAN.md, mark goals as fully done only when their acceptance criteria are met (all tests green, all code committed). Don't start dependent goals until the upstream goal's judge pass is recorded in LOG.md.

---

## Unit + integration split isolates operator bugs from logic bugs

**Why:** G3 split between 34 unit tests (each condition operator standalone) and integration tests (entry selection, priority, fallback). This prevented both "operator works alone but breaks in context" and "logic is right but one operator is broken" bugs.

**How to apply:** For dialogue, enemies, or other systems with many small rules + complex orchestration, test operators/rules separately (unit), then test the orchestration (integration). When a test fails, you immediately know which layer has the bug.

---

## Data-driven JSON + schema validation scales to many items without new code

**Why:** G2's DialogueData loader + validation meant 8 NPC dialogue files (G6) add no code, only JSON. The schema ensures each file is valid before runtime. This pattern scales to 40+ lore pages, many boss encounters, many NPCs in later weeks.

**How to apply:** Before writing item content (NPCs, lore, encounters), design the schema and write the validator tests. Then content additions are just new JSON files that must pass the validator. No new code per item.

---

## Separate rules from UI enables testing and reuse

**Why:** G8 (static CurrencyScaler), G5 (DialogueBox UI), G1–G3 (logic) all isolated rules from presentation. This meant G8's scaler could be tested without touching UI, G5's DialogueBox could be mocked, G1–G3 logic could be evaluated without rendering. G8 showed that separating the scaling math from drop/payout nodes made it testable for all three payout seams at once.

**How to apply:** Write static utility classes or pure functions for rules (currency scaling, entry selection, condition evaluation). Write thin node wrappers around them for UI/gameplay. Test the rules in isolation; test the wrappers separately if they add state or side effects. This pattern enables G9–G11 to do the same: rule classes (Shop prices, MapRoom logic) + thin UI/interactable nodes.

---

## Full test suite after major changes catches multi-goal regressions

**Why:** G8's currency scaling affected payouts across three seams (LootDrops, OrePayout, EchoShards), which in turn touched test_death_rules.gd, test_currency_gained, and test_echo_shards. Running the full suite after commit 4afb9d5 caught all of them; running only G8's new test would have missed the regressions.

**How to apply:** After any goal that touches a central system (payouts, state persistence, event hooks), run the full GUT suite before committing. Check for green baseline in prior commits; if the suite grows, spot-check dependent goal tests (e.g., "what calls this changed function?").

