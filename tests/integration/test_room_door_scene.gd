extends GutTest
## The W3-A2 scene wiring (G10b1): the Room and Door nodes the painted Floor
## builds lock and clear through the real scene flow — the room's own physics
## scan sees the player standing inside, its door nodes close (collision shape
## and visual), and the last tracked enemy leaving the scene tree clears the
## room and reopens them. The G10a2 unit tests call `Room._on_player_entered`
## by hand; this file drives the nodes the engine steps.
## Owned by floor-generation.
## Single instance: the offline peer is the server, so the host-only room scan
## runs; `Floor.set_room_locked` mirrors over RPC only with live peers, so no
## replicated state changes here.

const WORLD_SCENE: PackedScene = preload("res://scenes/main/world.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const RUN_SEED: int = 42

var _player: Player = null
var _cleared: Array[Node] = []
var _entered: Array[Node] = []


func before_each() -> void:
	_cleared.clear()
	_entered.clear()
	NetworkManager.start_solo()


func after_each() -> void:
	if Events.room_cleared.is_connected(_on_room_cleared):
		Events.room_cleared.disconnect(_on_room_cleared)
	if Events.room_entered.is_connected(_on_room_entered):
		Events.room_entered.disconnect(_on_room_entered)
	NetworkManager.players.erase(NetworkManager.local_peer_id)
	NetworkManager.disconnect_all()
	_player = null


func _on_room_cleared(room: Node) -> void:
	_cleared.append(room)


func _on_room_entered(room: Node, _who: Player) -> void:
	_entered.append(room)


func _make_world() -> World:
	var world := WORLD_SCENE.instantiate() as World
	world.debug_test_floor = false
	add_child_autofree(world)
	return world


## Paints seed RUN_SEED's real generated layout onto `world` (Floor._build_rooms
## builds the Room and Door nodes under it).
func _painted_floor(world: World) -> Floor:
	var floor_node := Floor.new()
	add_child_autofree(floor_node)
	var layout: FloorLayout = FloorGenerator.generate(RUN_SEED, 1, BiomeData.for_index(1), [] as Array[int])
	floor_node.paint(layout, BiomeData.for_index(1), world)
	return floor_node


func _locking_room_with_doors(floor_node: Floor) -> Room:
	for room: Room in floor_node.rooms:
		if room.spec.locks() and room.spec.door_cells.size() > 0:
			return room
	return null


## The door's own CollisionShape2D child (built in Door._ready, toggled by
## set_deferred in set_closed).
func _door_shape(door: Door) -> CollisionShape2D:
	for child: Node in door.get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
	return null


func _make_player(cell: Vector2i) -> Player:
	_player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(_player)
	_player.position = Iso.to_screen(cell)
	NetworkManager.players[NetworkManager.local_peer_id] = _player
	return _player


func test_the_built_doors_lock_on_enter_through_the_rooms_own_scan() -> void:
	Events.room_entered.connect(_on_room_entered)
	var floor_node := _painted_floor(_make_world())
	var room := _locking_room_with_doors(floor_node)
	assert_not_null(room, "seed %d has a locking room with doors" % RUN_SEED)
	var doors: Array = floor_node.doors_by_room.get(room.spec.index, [] as Array)
	assert_gt(doors.size(), 0, "the room has door nodes")
	# The room spawned something: a tracked body keeps it locked after the scan.
	var enemy := Node2D.new()
	floor_node.add_child(enemy)
	room.track_enemy(enemy)
	# The painted doors start open, their deferred shapes settled.
	await wait_physics_frames(2)
	for door: Door in doors:
		assert_false(door.closed, "door %s starts open" % str(door.cell))
		var shape := _door_shape(door)
		assert_not_null(shape, "door %s built its collision shape" % str(door.cell))
		if shape != null:
			assert_true(shape.disabled, "door %s's shape is off while open" % str(door.cell))
	# The player stands inside; the engine's own physics step runs the room's
	# scan and the room closes its doors through the scene nodes.
	_make_player(room.spec.center())
	await wait_physics_frames(2)
	assert_true(room.triggered, "the room's own scan triggered it")
	assert_eq(_entered.size(), 1, "room_entered fired once")
	assert_same(_entered[0], room, "the event carried the room")
	for door: Door in doors:
		assert_true(door.closed, "door %s closed on enter" % str(door.cell))
		var shape := _door_shape(door)
		if shape != null:
			assert_false(shape.disabled, "door %s's shape is live while closed" % str(door.cell))
	# No other room's doors moved.
	for other: Room in floor_node.rooms:
		if other == room:
			continue
		for door: Door in floor_node.doors_by_room.get(other.spec.index, [] as Array):
			assert_false(door.closed, "door %s of room %d stays open" % [str(door.cell), other.spec.index])


func test_the_built_doors_reopen_when_the_room_clears() -> void:
	Events.room_cleared.connect(_on_room_cleared)
	var floor_node := _painted_floor(_make_world())
	var room := _locking_room_with_doors(floor_node)
	assert_not_null(room, "seed %d has a locking room with doors" % RUN_SEED)
	var doors: Array = floor_node.doors_by_room.get(room.spec.index, [] as Array)
	var enemy := Node2D.new()
	floor_node.add_child(enemy)
	room.track_enemy(enemy)
	_make_player(room.spec.center())
	await wait_physics_frames(2)
	for door: Door in doors:
		assert_true(door.closed, "door %s locked on the way in" % str(door.cell))
	assert_eq(_cleared.size(), 0, "nothing cleared while the enemy lives")
	# The last tracked enemy leaving the scene tree clears the room through the
	# nodes: the room's own tree_exiting wiring counts it gone and opens its
	# doors.
	enemy.queue_free()
	await wait_physics_frames(3)
	assert_true(room.cleared, "the room cleared when its last enemy left the tree")
	assert_eq(_cleared.size(), 1, "one room_cleared was emitted")
	assert_same(_cleared[0], room, "the event carried the room")
	for door: Door in doors:
		assert_false(door.closed, "door %s reopened on room_cleared" % str(door.cell))
		var shape := _door_shape(door)
		if shape != null:
			assert_true(shape.disabled, "door %s's shape is off again while open" % str(door.cell))
	# A cleared room never locks again, even with the player still standing in it.
	await wait_physics_frames(3)
	assert_true(room.triggered, "the player is still inside")
	for door: Door in doors:
		assert_false(door.closed, "door %s stays open on the re-entry scan" % str(door.cell))
