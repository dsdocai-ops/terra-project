extends GutTest
## Tests for `Scaling` (SPEC-stats-status, "Scaling constants"; design doc 9.5,
## "Depth scaling: enemy HP and damage go up about 12% per biome, plus more
## enemies per room and more elites on deeper floors"). Owned by stats-status.
##
## The spec's sentence is the acceptance text: "`Scaling` static class:
## `enemy_hp_mult(biome_index) = 1.12 ** (biome_index - 1)`, same for damage;
## `enemies_per_room(floor)`, `elite_chance(floor)`; elite base `+100% HP`;
## co-op HP multiplier comes from `NetworkManager`." The first two curves are the
## spec's own formula and are asserted against it; the two floor curves have no
## formula in the design doc, so what is pinned here is the shape the design doc
## asks for (deeper floors have more enemies and more elites) plus the clamps at
## both ends of the floor range — never a balance number, which the week-12 pass
## owns.
##
## The co-op half is proven to be **read** rather than re-derived: the multiplier
## comes from a second peer id, so a copy of the constant in this class would
## fail.

const SPEC_PATH: String = "res://specs/SPEC-stats-status.md"
const DESIGN_DOC_PATH: String = "res://SINKHOLE_SPEC.md"
const SCALING_PATH: String = "res://scripts/scaling.gd"

## The floor range the curves are walked over: floors 1 to 30, the design doc's
## depth.
const FIRST_FLOOR: int = 1
const LAST_FLOOR: int = 30
## The biome the spec's formula starts at, and the deepest one the design doc
## names.
const FIRST_BIOME: int = 1
const LAST_BIOME: int = 6
## A base HP every derived number is taken from, so the arithmetic is readable.
const BASE_HP: float = 100.0
## The peer id a second player joins under, so `player_count()` reads 2.
const SECOND_PEER: int = 2


func before_each() -> void:
	# The solo session is the baseline the co-op case departs from, and it makes
	# the starting player count explicit rather than an accident of the previous
	# file's state (autoloads are shared across a GUT run).
	NetworkManager.start_solo()


func after_each() -> void:
	# `disconnect_all()` clears `peer_ids`, so the second peer the co-op case
	# adds cannot leak into another file.
	NetworkManager.disconnect_all()


# --- the spec's own formula -------------------------------------------------

func test_the_hp_curve_is_the_specs_formula() -> void:
	var spec := FileAccess.get_file_as_string(SPEC_PATH)
	assert_gt(spec.length(), 0, "SPEC-stats-status is readable")
	assert_true(spec.contains("1.12 ** (biome_index - 1)"), "the spec fixes the curve this way")
	var design := FileAccess.get_file_as_string(DESIGN_DOC_PATH)
	assert_gt(design.length(), 0, "the design doc is readable")
	assert_true(design.contains("about 12% per biome"), "and the design doc gives the 12%")

	assert_eq(Scaling.enemy_hp_mult(FIRST_BIOME), 1.0, "biome 1 is the baseline")
	assert_almost_eq(Scaling.enemy_hp_mult(2), 1.12, 1.0e-9, "biome 2 is one step up")
	assert_eq(Scaling.enemy_hp_mult(LAST_BIOME), 1.12 ** 5, "biome 6 is five steps up")


func test_the_damage_curve_is_the_same_as_the_hp_curve() -> void:
	var spec := FileAccess.get_file_as_string(SPEC_PATH)
	assert_true(spec.contains("same for damage"), "the spec's sentence applies the same curve to damage")
	for biome: int in range(FIRST_BIOME, LAST_BIOME + 1):
		assert_almost_eq(Scaling.enemy_damage_mult(biome), Scaling.enemy_hp_mult(biome), 1.0e-9, \
			"biome %d scales damage exactly as it scales HP" % biome)


func test_the_hp_curve_never_goes_down_and_grows_by_the_last_biome() -> void:
	var previous: float = 0.0
	for biome: int in range(FIRST_BIOME, LAST_BIOME + 1):
		var value := Scaling.enemy_hp_mult(biome)
		assert_gte(value, previous, "the curve does not fall at biome %d" % biome)
		previous = value
	assert_gt(previous, 1.0, "and by the last biome it has grown")


func test_the_hp_curve_is_clamped_at_the_first_biome() -> void:
	assert_eq(Scaling.enemy_hp_mult(0), Scaling.enemy_hp_mult(FIRST_BIOME), "biome 0 reads as biome 1")
	assert_eq(Scaling.enemy_hp_mult(-4), Scaling.enemy_hp_mult(FIRST_BIOME), "and so does a negative one")


# --- the two curves the design doc names but does not formula ---------------

func test_enemies_per_room_rises_with_depth_and_is_clamped_at_both_ends() -> void:
	var previous: int = 0
	for floor: int in range(FIRST_FLOOR, LAST_FLOOR + 1):
		var count := Scaling.enemies_per_room(floor)
		assert_gte(count, previous, "floor %d does not field fewer enemies than the floor before" % floor)
		assert_gte(count, 1, "and always at least one")
		previous = count
	assert_gt(previous, Scaling.enemies_per_room(FIRST_FLOOR), "the deepest floor really does field more")

	assert_eq(Scaling.enemies_per_room(0), Scaling.enemies_per_room(FIRST_FLOOR), "clamped below the first floor")
	assert_eq(Scaling.enemies_per_room(-3), Scaling.enemies_per_room(FIRST_FLOOR), "and for a negative floor")
	assert_eq(Scaling.enemies_per_room(LAST_FLOOR + 1), Scaling.enemies_per_room(LAST_FLOOR), "clamped above the last")
	assert_eq(Scaling.enemies_per_room(9999), Scaling.enemies_per_room(LAST_FLOOR), "however deep the index goes")


func test_elite_chance_rises_with_depth_and_is_clamped_at_both_ends() -> void:
	var previous: float = 0.0
	for floor: int in range(FIRST_FLOOR, LAST_FLOOR + 1):
		var chance := Scaling.elite_chance(floor)
		assert_gte(chance, previous, "floor %d does not roll fewer elites than the floor before" % floor)
		assert_gt(chance, 0.0, "and every floor can roll one")
		assert_lte(chance, 1.0, "and a floor never rolls more than one per slot")
		previous = chance
	assert_gt(previous, Scaling.elite_chance(FIRST_FLOOR), "the deepest floor really does roll more")

	assert_eq(Scaling.elite_chance(0), Scaling.elite_chance(FIRST_FLOOR), "clamped below the first floor")
	assert_eq(Scaling.elite_chance(-3), Scaling.elite_chance(FIRST_FLOOR), "and for a negative floor")
	assert_eq(Scaling.elite_chance(LAST_FLOOR + 1), Scaling.elite_chance(LAST_FLOOR), "clamped above the last")
	assert_eq(Scaling.elite_chance(9999), Scaling.elite_chance(LAST_FLOOR), "however deep the index goes")


# --- the elite's HP rule ----------------------------------------------------

func test_the_elite_hp_rule_is_plus_one_hundred_percent() -> void:
	assert_eq(Scaling.ELITE_HP_MULTIPLIER, 2.0, "the design doc's '+100% HP' is a doubling")
	var design := FileAccess.get_file_as_string(DESIGN_DOC_PATH)
	assert_true(design.contains("+100% HP"), "and the design doc says exactly that")
	assert_eq(Scaling.elite_hp(BASE_HP), 200.0, "an elite carries twice the base HP")
	assert_eq(Scaling.elite_hp(0.0), 0.0, "and a base of nothing stays nothing")


# --- the co-op half, read rather than re-derived ----------------------------

func test_the_coop_multiplier_is_read_from_the_network_manager() -> void:
	var source := FileAccess.get_file_as_string(SCALING_PATH)
	assert_gt(source.length(), 0, "scripts/scaling.gd is readable")
	assert_true(source.contains("NetworkManager.enemy_hp_multiplier()"), \
		"the co-op multiplier is read from NetworkManager, not re-derived here")

	assert_eq(NetworkManager.enemy_hp_multiplier(), 1.0, "a solo run is the baseline")
	assert_almost_eq(Scaling.enemy_max_hp(BASE_HP, FIRST_BIOME), BASE_HP, 1.0e-9, "so HP is the base")

	NetworkManager.peer_ids.append(SECOND_PEER)
	assert_eq(NetworkManager.enemy_hp_multiplier(), 1.5, "a second player raises the multiplier")
	assert_almost_eq(Scaling.enemy_max_hp(BASE_HP, FIRST_BIOME), BASE_HP * 1.5, 1.0e-9, \
		"and Scaling reads it rather than holding its own copy")
	assert_almost_eq(Scaling.enemy_max_hp(BASE_HP, LAST_BIOME), BASE_HP * 1.5 * 1.12 ** 5, 1.0e-6, \
		"composed with the biome curve")

	NetworkManager.peer_ids.erase(SECOND_PEER)
	assert_almost_eq(Scaling.enemy_max_hp(BASE_HP, FIRST_BIOME), BASE_HP, 1.0e-9, "and back for a solo run")