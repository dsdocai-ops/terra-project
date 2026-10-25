extends GutTest
## LampMap fog: only entered rooms and their path neighbours show.

var _map: LampMap


func before_each() -> void:
	_map = LampMap.new()
	add_child_autofree(_map)
	_map.rooms = [Rect2i(0, 0, 8, 8), Rect2i(10, 0, 8, 8), Rect2i(20, 0, 8, 8), Rect2i(30, 0, 8, 8)]


func test_without_fog_every_room_shows() -> void:
	for index: int in 4:
		assert_true(_map.is_revealed(index))
		assert_true(_map.is_explored(index))


func test_fog_shows_only_entered_rooms() -> void:
	_map.fog = true
	_map.visited = {0: true}
	assert_true(_map.is_explored(0))
	assert_false(_map.is_revealed(1), "a neighbour stays black until entered")
	assert_false(_map.is_revealed(2), "two steps away stays hidden")
	assert_false(_map.is_revealed(3))


func test_entering_a_room_lights_it() -> void:
	_map.fog = true
	_map.visited = {0: true, 1: true}
	assert_true(_map.is_explored(1))
	assert_false(_map.is_revealed(2))
	assert_false(_map.is_revealed(3))
