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
const FOG_SHADER: String = "res://scenes/dungeon/fog.gdshader"
const FOG_MAX_ROOMS: int = 16

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
var _fog: ColorRect = null
## Per layout edge: the tiles of its hallway; which are cleared; the mask texture.
var _edge_cells: Array[Dictionary] = []
var _edge_cleared: Dictionary[int, bool] = {}
var _corridor_mask: Image = null
var _corridor_texture: ImageTexture = null


## Paints `layout` into `world`'s tile layers and builds rooms, doors and the
## path grid. Replaces anything this node held before.
func paint(p_layout: FloorLayout, biome: BiomeData, world: World) -> void:
	layout = p_layout
	_world = world
	_clear_children()
	_paint_tiles(world, biome)
	_build_astar()
	_build_rooms()
	_build_fog()
	painted.emit(layout)


func _clear_children() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	rooms.clear()
	doors_by_room.clear()
	visited.clear()
	_fog = null
	_edge_cells.clear()
	_edge_cleared.clear()
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
	if room == null:
		_reveal_hallway_at(Iso.to_tile(player.position))
	current_room_index = room.spec.index if room != null else -1
	if room != null and not visited.has(room.spec.index):
		_visit(room.spec.index)


func _visit(index: int) -> void:
	visited[index] = true
	_sync_fog()
	room_visited.emit(index)


## Solid black over the whole floor; the shader clears entered rooms and a small
## lamp around the player in hallways. Local presentation only.
func _build_fog() -> void:
	var span: float = float(FloorGenerator.GRID) * Iso.HALF_W * 2.0
	_fog = ColorRect.new()
	_fog.name = "Fog"
	_fog.position = Vector2(-span * 0.5 - 200.0, -200.0)
	_fog.size = Vector2(span + 400.0, span * 0.5 + 400.0)
	_fog.color = Color.BLACK
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.z_index = 40
	var material := ShaderMaterial.new()
	material.shader = load(FOG_SHADER) as Shader
	var rects := PackedVector4Array()
	for spec: RoomSpec in layout.rooms:
		var grown: Rect2i = spec.rect.grow(1)
		rects.append(Vector4(grown.position.x - 0.5, grown.position.y - 0.5, grown.end.x - 0.5, grown.end.y - 0.5))
	while rects.size() < FOG_MAX_ROOMS:
		rects.append(Vector4.ZERO)
	material.set_shader_parameter(&"rects", rects)
	material.set_shader_parameter(&"count", mini(layout.rooms.size(), FOG_MAX_ROOMS))
	_build_hallway_cells()
	material.set_shader_parameter(&"corridors", _corridor_texture)
	_fog.material = material
	add_child(_fog)
	_sync_fog()


func _sync_fog() -> void:
	if _fog == null:
		return
	var lit := PackedFloat32Array()
	lit.resize(FOG_MAX_ROOMS)
	for index: int in visited:
		if index < FOG_MAX_ROOMS:
			lit[index] = 1.0
	(_fog.material as ShaderMaterial).set_shader_parameter(&"lit", lit)


## Stepping into a hallway clears that whole hallway, walls included.
func _reveal_hallway_at(cell: Vector2i) -> void:
	for index: int in _edge_cells.size():
		if _edge_cleared.has(index) or not _edge_cells[index].has(cell):
			continue
		_edge_cleared[index] = true
		for tile: Vector2i in _edge_cells[index]:
			for dx: int in range(-1, 2):
				for dy: int in range(-1, 2):
					var near: Vector2i = tile + Vector2i(dx, dy)
					if near.x >= 0 and near.y >= 0 and near.x < FloorGenerator.GRID and near.y < FloorGenerator.GRID:
						_corridor_mask.set_pixelv(near, Color.WHITE)
		_corridor_texture.update(_corridor_mask)


## The tiles each layout edge's hallway covers, from the generator's own carving.
func _build_hallway_cells() -> void:
	var rects: Array[Rect2i] = []
	for spec: RoomSpec in layout.rooms:
		rects.append(spec.rect)
	_edge_cells.clear()
	for edge: Vector2i in layout.edges:
		var cells: Dictionary = {}
		for cell: Vector2i in FloorGenerator._carve_corridors(rects, [edge]):
			cells[cell] = true
		_edge_cells.append(cells)
	_corridor_mask = Image.create(FloorGenerator.GRID, FloorGenerator.GRID, false, Image.FORMAT_R8)
	_corridor_texture = ImageTexture.create_from_image(_corridor_mask)
