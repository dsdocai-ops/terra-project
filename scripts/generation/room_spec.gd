class_name RoomSpec
extends RefCounted
## One room of a generated floor (SPEC-floor-generation `FloorLayout.rooms`):
## its tile rectangle, type, graph neighbours, the door cells that seal it and
## the cells enemies may spawn on. Owned by floor-generation.
## Sync: none; every peer derives identical specs from the same seed.

var index: int = 0
var rect: Rect2i = Rect2i()
## A `FloorGenerator.RoomType` value.
var type: int = FloorGenerator.RoomType.COMBAT
## Indices of the rooms joined to this one by a corridor.
var neighbors: PackedInt32Array = PackedInt32Array()
## Walkable cells just outside the rect; a locked room puts a door on each.
var door_cells: Array[Vector2i] = []
## Interior cells (two tiles from the walls) enemies may spawn on.
var spawn_points: Array[Vector2i] = []
## Where the room's interactable (chest, shrine, shop) stands.
var anchor: Vector2i = Vector2i.ZERO


func center() -> Vector2i:
	return rect.position + rect.size / 2


## Combat-style rooms: doors lock on enter and open when the room is clear.
func locks() -> bool:
	return FloorGenerator.LOCKING_TYPES.has(type)
