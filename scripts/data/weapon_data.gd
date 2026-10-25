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
## The weapon skill, fired by a heavy press inside the perfect-dodge window
## (combat v2 C4). Phase 1: a stronger heavy with its own shape; real per-weapon
## skills land with the weapons module in week 7.
@export var skill: AttackSpec = null
@export var skill_cooldown_seconds: float = 6.0
## Seconds of holding `attack_heavy` for a full charge.
@export var heavy_charge_seconds: float = 0.8
## Share of full move speed while holding a heavy charge (combat v2 C3).
@export_range(0.0, 1.0) var charge_move_factor: float = 0.3
@export var unlocked_at_start: bool = true
## Placeholder swing / held-sprite colour.
@export var color: Color = Color(0.9, 0.9, 0.9, 1.0)


## The combo step after `step`, wrapping at the end of the combo.
func next_step(step: int) -> int:
	if light_combo.is_empty():
		return 0
	return (step + 1) % light_combo.size()
