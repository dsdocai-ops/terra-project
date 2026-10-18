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

## Custom data layer (bool) that marks cells enemies and players can stand on.
const WALKABLE: StringName = &"walkable"
