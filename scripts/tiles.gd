class_name Tiles
extends RefCounted
## Atlas coordinates and layer names for the shared isometric TileSet.
## Owned by foundation. Sync: none (constants).
##
## Every biome TileSet (art-audio) keeps these same ids so floor-generation
## can paint without knowing which biome it is drawing.

## Atlas source id inside the TileSet.
const SOURCE := 0

const FLOOR := Vector2i(0, 0)
const WALL := Vector2i(1, 0)
const PIT := Vector2i(2, 0)

## Every walkable floor look, FLOOR first. Painters call `floor_at(cell)` so a
## room does not repeat one stamp; the rest of the game only reads WALKABLE.
const FLOOR_VARIANTS: Array[Vector2i] = [FLOOR, Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]

## Custom data layer (bool) that marks cells enemies and players can stand on.
const WALKABLE: StringName = &"walkable"


## The floor variant for `cell`. A pure hash of the coordinates, so every peer
## paints the same floor without syncing it.
static func floor_at(cell: Vector2i) -> Vector2i:
	var h: int = (cell.x * 73856093) ^ (cell.y * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	h ^= h >> 16
	return FLOOR_VARIANTS[posmod(h, FLOOR_VARIANTS.size())]
