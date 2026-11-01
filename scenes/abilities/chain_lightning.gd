class_name ChainLightningCast
extends AbilityCast
## Chain Lightning (SPEC-abilities section 8, Storm): a bolt jumps from the player
## to the nearest enemy in reach, then from each struck enemy to the nearest one it
## has not hit yet, up to the extra number of jumps (rank 1 4, rank 3 8). Each
## jump is a one-tick Zone where the enemy stands. All jumps are placed when the
## cast spawns, so the chain has no travel time. Owned by abilities. Sync: host
## only; the enemy positions are read on the host.

const FIRST_JUMP_RANGE: float = 160.0
const HOP_RANGE: float = 120.0
const JUMP_RADIUS: float = 24.0
const JUMP_SECONDS: float = 0.1


## The indices into `points` the bolt strikes, in order. The first jump is the
## nearest point to `start` within `first_range`; each later one is the nearest
## unstruck point to the last struck within `hop_range`. Stops at `max_jumps` or
## when nothing is in reach. Pure, so the rule is tested without a scene.
static func chain_order(start: Vector2, points: Array[Vector2], max_jumps: int, first_range: float, hop_range: float) -> Array[int]:
	var order: Array[int] = []
	var struck: Array[bool] = []
	for index: int in points.size():
		struck.append(false)
	var at: Vector2 = start
	var reach: float = first_range
	for _jump: int in maxi(max_jumps, 0):
		var best: int = -1
		var best_distance: float = reach
		for index: int in points.size():
			var distance: float = at.distance_to(points[index])
			if not struck[index] and distance <= reach and (best < 0 or distance < best_distance):
				best = index
				best_distance = distance
		if best < 0:
			break
		struck[best] = true
		order.append(best)
		at = points[best]
		reach = hop_range
	return order


func _perform() -> void:
	var points: Array[Vector2] = []
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var body := node as Node2D
		if body != null and body.is_inside_tree():
			points.append(body.global_position)
	var first_range: float = FIRST_JUMP_RANGE * size_mult()
	var hop_range: float = HOP_RANGE * size_mult()
	var order: Array[int] = chain_order(origin(), points, int(extra()), first_range, hop_range)
	for index: int in order:
		spawn_zone(points[index], JUMP_RADIUS * size_mult(), JUMP_SECONDS, JUMP_SECONDS, build_hit())
