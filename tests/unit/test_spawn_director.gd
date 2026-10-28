extends GutTest
## Tests for `SpawnDirector`'s budget by floor (SPEC-enemies-ai "Spawn
## director": "picks a budget `Scaling.enemies_per_room(floor)`"; the Testing
## section names this file). Owned by enemies-ai. G12a1 covers the budget only —
## the single-wave rule, the no-spawn-near-players check and the registry
## look-up are the later goals, and their tests extend this file.
##
## The budget table is `Scaling`'s constants (stats-status owns the tuning; the
## week-12 balance pass may move them), so no balance number is invented here:
## every expected value is recomposed from `Scaling.ENEMIES_PER_ROOM_*` and the
## clamp range, the way `Scaling.enemies_per_room` itself computes it, then
## floored at `SpawnDirector.MIN_ENEMIES`. What the test owns is the
## composition — the v1 floor at `MIN_ENEMIES` and the two seams: `room_budget`
## reads the spec's curve, and `fill_room` reads `room_budget` instead of
## re-deriving a second copy of the composition inline.

const SPAWN_DIRECTOR_PATH: String = "res://scripts/enemies/spawn_director.gd"
const SCALING_PATH: String = "res://scripts/scaling.gd"

## The floor range the budget is walked over, matching `Scaling`'s clamp range.
const FIRST_FLOOR: int = 1
const LAST_FLOOR: int = 30


## The budget recomposed from the constants, independently of
## `Scaling.enemies_per_room`: the curve's own arithmetic, then the v1 floor.
func _expected_budget(floor_index: int) -> int:
	var depth: int = clampi(floor_index, FIRST_FLOOR, LAST_FLOOR) - FIRST_FLOOR
	var curve: int = mini(Scaling.ENEMIES_PER_ROOM_BASE \
		+ floori(Scaling.ENEMIES_PER_ROOM_PER_FLOOR * float(depth)), \
		Scaling.ENEMIES_PER_ROOM_MAX)
	return maxi(curve, SpawnDirector.MIN_ENEMIES)


func test_the_budget_is_the_spec_curve_floored_at_min_enemies() -> void:
	for floor_index: int in range(FIRST_FLOOR, LAST_FLOOR + 1):
		assert_eq(SpawnDirector.room_budget(floor_index), _expected_budget(floor_index), \
			"floor %d fields exactly the recomposed budget" % floor_index)
		assert_eq(SpawnDirector.room_budget(floor_index), \
			maxi(Scaling.enemies_per_room(floor_index), SpawnDirector.MIN_ENEMIES), \
			"floor %d agrees with the curve read directly" % floor_index)


func test_the_floor_one_budget_is_the_curve_base_and_never_below_the_floor() -> void:
	assert_eq(SpawnDirector.room_budget(FIRST_FLOOR), \
		maxi(Scaling.ENEMIES_PER_ROOM_BASE, SpawnDirector.MIN_ENEMIES), \
		"floor 1 fields the curve's base count")
	assert_gte(SpawnDirector.room_budget(FIRST_FLOOR), SpawnDirector.MIN_ENEMIES, \
		"and the shallowest room never fields fewer than the v1 floor")


func test_the_budget_rises_with_depth_and_never_falls() -> void:
	var previous: int = 0
	for floor_index: int in range(FIRST_FLOOR, LAST_FLOOR + 1):
		var budget := SpawnDirector.room_budget(floor_index)
		assert_gte(budget, previous, "floor %d does not field fewer than the floor before" % floor_index)
		assert_lte(budget, Scaling.ENEMIES_PER_ROOM_MAX, \
			"floor %d stays under the curve's cap" % floor_index)
		previous = budget
	assert_gt(previous, SpawnDirector.room_budget(FIRST_FLOOR), \
		"the deepest floor really does field more than the first")


func test_the_budget_is_clamped_at_both_ends_of_the_floor_range() -> void:
	assert_eq(SpawnDirector.room_budget(0), SpawnDirector.room_budget(FIRST_FLOOR), \
		"clamped below the first floor")
	assert_eq(SpawnDirector.room_budget(-3), SpawnDirector.room_budget(FIRST_FLOOR), \
		"and for a negative floor")
	assert_eq(SpawnDirector.room_budget(LAST_FLOOR + 1), SpawnDirector.room_budget(LAST_FLOOR), \
		"clamped above the last")
	assert_eq(SpawnDirector.room_budget(9999), SpawnDirector.room_budget(LAST_FLOOR), \
		"however deep the index goes")


func test_the_budget_reads_the_spec_curve_not_a_second_table() -> void:
	var source := FileAccess.get_file_as_string(SPAWN_DIRECTOR_PATH)
	assert_gt(source.length(), 0, "scripts/enemies/spawn_director.gd is readable")
	assert_true(source.contains("Scaling.enemies_per_room(floor_index)"), \
		"room_budget reads the spec's curve, the one place the budget table lives")
	assert_true(source.contains("maxi(Scaling.enemies_per_room(floor_index), MIN_ENEMIES)"), \
		"and the v1 floor at MIN_ENEMIES is part of the composition")


func test_fill_room_reads_the_budget_function_not_an_inline_second_copy() -> void:
	var source := FileAccess.get_file_as_string(SPAWN_DIRECTOR_PATH)
	assert_true(source.contains("var count: int = room_budget(floor_index)"), \
		"fill_room's wave count is room_budget's")
	assert_eq(source.count( \
		"return maxi(Scaling.enemies_per_room(floor_index), MIN_ENEMIES)"), 1, \
		"the composition appears once, in room_budget — no second copy to drift")
