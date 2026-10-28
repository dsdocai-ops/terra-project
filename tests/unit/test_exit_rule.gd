extends GutTest
## Unit tests for the Exit-opens rule (W3-A2, G10a2): `ExitRule.required_clears`
## is the fewest locking rooms of any simple Start-Exit path (SPEC-floor-
## generation "Doors and clearing": the Exit requires all COMBAT/ELITE_COMBAT
## rooms on at least one Start-Exit path to be cleared), the painted `Floor`
## writes it into `RunState.required_rooms_cleared`, a locking room's doors
## close on enter and open again on `room_cleared`, and standing on the Exit
## advances the run only once the rule holds.
## Owned by floor-generation.
##
## Signal values are captured with named method callbacks, never lambdas
## (LESSONS: `.connect(lambda)` never fires under GUT). after_each clears
## GameState.run and the NetworkManager session so no autoload state leaks into
## the next test file (LESSONS: autoload state bleeds across GUT files).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const REAL_SEEDS: Array[int] = [7, 42, 1234, 90210, 555]

## Hand-built layouts keep rooms on a row, far enough apart to never touch.
const TEST_ROOM_W: int = 9
const TEST_ROOM_H: int = 7
const TEST_ROOM_STRIDE: int = 20

var _player: Player = null
var _cleared_rooms: Array[Node] = []


func before_each() -> void:
	GameState.run = null
	_cleared_rooms.clear()


func after_each() -> void:
	if Events.room_cleared.is_connected(_on_room_cleared):
		Events.room_cleared.disconnect(_on_room_cleared)
	_player = null
	NetworkManager.players.clear()
	NetworkManager.disconnect_all()
	GameState.run = null
	GameState.last_advance_refusal = GameState.ADVANCE_REFUSAL_NONE


func _on_room_cleared(room: Node) -> void:
	_cleared_rooms.append(room)


## A layout whose rooms are `types[i]` (indices in layout order), joined by
## exactly `edges`. Returns the assembled layout (start/exit picked by type).
func _layout(types: Array[int], edges: Array[Vector2i]) -> FloorLayout:
	var rects: Array[Rect2i] = []
	for i: int in types.size():
		rects.append(Rect2i(3 + i * TEST_ROOM_STRIDE, 3, TEST_ROOM_W, TEST_ROOM_H))
	return FloorGenerator.assemble(0, 1, 1, [] as Array[int], rects, types, [] as Array[Vector2i], edges)


# --- the pure rule -----------------------------------------------------------


func test_a_single_combat_room_on_the_path_requires_one_clear() -> void:
	var layout := _layout(
		[FloorGenerator.RoomType.START, FloorGenerator.RoomType.COMBAT, FloorGenerator.RoomType.EXIT] as Array[int],
		[Vector2i(0, 1), Vector2i(1, 2)] as Array[Vector2i])
	assert_eq(ExitRule.required_clears(layout), 1, "start -> combat -> exit demands the one combat room")


func test_a_path_with_no_locking_room_opens_the_exit_at_once() -> void:
	var layout := _layout(
		[FloorGenerator.RoomType.START, FloorGenerator.RoomType.TREASURE, FloorGenerator.RoomType.EXIT] as Array[int],
		[Vector2i(0, 1), Vector2i(1, 2)] as Array[Vector2i])
	assert_eq(ExitRule.required_clears(layout), 0, "a Start-Exit path through no locking room demands nothing")


func test_the_rule_takes_the_fewest_locks_of_any_path_not_the_fewest_hops() -> void:
	# Route A: start -> combat -> combat -> exit (3 hops, 2 locks).
	# Route B: start -> treasure -> rest -> exit (4 hops, no locks).
	# The fewest-hops path carries 2 locks; the rule is "at least one path", so 0.
	var layout := _layout(
		[
			FloorGenerator.RoomType.START, FloorGenerator.RoomType.COMBAT, FloorGenerator.RoomType.COMBAT,
			FloorGenerator.RoomType.EXIT, FloorGenerator.RoomType.TREASURE, FloorGenerator.RoomType.REST,
		] as Array[int],
		[
			Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3),
			Vector2i(0, 4), Vector2i(4, 5), Vector2i(5, 3),
		] as Array[Vector2i])
	assert_eq(ExitRule.required_clears(layout), 0, "the no-lock route opens the exit")
	assert_eq(layout.required_rooms, 0, "the assembled layout carries the same rule")


func test_an_elite_on_the_path_counts_like_a_combat_room() -> void:
	var layout := _layout(
		[
			FloorGenerator.RoomType.START, FloorGenerator.RoomType.ELITE_COMBAT,
			FloorGenerator.RoomType.ELITE_COMBAT, FloorGenerator.RoomType.EXIT,
		] as Array[int],
		[Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3)] as Array[Vector2i])
	assert_eq(ExitRule.required_clears(layout), 2, "both elite rooms on the one path are demanded")


func test_a_detour_that_avoids_a_lock_wins_over_the_straight_chain() -> void:
	# Straight: start -> combat -> exit (1 lock). Detour: start -> treasure ->
	# rest -> exit (0 locks, longest). The minimum is what counts.
	var layout := _layout(
		[
			FloorGenerator.RoomType.START, FloorGenerator.RoomType.COMBAT, FloorGenerator.RoomType.EXIT,
			FloorGenerator.RoomType.TREASURE, FloorGenerator.RoomType.REST,
		] as Array[int],
		[
			Vector2i(0, 1), Vector2i(1, 2), Vector2i(0, 3),
			Vector2i(3, 4), Vector2i(4, 2),
		] as Array[Vector2i])
	assert_eq(ExitRule.required_clears(layout), 0, "the longest route carries no lock at all")


func test_an_exit_reached_by_no_path_is_never_open() -> void:
	# Two components: the start's and the exit's. One more clear than the floor
	# even has is the demand, so rooms_cleared can never satisfy it.
	var layout := _layout(
		[
			FloorGenerator.RoomType.START, FloorGenerator.RoomType.COMBAT, FloorGenerator.RoomType.EXIT,
			FloorGenerator.RoomType.COMBAT,
		] as Array[int],
		[Vector2i(0, 1), Vector2i(2, 3)] as Array[Vector2i])
	assert_eq(ExitRule.required_clears(layout), 3, "unreachable exit demands more clears than the floor has")
	assert_eq(layout.required_rooms, 3, "the assembled layout carries the unreachable rule")


func test_a_layout_without_a_start_or_an_exit_requires_nothing() -> void:
	var no_start := _layout(
		[FloorGenerator.RoomType.COMBAT, FloorGenerator.RoomType.EXIT] as Array[int],
		[Vector2i(0, 1)] as Array[Vector2i])
	assert_eq(ExitRule.required_clears(no_start), 0, "no START, no rule")
	var no_exit := _layout(
		[FloorGenerator.RoomType.START, FloorGenerator.RoomType.COMBAT] as Array[int],
		[Vector2i(0, 1)] as Array[Vector2i])
	assert_eq(ExitRule.required_clears(no_exit), 0, "no EXIT, no rule")


## Brute force over every simple Start-Exit path: the smallest count of
## locking rooms on any of them, or -1 when no path exists.
func _brute_force_required(layout: FloorLayout) -> int:
	var seen: Dictionary[int, bool] = {}
	return _brute_force_from(layout, layout.start_room.index, 0, seen)


func _brute_force_from(layout: FloorLayout, index: int, locks: int, visited: Dictionary[int, bool]) -> int:
	visited[index] = true
	if index == layout.exit_room.index:
		return locks
	var best: int = -1
	for next: int in layout.rooms[index].neighbors:
		if visited.has(next):
			continue
		var step: int = locks + (1 if layout.rooms[next].locks() else 0)
		var total: int = _brute_force_from(layout, next, step, visited.duplicate())
		if total < 0:
			continue
		if best < 0 or total < best:
			best = total
	return best


func test_the_real_layouts_required_count_is_the_fewest_locks_of_any_path() -> void:
	for run_seed: int in REAL_SEEDS:
		for floor_index: int in [1, 2, 3]:
			var layout: FloorLayout = FloorGenerator.generate(run_seed, floor_index, BiomeData.for_index(1), [] as Array[int])
			var brute: int = _brute_force_required(layout)
			assert_eq(ExitRule.required_clears(layout), brute,
				"seed %d floor %d matches the brute force" % [run_seed, floor_index])
			assert_eq(layout.required_rooms, brute,
				"seed %d floor %d assembled count matches" % [run_seed, floor_index])


# --- the painted floor writes the rule into the run ------------------------------


func _become_host_with_run() -> void:
	NetworkManager.start_solo()
	var party: Array[PlayerSpawnInfo] = [PlayerSpawnInfo.new(1)]
	GameState.start_run(5, 1, party)
	assert_not_null(GameState.run, "the test run is live")


func _painted_floor(world: World, run_seed: int, floor_index: int = 1) -> Floor:
	var floor_node := Floor.new()
	add_child_autofree(floor_node)
	var layout: FloorLayout = FloorGenerator.generate(run_seed, floor_index, BiomeData.for_index(1), [] as Array[int])
	floor_node.paint(layout, BiomeData.for_index(1), world)
	return floor_node


func _make_world() -> World:
	var world := (load("res://scenes/main/world.tscn") as PackedScene).instantiate() as World
	world.debug_test_floor = false
	add_child_autofree(world)
	return world


func test_the_painted_floor_writes_the_rule_into_the_live_run() -> void:
	_become_host_with_run()
	var floor_node := _painted_floor(_make_world(), 42)
	assert_eq(GameState.run.required_rooms_cleared, floor_node.layout.required_rooms,
		"the run's requirement is the painted floor's rule")
	assert_eq(GameState.run.required_rooms_cleared, ExitRule.required_clears(floor_node.layout),
		"the run's requirement is the ExitRule's number")


func test_a_repaint_writes_the_new_floors_rule() -> void:
	_become_host_with_run()
	var world := _make_world()
	var first_floor := _painted_floor(world, 42)
	var second_floor := _painted_floor(world, 7)
	assert_eq(GameState.run.required_rooms_cleared, second_floor.layout.required_rooms,
		"the run follows the newest painted floor")
	assert_eq(second_floor.layout.required_rooms, ExitRule.required_clears(second_floor.layout),
		"the new floor's rule is its own (first was %d)" % first_floor.layout.required_rooms)
	assert_eq(GameState.run.rooms_cleared, 0, "the cleared counter is the run's, untouched by a repaint")


func test_painting_without_a_live_run_writes_nothing() -> void:
	assert_null(GameState.run, "precondition: no run")
	_painted_floor(_make_world(), 42)
	assert_null(GameState.run, "a paint without a run stays without one")


# --- the doors: lock on enter, open on room_cleared -----------------------------


func _room_of_type(floor_node: Floor, type: int) -> Room:
	for room: Room in floor_node.rooms:
		if room.type == type:
			return room
	return null


func _locking_room_with_doors(floor_node: Floor) -> Room:
	for room: Room in floor_node.rooms:
		if room.spec.locks() and room.spec.door_cells.size() > 0:
			return room
	return null


func _room_doors(floor_node: Floor, room: Room) -> Array:
	return floor_node.doors_by_room.get(room.spec.index, [] as Array)


func _all_other_doors(floor_node: Floor, room: Room) -> Array:
	var others: Array = []
	for index: int in floor_node.doors_by_room:
		if index == room.spec.index:
			continue
		others.append_array(floor_node.doors_by_room[index])
	return others


func _enter(room: Room, player: Player) -> void:
	room._on_player_entered(player)


func _make_player() -> Player:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	return _player


func test_a_locking_room_closes_its_doors_on_enter() -> void:
	var floor_node := _painted_floor(_make_world(), 42)
	var room := _locking_room_with_doors(floor_node)
	assert_not_null(room, "seed 42 has a locking room with doors")
	var enemy := Node2D.new()
	floor_node.add_child(enemy)
	room.track_enemy(enemy)
	_enter(room, _make_player())
	assert_true(room.triggered, "the room is triggered")
	for door: Door in _room_doors(floor_node, room):
		assert_true(door.closed, "door %s closed on enter" % str(door.cell))
	for door: Door in _all_other_doors(floor_node, room):
		assert_false(door.closed, "door %s belongs to no triggered room yet" % str(door.cell))


func test_a_room_that_never_locks_closes_no_doors_on_enter() -> void:
	var floor_node := _painted_floor(_make_world(), 42)
	var room := _room_of_type(floor_node, FloorGenerator.RoomType.TREASURE)
	assert_not_null(room, "seed 42 has a treasure room")
	assert_false(room.spec.locks(), "precondition: the treasure room does not lock")
	_enter(room, _make_player())
	assert_true(room.triggered, "the visit is registered")
	for index: int in floor_node.doors_by_room:
		for door: Door in floor_node.doors_by_room[index]:
			assert_false(door.closed, "door %s stays open" % str(door.cell))


func test_the_doors_open_on_room_cleared() -> void:
	Events.room_cleared.connect(_on_room_cleared)
	var floor_node := _painted_floor(_make_world(), 42)
	var room := _locking_room_with_doors(floor_node)
	var enemy := Node2D.new()
	floor_node.add_child(enemy)
	room.track_enemy(enemy)
	_enter(room, _make_player())
	for door: Door in _room_doors(floor_node, room):
		assert_true(door.closed, "locked on the way in")
	enemy.free()
	assert_true(room.cleared, "the last tracked enemy gone clears the room")
	for door: Door in _room_doors(floor_node, room):
		assert_false(door.closed, "door %s reopened on room_cleared" % str(door.cell))
	assert_eq(_cleared_rooms.size(), 1, "one room_cleared was emitted")
	assert_same(_cleared_rooms[0], room, "the event carried the cleared room")
	# Re-entering a cleared room never locks it again.
	_enter(room, _player)
	for door: Door in _room_doors(floor_node, room):
		assert_false(door.closed, "door %s stays open after a re-entry" % str(door.cell))


# --- the Exit: reachable only once the rule holds ---------------------------------


func _exit_room(floor_node: Floor) -> Room:
	return _room_of_type(floor_node, FloorGenerator.RoomType.EXIT)


func _seed_with_a_demanded_room() -> int:
	# The first test seed whose real layout demands at least one clear.
	for run_seed: int in REAL_SEEDS:
		var layout: FloorLayout = FloorGenerator.generate(run_seed, 1, BiomeData.for_index(1), [] as Array[int])
		if layout.required_rooms >= 1:
			return run_seed
	return -1


func test_the_exit_stays_shut_until_the_rule_holds() -> void:
	var run_seed: int = _seed_with_a_demanded_room()
	assert_gte(run_seed, 0, "a test seed demands a clear")
	_become_host_with_run()
	var floor_node := _painted_floor(_make_world(), run_seed)
	var exit_room := _exit_room(floor_node)
	assert_not_null(exit_room, "the floor has an Exit room")
	_make_player()
	NetworkManager.players[1] = _player
	_player.position = Iso.to_screen(exit_room.spec.anchor)
	var required: int = GameState.run.required_rooms_cleared
	assert_gte(required, 1, "the painted floor demands at least one clear")
	var floor_before: int = GameState.run.floor_index
	exit_room._check_exit()
	assert_eq(GameState.run.floor_index, floor_before, "a shut exit never advances")
	assert_eq(GameState.last_advance_refusal, GameState.ADVANCE_REFUSAL_NONE,
		"the shut exit returns silently; the refusal record is next_floor's own")
	GameState.run.rooms_cleared = required
	exit_room._check_exit()
	assert_eq(GameState.run.floor_index, floor_before + 1, "the rule met, the exit advances the run")
	assert_eq(GameState.run.floors_cleared, 1, "the advance counted the floor")


func test_the_exit_only_takes_a_player_on_its_anchor() -> void:
	var run_seed: int = _seed_with_a_demanded_room()
	_become_host_with_run()
	var floor_node := _painted_floor(_make_world(), run_seed)
	var exit_room := _exit_room(floor_node)
	_make_player()
	NetworkManager.players[1] = _player
	# The rule already holds; only the standing point is wrong.
	GameState.run.rooms_cleared = GameState.run.required_rooms_cleared
	_player.position = Iso.to_screen(exit_room.spec.anchor + Vector2i(3, 0))
	var floor_before: int = GameState.run.floor_index
	exit_room._check_exit()
	assert_eq(GameState.run.floor_index, floor_before, "off the anchor, the open exit is not reached")
