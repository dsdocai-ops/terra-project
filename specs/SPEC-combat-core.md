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
var is_projectile: bool
var is_crit: bool                # filled by Damage.compute
var from_behind: bool            # filled by Hurtbox
var final_damage: int            # filled by Damage.compute
var tags: Array[StringName]      # weapon id, ability id, "melee", "ranged", "proc"
var proc_depth: int = 0          # effect-system increments
var prevented: bool = false      # set by about_to_die handlers
```

### Attack input layer (`AttackController` on player)

- `attack_light` press: advance the current weapon's light combo (step index resets after 0.6 s idle). Buffer one input during active frames so mashing feels responsive.
- `attack_heavy` hold: enter `AttackHeavyCharge`, charge 0 to 1 over the weapon's `heavy_charge_seconds` (Warrior affinity 25% faster, Heavy Hands node). Release fires `AttackHeavyRelease` with `charge` passed to the weapon. Tap (<0.15 s) fires uncharged heavy.
- Weapon skill trigger: `attack_heavy` pressed while `Player.is_perfect_dodge_window()` fires `WeaponController.weapon_skill()` instead, if off cooldown (details in `SPEC-weapons.md`).
- `swap_weapon`, `weapon_1`, `weapon_2`: swap, 0.2 s lockout; Dual Wielder node triggers a free heavy on swap.
- Attack speed: animation `speed_scale = StatBlock.ATTACK_SPEED`.
- Movement during attacks: light attacks allow 50% move speed; heavy charge allows 30%; this is a weapon-type parameter.

### Hit reactions

- **Hit-stun**: target enters `HitStun` state for `hit.hit_stun_seconds` (enemies with `stagger_resist` reduce it; bosses mostly immune outside stagger windows).
- **Knockback**: impulse along hit direction scaled by `hit.knockback.length()`, decays over 0.2 s, blocked by walls. Enemies with `knockback_resist`. Stone Skin and Battle Cry grant immunity.
- **Post-hit i-frames**: players get 0.4 s `invulnerable` after any damage (design doc: brief invincibility). Enemies do not.

### Hit feedback

- Hit flash: shader `hit_flash.gdshader` white overlay 4 frames on the sprite material.
- Screen shake: `GameCamera.shake()` light 2 / heavy 5 / boss 8.
- Hit-stop: `TimeManager.hit_stop(attacker, target, frames)` 3 light, 6 heavy, 10 on boss kill.
- Damage numbers: pooled `DamageNumber` labels in `World/FX`, pool size 128; crits larger, element-colored, pop and drift. Local only, driven by `hit_landed` events replicated to clients.
- Hit SFX hook: `AudioManager.play_sfx("hit_<weapon_type>")`.

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

`Health`, `Hitbox`, `Hurtbox`, `HitInfo`, `StatusApplication`, `Team`, `AttackController`, `AttackPattern`, `Telegraph`, `Projectile`, `ProjectilePool`, `DamageNumberPool`. Events emitted here: `hit_landed`, `crit_landed`, `player_damaged`, `heavy_attack_released(player, charge)`, `weapon_swapped(player, index)`. Signal definitions live in `SPEC-effect-system.md`.

## Interfaces consumed

- `player-controller`: `Player`, state machine, `is_perfect_dodge_window()`, `GameCamera.shake()`.
- `stats-status`: `StatBlock`, `Damage.compute()`, `StatusEffects`.
- `time-manager`: `hit_stop`, `scale_for`.
- `networking`: hit resolution only on host; `hit_landed` broadcast for feedback.

## Data model

`AttackPattern` (Resource): `id`, `windup_seconds`, `active_frames: int`, `recovery_seconds`, `telegraph_shape`, `telegraph_size: Vector2`, `hit: HitInfo` template fields, `animation: String`, `sfx_windup`, `sfx_hit`. Stored under `data/enemies/attacks/` and `data/bosses/attacks/`, owned by `enemies-ai`/`bosses` but the class is defined here.

## Multiplayer ownership

Hit detection and damage: host only (`Hurtbox.receive` early-returns on clients). Hit feedback (flash, numbers, shake for the local player, hit-stop) runs on every peer from the replicated `hit_landed` event. Attack animations start on the input-owning client immediately for feel; the host starts them one RTT later and is the source of truth for hitbox timing.

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
