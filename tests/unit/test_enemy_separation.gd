extends GutTest
## The pure `EnemySeparation` spatial hash behind the enemy separation steering
## (SPEC-enemies-ai "Movement and pathfinding": groups do not stack, the push
## comes off a spatial hash, not a group-wide scan). The closing cases run the
## real enemy scene and prove its `_separation` pushes from the hash's
## neighbours alone. Owned by enemies-ai.

const ENEMY_SCENE := "res://scenes/enemies/enemy.tscn"
const CELL := 10.0
const RADIUS := 22.0
const PUSH := 40.0
const EPSILON := 0.0001

var _enemy: Enemy = null
var _other: Enemy = null


# --- the hash's neighbour lookup ---------------------------------------------------


func test_nearby_returns_exactly_the_nine_cells_around_the_query() -> void:
	var hash := EnemySeparation.new(CELL)
	# Cells (-1,-1), (0,0) x2 and (1,1) are inside the 3x3 of cell (0,0);
	# (2,0) and (-2,-1) are outside it.
	var inside: Array[Vector2] = [Vector2(5, 5), Vector2(-5, -5), Vector2(12, 3), Vector2(3, -2), Vector2(11, 11)]
	for position: Vector2 in inside:
		hash.insert(position)
	var outside: Array[Vector2] = [Vector2(25, 0), Vector2(-25, -5)]
	for position: Vector2 in outside:
		hash.insert(position)
	var found := hash.nearby(Vector2(1, 1))
	assert_eq(found.size(), inside.size(), "every body in the nine cells, none past them")
	for position: Vector2 in inside:
		assert_true(found.has(position), "%s is a neighbour" % position)
	for position: Vector2 in outside:
		assert_false(found.has(position), "%s is two cells away and never a neighbour" % position)


func test_the_same_cell_accumulates_bodies() -> void:
	var hash := EnemySeparation.new(CELL)
	hash.insert(Vector2(3, 3))
	hash.insert(Vector2(4, 4))
	assert_eq(hash.count(), 2, "both bodies ride in the hash")
	assert_eq(hash.nearby(Vector2(1, 1)).size(), 2, "and both come back from their cell")


func test_negative_coordinates_floor_into_the_cell_below_zero() -> void:
	var hash := EnemySeparation.new(CELL)
	# floorf(-0.5 / 10) is cell -1; an int() cast would fold it into cell 0,
	# which the query cell's 3x3 (x -3..-1) never reaches.
	hash.insert(Vector2(-0.5, -0.5))
	assert_true(hash.nearby(Vector2(-15, 0)).has(Vector2(-0.5, -0.5)), "the body sits in cell (-1,-1), beside the query")


func test_a_zero_cell_size_does_not_divide_by_zero() -> void:
	var hash := EnemySeparation.new(0.0)
	hash.insert(Vector2(1, 1))
	assert_eq(hash.nearby(Vector2(1, 1)).size(), 1, "the MIN_CELL guard keeps the hash usable")


# --- the push ----------------------------------------------------------------------


func test_the_push_points_away_at_the_old_falloff() -> void:
	# Halfway out of the radius: (1 - 11/22) = 0.5 of a unit push, times
	# SEPARATION_PUSH (40) over the 60 FPS the constant was tuned at.
	var push := EnemySeparation.push_for(Vector2.ZERO, [Vector2(11, 0)] as Array[Vector2], RADIUS, PUSH)
	assert_almost_eq(push.x, -1.0 / 3.0, EPSILON, "away from the other body")
	assert_almost_eq(push.y, 0.0, EPSILON)


func test_the_push_is_gone_at_and_past_the_radius() -> void:
	var at_edge := EnemySeparation.push_for(Vector2.ZERO, [Vector2(RADIUS, 0)] as Array[Vector2], RADIUS, PUSH)
	var past := EnemySeparation.push_for(Vector2.ZERO, [Vector2(RADIUS + 1.0, 0)] as Array[Vector2], RADIUS, PUSH)
	assert_eq(at_edge.length(), 0.0, "exactly at the radius the falloff reaches nothing")
	assert_eq(past.length(), 0.0, "past it, nothing either")


func test_coincident_bodies_push_nothing() -> void:
	# Two bodies on one spot (and a body reading its own hash position) must
	# not divide by a zero distance.
	var push := EnemySeparation.push_for(Vector2(5, 5), [Vector2(5, 5), Vector2(5, 5)] as Array[Vector2], RADIUS, PUSH)
	assert_eq(push.length(), 0.0, "no NaN, no push")
	var just_inside := EnemySeparation.push_for(Vector2.ZERO, [Vector2(0.01, 0)] as Array[Vector2], RADIUS, PUSH)
	assert_eq(just_inside.length(), 0.0, "the coincident epsilon holds at its edge too")


func test_a_tighter_overlap_pushes_harder() -> void:
	var tight := EnemySeparation.push_for(Vector2.ZERO, [Vector2(5.5, 0)] as Array[Vector2], RADIUS, PUSH)
	var loose := EnemySeparation.push_for(Vector2.ZERO, [Vector2(16.5, 0)] as Array[Vector2], RADIUS, PUSH)
	assert_almost_eq(tight.length(), 0.5, EPSILON, "a quarter out: 0.75 * 40/60")
	assert_almost_eq(loose.length(), 1.0 / 6.0, EPSILON, "three quarters out: 0.25 * 40/60")
	assert_gt(tight.length(), loose.length(), "the closer body pushes harder")


func test_the_push_scales_with_the_push_scale() -> void:
	var half := EnemySeparation.push_for(Vector2.ZERO, [Vector2(11, 0)] as Array[Vector2], RADIUS, PUSH)
	var full := EnemySeparation.push_for(Vector2.ZERO, [Vector2(11, 0)] as Array[Vector2], RADIUS, PUSH * 2.0)
	assert_almost_eq(full.length(), half.length() * 2.0, EPSILON, "double the scale, double the push")


# --- the push reads only the hash's neighbours ---------------------------------------


func test_a_neighbour_beyond_the_radius_in_an_adjacent_cell_pushes_nothing() -> void:
	# The cell edge is the separation radius, so a body just over one cell
	# away still lands in the 3x3 (its cell adjoins the query's) — the push's
	# distance filter is what drops it.
	var hash := EnemySeparation.new(RADIUS)
	var beyond := Vector2(40, 0)
	hash.insert(beyond)
	var neighbours := hash.nearby(Vector2.ZERO)
	assert_true(neighbours.has(beyond), "the query hands it over as a cell neighbour")
	assert_eq(EnemySeparation.push_for(Vector2.ZERO, neighbours, RADIUS, PUSH).length(), 0.0, "but past the radius it pushes nothing")


func test_the_push_through_the_hash_is_the_push_through_its_neighbours_alone() -> void:
	# Three bodies in the hash — one overlapping, one in an adjacent cell past
	# the radius, one far away — and the push must equal the push computed
	# from the overlapping body alone: the far two never reach it.
	var hash := EnemySeparation.new(RADIUS)
	var near_body := Vector2(11, 0)
	var cell_neighbour := Vector2(40, 0)
	var far_body := Vector2(500, 500)
	hash.insert(near_body)
	hash.insert(cell_neighbour)
	hash.insert(far_body)
	var through_hash := EnemySeparation.push_for(Vector2.ZERO, hash.nearby(Vector2.ZERO), RADIUS, PUSH)
	var through_near_only := EnemySeparation.push_for(Vector2.ZERO, [near_body] as Array[Vector2], RADIUS, PUSH)
	assert_almost_eq(through_hash.x, through_near_only.x, EPSILON)
	assert_almost_eq(through_hash.y, through_near_only.y, EPSILON)
	assert_gt(through_hash.length(), 0.0, "the overlap still pushes")
	var far_reached := false
	for position: Vector2 in hash.nearby(Vector2(510, 510)):
		if position == far_body:
			far_reached = true
	assert_true(far_reached, "the far body is in the hash for the cells around itself")


# --- the enemy scene separates through the hash ----------------------------------------


func before_each() -> void:
	Enemy.reset_separation_cache()
	GameState.world = null


func after_each() -> void:
	GameState.world = null
	Enemy.reset_separation_cache()


func _spawn(kind: StringName, position: Vector2) -> Enemy:
	var enemy: Enemy = (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	assert_true(enemy.setup(kind), "%s data loads" % kind)
	enemy.global_position = position
	add_child_autofree(enemy)
	return enemy


func test_the_scene_push_matches_the_pure_hash_push() -> void:
	_enemy = _spawn(&"hollow_miner", Vector2.ZERO)
	_other = _spawn(&"hollow_miner", Vector2(11, 0))
	var push: Vector2 = _enemy._separation()
	var hash := EnemySeparation.new(Enemy.SEPARATION_RADIUS)
	hash.insert(_other.global_position)
	var pure := EnemySeparation.push_for(_enemy.global_position, hash.nearby(_enemy.global_position), Enemy.SEPARATION_RADIUS, Enemy.SEPARATION_PUSH)
	assert_almost_eq(push.x, pure.x, EPSILON, "the scene pushes exactly what the hash's neighbours push")
	assert_almost_eq(push.y, pure.y, EPSILON)
	assert_gt(push.length(), 0.0, "the overlap pushes")


func test_the_scene_pushes_nothing_when_the_other_is_far() -> void:
	_enemy = _spawn(&"hollow_miner", Vector2.ZERO)
	_other = _spawn(&"hollow_miner", Vector2(500, 500))
	assert_eq(_enemy._separation().length(), 0.0, "out of the nine cells, out of the push")


func test_the_shared_hash_rebuilds_when_the_group_grows() -> void:
	_enemy = _spawn(&"hollow_miner", Vector2.ZERO)
	_other = _spawn(&"hollow_miner", Vector2(500, 500))
	assert_eq(_enemy._separation().length(), 0.0, "alone on the east side: no push")
	# A third body crowds in from the west inside the same physics frame — the
	# group size changed, so the frame's cached hash is rebuilt around it.
	_spawn(&"hollow_miner", Vector2(-11, 0))
	var push := _enemy._separation()
	assert_gt(push.x, 0.0, "the newcomer's push arrives without a frame passing")


func test_the_push_reads_the_frame_hash_not_the_live_group() -> void:
	# The frame's hash is the push's only input: move the other body away
	# inside the same physics frame (the group size does not change) and this
	# frame's push still reads the neighbours the hash was built from. A
	# group-wide scan would see the move at once and push nothing.
	_enemy = _spawn(&"hollow_miner", Vector2.ZERO)
	_other = _spawn(&"hollow_miner", Vector2(11, 0))
	assert_gt(_enemy._separation().length(), 0.0, "the overlap pushes")
	_other.global_position = Vector2(500, 500)
	assert_gt(_enemy._separation().length(), 0.0, "still the frame hash's answer — no group scan ran")


func test_the_move_bends_away_from_an_overlapping_body() -> void:
	_enemy = _spawn(&"hollow_miner", Vector2.ZERO)
	_other = _spawn(&"hollow_miner", Vector2(10, 5))
	# East is free, but the other body sits between here and there and north of
	# the line: the separation push must tilt the step below the straight line.
	_enemy.move_toward_point(Vector2(100, 0), 60.0, 1.0 / 60.0)
	assert_lt(_enemy.velocity.y, 0.0, "the step bends away from the other body")


func test_the_move_runs_straight_with_no_one_to_separate_from() -> void:
	_enemy = _spawn(&"hollow_miner", Vector2.ZERO)
	_enemy.move_toward_point(Vector2(100, 0), 60.0, 1.0 / 60.0)
	assert_almost_eq(_enemy.velocity.y, 0.0, EPSILON, "nothing nearby, nothing to bend around")
