extends GutTest
## Integration: the movement abilities move the real Player scene (SPEC-abilities
## "Testing", W5-G3b). Flame Dash's shove moves the player on the host, Thunder
## Step teleports the player to its landing, and a wall at the cursor stops the
## teleport at the last free point before it (D-P9). The offline peer is the host,
## so the casts and the moves run here as they do on the host. Physics processing
## is off, so no frame runs; the tests drive the flinch shove by hand. Owned by
## abilities.

const WORLD_SCENE := "res://scenes/main/world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const SLOT_Q: int = 0
const FLOOR_SIZE: int = 20
## The player starts on this cell of the test floor, well inside the ring.
const START_CELL := Vector2i(10, 10)
## One physics tick of the flinch shove, in seconds.
const SHOVE_SECONDS: float = 0.1

var _world: World
var _player: Player
var _controller: AbilityController


func before_each() -> void:
	_world = (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	_world.paint_test_floor(FLOOR_SIZE)
	GameState.world = _world
	NetworkManager.start_solo()
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_world.entities.add_child(_player)
	_player.global_position = _world.walls_layer.map_to_local(START_CELL)
	_controller = _player.get_node("AbilityController") as AbilityController
	_controller.set_physics_process(false)


func after_each() -> void:
	NetworkManager.disconnect_all()
	GameState.world = null


## Puts the ability `id` in the Q slot and casts it at `aim` from the player.
func _cast(id: StringName, aim: Vector2) -> AbilityCast:
	var data := load("res://data/abilities/%s.tres" % id) as AbilityData
	assert_not_null(data, "%s loads" % id)
	_controller.assign(SLOT_Q, data)
	assert_true(_controller.request_cast(SLOT_Q, aim), "%s casts from its slot" % id)
	return _controller.last_cast


## The wall cell's global position, for a cursor placed on it.
func _wall_at(cell: Vector2i) -> Vector2:
	_world.walls_layer.set_cell(cell, Tiles.SOURCE, Tiles.WALL)
	return _world.walls_layer.to_global(_world.walls_layer.map_to_local(cell))


func _cell_of(point: Vector2) -> Vector2i:
	return _world.walls_layer.local_to_map(_world.walls_layer.to_local(point))


func test_flame_dash_shoves_the_real_player_along_the_aim_on_the_host() -> void:
	var start := _player.global_position
	_cast(&"flame_dash", start + Vector2(64, 0))
	_player._shove_from_flinch(SHOVE_SECONDS)
	assert_ne(_player.global_position, start, "the dash moves the player")
	assert_gt(_player.global_position.x, start.x, "the dash moves the player along the aim")


func test_thunder_step_teleports_the_real_player_to_the_cursor_inside_reach() -> void:
	var start := _player.global_position
	var aim := start + Vector2(64, 0)
	_cast(&"thunder_step", aim)
	assert_true(_player.global_position.is_equal_approx(aim), "the player lands on the cursor")


func test_thunder_step_stops_short_of_a_wall_at_the_cursor() -> void:
	var data := load("res://data/abilities/thunder_step.tres") as AbilityData
	var start := _player.global_position
	var wall_cell := START_CELL + Vector2i(3, 0)
	var aim := _wall_at(wall_cell)
	assert_gte(data.rank_data(1).extra, start.distance_to(aim), "the wall is inside the step's reach")
	_cast(&"thunder_step", aim)
	var landed := _player.global_position
	assert_ne(_cell_of(landed), wall_cell, "the player does not land inside the wall")
	assert_eq(_world.walls_layer.get_cell_source_id(_cell_of(landed)), -1, "the landing cell is free")
	assert_gt(landed.distance_to(start), 0.0, "the step still moves the player toward the wall")
	assert_lt(landed.distance_to(start), start.distance_to(aim), "the player stops short of the cursor")


func test_landing_before_wall_is_the_end_with_no_wall_or_no_layer() -> void:
	var end := Vector2(300, 0)
	assert_eq(ThunderStepCast.landing_before_wall(Vector2.ZERO, end, null), end, "no layer means no wall")
	var empty := TileMapLayer.new()
	empty.tile_set = TileSet.new()
	add_child_autofree(empty)
	assert_eq(ThunderStepCast.landing_before_wall(Vector2.ZERO, end, empty), end, "a layer with no wall lets the step through")
	assert_eq(ThunderStepCast.landing_before_wall(end, end, empty), end, "a step of no length lands where it starts")
