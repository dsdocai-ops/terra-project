class_name ComboConsumerStub
extends Effect
## A stand-in for one of the two systems that multiply combo damage. Owned by
## stats-status (tests).
##
## SPEC-stats-status, "Element combos", last line: "Reactive skill node (+40%)
## and Elementalist synergy (x2) multiply combo damage." Neither system exists
## yet — Reactive is a week-7 skill node (progression-trees) and Elementalist is
## a week-8 synergy (SynergyTracker) — so this double stands in for both.
##
## The whole hook is the method below: `StatusEffects.combo_damage_multiplier()`
## walks the attaching player's `EffectHost` and multiplies by the factor of
## every effect that exposes `StatusEffects.COMBO_MULTIPLIER_METHOD`, so a
## consumer is an attached `Effect` and never a relic id the component knows.
## `multiplier` is what the real week-7/week-8 effects will take from their own
## state instead; everything else about them is the same shape.
##
## The real consumers attach to the player's `EffectHost` at spawn (recorded in
## `tasks/todo.md` as the swap-in); this helper is deleted when they land, the
## same way `RelicMarkerEffect` is.
##
## Sync: none — a test double, attached to a test fixture's player. The hook it
## exposes is read on the host only, because a combo only fires there
## (`StatusEffects._resolves_statuses()`).

## The factor this consumer multiplies combo damage by. A case sets it to
## `StatusEffects.COMBO_ELEMENTALIST_MULTIPLIER` for the synergy and to
## `1.0 + StatusEffects.COMBO_REACTIVE_BONUS` for the skill node.
var multiplier: float = 1.0


## The hook: this consumer's factor for a combo. Read by
## `StatusEffects.combo_damage_multiplier()`; nothing else calls it, and the
## signature is deliberately the method's whole contract.
func combo_damage_multiplier() -> float:
	return multiplier