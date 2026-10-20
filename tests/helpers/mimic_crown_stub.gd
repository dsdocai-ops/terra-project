class_name MimicCrownStub
extends Effect
## The W4-B3 stand-in for **Mimic Crown** (design doc 9.1 no. 58, a week-8
## relic): an effect that, on attach, copies the effect of the last picked
## relic — which is what SPEC-effect-system, "Proc chain limits", rule 4
## describes. Never shipped; it lives under `tests/helpers/` beside the other
## doubles.
##
## The real `mimic_crown.gd` arrives with the week-8 relic batch and differs
## only in how it finds the last pick: this double reads it off the host's
## attach order (the most recently attached effect that is not itself), while
## the shipped relic will resolve it from the replicated `RunPlayerState`. Both
## call the same `EffectHost.add_mimic_copy()` — the duplication rule itself is
## the host's, not the relic's (rule 4 is one of the rules SPEC-effect-system
## requires to be "enforced in the helpers, not in each effect").
##
## Sync: none — a test double. The duplication path it drives is host-only, like
## every other effect path (clients hold no `Effect` instances).
##
## blocked on Dev B (W8-B?, the Mimic Crown relic): when that lands, this double
## is deleted and its case re-pointed at `data/relics/mimic_crown.tres`.


func _on_attach() -> void:
	if host == null:
		push_warning("[mimic-crown-stub] attached with no EffectHost, nothing copied")
		return
	var last_picked: Effect = _last_picked()
	if last_picked == null or last_picked.source == null:
		return
	host.add_mimic_copy(last_picked.source, source_id())


## The effect attached most recently before this one, which is this host's
## stand-in for "your last picked relic". An effect is registered by `add()`
## after its `_on_attach()` runs, so this crown is not in the list yet either
## way; it is skipped by id as well, so the lookup cannot pick the crown itself
## if that ordering ever changes.
func _last_picked() -> Effect:
	var attached: Array[Effect] = host.effects()
	for index: int in range(attached.size() - 1, -1, -1):
		if attached[index].source_id() != source_id():
			return attached[index]
	return null
