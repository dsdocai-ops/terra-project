class_name GravityStoneEffect
extends Effect
## Gravity Stone — design doc 9.1 no. 12: "hits pull nearby enemies slightly
## toward the target". Owned by relics (W4-B6, goal G7).
##
## Every hit this player lands asks each enemy within `PULL_RADIUS` of the enemy
## it landed on to move toward that enemy. The *movement* is the enemy body's
## (Dev A, W4-A1) and a relic cannot move a node, so the relic makes the request
## through the seam stats-status already publishes for the same gesture —
## `StatusEffects.PULL_METHOD` (`pull_toward`), the one COLLAPSE's row uses — by
## name, guarded by `has_method()`. An enemy without the seam is a skipped ask,
## not an error: the swap-in is Dev A declaring the same method, and this script
## does not change (**blocked on Dev A (W4-A1)**).
##
## **Who is "nearby".** The candidate set is the group
## `StatusEffects.ENEMY_TAG` — the same group, read the same way, as SHOCK's
## chain and Storm Sandals' dodge — and the measure is the distance from the
## enemy the hit landed on, not from this player: the design doc's sentence is
## "toward the target", so the target is the centre of the pull. Nothing else can
## be the centre, or a relic that hangs off a ranged hit would drag enemies
## toward the archer instead of toward the fight.
##
## The hit's own target is never asked to pull toward itself. It is the centre;
## COLLAPSE's `_request_pull()` skips `entity()` for the same reason.
##
## **The reach is this lane's balance call.** The design doc says "slightly" and
## gives no number, so `PULL_RADIUS` is pinned here (and asserted in the batch's
## case) rather than left to drift — deliberately *less* than
## `StatusEffects.COLLAPSE_RADIUS` (128 px), because COLLAPSE is a combo's burst
## and this is a nudge, and "slightly" is not "the same reach as the combo".
##
## **Which hits count.** This player's `proc_depth == 0` hits — the weapon-class
## ones — for the reason Echo Blade documents: `hit_landed` carries no `Player`
## argument for `Effect.listen()` to filter on, and this relic's own procs (it
## deals none) and any other relic's must not pull through it.
##
## `max_stacks = 1` in the data file: one hit is one pull, so a second copy has
## no second effect to deepen; the number of copies does not change how far
## "nearby" reaches.
##
## Sync: host-only (SPEC-relics, "Multiplayer ownership"). SPEC-effect-system —
## "Movement calls position changes; those are replicated by position sync", so
## a pulled enemy reaches clients through its own `StateSync`, not from here.

## How far from the enemy the hit landed on an enemy counts as nearby. Design doc
## 9.1 no. 12: "pull nearby enemies slightly toward the target" — no number is
## given, so this lane's balance call, pinned by the batch's case.
const PULL_RADIUS: float = 96.0
## The method the pull is requested through. `StatusEffects.PULL_METHOD` rather
## than a second literal, so the nudge and COLLAPSE ask for the same gesture by
## the same name and Dev A implements one method for both.
const PULL_METHOD: StringName = StatusEffects.PULL_METHOD


func _on_attach() -> void:
	listen(Events.hit_landed, _on_hit_landed)


## One of this player's own hits: every enemy near what it landed on is asked to
## move toward it.
func _on_hit_landed(hit: HitInfo) -> void:
	if not _is_my_hit(hit):
		return
	_pull_toward_target(hit.target)


## True when `hit` is a hit this effect's own player landed, and not one of the
## procs this player's own effects produced.
func _is_my_hit(hit: HitInfo) -> bool:
	if player == null or hit == null or hit.owner_player != player:
		return false
	return hit.proc_depth == 0


## Asks every enemy within `PULL_RADIUS` of `target` to pull toward it. A hit
## whose payload names no positionable target has no centre to pull toward, so
## the whole gesture is skipped rather than centred on the origin.
func _pull_toward_target(target: Node) -> void:
	var centre := target as Node2D
	if centre == null or not is_instance_valid(centre):
		return
	for enemy: Node in _enemies_near(centre):
		if enemy.has_method(PULL_METHOD):
			enemy.call(PULL_METHOD, centre, PULL_RADIUS)


## The enemies within `PULL_RADIUS` of `centre`, in group order, excluding
## `centre` itself. An entity that is not positioned is skipped rather than
## assumed to be at the origin.
func _enemies_near(centre: Node2D) -> Array[Node]:
	var reached: Array[Node] = []
	var tree := get_tree()
	if tree == null:
		return reached
	var here: Vector2 = centre.global_position
	for candidate: Node in tree.get_nodes_in_group(StatusEffects.ENEMY_TAG):
		if candidate == centre or not is_instance_valid(candidate):
			continue
		var positioned := candidate as Node2D
		if positioned == null:
			continue
		if here.distance_to(positioned.global_position) <= PULL_RADIUS:
			reached.append(candidate)
	return reached