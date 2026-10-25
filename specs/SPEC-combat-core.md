# Spec: combat-core

| | |
|---|---|
| Module id | `combat-core` |
| Owner | Dev A |
| Weeks | 2 |
| Design doc | section 6, section 7 (attack inputs), section 23 (perf) |
| Depends on | `player-controller`, `stats-status`, `time-manager` |
| Depended on by | `enemies-ai`, `weapons`, `abilities`, `bosses`, `effect-system` |

## Objective

Hits that feel good and are fair: shared Health, Hitbox, and Hurtbox components for players, enemies, and bosses; the attack input layer (light combo, heavy charge, swap); hit-stun, knockback, post-hit i-frames; hit feedback; and the windup, active, recovery contract every enemy attack follows.

## Scope

### Components (`scripts/components/`)

- `Health`: `max_hp` from `StatBlock.MAX_HP`, `current_hp`, `apply_damage(hit: HitInfo)`, `heal(amount, source)`, signals `damaged(hit)`, `healed(amount)`, `about_to_die(hit)` (effects like Second Wind, Undying, Twin Souls set `hit.prevented = true`), `died(hit)`. Healing respects `TOXIN` penalty and Coward's Cloak. Overheal hook for Oracle shields.
- `Hitbox` (Area2D): carries a `HitInfo` template, `active: bool`, `hit_once_per_target: bool`, collision layer `hitbox_player` or `hitbox_enemy`. On overlap with a `Hurtbox` of the opposing team, calls `hurtbox.receive(hit_info_copy)`. Can be a shape or a sweep (for melee arcs, enabled for the active frames only).
- `Hurtbox` (Area2D): `invulnerable: bool`, `team: Team`, `receive(hit)` on the host: if invulnerable and owner is a player mid-dodge, report `blocked_during_dodge` to `Player` for the perfect-dodge check; else compute damage via `Damage.compute`, pass to `Health`, apply `knockback`, apply statuses from `hit.statuses`, emit `Events.hit_landed`. From-behind detection: angle between target facing and hit direction > 120 degrees sets `hit.from_behind` (Rogue Backstab, Geode Turtle, Heart Guard).
- `Team` enum: `PLAYER, ENEMY, NEUTRAL` (destructibles). Minions and turrets are `PLAYER`.

### HitInfo

RefCounted, created by the attacker, copied per target:

```gdscript
class_name HitInfo extends RefCounted
var source: Node                 # attacker entity (player, enemy, minion, turret)
var owner_player: Player         # for attribution of minion/turret/proc hits
var base_damage: float
var multiplier: float = 1.0
var bonus_crit_chance: float = 0.0
var element: Element = Element.NONE
var statuses: Array[StatusApplication]   # status + stacks to apply on hit
var knockback: Vector2
var hit_stun_seconds: float = 0.15
var is_heavy: bool
var poise_damage: float          # drained from the target's poise (light 10, finisher 20, heavy 30+)
var staggered: bool              # set by the target's poise logic before hit_landed
var is_projectile: bool
var is_crit: bool                # filled by Damage.compute
var from_behind: bool            # filled by Hurtbox
var final_damage: int            # filled by Damage.compute
var tags: Array[StringName]      # weapon id, ability id, "melee", "ranged", "proc"
var proc_depth: int = 0          # effect-system increments
var prevented: bool = false      # set by about_to_die handlers
```

Decision 2026-10-21 (Dev A and Dev B): **`HitInfo` replaces `HitData`.** `scripts/components/hit_data.gd` (`class_name HitData`) is stats-status's week-2 stand-in for this class, written while W2-A1 was open; it already carries the damage-relevant fields above under the same names plus `owner_player`, `target`, `proc_depth`, `force_crit` and `scales_with_ability_power`. When W2-A1 lands, that script becomes `HitInfo` (rename, same file moved to `scripts/components/hit_info.gd`, fields merged with the list above, `target` and the two compute flags kept), and every `HitData` reference (`Events` signal types, `Damage.compute`, `StatusEffects`, the relic effect scripts, `LootDrops`, test helpers) is retyped in the same PR. There is no second payload type and no adapter between the two.

### Attack input layer (`AttackController` on player)

- `attack_light` press: advance the current weapon's light combo (step index resets after 0.6 s idle). Buffer one input during active frames so mashing feels responsive.
- `attack_heavy` hold: enter `AttackHeavyCharge`, charge 0 to 1 over the weapon's `heavy_charge_seconds` (Warrior affinity 25% faster, Heavy Hands node). Release fires `AttackHeavyRelease` with `charge` passed to the weapon. Tap (<0.15 s) fires uncharged heavy.
- Weapon skill trigger: `attack_heavy` pressed while `Player.is_perfect_dodge_window()` fires `WeaponController.weapon_skill()` instead, if off cooldown (details in `SPEC-weapons.md`).
- `swap_weapon`, `weapon_1`, `weapon_2`: swap, 0.2 s lockout; Dual Wielder node triggers a free heavy on swap.
- Attack speed: animation `speed_scale = StatBlock.ATTACK_SPEED`.
- Movement during attacks: light attacks allow 50% move speed; heavy charge allows 30%; this is a weapon-type parameter.

### Hit reactions

- **Poise and stagger (enemies, combat v2 C2)**: every enemy has a poise pool (`EnemyData.poise`: 0 for fodder like Rock Tick, 40 Hollow Miner, 20 Lantern Wisp, 300+ for bosses). A hit drains `HitInfo.poise_damage * (1 - stagger_resist)` (light 10, finisher 20, heavy 30 + 30 x charge; `AttackSpec.poise_damage`). `Hurtbox` calls the target's `absorb_hit_poise(hit)` before `hit_landed`, which sets `hit.staggered` when the hit broke the pool.
  - **Poise above 0 after the hit: flinch.** Knockback (scaled by `knockback_resist`), flash and hit-stop only. No state change, so a windup keeps winding up and its telegraph stays.
  - **Poise broke, or the enemy has 0 poise: `Stagger`** (`scenes/enemies/states/stagger.gd`) for `EnemyData.stagger_seconds` (default 0.8 s). It cancels the attack and clears the telegraph, the enemy takes **+25% damage** (a `Hurtbox` damage-taken factor, never a base-stat edit), poise refills to full on exit, and `Events.enemy_staggered(enemy, hit)` fires. A hit on an already staggered enemy drains nothing and does not restart the stagger. A hit with 0 poise damage never staggers fodder.
  - **Refill**: 1.5 s after the last hit, 50% of the pool per second, in `TimeManager`-scaled time.
  - **Sync**: poise is host only. The `staggered` flag rides the enemy's StateSync so every peer can draw the dazed marker. Stagger feedback: 8 frames of hit-stop, shake 4, a 6-frame flash and a "STAGGER" pop (see Hit feedback).
  - The older two-argument `apply_knockback(impulse, stun_seconds)` (no hit) still gives a plain `HitStun`; `Hurtbox` passes the hit as a third argument to any entity whose method declares it.
- **Hit-stun (players)**: the target enters `HitStun` for `hit.hit_stun_seconds`. Enemy `stagger_resist` no longer shortens a stun; it scales poise damage.
- **Knockback**: impulse along hit direction scaled by `hit.knockback.length()`, decays over 0.2 s, blocked by walls. Enemies with `knockback_resist`. Stone Skin and Battle Cry grant immunity.
- **Post-hit i-frames**: players get 0.4 s `invulnerable` after any damage (design doc: brief invincibility). Enemies do not.

### Hit feedback

Every landed hit plays its feedback on every peer (combat v2 C1, `docs/proposals/combat-v2.md` 3.6). The host sees `Events.hit_landed`; a local `CombatFeedback` node (one per peer, created by `World` under the fixed name `CombatFeedback`) applies hit-stop through `TimeManager` and sends one unreliable `call_local` RPC to every peer carrying `{target_path, final_damage, is_crit, is_heavy, staggered}` (plus `point` for the spark and `boss_kill` for the shake tier). Each peer plays the number, flash, shake and spark from that copy. `Events.hit_landed` keeps its signature.

| Event | Hit-stop (frames) | Shake (px) | Flash | Other |
|---|---|---|---|---|
| Light hit | 3 | none | 4 frames white | small spark |
| Finisher or heavy | 6 | 2 | 4 frames white | large spark |
| Crit | +2 | +1 | 4 frames gold | crit number |
| Player hurt | 4, on the player only | 3, local player only | 4 frames red | |
| Boss kill | 10 | 8 | n/a | |

The numbers live in one table, `CombatFeedbackConstants` (`scripts/combat/combat_feedback_constants.gd`). A finisher is the last step of a weapon's light combo (`WeaponController.build_hit` tags it `finisher`).

- **Hit-stop**: `TimeManager.hit_stop(attacker, target, frames)` on the host, which broadcasts it. Projectile hits freeze the target only; a hit on a player freezes the player only. `StateMachine.physics_update` multiplies every state's delta by `TimeManager.scale_for(actor)` and does not step a state at all at scale 0, so players and enemies actually stop; states that set `velocity` directly scale it by `machine.effective_scale`.
- **Hit flash**: `hit_flash.gdshader` (`flash_amount`, `flash_color`) on the enemy body and sprite and the player sprite, driven by `HitFlash`.
- **Slash arc**: `SlashArc` draws the attack's real shape (`AttackSpec.shape`, `reach` with the charge bonus, `arc_degrees`) for the active window. `WeaponController.begin_swing` plays it on the owner and the host; the host sends an unreliable RPC to the other clients.
- **Spark**: `HitSpark` at the hit point, small for a light hit, large for a heavy one.
- **Damage numbers**: `DamageNumber` labels in `World/FX`; crits larger and gold. Local only, from the RPC above.
- Hit SFX hook: `AudioManager.play_sfx("hit_<weapon_type>")` (not wired yet).

### Enemy attack contract

Every enemy and boss attack is an `AttackPattern` Resource with three phases driven by the state machine:

```
windup   : telegraph shown (shape outline on the ground, sprite tint, sound), no hitbox, duration >= 0.3 s (0.2 s for fast enemies with a distinct sound)
active   : hitbox enabled for the listed frames
recovery : enemy vulnerable, cannot act, duration >= 0.3 s
```

`Telegraph` scene: draws a ground shape (`circle`, `cone`, `line`, `ring`) that fills from 0 to 100% over the windup. The Pit's Eye relic multiplies windup display lead by showing it 0.5 s earlier (telegraph fills over `windup + 0.5`, attack still fires at the original time). Telegraph drawing is `combat-core`; which pattern each enemy uses is `enemies-ai`.

### Projectiles

`Projectile` base scene with `Hitbox`, pooled through `ProjectilePool` (per scene type, grow-on-demand, pre-warm 64 per common type). Supports `pierce_count`, `bounce_count`, `homing_strength`, lifetime, `reflectable` (Guardian block, Crystal Hollows crystals), and `Unmake` erasure. Enemy projectiles respect `TimeManager.scale_for(self)`.

## Interfaces provided

`Health`, `Hitbox`, `Hurtbox`, `HitInfo`, `StatusApplication`, `Team`, `AttackController`, `AttackPattern`, `Telegraph`, `Projectile`, `ProjectilePool`, `DamageNumberPool`. Events emitted here: `hit_landed`, `crit_landed`, `player_damaged`, `heavy_attack_released(player, charge)`, `weapon_swapped(player, index)`, `enemy_staggered(enemy, hit)`. Signal definitions live in `SPEC-effect-system.md`.

## Interfaces consumed

- `player-controller`: `Player`, state machine, `is_perfect_dodge_window()`, `GameCamera.shake()`.
- `stats-status`: `StatBlock`, `Damage.compute()`, `StatusEffects`.
- `time-manager`: `hit_stop`, `scale_for`.
- `networking`: hit resolution only on host; `hit_landed` broadcast for feedback.

## Data model

`AttackPattern` (Resource): `id`, `windup_seconds`, `active_frames: int`, `recovery_seconds`, `telegraph_shape`, `telegraph_size: Vector2`, `hit: HitInfo` template fields, `animation: String`, `sfx_windup`, `sfx_hit`. Stored under `data/enemies/attacks/` and `data/bosses/attacks/`, owned by `enemies-ai`/`bosses` but the class is defined here.

## Multiplayer ownership

Hit detection and damage: host only (`Hurtbox.receive` early-returns on clients). Hit feedback (flash, numbers, shake for the local player, sparks) runs on every peer from the `CombatFeedback` RPC the host sends for each `hit_landed`; hit-stop is applied on the host and replicated by `TimeManager`. Attack animations start on the input-owning client immediately for feel; the host starts them one RTT later and is the source of truth for hitbox timing.

Sync: host-authoritative; `Hitbox.active` is not synced (host only); `Health.current_hp` via `StateSync`.

## Testing

- Unit: `test_health.gd` (about_to_die prevention, heal with Toxin, overheal hook), `test_hit_info.gd` (from_behind angle math), `test_attack_controller.gd` (combo step reset, buffer, charge value at release, swap lockout).
- Integration: scripted enemy with one `AttackPattern`; assert no hit during windup, hit during active frames, none during recovery; player perfect dodge during active frames reports blocked.
- Perf: `debug-tools` perf scene fires 500 pooled projectiles; no allocations after warm-up (check `Performance.OBJECT_NODE_COUNT` stable).
- Manual feel pass weekly.

## Success criteria

- [ ] Light combo, heavy charge and release, swap all work on the Pickaxe and Crossbow in week 2.
- [ ] 3 enemies attack through windup, active, recovery with visible telegraphs; none can hit without a telegraph (CI test asserts every `AttackPattern` has `windup_seconds >= 0.2`).
- [ ] Hit flash, shake, hit-stop, and damage numbers on every hit; crits visibly different.
- [ ] Perfect dodge registers only when a hit was actually blocked.
- [ ] All of the above synced in two-instance smoke.

## Open questions

- Melee hitbox: shape overlap vs sweep. Start with shapes enabled on active frames; revisit if fast weapons (Twin Daggers) miss at high attack speed.
