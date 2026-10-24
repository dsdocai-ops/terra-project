class_name WeaponData
extends ContentData
## A weapon (SPEC-weapons `WeaponData`): a light combo, a heavy and the numbers
## the WeaponController needs. Owned by weapons. Sync: none (data).
## Phase 1 ships Pickaxe and Crossbow; skills and mutations arrive in week 7.

enum Type { BLADE, HEAVY, RANGED, MAGIC, EXOTIC }

@export var type: Type = Type.BLADE
@export var description: String = ""
@export var light_combo: Array[AttackSpec] = []
@export var heavy: AttackSpec = null
## Seconds of holding `attack_heavy` for a full charge.
@export var heavy_charge_seconds: float = 0.8
@export var unlocked_at_start: bool = true
## Placeholder swing / held-sprite colour.
@export var color: Color = Color(0.9, 0.9, 0.9, 1.0)


## The combo step after `step`, wrapping at the end of the combo.
func next_step(step: int) -> int:
	if light_combo.is_empty():
		return 0
	return (step + 1) % light_combo.size()
