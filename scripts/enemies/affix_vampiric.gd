class_name AffixVampiric
extends EliteBehavior
## VAMPIRIC (SPEC-enemies-ai): heals HEAL_SHARE of the damage the elite deals.
## Heals through Health.heal, so the heal is host-side and replicates with HP.
## Owned by enemies-ai; host only.

const HEAL_SHARE: float = 0.2


func on_dealt(enemy: Enemy, damage: int) -> void:
	if damage <= 0 or enemy.health == null or enemy.health.is_dead:
		return
	enemy.health.heal(roundi(damage * HEAL_SHARE), enemy)
