class_name Iso
extends RefCounted
## Isometric math for 64x32 diamond-down tiles. Owned by foundation.
## Pure functions, no state. Sync: none.
##
## Tile space: +x runs down-right on screen, +y runs down-left. Screen space is
## the TileMapLayer's local space, which Godot centers so that tile (0, 0) sits
## at (32, 16). These formulas match TileMapLayer.map_to_local / local_to_map
## for TileSet.TILE_SHAPE_ISOMETRIC + TILE_LAYOUT_DIAMOND_DOWN; test_iso.gd
## asserts that against a real layer.

const TILE_SIZE := Vector2i(64, 32)
const HALF_W := TILE_SIZE.x * 0.5
const HALF_H := TILE_SIZE.y * 0.5

## Screen-space angle (degrees, clockwise from +x) of each facing, in
## Player.FACING_SUFFIXES order: s, sw, w, nw, n, ne, e, se. Cardinals are
## screen-aligned; diagonals follow the tile axes (2:1 slope).
const FACING_CENTERS_DEG: Array[float] = [90.0, 153.435, 180.0, 206.565, 270.0, 333.435, 0.0, 26.565]
## Facing indices sorted by increasing angle: e, se, s, sw, w, nw, n, ne.
const FACING_ANGULAR_ORDER: Array[int] = [6, 7, 0, 1, 2, 3, 4, 5]


## Center of a tile in screen (layer-local) pixels.
static func to_screen(tile: Vector2i) -> Vector2:
	return Vector2(
		(tile.x - tile.y) * HALF_W + HALF_W,
		(tile.x + tile.y) * HALF_H + HALF_H,
	)


## Tile that contains a screen (layer-local) point.
static func to_tile(screen: Vector2) -> Vector2i:
	var u := screen.x / HALF_W
	var v := screen.y / HALF_H
	# Invert to_screen: u = x - y + 1, v = x + y + 1
	var x := (u + v) * 0.5 - 1.0
	var y := (v - u) * 0.5
	return Vector2i(roundi(x), roundi(y))


## Rotate a WASD input vector onto the isometric plane.
## Cardinal inputs stay screen-aligned (W is screen up). Diagonal inputs land
## on the tile axes, so the eight input directions are the eight compass
## directions of the tile grid. The result keeps the input's magnitude, so
## every direction moves at the same on-screen speed.
static func input_to_world(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO:
		return Vector2.ZERO
	var magnitude := minf(dir.length(), 1.0)
	var squashed := Vector2(dir.x, dir.y * 0.5)
	return squashed.normalized() * magnitude


## Facing index (Player.FACING_SUFFIXES order) for a screen-space direction.
## Sector boundaries sit midway between neighbouring facings, so the sectors
## are not equal in width (diagonals are at 26.565 degrees, not 45).
## With `hysteresis_deg` > 0 the `current` index is kept while the direction
## is within that many degrees past its sector's edge, which stops flicker on
## a boundary. A zero vector returns `current`.
static func facing_index(dir: Vector2, current: int = 0, hysteresis_deg: float = 0.0) -> int:
	if dir == Vector2.ZERO:
		return current
	var angle := fposmod(rad_to_deg(dir.angle()), 360.0)
	if hysteresis_deg > 0.0 and current >= 0 and current < FACING_CENTERS_DEG.size():
		var bounds := _sector_bounds(current)
		var width := fposmod(bounds.y - bounds.x, 360.0) + hysteresis_deg * 2.0
		if fposmod(angle - (bounds.x - hysteresis_deg), 360.0) < width:
			return current
	for i in FACING_CENTERS_DEG.size():
		var bounds := _sector_bounds(i)
		if fposmod(angle - bounds.x, 360.0) < fposmod(bounds.y - bounds.x, 360.0):
			return i
	return current


## Lower and upper angle (degrees) of a facing's sector, midway to neighbours.
static func _sector_bounds(index: int) -> Vector2:
	var pos := FACING_ANGULAR_ORDER.find(index)
	var count := FACING_ANGULAR_ORDER.size()
	var prev := FACING_CENTERS_DEG[FACING_ANGULAR_ORDER[(pos - 1 + count) % count]]
	var next := FACING_CENTERS_DEG[FACING_ANGULAR_ORDER[(pos + 1) % count]]
	var center := FACING_CENTERS_DEG[index]
	return Vector2(_midpoint_deg(prev, center), _midpoint_deg(center, next))


static func _midpoint_deg(a: float, b: float) -> float:
	var diff := fposmod(b - a + 180.0, 360.0) - 180.0
	return fposmod(a + diff * 0.5, 360.0)
