class_name DominoEffect
extends Effect
## Domino — design doc 9.1 no. 19: "killing an enemy with a status effect spreads
## it to nearby enemies". Owned by relics (W4-B6, goal G8a).
##
## When this player kills an enemy that was carrying statuses, every enemy within
## `SPREAD_RADIUS` of the corpse is given those same statuses, at the stacks the
## corpse was holding them at. The corpse itself is skipped: it is the centre of
## the spread and it is already dead.
##
## **The trigger is "with a status effect".** A corpse carrying nothing spreads
## nothing: the pass reads the victim's `StatusEffects` component, and an empty
## `active_statuses()` ends it there. That is the doc's own condition, and it is
## why the batch's case kills a clean enemy first and asserts the spread is still
## 0 before applying a burn and a toxin to the next one.
##
## **The statuses are read through the component's contract, never its class.**
## `StatusEffects` is stats-status's (`scripts/components/status_effects.gd`,
## W4-B4 / G20) and the enemy it rides on is Dev A's (**blocked on Dev A
## (W4-A1)**); the batch's fixture mounts a recording double in its place. So the
## read is `active_statuses()` and `stacks(status)` looked up by name on the
## node, exactly the way `Effect.apply_status()` looks up `apply_status()` — a
## `has_method` check and a dynamic call, and a corpse with no component (or one
## that does not answer) spreads nothing rather than erroring. The application
## goes back through `Effect.apply_status()`, so the component records *this
## relic* as the source of every status it receives and
## `Events.status_applied(target, status, stacks, source)` names the Domino that
## moved it.
##
## **The stacks travel whole.** The neighbour receives the status at the stacks
## the corpse died holding — a burn of 3 is spread as 3, not as 1 — because the
## doc's "spreads it" is the status, and a status in this game *is* its stack
## count (`StatusEffects.stacks()`). The component's own caps and resistances
## still apply to the application: `apply_status` is the normal path, so a
## neighbour with MAX_STACKS already on it clamps the spread exactly as it clamps
## every other application.
##
## **The radius is SHOCK's, and named from it.** The doc gives no number for
## "nearby". `StatusEffects.SHOCK_CHAIN_RADIUS` (96 px) is the game's existing
## answer to the same question — "which enemies count as next to this one" — and
## SHOCK's chain, Volatile Core's blast and this relic's spread are the same
## shape of query. Reading the constant rather than copying 96.0 into this file
## means the two cannot drift, and the batch's case asserts the value against the
## component's own.
##
## **Nothing here is a hit.** No damage is dealt and no `HitInfo` is built, so
## there is no proc depth to stamp and no rule-2 tag to carry: a spread status is
## an application, not a link in the damage chain (`SPEC-effect-system`, "Proc
## chain limits"). The relic cannot re-trigger off its own spread, because what
## it listens to is a kill and what it produces is a status.
##
## **Which kills count.** This player's, read off `hit.owner_player`, for the
## reason the rest of the On Kill batch reads it: `enemy_killed` is emitted by the
## dying enemy (Dev A, W4-A4) and carries no `Player` argument for
## `Effect.listen()`'s filter. A death announced on `elite_killed` instead is
## **not** a second death — see the batch note in `bloodthirst.gd`.
##
## `max_stacks = 1` in the data file: no line of no. 19 says "(stacks)" and the
## doc's sentence has no per-copy term, so a second Domino spreads nothing extra.
##
## Sync: host-only (SPEC-relics, "Multiplayer ownership"). The statuses land on
## host-side enemy state, which the enemy's own `StateSync` replicates; nothing
## here is read by a client.

## How far from the corpse the spread reaches, in pixels. SPEC-stats-status's own
## chain radius rather than a second 96.0: the doc says "nearby" and the game
## already answered what nearby means for exactly this query.
const SPREAD_RADIUS: float = StatusEffects.SHOCK_CHAIN_RADIUS
## The two methods the corpse's `StatusEffects` component is read through, named
## the way `Effect.STATUS_METHOD` names the one it applies through: both are
## other modules' contracts, so both are looked up by name on the node.
const STATUSES_METHOD: StringName = &"active_statuses"
const STACKS_METHOD: StringName = &"stacks"

## How many status applications this effect has made, ever — one per status per
## enemy reached, so a two-status corpse beside one neighbour reads 2.
var _spreads: int = 0


func _on_attach() -> void:
	listen(Events.enemy_killed, _on_enemy_killed)


## How many status applications this effect has made — the read the batch's cases
## assert 0 and 2 against.
func spread_count() -> int:
	return _spreads


## One of this player's kills: the corpse's statuses go out to its neighbours.
func _on_enemy_killed(enemy: Node, hit: HitInfo) -> void:
	if not _is_my_kill(enemy, hit):
		return
	_spread(enemy)


## True when `enemy` is a positioned, valid node and `hit` is this player's own
## kill. The `owner_player` read is the payload's, not a signal argument:
## `enemy_killed` carries no `Player` for `Effect.listen()` to filter on.
func _is_my_kill(enemy: Node, hit: HitInfo) -> bool:
	if player == null or enemy == null or not is_instance_valid(enemy):
		return false
	if hit == null:
		return false
	return hit.owner_player == player


## Spreads what the corpse was carrying over the enemies beside it. A corpse with
## no position has no neighbours to be near, and one with no statuses has nothing
## to spread — the doc's "killing an enemy *with a status effect*".
func _spread(enemy: Node) -> void:
	var corpse := enemy as Node2D
	if corpse == null:
		return
	var component: Node = _corpse_statuses(corpse)
	if component == null:
		return
	var statuses: Array[int] = []
	statuses.assign(component.call(STATUSES_METHOD))
	if statuses.is_empty():
		return
	var neighbours: Array[Node] = _neighbours(corpse)
	if neighbours.is_empty():
		return
	for neighbour: Node in neighbours:
		for i: int in statuses.size():
			_spread_one(neighbour, component, statuses[i])


## Gives `target` one of the corpse's statuses, at the stacks the corpse held it
## at. A status the corpse had run down to zero stacks is not spread, and one the
## corpse never had is not asked for.
func _spread_one(target: Node, component: Node, status: int) -> void:
	var held: int = int(component.call(STACKS_METHOD, status))
	if held <= 0:
		return
	var known: StatusEffects.Status = int(status)
	apply_status(target, known, held)
	_spreads += 1


## The `StatusEffects` component on the corpse, or null when it carries none —
## or carries something that does not answer the two questions this relic asks.
## `has_method` checks rather than a cast, for the reason `Effect._status_component()`
## gives: the effect tests mount a recording double where the real component goes.
func _corpse_statuses(corpse: Node2D) -> Node:
	var component: Node = corpse.get_node_or_null(STATUS_NODE)
	if component == null:
		return null
	if not component.has_method(STATUSES_METHOD) or not component.has_method(STACKS_METHOD):
		return null
	return component


## The enemies within `SPREAD_RADIUS` of the corpse, in group order, excluding the
## corpse itself. The candidate set is the group `StatusEffects.ENEMY_TAG`, read
## the way SHOCK's chain and Volatile Core's blast read it, and an entity that is
## not positioned is skipped rather than assumed to be at the origin.
func _neighbours(corpse: Node2D) -> Array[Node]:
	var reached: Array[Node] = []
	var tree := get_tree()
	if tree == null:
		return reached
	var here: Vector2 = corpse.global_position
	for candidate: Node in tree.get_nodes_in_group(StatusEffects.ENEMY_TAG):
		if candidate == corpse or not is_instance_valid(candidate):
			continue
		var positioned := candidate as Node2D
		if positioned == null:
			continue
		if here.distance_to(positioned.global_position) <= SPREAD_RADIUS:
			reached.append(candidate)
	return reached
