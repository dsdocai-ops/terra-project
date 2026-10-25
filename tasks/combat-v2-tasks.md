# Combat v2: task list for handoff

The design source is [docs/proposals/combat-v2.md](../docs/proposals/combat-v2.md), approved 2026-10-24. Read it first, then follow `CLAUDE.md` and `specs/SPEC-project.md`.

## Rules that apply to every task

- Branch off `main` as `feat/<module-id>-<desc>`. Each step below is one PR into `main`.
- Use strict static typing. Every stateful script gets a doc comment that says who owns it and how it syncs.
- Gameplay runs on the host only. Never touch `Engine.time_scale`; use `TimeManager`. Never edit base stats; use `StatBlock` modifiers.
- Tests ship in the same PR, written red first. Never skip or delete a failing test.
- In GUT, `.connect(lambda)` never fires, so use named method callbacks. Clear `TimeManager` sources in `after_each`.
- Before every PR, all of these must pass:
  - `godot --headless --path . --import` exits with 0 errors.
  - The full GUT suite is green.
  - The two-instance smoke test passes (`tools/smoke_two.sh`), required for any change that touches sync.
  - A manual feel pass is recorded in `specs/WEEKLY.md`.
- Use only "Dev A" and "Dev B" in files, commits and PRs, never real names.
- Ask a human before editing a `.tscn` owned by the other lane. Ownership is in `SPEC-project.md#ownership`.
- The section 4 changes to data resources and `Events` are **already approved**. Anything beyond them still needs a human decision.
- `docs/proposals/combat-v2.md` is uncommitted on `feat/art-audio-v2-pipeline`. Commit it to the first combat branch.

---

## C1 `feat/combat-core-hit-feedback`: hit feedback (proposal 3.6)

No data or signal changes.

- [ ] **Make hit-stop actually freeze entities.** `TimeManager.hit_stop(a, b, frames)` exists ([time_manager.gd:89](../scripts/autoload/time_manager.gd)), but the player and enemy state machines never read `TimeManager.scale_for()`. Only `StatusEffects`, `Pickup` and active relics do. Multiply `delta` by `TimeManager.scale_for(entity)` in the player and enemy state-machine ticks: `scenes/player/states/*.gd` and `scenes/enemies/states/*.gd`, or once in their state machine's `physics_update` dispatch. Anything that sets velocity directly (Attack `_steer`, Dodge, HitStun, enemy RUSH) must zero or freeze motion while the scale is 0.
- [ ] **Call hit-stop on every landed hit** (host side, from `hit_landed` handling). Use these tiers:
  - light 3 frames
  - finisher or heavy 6 frames
  - crit +2
  - player hurt 4 frames, on the player only
  - boss kill 10 frames

  Put the tier numbers in one constants table.
- [ ] **Create `hit_flash.gdshader`**: a white overlay with a `flash_amount` uniform and a `flash_color` uniform. Apply it to enemy sprite materials and the player sprite. Flash for 4 frames on a hit (white, or gold on a crit). This replaces the player's modulate tint at [player.gd:221](../scenes/player/player.gd).
- [ ] **Replicate feedback to clients.** Today `World._on_hit_landed` ([world.gd](../scenes/main/world.gd), about line 157) only runs on the host.
  - Add a `CombatFeedback` node: local, one per peer, under `World`.
  - The host sends an unreliable RPC carrying `{target_path, final_damage, is_crit, is_heavy, staggered=false}`.
  - Every peer, host included, plays the damage number, flash, shake and spark from that RPC.
  - Keep the `Events.hit_landed` signature unchanged.
  - Move the existing number and shake code out of `world.gd` into `CombatFeedback`. `world.tscn` is a shared scene, so ask a human before editing it.
- [ ] **Shake tiers:**
  - light none
  - heavy 2
  - crit +1
  - player hurt 3, local player only
  - boss kill 8
- [ ] **Slash VFX.** Add a `SlashArc` node (a placeholder drawn with `_draw()` or a sprite) shaped from `AttackSpec.shape`, `reach`, `arc_degrees` and the charge reach bonus. It plays for the attack's active window, from `WeaponController.begin_swing` and `end_swing`. It must run on every peer, because the Attack state already runs on the owning client and on the host. Remote peers need a trigger too: drive it from replicated state or an RPC.
- [ ] **Add a spark** at the hit point: small for a light hit, large for a heavy hit.
- [ ] **Tests**, in a new `tests/unit/test_combat_feedback.gd`:
  - Hit-stop is called with the right frames for each tier.
  - An entity with scale 0 does not move for N frames.
  - A client receives the feedback RPC and spawns a number.
  - The flash runs and resets.
  - Update `test_hit_reactions.gd` if the timing changes.

## C2 `feat/combat-core-poise`: poise and stagger (proposal 3.1)

- [ ] Add `EnemyData.poise: float` and `EnemyData.stagger_seconds: float = 0.8` ([enemy_data.gd](../scripts/data/enemy_data.gd)). Set values in `data/enemies/collapsed_mines/`:
  - `rock_tick` 0
  - `hollow_miner` ~40
  - `lantern_wisp` ~20
- [ ] Add `AttackSpec.poise_damage: float`. Set it in `data/weapons/pickaxe.tres` and `crossbow.tres`:
  - light 10
  - finisher 20
  - heavy 30 (the controller adds +30 × charge)
- [ ] Add `HitInfo.poise_damage` and `HitInfo.staggered`, and copy them in `copy()`. Fill them in `WeaponController.build_hit`.
- [ ] Add `Events.enemy_staggered(enemy: Node, hit: HitInfo)` and its row in the signal table in `SPEC-effect-system.md`. Add an emitter method to `tests/helpers/event_emitter.gd`. The conformance tests `test_events_bus.gd` and `test_events_emitters.gd` will fail until you do.
- [ ] **Rewrite `Enemy.apply_knockback`** ([enemy.gd:274](../scenes/enemies/enemy.gd)):
  - Subtract `poise_damage × (1 − stagger_resist)` from poise.
  - Poise still above 0: flinch. Apply knockback, flash and hit-stop with **no state change**, so the windup keeps going.
  - Poise breaks, or the enemy has 0 poise: enter the new `Stagger` state, which cancels the attack and clears the telegraph.
- [ ] **Poise refill:** after 1.5 s without a hit, refill 50% per second. Use `TimeManager`-scaled time. Refill to full when the enemy leaves `Stagger`.
- [ ] **New enemy state** `scenes/enemies/states/stagger.gd`, added to `enemy.tscn`. Damage taken while staggered is ×1.25. Apply it as a `StatBlock` modifier or a hurtbox damage multiplier, never a base stat edit.
- [ ] **Sync:** poise is host-only. Replicate the `staggered` flag through the existing enemy state sync for visuals.
- [ ] **Feedback:** set `staggered=true` in the C1 feedback RPC. Stagger gets 8 frames of hit-stop, shake 4, a 6-frame flash and a "STAGGER" pop.
- [ ] **Tests**, in a new `test_poise.gd`:
  - A flinch keeps the windup and its telegraph.
  - A break cancels the attack and emits `enemy_staggered`.
  - Poise refills on schedule.
  - The ×1.25 damage applies while staggered.
  - A 0-poise enemy staggers on every hit.

## C3 `feat/combat-core-attack-timeline`: buffer, cancels, heavy charge (proposal 3.2 + 3.3)

- [ ] Add `AttackSpec.combo_cancel_at: float = 0.4` (a fraction of recovery) and `AttackSpec.dodge_cancel_at`, which defaults to the end of active.
- [ ] Add `WeaponData.charge_move_factor: float = 0.3`.
- [ ] **Replace the light-only buffer** in [attack_controller.gd](../scripts/combat/attack_controller.gd) with one slot (last press wins, 0.2 s). It holds `LIGHT | HEAVY_PRESS | DODGE | SKILL` and fires at the first frame that's legal for that action.
- [ ] **Attack state** ([attack.gd](../scenes/player/states/attack.gd)) reports its cancel windows. The controller can start the next combo step after `combo_cancel_at`, and can dodge after `dodge_cancel_at`.
- [ ] **Combo reset:** in [weapon_controller.gd](../scripts/weapons/weapon_controller.gd), start the 0.6 s timer when the attack ends, not when it's pressed.
- [ ] **New player state** `HeavyCharge` (`scenes/player/states/heavy_charge.gd`, added to `player.tscn`):
  - It's entered on heavy press, or from the buffer.
  - Move speed is `charge_move_factor`.
  - A charge ring around the player fills.
  - At full charge the ring flashes and plays an SFX hook.
  - Releasing within 0.15 s of full is a **perfect release**: +20% damage and +poise damage.
  - Holding past full keeps the full charge and loses the perfect bonus.
  - A tap under 0.15 s fires an uncharged heavy.
  - Emit `Events.heavy_attack_released(player, charge)`, host only.
- [ ] **Sync:** the owning client predicts, and the host validates as `AttackController.send` and `_request` do today. Send the charge value with the release.
- [ ] **Tests:** create or extend `test_attack_controller.gd`:
  - The buffer keeps the last press.
  - Each buffered action fires at its legal frame.
  - Cancel windows apply.
  - The combo timer starts at attack end.
  - Charge tiers and perfect release work.
  - A heavy released while busy is buffered, not dropped.

## C4 `feat/combat-core-weapon-skill`: perfect dodge to weapon skill (proposal 3.4)

- [ ] Add `WeaponData.skill: AttackSpec` and `WeaponData.skill_cooldown_seconds: float = 6.0`. Give the Pickaxe and Crossbow a Phase 1 skill: a stronger heavy with a distinct shape.
- [ ] Add `WeaponController.weapon_skill()` and a cooldown that uses `TimeManager`-scaled time.
- [ ] **AttackController:** pressing heavy while `Player.is_perfect_dodge_window()` is open fires the skill if it's off cooldown and calls `consume_perfect_dodge_window()`. Otherwise it goes to `HeavyCharge`.
- [ ] **Perfect-dodge feedback:** 3 frames of hit-stop on the dodger plus a visual ping. Emit `Events.player_dodged(player, perfect)` if it isn't emitted already (W4-A4).
- [ ] **Tests**, in a new `test_weapon_skill.gd`:
  - The skill fires only inside the window.
  - It consumes the window.
  - The cooldown blocks a second fire.
  - Outside the window the press charges a heavy.

## C5 `feat/combat-core-player-reactions`: player reactions and housekeeping (proposal 3.5 + 3.7)

- [ ] Add `AttackPattern.is_heavy: bool`, `AttackPattern.poise_damage`, and `TelegraphShape.RING`. Draw the ring in [telegraph.gd](../scripts/combat/telegraph.gd).
- [ ] **Enemy hits:** `enemies/states/attack.gd` `_build_hit` sets `hit.is_heavy` from the pattern.
- [ ] **`Player.apply_knockback`** ([player.gd:231](../scenes/player/player.gd)):
  - A light hit is a flinch only: knockback impulse and flash, the player keeps control, and the 0.4 s i-frames still apply.
  - A heavy hit is the full `HitStun`, as today.
- [ ] **Shape cache:** build each melee `Shape2D` once per spec and charge bucket in `WeaponController._melee_shape`, and per pattern in `enemies/states/attack.gd` `_cone_shape`. Don't allocate a shape per swing.
- [ ] **CI test:** every `AttackPattern` has `active_seconds > 0` and `recovery_seconds >= 0.3`. Keep the existing `windup >= 0.2` check.
- [ ] **Tests:** update `test_hit_reactions.gd` so a light hit keeps control and a heavy hit stuns. Add a no-allocation check for the shape cache. Add a draw test for the ring telegraph.

## Deferred: do not build

- C6, co-op attack tokens (proposal 3.8). The decision was "later" and it belongs to `enemies-ai`.

## Done when

- C1 to C5 are merged into `main` with CI green.
- Each PR has passed the two-instance smoke test and a manual feel pass recorded in `specs/WEEKLY.md`.
- `specs/SPEC-combat-core.md` is updated to match: attack input layer, hit reactions, hit feedback, poise, and the `AttackPattern` fields.
- The proposal's status line reads "Implemented".
