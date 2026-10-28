class_name FloorPaint
extends RefCounted
## The tile kind of every grid cell of one generated floor (SPEC-floor-generation
## step 5: "Paint: floor tiles, wall tiles around every walkable cell, pit tiles
## elsewhere"). Owned by floor-generation (Dev A lane).
## Sync: none; every peer derives identical kinds from its own generated layout,
## so painting never syncs a tile.

enum Kind { PIT, FLOOR, WALL }

## The layout whose walkable set decides every kind.
var layout: FloorLayout
## Side of the square grid the floor paints onto.
var grid: int = FloorGenerator.GRID

## The wall ring: every non-walkable cell touching a walkable one.
var _walls: Dictionary[Vector2i, bool] = {}


func _init(p_layout: FloorLayout, p_grid: int = FloorGenerator.GRID) -> void:
	layout = p_layout
	grid = p_grid
	for cell: Vector2i in layout.walkable:
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2):
				var near: Vector2i = cell + Vector2i(dx, dy)
				var inside: bool = near.x >= 0 and near.y >= 0 and near.x < grid and near.y < grid
				if inside and not layout.is_walkable(near):
					_walls[near] = true


## The tile kind `cell` paints as: floor on the layout's walkable cells, wall on
## the ring around them, pit everywhere else in the grid.
func kind(cell: Vector2i) -> int:
	if layout.is_walkable(cell):
		return Kind.FLOOR
	if _walls.has(cell):
		return Kind.WALL
	return Kind.PIT


## Every wall cell, in row-major order (the order a grid sweep paints them in).
func wall_cells() -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for y: int in grid:
		for x: int in grid:
			var cell := Vector2i(x, y)
			if _walls.has(cell):
				found.append(cell)
	return found
