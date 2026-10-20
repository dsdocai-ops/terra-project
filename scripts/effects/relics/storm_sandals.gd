class_name StormSandalsEffect
extends Effect
## Storm Sandals — design doc 9.1 no. 2: "dodging through an enemy shocks it".
## Owned by relics (W4-B6, goal G5).
##
## On `player_dodged` it shocks every enemy the dodge went through: the ones
## within one dodge's reach of the player, found by the group
## `StatusEffects.ENEMY_TAG` — the same candidate set, and the same name, that
## stats-status' SHOCK chain reads for its own radius, so "who is an enemy" has
## one answer in the codebase rather than one per relic. Each enemy gets one
## application of one stack, once per dodge. An enemy outside the radius is
## untouched: "through" is what the radius decides, and the radius is the
## dodge's own length.
##
## Nothing is spawned: the shock is a status, and `StatusEffects` owns what a
## shocked enemy then does (its chain, its stacks, its expiry). The relic's only
## decision is who is close enough and how hard.
##
## The status lands through `Effect.apply_status()`, which looks the target's
## `StatusEffects` component up by name and drops the application with a warning
## when the target carries none — so a spawned hazard or a breakable that has no
## status component is skipped rather than crashing the relic.
##
## Sync: host-only. SPEC-relics, "Multiplayer ownership": "Rolls, picks,
## attaches, actives, synergy evaluation: host." The stacks themselves replicate
## through the entity's `StateSync`, not from here.

## How far from the player a dodge counts as having gone *through* something.
## One dodge is a fixed distance in SPEC-player-controller ("Fixed distance
## (~96 px …)"), so one dodge's length is the reach: an enemy at 96 px is the
## last one the dodge body passes, and anything beyond it was not dodged through.
const DODGE_THROUGH_RADIUS: float = 96.0
## The stacks one dodge applies. One: the relic shocks, it does not stack the
## shock up; repeated dodges through the same enemy are repeated applications,
## which is the component's business, not this relic's.
const SHOCK_STACKS: int = 1
## The status the dodge applies.
const DODGE_STATUS: StatusEffects.Status = StatusEffects.Status.SHOCK


func _on_attach() -> void:
	listen(Events.player_dodged, _on_player_dodged)


## One dodge shocks what it went through. `perfect` is not read: the line is
## about every dodge.
func _on_player_dodged(_player: Player, _perfect: bool) -> void:
	for enemy: Node in _enemies_dodged_through():
		apply_status(enemy, DODGE_STATUS, SHOCK_STACKS)


## The enemies within one dodge's reach of the player, in group order. An entity
## that is not positioned is skipped rather than assumed to be at the origin.
func _enemies_dodged_through() -> Array[Node]:
	var reached: Array[Node] = []
	if player == null:
		return reached
	var tree := get_tree()
	if tree == null:
		return reached
	var here: Vector2 = player.global_position
	for candidate: Node in tree.get_nodes_in_group(StatusEffects.ENEMY_TAG):
		var positioned := candidate as Node2D
		if positioned == null or not is_instance_valid(positioned):
			continue
		if here.distance_to(positioned.global_position) <= DODGE_THROUGH_RADIUS:
			reached.append(positioned)
	return reached
