class_name EnemySeparation
extends RefCounted
## Pure separation steering over a spatial hash grid (SPEC-enemies-ai
## "Movement and pathfinding": "simple separation steering so groups do not
## stack ... O(n) per unit via a spatial hash grid, not O(n^2)"). Owned by
## enemies-ai. Sync: host-only; every caller runs on the host.
##
## Pure on purpose: the hash stores snapshot positions plus an instance id and
## returns plain `Vector2` positions — no tree access, no group scan, no
## physics. The scene (`scenes/enemies/enemy.gd` `_separation`) collects the
## enemies group into one shared hash per physics frame, then computes its push
## from `nearby()`'s result alone — a push can never read past the nine cells
## around the query. Movement stays time-scaled by the caller, never
## `Engine.time_scale`.
##
## Deliberate behaviour change over the old live group scan (recorded by the
## judge): the hash is a snapshot taken at the first `_separation` of the
## physics frame, so a body that moved earlier in that frame (the flinch
## shove's `move_and_slide` runs before a state's `_separation`) is read at its
## snapshot position, up to one frame stale. The old scan read positions live.
## What is *not* stale is the query's own entry: every entry carries its node's
## instance id and `nearby()` drops the caller's own id, so a body's stale
## snapshot position can never push it along its own shove (the old code's
## `if node == self: continue`).

## A hash cell never smaller than this, so the key division cannot blow up.
const MIN_CELL: float = 0.001
## The push falloff reads distances in pixels and scales by `push_scale / 60.0`
## (the scene's SEPARATION_PUSH constant over the 60 FPS the number was tuned
## at); kept here so the formula has one home.
const PUSH_PER_60FPS: float = 60.0
## Pairs closer than this count as one body (two *neighbours* on one spot; the
## query's own entry never reaches the push — `nearby()` drops it by id).
const COINCIDENT_EPSILON: float = 0.01

var _cell: float = MIN_CELL
var _buckets: Dictionary[Vector2i, Bucket] = {}


## One stored body: its snapshot position plus its node's instance id, so the
## lookup can drop the caller's own (possibly moved-since) entry.
class Entry:
	var pos: Vector2 = Vector2.ZERO
	var id: int = -1


## One bucket: the entries whose cell key maps here. A holder class because
## a typed dictionary's value cannot itself be a typed array.
class Bucket:
	var items: Array[Entry] = []


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


## Files a body's snapshot position into its cell. Nothing dedupes: the caller
## inserts every group member once per rebuild, each with its node's instance
## id (the lookup drops the query's own entry, however far it has moved since
## the snapshot).
func insert(position: Vector2, id: int) -> void:
	var key := _key(position)
	var bucket: Bucket = _buckets.get(key)
	if bucket == null:
		bucket = Bucket.new()
		_buckets[key] = bucket
	var entry := Entry.new()
	entry.pos = position
	entry.id = id
	bucket.items.append(entry)


## Every stored position in the 3x3 cells around `position` — a superset of
## everything within one cell size of it; the push filters by distance.
## `exclude_id` (a node's instance id) drops the caller's own entry, so a body
## whose snapshot position is behind its current one is never pushed along the
## move that separated them. The returned array is a fresh copy: callers may
## keep it.
func nearby(position: Vector2, exclude_id: int = -1) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var center := _key(position)
	for offset_x: int in range(-1, 2):
		for offset_y: int in range(-1, 2):
			var bucket: Bucket = _buckets.get(center + Vector2i(offset_x, offset_y))
			if bucket != null:
				for entry: Entry in bucket.items:
					if entry.id != exclude_id:
						found.append(entry.pos)
	return found


## The separation push for one body: away from each neighbour, fading linearly
## to nothing at `radius` (the old `_separation` falloff, verbatim), scaled by
## `push_scale / PUSH_PER_60FPS`. A neighbour at or past `radius`, and a
## coincident one (two bodies on one spot), contributes nothing. The query's
## own entry is dropped upstream, in `nearby()`.
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
