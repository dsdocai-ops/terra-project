class_name Floor
extends Node2D
## The live scene of one generated floor (SPEC-floor-generation `Floor`): paints
## a `FloorLayout` onto the World's tile layers, holds the `Room` and `Door`
## nodes and the `AStarGrid2D` enemies path on. Owned by floor-generation.
## Sync: every peer paints the same layout from the same seed. The host decides
## when rooms lock and clear and mirrors the door state to clients over
## `_apply_room_locked`; populators run on the host only.

## Fired on every peer once the layout is painted.
signal painted(layout: FloorLayout)

## Fired on every peer the first time the local player stands in a room.
signal room_visited(index: int)

const FLOOR_TILE_TINT_NODE: StringName = &"Floor"
## Dark veil over a room the local player has not entered yet.
const SHADE_COLOR := Color(0.02, 0.02, 0.05, 0.82)
const SHADE_FADE_SECONDS: float = 0.45

var layout: FloorLayout = null
var astar: AStarGrid2D = null
var rooms: Array[Room] = []
## Room index -> that room's Door nodes.
var doors_by_room: Dictionary[int, Array] = {}

## Local presentation only: which rooms this peer's player has entered, and the
## room they stand in now (-1 in a corridor). Never synced.
var visited: Dictionary[int, bool] = {}
var current_room_index: int = -1

var _world: World = null
var _shades: Dictionary[int, Polygon2D] = {}


## Paints `layout` into `world`'s tile layers and builds rooms, doors and the
## path grid. Replaces anything this node held before.
func paint(p_layout: FloorLayout, biome: BiomeData, world: World) -> void:
	layout = p_layout
	_world = world
	_clear_children()
	_paint_tiles(world, biome)
	_build_astar()
	_build_rooms()
	painted.emit(layout)


func _clear_children() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	rooms.clear()
	doors_by_room.clear()
	visited.clear()
	_shades.clear()
	current_room_index = -1


func _paint_tiles(world: World, biome: BiomeData) -> void:
	world.floor_layer.clear()
	world.walls_layer.clear()
	world.floor_layer.modulate = biome.tint if biome != null else Color.WHITE
	for cell: Vector2i in layout.walkable:
		world.floor_layer.set_cell(cell, Tiles.SOURCE, Tiles.FLOOR)
	for cell: Vector2i in layout.walkable:
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2):
				var neighbor: Vector2i = cell + Vector2i(dx, dy)
				if not layout.walkable.has(neighbor):
					world.walls_layer.set_cell(neighbor, Tiles.SOURCE, Tiles.WALL)


func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, FloorGenerator.GRID, FloorGenerator.GRID)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for x: int in FloorGenerator.GRID:
		for y: int in FloorGenerator.GRID:
			if not layout.walkable.has(Vector2i(x, y)):
				astar.set_point_solid(Vector2i(x, y), true)


func _build_rooms() -> void:
	for spec: RoomSpec in layout.rooms:
		var room := Room.new()
		room.setup(spec, self)
		add_child(room)
		rooms.append(room)
		var doors: Array = []
		for cell: Vector2i in spec.door_cells:
			var door := Door.new()
			door.cell = cell
			door.name = "Door_%d_%d" % [cell.x, cell.y]
			door.position = Iso.to_screen(cell)
			add_child(door)
			doors.append(door)
		doors_by_room[spec.index] = doors
		_add_shade(spec)


## Host. Runs every registered populator for every room (chests, shrines,
## shops, combat wave hooks). Call once, after `paint`.
func populate() -> void:
	if not multiplayer.is_server():
		return
	for room: Room in rooms:
		FloorGenerator.run_populators(room)


func room_at(world_pos: Vector2) -> Room:
	var cell: Vector2i = Iso.to_tile(world_pos)
	for room: Room in rooms:
		if room.spec.rect.has_point(cell):
			return room
	return null


func room_of_type(type: int) -> Room:
	for room: Room in rooms:
		if room.type == type:
			return room
	return null


## World position of the Start room's anchor: where players appear.
func start_position() -> Vector2:
	if layout == null or layout.start_room == null:
		return Vector2.ZERO
	return Iso.to_screen(layout.start_room.anchor)


## Host. Closes or opens a room's doors here and on every client.
func set_room_locked(room: Room, locked: bool) -> void:
	if not is_inside_tree():
		return
	_apply_room_locked(room.spec.index, locked)
	if multiplayer.is_server() and NetworkManager.is_active and multiplayer.get_peers().size() > 0:
		_apply_room_locked.rpc(room.spec.index, locked)


@rpc("authority", "call_remote", "reliable")
func _apply_room_locked(room_index: int, locked: bool) -> void:
	var doors: Array = doors_by_room.get(room_index, [])
	for door: Door in doors:
		door.set_closed(locked)


func _physics_process(_delta: float) -> void:
	var player: Player = NetworkManager.players.get(NetworkManager.local_peer_id)
	if player == null or not is_instance_valid(player):
		return
	var room: Room = room_at(player.position)
	current_room_index = room.spec.index if room != null else -1
	if room != null and not visited.has(room.spec.index):
		_visit(room.spec.index)


func _visit(index: int) -> void:
	visited[index] = true
	var shade: Polygon2D = _shades.get(index)
	if shade != null and is_instance_valid(shade):
		var tween: Tween = shade.create_tween()
		tween.tween_property(shade, "modulate:a", 0.0, SHADE_FADE_SECONDS)
		tween.tween_callback(shade.queue_free)
	_shades.erase(index)
	room_visited.emit(index)


## A veil over the room (and its wall ring) until the local player walks in.
func _add_shade(spec: RoomSpec) -> void:
	var rect: Rect2i = spec.rect.grow(1)
	var x0: float = float(rect.position.x) - 0.5
	var y0: float = float(rect.position.y) - 0.5
	var x1: float = float(rect.end.x) - 0.5
	var y1: float = float(rect.end.y) - 0.5
	var shade := Polygon2D.new()
	shade.name = "Shade%d" % spec.index
	shade.polygon = PackedVector2Array([
		_tile_corner(x0, y0), _tile_corner(x1, y0), _tile_corner(x1, y1), _tile_corner(x0, y1)])
	shade.color = SHADE_COLOR
	shade.z_index = 40
	add_child(shade)
	_shades[spec.index] = shade


## Screen point of a fractional tile-space position (see Iso.to_screen).
func _tile_corner(x: float, y: float) -> Vector2:
	return Vector2((x - y) * Iso.HALF_W + Iso.HALF_W, (x + y) * Iso.HALF_H + Iso.HALF_H)
