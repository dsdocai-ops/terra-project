# Combat v2 Implementation Plan

**Goal:** Implement the approved Combat v2 proposal (2026-10-24) as five sequential PRs (C1–C5) into `main`, fully merged with CI green and two-instance smoke tests passing.

**Scope:** C1–C5 only; C6 deferred to `enemies-ai`.

---

## Goals

- [ ] G1: C1 feat/combat-core-hit-feedback — hit-stop tiers, shader, replicated feedback, slash VFX

  **Why it matters:** Hit-stop is the single largest feel gap in current combat (audit A5). This PR unblocks all later feedback improvements and makes testing subsequent PRs visually clear.

  **Success criteria:**
  - `godot --headless --path . --import` exits 0
  - `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` is green
  - `bash tools/smoke_two.sh` passes (replicated RPC requires sync test)
  - Manual feel pass recorded in `specs/WEEKLY.md`
  - All hit-landed events call TimeManager.hit_stop() with the correct frame tier for light/finisher/heavy/crit/player-hurt/boss-kill
  - Enemies and player have the flash shader applied and flash for 4 frames (white on hit, gold on crit)
  - Clients in two-instance smoke test receive damage numbers via RPC
  - SlashArc placeholder draws for the attack's active window

  **Sub-tasks:**
  1. Add `HIT_STOP_FRAMES` constants table (light 3, finisher/heavy 6, crit +2, player hurt 4, boss kill 10) in `world.gd` or a new `constants/combat_feedback.gd`
  2. Modify `world._on_hit_landed()` to call `TimeManager.hit_stop(hit.source, hit.target, frames)` with the correct tier
  3. Create `hit_flash.gdshader`: white overlay with `flash_amount` (0–1) and `flash_color` uniforms; apply to enemy sprite material and player sprite
  4. Create `CombatFeedback` node (local, one per peer) under World; implement RPC receiver and feedback dispatch (damage number, flash timer, shake)
  5. Modify `World._on_hit_landed()` to emit an unreliable RPC carrying `{target_path, final_damage, is_crit, is_heavy, staggered}` to all peers
  6. Create `SlashArc` node (placeholder drawn with _draw() or sprite) shaped from `AttackSpec.shape`, `reach`, `arc_degrees`; play for attack active window
  7. Drive SlashArc from `WeaponController.begin_swing()` / `end_swing()` (host + owner client); replicate to other clients via state or RPC
  8. Create `tests/unit/test_combat_feedback.gd`: hit-stop called with correct frames per tier, entity frozen under scale=0 for N frames, client receives RPC and spawns number
  9. Test hit feedback on both host and client in two-instance smoke test
  10. Commit `docs/proposals/combat-v2.md` to this branch

- [ ] G2: C2 feat/combat-core-poise — poise, stagger, refill, damage multiplier

  **Why it matters:** Poise replaces stunlock and makes telegraphs matter (fixes A1). It's foundational for all later combat tuning and the stagger state is new required logic.

  **Success criteria:**
  - Import 0, tests green, two-instance smoke test passes
  - Manual feel pass recorded in `specs/WEEKLY.md`
  - EnemyData.poise and stagger_seconds fields exist and are set on all enemy data files
  - AttackSpec.poise_damage field exists and is set on pickaxe/crossbow light/finisher/heavy specs
  - HitInfo carries poise_damage and staggered; copy() includes both
  - Enemy.apply_knockback implements flinch (poise > 0, flash+knockback, no state change) vs stagger (poise breaks, Stagger state, cancel attack)
  - Stagger state cancels telegraph, disables attack, deals ×1.25 damage, refills poise to full on exit
  - Poise refills at 50%/sec after 1.5 s without a hit, using TimeManager-scaled time
  - Events.enemy_staggered(enemy: Node, hit: HitInfo) signal exists and is emitted when stagger breaks
  - Feedback tier for stagger: 8 frames hit-stop, 4 shake, 6-frame flash, "STAGGER" pop, distinct SFX hook

  **Sub-tasks:**
  1. Add `EnemyData.poise: float` and `EnemyData.stagger_seconds: float = 0.8` fields in `scripts/data/enemy_data.gd`
  2. Set poise values on `data/enemies/collapsed_mines/*` and other biomes: Rock Tick 0, Hollow Miner ~40, Lantern Wisp ~20 (and all others)
  3. Add `AttackSpec.poise_damage: float` field in `scripts/data/attack_spec.gd`
  4. Set poise_damage on pickaxe and crossbow specs: light 10, finisher 20, heavy 30 (controller adds +30 × charge)
  5. Add `HitInfo.poise_damage: float` and `HitInfo.staggered: bool` fields; update `copy()` method to include both
  6. Fill `poise_damage` and `staggered` in `WeaponController.build_hit()` and enemy attack _build_hit
  7. Add `Events.enemy_staggered(enemy: Node, hit: HitInfo)` signal to `scripts/autoload/events.gd` and SPEC-effect-system.md table
  8. Create `scenes/enemies/states/stagger.gd` state: cancels attack/telegraph, applies damage multiplier, runs stagger duration, refills poise on exit
  9. Rewrite `Enemy.apply_knockback()`: subtract poise_damage × (1 − stagger_resist); if poise > 0 flinch, else enter Stagger; handle zero-poise always staggers
  10. Add poise refill logic to Enemy: 1.5 s idle timer using TimeManager, 50%/sec refill, reset on hit, full on stagger exit
  11. Add Stagger state to `scenes/enemies/enemy.tscn`
  12. Create `tests/unit/test_poise.gd`: flinch keeps telegraph, stagger breaks attack, refill schedule, ×1.25 damage, zero-poise staggers

- [ ] G3: C3 feat/combat-core-attack-timeline — cancel windows, unified buffer, heavy charge state

  **Why it matters:** Cancel windows and unified buffer fix stiffness (A4). HeavyCharge state and perfect release add build depth and charge visibility.

  **Success criteria:**
  - Import 0, tests green (C3 and C5 don't require smoke test, only input/state)
  - Manual feel pass recorded in `specs/WEEKLY.md`
  - AttackSpec.combo_cancel_at and dodge_cancel_at fields exist, set on all specs
  - WeaponData.charge_move_factor field exists and defaults to 0.3
  - Input buffer is unified: one slot, last-press-wins, 0.2 s lifetime, holds LIGHT | HEAVY_PRESS | DODGE | SKILL
  - Buffer fires at first legal frame (combo_cancel_at for combos, dodge_cancel_at for dodges, etc.)
  - Combo reset timer starts at attack **end**, not attack press
  - HeavyCharge state exists: charge ring fills, move speed scales to charge_move_factor, perfect release (+20% damage/poise) fires within 0.15 s of full
  - Events.heavy_attack_released(player, charge) signal emits on release
  - Charge held past full keeps full charge, loses perfect bonus

  **Sub-tasks:**
  1. Add `AttackSpec.combo_cancel_at: float = 0.4` (fraction of recovery) and `AttackSpec.dodge_cancel_at` fields in `scripts/data/attack_spec.gd`
  2. Set combo_cancel_at and dodge_cancel_at on all existing specs (pickaxe light/finisher/heavy, crossbow specs)
  3. Add `WeaponData.charge_move_factor: float = 0.3` field in `scripts/data/weapon_data.gd`
  4. Rewrite input buffer in `AttackController`: one slot, last-press-wins, 0.2 s, fires at first legal frame for the buffered action
  5. Modify `Attack` state to report cancel windows: expose combo_cancel_at and dodge_cancel_at so controller knows when to allow next action
  6. Change `WeaponController` combo timer to start at `end_swing()` instead of `take_light()` / `take_heavy()`
  7. Create `scenes/player/states/heavy_charge.gd` state: move speed = charge_move_factor, charge ring (fills 0–1 over heavy_charge_seconds), perfect release check (within 0.15 s of full)
  8. Add charge ring visual (placeholder geometry or sprite) that fills and flashes at full charge
  9. Emit `Events.heavy_attack_released(player, charge)` on release; set `force_perfect = true` if within 0.15 s of full
  10. Add HeavyCharge state to `scenes/player/player.tscn`
  11. Add `Events.heavy_attack_released(player: Player, charge: float)` signal to events.gd
  12. Extend `tests/unit/test_attack_controller.gd`: buffer last-wins, cancel windows apply, charge tiers, perfect release, buffered heavy doesn't drop, combo timer at attack end

- [ ] G4: C4 feat/combat-core-weapon-skill — skill data, cooldown, perfect-dodge trigger

  **Why it matters:** Weapon skill is the game's signature input (dodge → heavy = skill). This PR gates later weapon balance and skill mutations. It's the smallest of the PRs but required for the full combat loop.

  **Success criteria:**
  - Import 0, tests green, two-instance smoke test passes (skill sync goes through RPC/state)
  - Manual feel pass recorded in `specs/WEEKLY.md`
  - WeaponData.skill (AttackSpec) and skill_cooldown_seconds (6.0) fields exist
  - Pickaxe and Crossbow have Phase 1 skills: stronger heavy with distinct shape
  - WeaponController.weapon_skill() method exists, uses TimeManager-scaled cooldown
  - Perfect-dodge window press fires skill if off cooldown, consumes window, otherwise charges heavy
  - Perfect-dodge hit-stop: 3 frames on dodger only, plus visual ping
  - Skill cooldown blocks subsequent fires until expired

  **Sub-tasks:**
  1. Add `WeaponData.skill: AttackSpec` and `skill_cooldown_seconds: float = 6.0` fields in `scripts/data/weapon_data.gd`
  2. Create Phase 1 skills for Pickaxe and Crossbow in `data/weapons/`: stronger heavy AttackSpec with unique shape (e.g., CIRCLE instead of ARC)
  3. Add `skill_cooldown_left: float` tracking and `weapon_skill()` method in `WeaponController`
  4. Use `TimeManager.timer()` for cooldown countdown
  5. Modify `AttackController.apply()` to check `Player.is_perfect_dodge_window()` when heavy is pressed: if true and cooldown ready, call `weapon_skill()` and consume window; else charge heavy
  6. Modify `Player.consume_perfect_dodge_window()` to close the window immediately
  7. Add 3-frame hit-stop on dodger via `TimeManager.hit_stop(player, player, 3)` when dodge lands
  8. Add visual "ping" feedback on successful perfect dodge (placeholder: a brief scale-up or flash)
  9. Create `tests/unit/test_weapon_skill.gd`: skill fires in window only, consumes window, cooldown blocks second fire, outside window charges heavy
  10. Test co-op skill sync in two-instance smoke test

- [ ] G5: C5 feat/combat-core-player-reactions — light-hit flinch, shape caching, CI test, telegraph ring

  **Why it matters:** Light-hit flinch fixes stunlock on co-op players (A8). Shape caching removes per-frame allocations (A9). RING telegraph unblocks boss patterns (A10). This is the final combat-core PR and unlocks later balance work.

  **Success criteria:**
  - Import 0, tests green (no smoke test required, only state/input changes)
  - Manual feel pass recorded in `specs/WEEKLY.md`
  - AttackPattern.is_heavy and poise_damage fields exist and are set on all patterns
  - TelegraphShape.RING exists and draws in telegraph.gd
  - Player.apply_knockback() handles light hits (flinch: knockback + flash, keep control) vs heavy hits (full HitStun)
  - Shape2D allocated once per spec + charge bucket and per pattern; no per-swing allocation
  - CI test: every AttackPattern has active_seconds > 0 and recovery_seconds >= 0.3
  - test_hit_reactions.gd updated: light hit keeps control, heavy hit stuns

  **Sub-tasks:**
  1. Add `AttackPattern.is_heavy: bool` and `poise_damage: float` fields in `scripts/data/attack_pattern.gd`
  2. Add `TelegraphShape.RING` enum value to `AttackPattern`
  3. Set `is_heavy` and `poise_damage` on all enemy attack patterns
  4. Implement RING telegraph drawing in `Telegraph` (placeholder circle or ring shape)
  5. Modify enemy `attack.gd` _build_hit to set `hit.is_heavy = _pattern.is_heavy`
  6. Rewrite `Player.apply_knockback()`: light hit is flinch (knockback impulse, flash, 0.4 s i-frames, keep control); heavy hit is full HitStun
  7. Cache melee Shape2D in WeaponController by `(spec, charge_level)` key; reuse per swing
  8. Cache melee Shape2D in enemy attack state by `pattern` key; reuse per swing
  9. Add CI test in `tests/integration/test_combat_validation.gd`: every AttackPattern has `active_seconds > 0` and `recovery_seconds >= 0.3`, windup >= 0.2
  10. Update `tests/unit/test_hit_reactions.gd`: light hit keeps control and i-frames, heavy hit enters HitStun, shape cache no-alloc check
  11. Test shape cache doesn't allocate per-frame in headless import and test runs

---

## Assumptions and Decisions

1. **Dev A owns C1–C5** per capability map; Dev B review gate implicit for shared systems.
2. **Hit-stop tiers** are global constants in one place (e.g., `constants/combat_feedback.gd`), reused by TimeManager calls.
3. **Poise refill** uses `TimeManager.timer()` for scaled 1.5 s idle, then 50%/sec linear refill.
4. **Buffer fires at first legal frame** = earliest frame when the current attack's cancel window for that action opens.
5. **Perfect release** is within 0.15 s of reaching max charge, not "on full"; holding 0.16 s+ loses the bonus.
6. **Stagger always cancels attack** regardless of pattern type; only flinch if poise remains > 0.
7. **Feedback RPC** carries all data; `CombatFeedback` node (local, per peer) receives and plays it; `World._on_hit_landed` only emits the RPC.
8. **Weapon skill** is an `AttackSpec` in `WeaponData.skill`, not a separate class; reuses attack machinery.
9. **Perfect dodge consumes the window** immediately on skill fire; won't reopen until next dodge lands.
10. **Spec updates** (SPEC-combat-core.md, proposal status) happen after C5 merges, not per-PR.

---

## Build sequence

1. Commit `docs/proposals/combat-v2.md` to C1 branch (already approved, unmarked as uncommitted)
2. C1 → C2 → C3 → C4 → C5 in order; each merges to main before the next starts
3. After C5 merges: update SPEC-combat-core.md and proposal status line to "Implemented"

---

## Definition of Done (all five PRs)

- [ ] All five PRs merged into main with CI green
- [ ] Each PR has passed `bash tools/smoke_two.sh` (C1, C2, C4 required; C3, C5 optional)
- [ ] Manual feel pass recorded in `specs/WEEKLY.md` for each PR
- [ ] `specs/SPEC-combat-core.md` updated to reflect all changes: attack input layer, hit reactions, hit feedback, poise system, AttackPattern fields
- [ ] `docs/proposals/combat-v2.md` status line reads "Implemented"
