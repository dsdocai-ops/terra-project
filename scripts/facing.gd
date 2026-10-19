class_name Facing
extends RefCounted
## The eight isometric facings: sprite suffixes, screen angles, and the
## sector math that turns a direction into a facing index.
## Owned by player-controller. Sync: none (constants and pure functions).
##
## Single source of truth: Player animations, the placeholder sprite
## generator, and tests all read these tables. Index 0 faces the camera.
## Cardinals are screen-aligned; diagonals follow the 2:1 tile axes, so the
## sectors are not equal in width (see SPEC-player-controller, Facing).

const SUFFIXES: Array[StringName] = [&"s", &"sw", &"w", &"nw", &"n", &"ne", &"e", &"se"]
## Screen-space angle (degrees, clockwise from +x) of each facing.
const CENTERS_DEG: Array[float] = [90.0, 153.435, 180.0, 206.565, 270.0, 333.435, 0.0, 26.565]
## Facing indices sorted by increasing angle: e, se, s, sw, w, nw, n, ne.
const ANGULAR_ORDER: Array[int] = [6, 7, 0, 1, 2, 3, 4, 5]

## Lower and upper angle (degrees) of each facing's sector, midway to its
## angular neighbours. Computed once on class load.
static var SECTOR_BOUNDS: Array[Vector2] = _compute_sector_bounds()


static func count() -> int:
	return SUFFIXES.size()


static func suffix(index: int) -> StringName:
	return SUFFIXES[posmod(index, SUFFIXES.size())]


## Facing index for a screen-space direction. With `hysteresis_deg` > 0 the
## `current` index is kept while the direction is within that many degrees
## past its sector's edge, which stops flicker on a boundary. A zero vector
## returns `current`.
static func index_for(dir: Vector2, current: int = 0, hysteresis_deg: float = 0.0) -> int:
	if dir == Vector2.ZERO:
		return current
	var angle := fposmod(rad_to_deg(dir.angle()), 360.0)
	if hysteresis_deg > 0.0 and current >= 0 and current < SECTOR_BOUNDS.size():
		var bounds := SECTOR_BOUNDS[current]
		var width := fposmod(bounds.y - bounds.x, 360.0) + hysteresis_deg * 2.0
		if fposmod(angle - (bounds.x - hysteresis_deg), 360.0) < width:
			return current
	for i in SECTOR_BOUNDS.size():
		var bounds := SECTOR_BOUNDS[i]
		if fposmod(angle - bounds.x, 360.0) < fposmod(bounds.y - bounds.x, 360.0):
			return i
	return current


static func _compute_sector_bounds() -> Array[Vector2]:
	var result: Array[Vector2] = []
	result.resize(CENTERS_DEG.size())
	var n := ANGULAR_ORDER.size()
	for pos in n:
		var index := ANGULAR_ORDER[pos]
		var prev := CENTERS_DEG[ANGULAR_ORDER[(pos - 1 + n) % n]]
		var next := CENTERS_DEG[ANGULAR_ORDER[(pos + 1) % n]]
		var center := CENTERS_DEG[index]
		result[index] = Vector2(_midpoint_deg(prev, center), _midpoint_deg(center, next))
	return result


static func _midpoint_deg(a: float, b: float) -> float:
	var diff := fposmod(b - a + 180.0, 360.0) - 180.0
	return fposmod(a + diff * 0.5, 360.0)
