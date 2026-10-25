# Combat v2: Task List for Handoff

## Objective

Implement Combat v2 (proposal approved 2026-10-24) as five sequential PRs into `main`, fully merged with CI green, two-instance smoke tests passing, and manual feel passes recorded in `specs/WEEKLY.md`. The implementation covers hit feedback, poise/stagger, attack timeline and heavy charge, weapon skills, and player-side hit reactions (C1–C5; C6 deferred to `enemies-ai`).

## Definition of Done

Each PR (C1, C2, C3, C4, C5) is merged when:
- `godot --headless --path . --import` exits with 0 errors
- `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` is green
- PRs C1, C2, C4 (touch sync) pass `bash tools/smoke_two.sh` on host and client
- Manual feel pass is recorded in `specs/WEEKLY.md` (one line per PR, dated, noting what changed)

All work is committed to `feat/<module-id>-<desc>` branches off `main` with strict static typing, doc comments on every stateful script saying who owns it and how it syncs, no `Engine.time_scale`, no base stat edits, and attribution to Claude Haiku 4.5.

## In Scope

Five PRs in this exact sequence, each a complete, testable increment:

1. **C1 feat/combat-core-hit-feedback**: hit-stop tiers (light 3, finisher/heavy 6, crit +2, player hurt 4, boss kill 10), `hit_flash.gdshader` (white/gold flash overlay), `CombatFeedback` node replicating feedback via RPC to all peers, `SlashArc` VFX driven by `AttackSpec.shape`, `reach`, `arc_degrees`, small/large sparks. Tests: hit-stop tier frames, entity frozen under scale=0, client receives feedback RPC.

2. **C2 feat/combat-core-poise**: `EnemyData.poise` and `stagger_seconds`, `AttackSpec.poise_damage`, `HitInfo.poise_damage` and `staggered`, `Events.enemy_staggered(enemy, hit)`, rewrite `Enemy.apply_knockback` (flinch vs stagger logic), `Stagger` state cancels attack, ×1.25 damage while staggered, poise refill (1.5 s delay, 50%/sec, full on stagger exit). Tests: flinch keeps windup, stagger breaks attack, refill schedule, damage multiplier, 0-poise always staggers.

3. **C3 feat/combat-core-attack-timeline**: `AttackSpec.combo_cancel_at` (fraction of recovery), `AttackSpec.dodge_cancel_at`, `WeaponData.charge_move_factor` (0.3), unified input buffer (one slot, last-press-wins, 0.2 s, fires at first legal frame), combo reset timer starts at attack end, new `HeavyCharge` state with charge ring fill, perfect release (+20% damage/poise damage within 0.15 s of full), `Events.heavy_attack_released(player, charge)`. Tests: buffer order, cancel windows, charge tiers, perfect release, buffered heavies don't drop.

4. **C4 feat/combat-core-weapon-skill**: `WeaponData.skill` (AttackSpec) and `skill_cooldown_seconds` (6.0), Pickaxe and Crossbow Phase 1 skill (stronger heavy, unique shape), `WeaponController.weapon_skill()` with cooldown, heavy press inside `is_perfect_dodge_window()` fires skill and consumes window (otherwise charges), 3-frame hit-stop on dodger plus visual ping. Tests: fires in window only, consumes window, cooldown blocks second fire, outside window charges.

5. **C5 feat/combat-core-player-reactions**: `AttackPattern.is_heavy`, `AttackPattern.poise_damage`, `TelegraphShape.RING`, ring telegraph draw, enemy `_build_hit` sets `is_heavy`, light hits flinch (knockback + flash, keep control, 0.4 s i-frames), heavy hits full `HitStun`, shape cache (one `Shape2D` per spec/charge bucket and per enemy pattern, no per-swing allocation), CI test (every `AttackPattern` has `active_seconds > 0` and `recovery_seconds >= 0.3`). Tests: light keeps control, heavy stuns, no-alloc shape cache, ring telegraph draw.

## Out of Scope

- C6 (co-op attack tokens, `enemies-ai` module, deferred decision)
- Any design-doc cuts (nothing is narrowed without explicit human sign-off, which this handoff does not include)
- New systems for single-item effects (all changes are data on existing Resource definitions or stat modifiers)
- Anything beyond the 5 PRs above or the spec updates below

## Constraints

**Stack and commands:**
- Godot 4.7.2, GDScript, Compatibility renderer
- Strict static typing; `untyped_declaration` is an error
- All tests in GUT 9.x, shipped in the same PR as code
- No `Engine.time_scale`; all time control via `TimeManager`
- No base stat edits; all multipliers via `StatBlock` modifiers
- Two-instance smoke test: `bash tools/smoke_two.sh`

**Files and rules:**
- `world.tscn` is shared; ask before editing (Dev B owns UI-HUD lane, Dev A owns combat-core)
- `scripts/data/` Resource definitions are locked; data changes are pre-approved in the proposal section 4
- New signals (`Events.enemy_staggered`, `Events.heavy_attack_released`, `Events.player_dodged` if missing) pre-approved
- No changes to `project.godot`, Input Map, autoloads, save schema, or CI
- Tests red-first; never skip or delete a failing test
- Commits use no real names, only "Dev A" and "Dev B"

**Testing and review:**
- Every PR is tested both locally (import, GUT suite, smoke test) and by CI before merge
- Manual feel pass recorded in `specs/WEEKLY.md` (describe what changed, how it felt)
- Review required for shared systems (all of combat-core PRs are shared; effect-system ownership per SPEC-effect-system.md)

**Spec and design:**
- `docs/proposals/combat-v2.md` is uncommitted on feat/art-audio-v2-pipeline; commit it to the first C1 branch
- After C5 merges, update `specs/SPEC-combat-core.md` to match: attack input layer, hit reactions, hit feedback, poise system, new `AttackPattern` fields
- Update proposal status line to "Implemented"

## Assumptions

1. **Dev A owns C1–C5**: `combat-core` module is Dev A per capability map; Dev B review gate is implicit
2. **Smoke test coverage**: C1 (replicated RPC), C2 (stagger sync), C4 (weapon skill sync) require two-instance smoke test; C3, C5 do not touch sync (state machines + input)
3. **Hit-stop tiers are global constants**: Place in a single constants table, reused by `TimeManager.hit_stop()` calls in world feedback handler
4. **Shape cache is per-spec plus charge bucket**: Melee shapes are pooled by `(AttackSpec, charge_level)` in `WeaponController`; enemy patterns cached by `(AttackPattern,)` in enemy state machine—no per-frame allocation
5. **Buffer fires first legal frame**: "First legal frame" = the earliest frame in the buffer's lifetime when the action's cancel window opens (e.g., a buffered heavy fires at `combo_cancel_at` if the current attack ends by then)
6. **Perfect release is within 0.15 s of full, not on full**: The player must release the button within 0.15 s of reaching max charge; holding 0.16 s+ loses the bonus
7. **Stagger always cancels attack**: Every attack in `Enemy.apply_knockback`, regardless of type, is cancelled if poise breaks; only flinch (no state change) if poise remains > 0
8. **Feedback RPC replaces direct calls**: `World._on_hit_landed` (host) sends one unreliable RPC; every peer (host + clients) receives it and runs `CombatFeedback` logic (no direct signal emit to clients)
9. **Weapon skill is AttackSpec**: `WeaponData.skill` is an `AttackSpec` resource, not a separate class; it reuses attack machinery with custom shape and cooldown
10. **Perfect dodge consumes the window**: Pressing heavy inside the window fires the skill; the window closes immediately and won't reopen until the next dodge lands
11. **Spec updates are async**: `SPEC-combat-core.md` and proposal status are updated after all five PRs merge, not per-PR

## Removed from the Request

- "Read it first, then follow CLAUDE.md and specs/SPEC-project.md" → assumed implicit to all work
- "ask a human before editing a .tscn" → noted in Constraints; work proceeds without pausing
- "Step 0 is prompt improvement only. Do not plan or implement anything yet." → this brief completes Step 0; Step 1 starts implementation planning
- Progress reporting after each task (replaced by `.goals/LOG.md` logging)
- Pausing for user approval between PRs (replaced by automated CI gates and manual feel recording)
- "Resolve ambiguity yourself" and "Create .goals/LESSONS.md" are incorporated into this brief and the lessons file below
