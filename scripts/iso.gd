class_name Iso
extends RefCounted
## Isometric math for 64x32 diamond-down tiles. Owned by foundation.
## Pure functions, no state. Sync: none.
##
## Tile space: +x runs down-right on screen, +y runs down-left. Screen space is
## the TileMapLayer's local space, which Godot centers so that tile (0, 0) sits
## at (32, 16). These formulas match TileMapLayer.map_to_local / local_to_map
## for TileSet.TILE_SHAPE_ISOMETRIC + TILE_LAYOUT_DIAMOND_DOWN; test_iso.gd
## asserts that against a real layer. Facing sectors live in Facing.

const TILE_SIZE := Vector2i(64, 32)
const HALF_W := TILE_SIZE.x * 0.5
const HALF_H := TILE_SIZE.y * 0.5


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
