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
@export var hit_stun_seconds: float = 0.15
@export var element: HitInfo.Element = HitInfo.Element.NONE
@export var projectile_speed: float = 360.0
## How far a projectile flies before it expires.
@export var projectile_range: float = 320.0
@export var pierce: int = 0
## Share of full move speed while this attack plays.
@export var move_speed_factor: float = 0.5


func total_seconds() -> float:
	return windup_seconds + active_seconds + recovery_seconds
