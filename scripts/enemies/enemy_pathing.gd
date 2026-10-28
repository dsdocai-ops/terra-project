class_name EnemyPathing
extends RefCounted
## Pure pathing decisions for the enemy standard states (SPEC-enemies-ai
## "Pathfinding"): the A* route over the floor's `AStarGrid2D` and which
## waypoint of it to steer at. Owned by enemies-ai. Sync: host-only; every
## caller runs on the host.
##
## Pure on purpose: every function sees plain values — the grid comes in as an
## argument (`Floor._build_astar` builds it from the painted layout) — and
## returns plain values, no tree access, no physics. `scenes/enemies/enemy.gd`
## calls these in `_next_waypoint` and applies the result to `velocity` and
## `move_and_slide`, so the scene stays wiring and this file is the one source
## of the routing. The waypoint clock (how often the path is rebuilt) stays
## with the caller; movement is time-scaled there, never `Engine.time_scale`.

## A waypoint within this distance of the enemy counts as reached and is
## dropped from the path.
const ARRIVAL_RADIUS: float = 10.0


## The A* route from `from_world` to `to_world` in screen-space waypoints, the
## start tile's own center excluded. Falls back to a one-point path straight at
## `to_world` when either end is outside the grid's region or inside a wall:
## direct pursuit beats standing still, and `_next_waypoint` rebuilds on its
## timer anyway. An empty route (no way out, e.g. every neighbour solid with
## the floor's no-obstacles diagonal mode) also pursues directly via `goal`.
static func build_path(astar: AStarGrid2D, from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	var from: Vector2i = Iso.to_tile(from_world)
	var to: Vector2i = Iso.to_tile(to_world)
	var region: Rect2i = astar.region
	if not region.has_point(from) or not region.has_point(to) or astar.is_point_solid(from) or astar.is_point_solid(to):
		return PackedVector2Array([to_world])
	var cells: Array[Vector2i] = astar.get_id_path(from, to)
	var path := PackedVector2Array()
	for index: int in range(1, cells.size()):
		path.append(Iso.to_screen(cells[index]))
	return path


## The path after this frame: leading waypoints `position` has reached (within
## `arrival_radius`) are dropped. Pure — returns the trimmed path instead of
## touching a member, so the caller stores it back.
static func advance(path: PackedVector2Array, position: Vector2, arrival_radius: float) -> PackedVector2Array:
	var trimmed := path
	while trimmed.size() > 0 and position.distance_to(trimmed[0]) < arrival_radius:
		trimmed.remove_at(0)
	return trimmed


## The point to steer at this frame: the path's first remaining waypoint, or
## `fallback` (the direct target) when nothing is left on the path.
static func goal(path: PackedVector2Array, fallback: Vector2) -> Vector2:
	if path.is_empty():
		return fallback
	return path[0]
