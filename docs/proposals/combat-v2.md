# Proposal: combat v2

| | |
|---|---|
| Status | **Approved 2026-10-24** (C1 to C5; C6 deferred). Nothing implemented yet |
| Modules | `combat-core` (primary), `weapons`, `player-controller`, `enemies-ai` |
| Design doc | section 1 pillar 3, section 6, section 7 |
| Supersedes on approval | parts of `specs/SPEC-combat-core.md` "Attack input layer", "Hit reactions", "Hit feedback" |

Nothing here cuts design-doc scope. Every change either makes a locked rule actually happen in game or changes *how* a rule is met. The rows marked **Ask first** touch `scripts/data/` Resources or the `Events` bus and need sign-off under the project's hard rules.

## 1. What the current code does (audit)

Read against the tree at `b0b813e`.

| # | Finding | Where | Effect on play |
|---|---|---|---|
| A1 | **Any hit cancels any enemy attack.** `Enemy.apply_knockback` switches to `HitStun` whenever `hit_stun_seconds > 0`, which clears the telegraph mid-windup. No enemy has `stagger_resist` set. | `scenes/enemies/enemy.gd:274` | A light combo stunlocks every enemy forever. Telegraphs (pillar 3) never matter because nothing finishes a windup while you're hitting it. Bosses would have the same problem. |
| A2 | **Weapon skill isn't wired.** The perfect-dodge window opens (`Player._on_dodge_blocked`) but nothing calls `is_perfect_dodge_window()`, and there's no `weapon_skill()` anywhere. | `scenes/player/player.gd:535`, `scripts/combat/attack_controller.gd` | The game's signature input (dodge through an attack, then press heavy) does nothing. |
| A3 | **Heavy charge has no state.** Holding `attack_heavy` only counts a float. The player walks at full speed, there's no charge visual, and the spec's 30% move speed while charging isn't applied. On release, a heavy that arrives while the player is busy is dropped. | `attack_controller.gd:38-46,95` | Heavies feel like a delayed light attack, and players get no read on how far the charge is. |
| A4 | **No cancel windows.** An attack locks the player until recovery ends. Only dodge interrupts it, and only light attacks are buffered (0.25 s). | `scenes/player/states/attack.gd`, `attack_controller.gd:58` | Combos feel stiff at low attack speed, and heavy or skill presses during a swing are lost. |
| A5 | **Hit-stop is never called.** `TimeManager.hit_stop` exists and nothing uses it. | `scripts/autoload/time_manager.gd:89` | Hits have no weight. This is the single biggest feel gap. |
| A6 | **Feedback runs on the host only.** `World._on_hit_landed` draws damage numbers and shake from a signal that only fires on the host. | `scenes/main/world.gd:157` | Clients in co-op see no damage numbers and no shake. The spec says feedback runs on every peer. |
| A7 | **No swing visual.** The Attack state plays `idle`. Enemies get no hit flash (only the player gets a modulate tint). | `attack.gd:31`, `player.gd:221` | Players can't see their own reach or what they hit. |
| A8 | **Player hit-stun removes control on every hit** (0.15 to 0.3 s), and knockback comes on top of that. | `player.gd:231`, `scenes/player/states/hit_stun.gd` | With 4 players and packs of enemies, chip hits from small enemies cost a lot of control. |
| A9 | A new `Shape2D` is allocated on every swing and every enemy attack. | `weapon_controller.gd:155`, `enemies/states/attack.gd:102` | Minor. It goes against the perf section's no-allocations-after-warm-up rule. |
| A10 | Telegraph supports `CIRCLE, CONE, LINE`. The spec also lists `ring`. | `scripts/data/attack_pattern.gd:10` | Blocks boss patterns later. |

## 2. Design goals

1. **Fair:** every enemy attack that has a telegraph either finishes or is broken by a deliberate player action (stagger, a heavy, a skill). Chip damage never cancels it.
2. **Weighty:** every landed hit has hit-stop, a flash and a sound. Heavies and staggers are louder than lights.
3. **Responsive:** whatever the player presses during a swing is buffered and plays at the first legal frame.
4. **Build-friendly:** the new numbers (poise damage, cancel windows, charge tiers) are data on `AttackSpec`, `AttackPattern` and `EnemyData`, so mutations and relics change them through `StatBlock` modifiers and never through new systems.

## 3. Proposed changes

### 3.1 Poise and stagger (fixes A1)

Every combat entity gets a poise pool. Hits drain it, and it refills after a short delay.

- `EnemyData.poise: float` (0 for fodder like Rock Tick, ~40 for Hollow Miner, 300+ for bosses). It refills after 1.5 s without being hit, at 50% per second. **Ask first**
- `AttackSpec.poise_damage: float` (defaults: light 10, light finisher 20, heavy 30 + 30 × charge). `HitInfo.poise_damage` carries the value. **Ask first**
- How a hit resolves on an enemy:
  - **Poise above 0 after the hit:** *flinch*. Flash, hit-stop and knockback scaled by `knockback_resist`, with **no state change**. An enemy in windup keeps winding up.
  - **Poise breaks:** enter `Stagger` for `EnemyData.stagger_seconds` (default 0.8 s). It cancels the current attack, the enemy takes **+25% damage** while staggered, and poise refills to full on exit. Emits `Events.enemy_staggered(enemy, hit)`. **Ask first** (new signal)
  - **Poise 0 (fodder):** every hit staggers, so trash still feels good to juggle.
- Bosses use the same rule with a large pool. That gives the spec's "stagger windows" a concrete mechanic and also gives relics a hook (`on_stagger`).
- `stagger_resist` stays and scales `poise_damage` taken. `knockback_resist` is unchanged.

### 3.2 Attack timeline and cancels (fixes A4)

`AttackSpec` gets two fields. **Ask first**

```
windup | active | recovery
                 ^ combo_cancel_at   (light/heavy may start the next attack)
       ^ dodge_cancel_at             (dodge may cancel; default = end of active)
```

- `combo_cancel_at: float` is a fraction of recovery, default 0.4. The rest of recovery is skipped when the next combo step starts.
- `dodge_cancel_at`: dodge is allowed from the end of active by default. Windup can only be dodge-cancelled on weapons flagged `light` type.
- **Unified input buffer:** one slot, last press wins, 0.2 s. It holds `LIGHT | HEAVY_PRESS | DODGE | SKILL` and fires at the first frame that's legal for that action. This replaces the light-only buffer.
- The combo reset timer (0.6 s) starts when the attack **ends**, not when it's pressed, so slow weapons at low attack speed don't drop their combo.

### 3.3 A real heavy charge (fixes A3)

- New player state `HeavyCharge` (the spec already names `AttackHeavyCharge`). It's entered on press, or from the buffer at the first legal frame after an attack. Move speed is `weapon.charge_move_factor` (30% default).
- Charge tiers, shown by a ring around the player that fills:
  - **Tap** (< 0.15 s): uncharged heavy.
  - **Partial**: linear 0 to 1 over `heavy_charge_seconds`.
  - **Full**: the ring flashes and plays a sound. Releasing within 0.15 s of full is a *perfect release* with +20% damage and +poise damage. A relic hook is possible later.
- A heavy released while busy is buffered instead of dropped.
- Holding past full doesn't cancel. It keeps the full charge, and the perfect-release bonus is lost.

### 3.4 Perfect dodge to weapon skill (fixes A2)

- `AttackController`: pressing `attack_heavy` while `Player.is_perfect_dodge_window()` calls `WeaponController.weapon_skill()` if it's off cooldown, consumes the window, and goes into `HeavyCharge` otherwise. This follows design doc section 7 exactly.
- `WeaponData.skill: AttackSpec` plus `skill_cooldown_seconds` (6 s). Phase 1 skill for Pickaxe and Crossbow is a stronger heavy with a unique shape. Real per-weapon skills land with `weapons` in week 7. **Ask first**
- Perfect dodge triggers a 3-frame hit-stop on the dodger and a visual "ping" so players learn the timing.

### 3.5 Hit reactions for players (fixes A8)

- **Light enemy hits** (`hit.is_heavy == false`): flinch only. The flash, a short knockback and the 0.4 s i-frames still apply, and the **player keeps control**.
- **Heavy enemy hits** (`AttackPattern.is_heavy`, boss slams): full `HitStun` as today. **Ask first**

This still meets design doc section 6 ("hit-stun, knockback, brief invincibility") for attacks that are meant to punish, and stops chip damage from stunlocking a co-op player.

### 3.6 Feedback everywhere (fixes A5, A6, A7)

| Event | Hit-stop (frames) | Shake | Flash | Other |
|---|---|---|---|---|
| Light hit | 3 | none | 4 frames white | small spark |
| Finisher or heavy | 6 | 2 | 4 frames white | large spark |
| Crit | +2 | +1 | 4 frames gold | crit number |
| Stagger | 8 | 4 | 6 frames white | "STAGGER" pop, distinct SFX |
| Boss kill | 10 | 8 | n/a | as spec |
| Player hurt | 4 on the player only | 3 | red | vignette pulse |

- The host emits `hit_landed`, and a `CombatFeedback` node (local, one per peer) plays everything above from a **replicated** copy: an unreliable RPC carrying `{target_path, final_damage, is_crit, is_heavy, staggered}`. This fixes A6 without changing the `Events` signature.
- Swing VFX: a `SlashArc` sprite matched to `AttackSpec.shape`, `reach` and `arc_degrees` and played on the active frames, so players always see the real hitbox. It's placeholder art until AR-3.
- `hit_flash.gdshader` goes on the enemy sprite material (the spec already requires it).

### 3.7 Housekeeping (A9, A10)

- Build each `AttackSpec`'s melee `Shape2D` once, cache it per spec and charge bucket, and reuse it.
- Add `RING` to `AttackPattern.TelegraphShape` and `Telegraph`. **Ask first**
- `AttackPattern.MIN_WINDUP` is unchanged. A new CI test asserts that every pattern's `active_seconds > 0` and `recovery_seconds >= 0.3`, as the spec says.

### 3.8 Optional: co-op attack tokens (`enemies-ai`)

To keep 4-player rooms readable, each player holds at most **2 attack tokens**. An enemy needs one to start a windup and returns it in recovery. Enemies without a token circle or reposition. It's a cheap change and the standard fix for being swarmed by 6 simultaneous telegraphs. This is `enemies-ai` scope, so it's listed for decision only.

## 4. Data and interface changes (all need sign-off)

| Change | File | Owner |
|---|---|---|
| `AttackSpec`: `poise_damage`, `combo_cancel_at`, `dodge_cancel_at` | `scripts/data/attack_spec.gd` | weapons |
| `WeaponData`: `skill`, `skill_cooldown_seconds`, `charge_move_factor` | `scripts/data/weapon_data.gd` | weapons |
| `EnemyData`: `poise`, `stagger_seconds` | `scripts/data/enemy_data.gd` | enemies-ai |
| `AttackPattern`: `is_heavy`, `poise_damage`, `TelegraphShape.RING` | `scripts/data/attack_pattern.gd` | combat-core |
| `HitInfo`: `poise_damage`, `staggered` | `scripts/components/hit_info.gd` | combat-core |
| `Events.enemy_staggered(enemy: Node, hit: HitInfo)` | `scripts/autoload/events.gd` + `SPEC-effect-system.md` table | effect-system |
| New states `HeavyCharge` (player), `Stagger` (enemy) | `scenes/player/player.tscn`, `scenes/enemies/enemy.tscn` | player-controller, enemies-ai |

No save schema, Input Map, `project.godot` or autoload changes.

## 5. Build order (each step is one PR with tests)

| Step | Branch | Content | Tests |
|---|---|---|---|
| C1 | `feat/combat-core-hit-feedback` | 3.6: hit-stop, flash shader, replicated feedback, slash VFX | `test_combat_feedback.gd`: client receives feedback RPC; hit-stop called with tier frames |
| C2 | `feat/combat-core-poise` | 3.1: poise, flinch vs stagger, `enemy_staggered` | `test_poise.gd`: flinch keeps windup; break cancels; refill; +25% while staggered |
| C3 | `feat/combat-core-attack-timeline` | 3.2 + 3.3: buffer, cancels, `HeavyCharge` | extend `test_attack_controller.gd`: buffer last-wins, cancel windows, charge tiers, perfect release |
| C4 | `feat/combat-core-weapon-skill` | 3.4 | `test_weapon_skill.gd`: fires only in window, consumes window, cooldown |
| C5 | `feat/combat-core-player-reactions` | 3.5 + 3.7 | `test_hit_reactions.gd` updated; shape-cache no-alloc check |
| C6 | `feat/enemies-ai-attack-tokens` | 3.8 (if approved) | `test_attack_tokens.gd` |

Every step runs the two-instance smoke test (C1, C2 and C4 touch sync) and a manual feel pass recorded in `specs/WEEKLY.md`. C1 goes first because it's the largest feel improvement for the least risk, and it makes the later tuning visible.

## 6. Decisions

Recorded 2026-10-24:

1. **Approved:** poise and stagger (3.1) replace "every hit stuns".
2. **Approved:** players get full hit-stun only from heavy enemy hits (3.5). Light hits cause a flinch, knockback and i-frames.
3. **Approved:** all data and `Events` changes in section 4.
4. **Deferred:** co-op attack tokens (3.8). Not built in this pass. Noted for `enemies-ai`.
5. Open: which lane owns C1 to C5? `combat-core` is Dev A's per the capability map.
