class_name CrossbowAttack
extends WeaponAttack
## The Crossbow's per-weapon attack node (SPEC-weapons): its signature is the
## piercing charged bolt. The pierce and the damage are in `crossbow.tres` and
## `WeaponController.build_hit`; the size half of SPEC-weapons "Charged
## attacks" (`heavy(charge)` scales damage and size) is this node's
## `shot_scale`, which the controller reads the moment the swing's bolt fires
## and rides into the `ProjectileSpawnInfo`, so every peer draws the bolt at
## the size that does the hitting. Owned by weapons. Sync: the hook runs
## inside the swing each peer executes (the owner's prediction, the host's
## authority); the bolt's flight and damage are host-owned, and the drawn
## scale reaches remote peers through the spawn data.

## A full charge fires the bolt this much bigger, linear in between.
const FULL_CHARGE_SCALE_BONUS: float = 0.5


func light(_step: int) -> void:
	shot_scale = 1.0


func heavy(charge: float) -> void:
	shot_scale = 1.0 + charge * FULL_CHARGE_SCALE_BONUS


func skill() -> void:
	shot_scale = 1.0
