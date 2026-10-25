class_name FloorLayout
extends RefCounted
## The pure, deterministic description of one floor (SPEC-floor-generation
## `FloorLayout`). Owned by floor-generation.
## Sync: none; each peer generates it locally from the host's seed and the
## `layout_hash` assertion catches divergence. `to_wire`/`from_wire` carry the
## host's layout to a peer whose generation diverged.

const SOURCE: StringName = &"floor-generation"
## Ints per room on the wire: x, y, w, h, type.
const WIRE_ROOM_STRIDE: int = 5

var seed: int = 0
var floor_index: int = 1
var biome_id: int = 1
var modifiers: Array[int] = []
var rooms: Array[RoomSpec] = []
## Every corridor cell, in row-major order.
var corridors: Array[Vector2i] = []
## Room index pairs joined by a corridor (MST plus loops).
var edges: Array[Vector2i] = []
var start_room: RoomSpec = null
var exit_room: RoomSpec = null
## Combat rooms on the shortest Start to Exit path: the Exit-opens rule.
var required_rooms: int = 0
var layout_hash: int = 0
var source: StringName = SOURCE
## Every walkable cell (rooms and corridors) -> true.
var walkable: Dictionary[Vector2i, bool] = {}


func is_walkable(cell: Vector2i) -> bool:
	return walkable.has(cell)


## The room whose rect holds `cell`, or null (corridors belong to no room).
func room_at_cell(cell: Vector2i) -> RoomSpec:
	for room: RoomSpec in rooms:
		if room.rect.has_point(cell):
			return room
	return null


func rooms_of_type(type: int) -> Array[RoomSpec]:
	var found: Array[RoomSpec] = []
	for room: RoomSpec in rooms:
		if room.type == type:
			found.append(room)
	return found


func to_wire() -> Dictionary:
	var flat_rooms := PackedInt32Array()
	for room: RoomSpec in rooms:
		flat_rooms.append_array(PackedInt32Array([room.rect.position.x, room.rect.position.y, room.rect.size.x, room.rect.size.y, room.type]))
	var flat_corridors := PackedInt32Array()
	for cell: Vector2i in corridors:
		flat_corridors.append(cell.x)
		flat_corridors.append(cell.y)
	var flat_edges := PackedInt32Array()
	for edge: Vector2i in edges:
		flat_edges.append(edge.x)
		flat_edges.append(edge.y)
	return {
		"source": String(SOURCE),
		"seed": seed,
		"floor_index": floor_index,
		"biome_id": biome_id,
		"modifiers": PackedInt32Array(modifiers),
		"rooms": flat_rooms,
		"corridors": flat_corridors,
		"edges": flat_edges,
		"layout_hash": layout_hash,
	}


## The layout a `to_wire()` Dictionary describes, rebuilt through the same
## assembly the generator uses; the hash is recomputed, not trusted.
static func from_wire(data: Dictionary) -> FloorLayout:
	var flat_rooms: PackedInt32Array = data.get("rooms", PackedInt32Array())
	var rects: Array[Rect2i] = []
	var types: Array[int] = []
	var index: int = 0
	while index + WIRE_ROOM_STRIDE - 1 < flat_rooms.size():
		rects.append(Rect2i(flat_rooms[index], flat_rooms[index + 1], flat_rooms[index + 2], flat_rooms[index + 3]))
		types.append(flat_rooms[index + 4])
		index += WIRE_ROOM_STRIDE
	var flat_corridors: PackedInt32Array = data.get("corridors", PackedInt32Array())
	var corridor_cells: Array[Vector2i] = []
	index = 0
	while index + 1 < flat_corridors.size():
		corridor_cells.append(Vector2i(flat_corridors[index], flat_corridors[index + 1]))
		index += 2
	var flat_edges: PackedInt32Array = data.get("edges", PackedInt32Array())
	var edge_list: Array[Vector2i] = []
	index = 0
	while index + 1 < flat_edges.size():
		edge_list.append(Vector2i(flat_edges[index], flat_edges[index + 1]))
		index += 2
	var wire_modifiers: Array[int] = []
	for value: int in data.get("modifiers", PackedInt32Array()):
		wire_modifiers.append(value)
	return FloorGenerator.assemble(
		int(data.get("seed", 0)), int(data.get("floor_index", 1)), int(data.get("biome_id", 1)),
		wire_modifiers, rects, types, corridor_cells, edge_list)
