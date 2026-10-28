class_name EnemySeparation
extends RefCounted
## Pure separation steering over a spatial hash grid (SPEC-enemies-ai
## "Movement and pathfinding": "simple separation steering so groups do not
## stack ... O(n) per unit via a spatial hash grid, not O(n^2)"). Owned by
## enemies-ai. Sync: host-only; every caller runs on the host.
##
## Pure on purpose: the hash stores plain `Vector2` positions and returns plain
## `Vector2` positions — no tree access, no group scan, no physics. The scene
## (`scenes/enemies/enemy.gd` `_separation`) collects the enemies group into
## one shared hash per physics frame, then computes its push from
## `nearby()`'s result alone — a push can never read past the nine cells
## around the query. Movement stays time-scaled by the caller, never
## `Engine.time_scale`.

## A hash cell never smaller than this, so the key division cannot blow up.
const MIN_CELL: float = 0.001
## The push falloff reads distances in pixels and scales by `push_scale / 60.0`
## (the scene's SEPARATION_PUSH constant over the 60 FPS the number was tuned
## at); kept here so the formula has one home.
const PUSH_PER_60FPS: float = 60.0
## Pairs closer than this count as one body (also the self-in-the-hash guard:
## a body's own position rides in the shared hash and drops out here).
const COINCIDENT_EPSILON: float = 0.01

var _cell: float = MIN_CELL
var _buckets: Dictionary[Vector2i, Bucket] = {}


## One bucket: the positions whose cell key maps here. A holder class because
## a typed dictionary's value cannot itself be a typed array.
class Bucket:
	var items: Array[Vector2] = []


## `cell_size` is the cell edge in pixels. The scene passes its separation
## radius, so everything within one radius of the query sits in one of the
## nine cells around it.
func _init(cell_size: float) -> void:
	_cell = maxf(cell_size, MIN_CELL)


## How many positions the hash holds (test read).
func count() -> int:
	var total: int = 0
	for bucket: Bucket in _buckets.values():
		total += bucket.items.size()
	return total


## Files a body's position into its cell. Nothing dedupes: the caller inserts
## every group member once per rebuild, self included (the push's coincident
## guard drops it again).
func insert(position: Vector2) -> void:
	var key := _key(position)
	var bucket: Bucket = _buckets.get(key)
	if bucket == null:
		bucket = Bucket.new()
		_buckets[key] = bucket
	bucket.items.append(position)


## Every stored position in the 3x3 cells around `position` — a superset of
## everything within one cell size of it; the push filters by distance. The
## returned array is a fresh copy: callers may keep it.
func nearby(position: Vector2) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var center := _key(position)
	for offset_x: int in range(-1, 2):
		for offset_y: int in range(-1, 2):
			var bucket: Bucket = _buckets.get(center + Vector2i(offset_x, offset_y))
			if bucket != null:
				found.append_array(bucket.items)
	return found


## The separation push for one body: away from each neighbour, fading linearly
## to nothing at `radius` (the old `_separation` falloff, verbatim), scaled by
## `push_scale / PUSH_PER_60FPS`. A neighbour at or past `radius`, and a
## coincident one (self included), contributes nothing.
static func push_for(position: Vector2, neighbours: Array[Vector2], radius: float, push_scale: float) -> Vector2:
	var push: Vector2 = Vector2.ZERO
	for other: Vector2 in neighbours:
		var offset: Vector2 = position - other
		var dist: float = offset.length()
		if dist > COINCIDENT_EPSILON and dist < radius:
			push += offset / dist * (1.0 - dist / radius)
	return push * (push_scale / PUSH_PER_60FPS)


## The cell a position falls in. Floors, so negative coordinates land in the
## cell below zero (an `int()` cast would fold the -1 cell into 0).
func _key(position: Vector2) -> Vector2i:
	return Vector2i(int(floorf(position.x / _cell)), int(floorf(position.y / _cell)))
