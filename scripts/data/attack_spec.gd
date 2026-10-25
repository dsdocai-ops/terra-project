class_name AttackSpec
extends Resource
## One player attack step (SPEC-weapons `AttackSpec`): a melee arc or circle in
## front of the player, or a projectile. Owned by weapons. Sync: none (data).
## Phase 1 carries what placeholder combat needs; hit-stop frames, sfx ids and
## per-weapon skill hooks join with the real weapons.

enum Shape { ARC, CIRCLE, PROJECTILE }

@export var animation: StringName = &"attack"
@export var shape: Shape = Shape.ARC
## Seconds before the hitbox goes live.
@export var windup_seconds: float = 0.06
## Seconds the hitbox stays live.
@export var active_seconds: float = 0.12
@export var recovery_seconds: float = 0.18
## Forward reach in px (screen space).
@export var reach: float = 56.0
@export var arc_degrees: float = 110.0
@export var base_damage: float = 20.0
@export var knockback: float = 140.0
## Poise drained from the target (combat v2): light 10, finisher 20, heavy 30.
## A charged heavy adds more on top (WeaponController.HEAVY_POISE_CHARGE_BONUS).
@export var poise_damage: float = 10.0
@export var hit_stun_seconds: float = 0.15
@export var element: HitInfo.Element = HitInfo.Element.NONE
@export var projectile_speed: float = 360.0
## How far a projectile flies before it expires.
@export var projectile_range: float = 320.0
@export var pierce: int = 0
## Share of full move speed while this attack plays.
@export var move_speed_factor: float = 0.5
## Cancel windows, as a fraction of `recovery_seconds` after the active window
## (combat v2 C3). The next combo step, or a heavy, may start once this share of
## recovery has passed; the rest of recovery is skipped.
@export_range(0.0, 1.0) var combo_cancel_at: float = 0.4
## A dodge may cancel once this share of recovery has passed. 0.0, the default,
## is the end of the active window.
@export_range(0.0, 1.0) var dodge_cancel_at: float = 0.0


func total_seconds() -> float:
	return windup_seconds + active_seconds + recovery_seconds


## Attack-clock time (seconds since the attack began) at which the next combo
## step or a heavy may cancel the rest of recovery.
func combo_cancel_seconds() -> float:
	return windup_seconds + active_seconds + combo_cancel_at * recovery_seconds


## Attack-clock time at which a dodge may cancel.
func dodge_cancel_seconds() -> float:
	return windup_seconds + active_seconds + dodge_cancel_at * recovery_seconds
