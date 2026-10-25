class_name RoomFurniture
extends RefCounted
## Spreads a room's interactables around its centre instead of stacking them on
## the anchor, and places the furniture no room type owns: crates and ore seams
## in combat rooms. Owned by run-economy. Sync: host only, it runs from the
## floor populators.

## Screen pixels from the room centre to the ring the furniture stands on.
const RING_RADIUS: float = 96.0
## Isometric squash of the ring, so it reads as a circle on the ground.
const RING_SQUASH: float = 0.5


## Where item `index` of `count` stands, relative to the room centre. One item
## stays in the middle.
static func spot(index: int, count: int) -> Vector2:
	if count <= 1:
		return Vector2.ZERO
	var angle: float = TAU * float(index) / float(count) + 0.6
	return Vector2(cos(angle) * RING_RADIUS, sin(angle) * RING_RADIUS * RING_SQUASH)


## Moves already-placed furniture onto the ring.
static func arrange(items: Array) -> void:
	for index: int in items.size():
		var item: Node2D = items[index] as Node2D
		if item != null:
			item.position = spot(index, items.size())


## The COMBAT populator: one to three crates, and an ore seam in every second
## room, spread around the room. Counts come from the room index so every run of
## the same floor places the same furniture.
static func populate_combat(room: Node) -> void:
	var spec: RoomSpec = room.get(&"spec") as RoomSpec
	if spec == null:
		return
	var crates: int = 1 + spec.index % 3
	var seams: int = spec.index % 2
	var placed: Array = []
	placed.append_array(Breakable.place_in(room, crates))
	placed.append_array(MiningNode.place_in(room, seams))
	arrange(placed)


## Registers the COMBAT populator once. Returns true when it is registered.
static func register_populator() -> bool:
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, Callable(RoomFurniture, &"populate_combat"))
	return true
