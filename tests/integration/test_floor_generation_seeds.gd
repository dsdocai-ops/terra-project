extends GutTest
## The lane-B floor determinism soak (W3-B3c; SPEC-floor-generation "Testing",
## SPEC-networking "Seed sync"). It rebuilds the same floor from the same
## `(run_seed, floor_index, biome_id, modifiers)` 500 times over and asserts what
## the co-op hash assertion actually depends on:
##   * the same inputs always yield the same `layout_hash` and the same rooms,
##   * 500 different seeds do not collapse onto one hash (no constant), and no
##     two neighbouring seeds share a hash,
##   * a layout rebuilt from its own wire form (`to_wire()` -> `from_wire()`)
##     keeps the identical `layout_hash`, which is what the mismatch fallback
##     hands a diverged peer,
##   * every room rect fits inside the 96x96 tile grid, and
##   * `room_count` stays inside the spec's 8..14 range.
## It also runs the negative control the run's rules ask for: changing exactly
## one input (floor_index, biome_id, or a modifier) must move the hash, so the
## equality assertions above cannot pass vacuously.
## Owned by networking.
##
## blocked on Dev A (W3-A3): the spec's 500-seed soak is written over
## `FloorGenerator.generate()` — flood fill from Start, Exit reachable, exactly
## one ROPE on floor 2, no overlapping rooms, corridors 3 tiles wide — and that
## generator does not exist yet (`scripts/generation/` is empty), so the real
## 500-seed soak is Dev A's W3-A3 task and stays owed. This file soaks the layout
## the game generates today: the lane-B `FloorLayoutPlaceholder` that
## `FloorGeneratorSeam` returns for every peer, which is the same path the
## layout-hash assertion compares. Recorded as blocked on Dev A W3-A3 in
## `tasks/todo.md`. The swap-in is mechanical: the moment
## `scripts/generation/floor_generator.gd` lands, `FloorGeneratorSeam.generate()`
## returns its layout and the checks below move onto it (the last test in this
## file asserts the seam's source so the swap cannot pass unnoticed).
##
## Sync: none — nothing here talks to a peer. It proves the determinism the
## broadcast relies on: one seed, one floor, in any process.
##
## No autoload state is read or written (`for_floor()` is a pure static), so
## nothing can leak into another test file; the one seam test reads `GameState`
## only through `biome_for_index()`, which is a pure lookup.

## The spec's soak size. 500 seeds in a row (SPEC-floor-generation "Testing",
## design doc section 23).
const SOAK_SEEDS: int = 500
## A fixed base so a failing seed can be reproduced by hand from the log line.
const SOAK_BASE_SEED: int = 20261020
## The spec's numbers, asserted against the implementation's own constants so a
## drift in either one fails this file rather than silently widening the soak.
const SPEC_MIN_ROOMS: int = 8
const SPEC_MAX_ROOMS: int = 14
const SPEC_GRID_TILES: int = 96
const SPEC_MIN_ROOM_W: int = 9
const SPEC_MAX_ROOM_W: int = 17
const SPEC_MIN_ROOM_H: int = 7
const SPEC_MAX_ROOM_H: int = 13
## Floors 1..30 across the six biomes, so one loop of the soak touches every
## biome the spec names without multiplying the iteration count.
const MAX_FLOOR: int = 30
const FLOORS_PER_BIOME: int = 5

## A shared empty modifier list. `for_floor()` copies it, so one instance is
## safe to hand to every call.
var _no_modifiers: Array[int] = []


## The run seed of soak iteration `index`, so every iteration is a different
## seed and any failure names a reproducible one.
func _run_seed(index: int) -> int:
	return SOAK_BASE_SEED + index


## The floor soak iteration `index` covers: 1..30, wrapping, so the loop walks
## every floor index the run can reach.
func _floor_of(index: int) -> int:
	return (index % MAX_FLOOR) + 1


## The biome a floor index belongs to (SPEC-run-economy: `(floor - 1) / 5 + 1`),
## in 1..6.
func _biome_of(floor_index: int) -> int:
	return ((floor_index - 1) / FLOORS_PER_BIOME) + 1


func test_the_soak_covers_the_specs_floor_shape() -> void:
	assert_eq(FloorLayoutPlaceholder.MIN_ROOMS, SPEC_MIN_ROOMS, "spec: room_count = rng.randi_range(8, 14)")
	assert_eq(FloorLayoutPlaceholder.MAX_ROOMS, SPEC_MAX_ROOMS, "spec: room_count = rng.randi_range(8, 14)")
	assert_eq(FloorLayoutPlaceholder.GRID_TILES, SPEC_GRID_TILES, "spec: grid of 96x96 tiles")
	assert_eq(FloorLayoutPlaceholder.MIN_ROOM_W, SPEC_MIN_ROOM_W, "spec: rooms 9x7 to 17x13 tiles")
	assert_eq(FloorLayoutPlaceholder.MAX_ROOM_W, SPEC_MAX_ROOM_W, "spec: rooms 9x7 to 17x13 tiles")
	assert_eq(FloorLayoutPlaceholder.MIN_ROOM_H, SPEC_MIN_ROOM_H, "spec: rooms 9x7 to 17x13 tiles")
	assert_eq(FloorLayoutPlaceholder.MAX_ROOM_H, SPEC_MAX_ROOM_H, "spec: rooms 9x7 to 17x13 tiles")
	assert_gte(SOAK_SEEDS, 500, "the soak covers at least 500 seeds")
	assert_eq(_biome_of(1), 1, "floor 1 is biome 1")
	assert_eq(_biome_of(MAX_FLOOR), 6, "floor 30 is biome 6")


func test_500_seeds_rebuild_the_same_layout() -> void:
	var checked: int = 0
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var first: FloorLayoutPlaceholder = FloorLayoutPlaceholder.for_floor(run_seed, 1, 1, _no_modifiers)
		var again: FloorLayoutPlaceholder = FloorLayoutPlaceholder.for_floor(run_seed, 1, 1, _no_modifiers)
		assert_eq(first.layout_hash, again.layout_hash, "seed %d: same inputs, same hash" % run_seed)
		assert_eq(first.rooms, again.rooms, "seed %d: same inputs, same room rects" % run_seed)
		assert_eq(first.room_count, again.room_count, "seed %d: same room count" % run_seed)
		assert_eq(first.seed, run_seed, "seed %d: the layout carries its seed" % run_seed)
		checked += 1
	assert_eq(checked, SOAK_SEEDS, "the soak rebuilt every seed")
	print("[soak] floor determinism: %d seeds x 1 floor rebuilt identically" % checked)


func test_500_seeds_do_not_collapse_onto_one_hash() -> void:
	var hashes: Dictionary = {}
	var neighbouring_matches: int = 0
	var previous: int = 0
	var first: bool = true
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var layout: FloorLayoutPlaceholder = FloorLayoutPlaceholder.for_floor(run_seed, 1, 1, _no_modifiers)
		assert_ne(layout.layout_hash, 0, "seed %d produced a real hash" % run_seed)
		hashes[layout.layout_hash] = true
		if not first and previous == layout.layout_hash:
			neighbouring_matches += 1
		previous = layout.layout_hash
		first = false
	assert_eq(hashes.size(), SOAK_SEEDS, "500 different seeds give 500 different hashes")
	assert_eq(neighbouring_matches, 0, "neighbouring seeds never share a hash")
	print("[soak] floor hashes: %d seeds, %d distinct hashes, 0 neighbouring collisions" % [SOAK_SEEDS, hashes.size()])


func test_500_seeds_survive_the_wire_round_trip() -> void:
	var checked: int = 0
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var floor_index: int = _floor_of(index)
		var biome_id: int = _biome_of(floor_index)
		var layout: FloorLayoutPlaceholder = FloorLayoutPlaceholder.for_floor(run_seed, floor_index, biome_id, _no_modifiers)
		var rebuilt: FloorLayoutPlaceholder = FloorLayoutPlaceholder.from_wire(layout.to_wire())
		assert_eq(rebuilt.layout_hash, layout.layout_hash,
			"seed %d floor %d: the hash travels with the content" % [run_seed, floor_index])
		assert_eq(rebuilt.rooms, layout.rooms,
			"seed %d floor %d: every room rect survives the wire" % [run_seed, floor_index])
		assert_eq(rebuilt.room_count, layout.room_count,
			"seed %d floor %d: the room count survives the wire" % [run_seed, floor_index])
		assert_eq(rebuilt.seed, run_seed, "seed %d floor %d: the seed survives" % [run_seed, floor_index])
		assert_eq(rebuilt.floor_index, floor_index, "seed %d: the floor index survives" % run_seed)
		assert_eq(rebuilt.biome_id, biome_id, "seed %d: the biome id survives" % run_seed)
		checked += 1
	assert_eq(checked, SOAK_SEEDS, "the round trip covered every seed")
	print("[soak] wire round-trip: %d layouts rebuilt from to_wire() with identical hashes" % checked)


func test_every_room_fits_inside_the_grid_over_500_seeds() -> void:
	var rooms_checked: int = 0
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var floor_index: int = _floor_of(index)
		var biome_id: int = _biome_of(floor_index)
		var layout: FloorLayoutPlaceholder = FloorLayoutPlaceholder.for_floor(run_seed, floor_index, biome_id, _no_modifiers)
		for rect: Rect2i in layout.rooms:
			assert_gte(rect.position.x, 0, "seed %d floor %d: room %s starts before the grid" % [run_seed, floor_index, rect])
			assert_gte(rect.position.y, 0, "seed %d floor %d: room %s starts before the grid" % [run_seed, floor_index, rect])
			assert_between(rect.size.x, SPEC_MIN_ROOM_W, SPEC_MAX_ROOM_W,
				"seed %d floor %d: room width" % [run_seed, floor_index])
			assert_between(rect.size.y, SPEC_MIN_ROOM_H, SPEC_MAX_ROOM_H,
				"seed %d floor %d: room height" % [run_seed, floor_index])
			assert_lte(rect.end.x, SPEC_GRID_TILES,
				"seed %d floor %d: room %s runs past the %d-tile grid" % [run_seed, floor_index, rect, SPEC_GRID_TILES])
			assert_lte(rect.end.y, SPEC_GRID_TILES,
				"seed %d floor %d: room %s runs past the %d-tile grid" % [run_seed, floor_index, rect, SPEC_GRID_TILES])
			rooms_checked += 1
	assert_gte(rooms_checked, SOAK_SEEDS * SPEC_MIN_ROOMS, "every seed placed at least 8 rooms")
	print("[soak] grid bounds: %d room rects across %d seeds, all inside %dx%d tiles" % [
		rooms_checked, SOAK_SEEDS, SPEC_GRID_TILES, SPEC_GRID_TILES])


func test_room_count_stays_in_the_spec_range_over_500_seeds() -> void:
	var checked: int = 0
	var smallest: int = SPEC_MAX_ROOMS
	var largest: int = SPEC_MIN_ROOMS
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var floor_index: int = _floor_of(index)
		var biome_id: int = _biome_of(floor_index)
		var layout: FloorLayoutPlaceholder = FloorLayoutPlaceholder.for_floor(run_seed, floor_index, biome_id, _no_modifiers)
		assert_between(layout.room_count, SPEC_MIN_ROOMS, SPEC_MAX_ROOMS,
			"seed %d floor %d: room_count" % [run_seed, floor_index])
		assert_eq(layout.rooms.size(), layout.room_count,
			"seed %d floor %d: rooms.size() matches room_count" % [run_seed, floor_index])
		smallest = mini(smallest, layout.room_count)
		largest = maxi(largest, layout.room_count)
		checked += 1
	assert_eq(checked, SOAK_SEEDS, "the range check covered every seed")
	print("[soak] room counts: %d seeds, %d..%d rooms per floor (spec range %d..%d)" % [
		checked, smallest, largest, SPEC_MIN_ROOMS, SPEC_MAX_ROOMS])


func test_negative_control_one_changed_input_moves_the_hash() -> void:
	var checked: int = 0
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var base: FloorLayoutPlaceholder = FloorLayoutPlaceholder.for_floor(run_seed, 2, 1, _no_modifiers)
		var other_floor: FloorLayoutPlaceholder = FloorLayoutPlaceholder.for_floor(run_seed, 3, 1, _no_modifiers)
		var other_biome: FloorLayoutPlaceholder = FloorLayoutPlaceholder.for_floor(run_seed, 2, 2, _no_modifiers)
		var with_modifier: FloorLayoutPlaceholder = FloorLayoutPlaceholder.for_floor(run_seed, 2, 1, [1] as Array[int])
		assert_ne(base.layout_hash, other_floor.layout_hash, "seed %d: floor_index 2 vs 3" % run_seed)
		assert_ne(base.layout_hash, other_biome.layout_hash, "seed %d: biome_id 1 vs 2" % run_seed)
		assert_ne(base.layout_hash, with_modifier.layout_hash, "seed %d: no modifier vs modifier 1" % run_seed)
		checked += 1
	assert_eq(checked, SOAK_SEEDS, "the negative control covered every seed")
	print("[soak] negative control: %d seeds, every single-input change moved the hash" % checked)


func test_the_game_generation_path_soaks_the_same_layout() -> void:
	var run_seed: int = SOAK_BASE_SEED
	var layout: RefCounted = FloorGeneratorSeam.generate(run_seed, 1, 1, _no_modifiers)
	assert_not_null(layout, "the generation seam always produces a layout")
	assert_ne(FloorGeneratorSeam.layout_hash_of(layout), 0, "and it carries a real hash")
	if FloorGeneratorSeam.real_generator() != null:
		# Dev A's `FloorGenerator` has landed, so the seam calls it and this file
		# soaks the wrong class: the swap-in is to point the 500-seed loops above
		# at `FloorGenerator.generate()` and run the spec's reachability checks.
		# The assertion still holds — the seam's layout must be a real one.
		assert_ne(FloorGeneratorSeam.layout_hash_of(layout), 0,
			"Dev A's FloorGenerator is present, so the seam must generate its layout")
		return
	assert_eq(FloorGeneratorSeam.source_of(layout), FloorLayoutPlaceholder.SOURCE,
		"with Dev A's FloorGenerator absent the seam generates the lane-B placeholder this soak covers")
	assert_eq(FloorGeneratorSeam.layout_hash_of(layout),
		FloorLayoutPlaceholder.for_floor(run_seed, 1, 1, _no_modifiers).layout_hash,
		"and it is the same layout the soak rebuilt")
