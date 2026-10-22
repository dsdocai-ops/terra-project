class_name ProcChainLog
extends RefCounted
## The shared record of what a proc chain actually did: one entry per effect
## reaction, naming the effect that reacted, the signal it reacted to and the
## proc depth the event carried. Every `ProcChainProbe` in a case writes into
## the same log, so a chain of five effects can be read back source by source —
## which is what makes "the chain stopped at the third link" an assertion about
## a *named* effect rather than about a total.
##
## A reaction is recorded only when the effect's own filter let the event
## through (its `react_tag` matched, or it has none): a probe whose handler ran
## but whose tag did not match has not reacted to anything.
##
## Owned by tests (effect-system). Sync: none — a test double, one process.

## The effect id that reacted, the signal it heard, and the `trigger_depth` the
## dispatch wrapper had set when the handler ran. Parallel arrays rather than a
## list of Dictionaries so every field is typed.
var reaction_sources: Array[StringName] = []
var reaction_signals: Array[StringName] = []
var reaction_depths: Array[int] = []


## Records one reaction.
func record(source_id: StringName, signal_name: StringName, depth: int) -> void:
	reaction_sources.append(source_id)
	reaction_signals.append(signal_name)
	reaction_depths.append(depth)


## How many reactions the chain produced in total.
func count() -> int:
	return reaction_depths.size()


## The proc depths at which effects reacted to `signal_name`, in order. The gate
## is asserted as this list rather than as a count, so "three reactions" cannot
## be a pass produced by two effects reacting at the wrong depths.
func depths_for(signal_name: StringName) -> Array[int]:
	var depths: Array[int] = []
	for i: int in reaction_signals.size():
		if reaction_signals[i] == signal_name:
			depths.append(reaction_depths[i])
	return depths


## The proc depths at which one effect reacted to `signal_name`, in order — the
## per-effect view the mutual-reaction case (rule 2, goal G17) needs. Two
## effects reacting inside the same dispatch produce one interleaved list whose
## order depends on connection order; each effect's own list does not, so
## "this effect reacted three times, at depths 0, 1 and 2" is an assertion about
## the effect rather than about the order two connections happened to be made.
func depths_for_source(source_id: StringName, signal_name: StringName) -> Array[int]:
	var depths: Array[int] = []
	for i: int in reaction_signals.size():
		if reaction_signals[i] == signal_name and reaction_sources[i] == source_id:
			depths.append(reaction_depths[i])
	return depths


## Every source id that reacted to `signal_name`, in order. The negative
## control for the chain: the id of the effect whose link should never have run.
func sources_for(signal_name: StringName) -> Array[StringName]:
	var sources: Array[StringName] = []
	for i: int in reaction_signals.size():
		if reaction_signals[i] == signal_name:
			sources.append(reaction_sources[i])
	return sources


## True when `source_id` reacted at least once, whatever the signal.
func reacted(source_id: StringName) -> bool:
	return reaction_sources.has(source_id)


## Forgets everything recorded. Used between the steps of one case (a chain is
## driven twice, once per boundary) rather than between cases, which build a
## fresh log.
func clear() -> void:
	reaction_sources.clear()
	reaction_signals.clear()
	reaction_depths.clear()
