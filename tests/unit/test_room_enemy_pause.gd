extends GutTest
## Off-room enemies (SPEC-enemies-ai "Spawn director", W4-A2 part 2): an enemy whose
## room has no player inside pauses processing and is hidden, and resumes when a
## player comes back in. Owned by enemies-ai, driven by Room (host only). Clients
## are not told, so the pause is a host-side fact; StateSync carries positions only.

const WORLD_SCENE_PATH: String = "res://scenes/main/world.tscn"

var _world: World = null


func before_each() -> void:
	FloorGenerator.clear_populators()


func after_each() -> void:
	NetworkManager.players.erase(1)
	GameState.world = null
	_world = null
	Enemy.reset_separation_cache()


func _wire_world() -> void:
	_world = (load(WORLD_SCENE_PATH) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	GameState.world = _world


func _room_with_wave() -> Room:
	var spec := RoomSpec.new()
	spec.index = 3
	spec.type = FloorGenerator.RoomType.COMBAT
	var points: Array[Vector2i] = []
	for index: int in 8:
		points.append(Vector2i(40 + index * 20, 0))
	spec.spawn_points = points
	var room := Room.new()
	room.spec = spec
	room.type = spec.type
	add_child_autofree(room)
	SpawnDirector.fill_room(room)
	return room


func _enemies_of(room: Room) -> Array[Enemy]:
	var found: Array[Enemy] = []
	for node: Node in _world.entities.get_children():
		if node is Enemy and (node as Enemy).room == room:
			found.append(node as Enemy)
	return found


func test_an_empty_room_pauses_and_hides_its_enemies() -> void:
	_wire_world()
	var room := _room_with_wave()
	var enemies := _enemies_of(room)
	assert_gt(enemies.size(), 0, "the room has enemies to pause")
	room._set_enemies_active(false)
	for enemy: Enemy in enemies:
		assert_eq(enemy.process_mode, Node.PROCESS_MODE_DISABLED, "processing paused")
		assert_false(enemy.visible, "hidden")


func test_a_player_back_in_the_room_resumes_its_enemies() -> void:
	_wire_world()
	var room := _room_with_wave()
	var enemies := _enemies_of(room)
	room._set_enemies_active(false)
	room._set_enemies_active(true)
	for enemy: Enemy in enemies:
		assert_eq(enemy.process_mode, Node.PROCESS_MODE_INHERIT, "processing restored")
		assert_true(enemy.visible, "drawn again")


func test_the_scan_pauses_a_room_with_no_player_in_it() -> void:
	_wire_world()
	var room := _room_with_wave()
	room._scan_players()
	for enemy: Enemy in _enemies_of(room):
		assert_eq(enemy.process_mode, Node.PROCESS_MODE_DISABLED, "no player inside: paused by the scan")


## A wave released into an empty room (an enemy died after the last player left)
## is spawned through SpawnDirector.spawn_one, the same path _spawn_next_wave uses,
## and must start paused and hidden.
func test_a_wave_released_into_an_empty_room_starts_paused() -> void:
	_wire_world()
	var room := _room_with_wave()
	room._set_enemies_active(false)
	var late: Enemy = SpawnDirector.spawn_one(&"grub", Iso.to_screen(Vector2i(40, 60)), false, room)
	assert_not_null(late, "the late enemy spawned")
	assert_eq(late.process_mode, Node.PROCESS_MODE_DISABLED, "a late enemy starts paused")
	assert_false(late.visible, "and hidden")


func test_pausing_leaves_other_rooms_enemies_alone() -> void:
	_wire_world()
	var room := _room_with_wave()
	var other := _room_with_wave()
	var other_enemies := _enemies_of(other)
	room._set_enemies_active(false)
	for enemy: Enemy in other_enemies:
		assert_eq(enemy.process_mode, Node.PROCESS_MODE_INHERIT, "another room is untouched")
		assert_true(enemy.visible, "and still drawn")
