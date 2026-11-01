class_name AffixHasted
extends EliteBehavior
## HASTED (SPEC-enemies-ai): +40 % move and attack speed, as StatBlock modifiers
## under SOURCE (never a base edit). Owned by enemies-ai; host only.

const SPEED_PERCENT: float = 0.4
const SOURCE: StringName = &"affix_hasted"


func on_spawn(enemy: Enemy) -> void:
	var stats := enemy.get_node("StatBlock") as StatBlock
	stats.add_modifier(StatBlock.Stat.MOVE_SPEED, 0.0, SPEED_PERCENT, SOURCE)
	stats.add_modifier(StatBlock.Stat.ATTACK_SPEED, 0.0, SPEED_PERCENT, SOURCE)
