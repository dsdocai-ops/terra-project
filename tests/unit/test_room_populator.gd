extends GutTest
## Unit tests for the populator registry (W3-A3, G11b). SPEC-floor-generation,
## "Populators": "each owning module registers `FloorGenerator.register_populator(
## RoomType, Callable(room: Room) -> void)` at startup. The generator places the
## room and calls the populator on the host after painting."
##
## The registry itself lives on `FloorGenerator` (the spec names it as one of
## that class's provided interfaces, so it sits in
## `scripts/generation/floor_generator.gd`); `scripts/run/room_populator.gd` is
## run-economy's seam read of it. This file covers both: the registry's
## register, lookup and populate order, the `RoomType` members against the
## spec's room-type table, the seam's reads now that the generator exists (its
## absent-generator path was the suite's one pending test), and the wiring — a
## painted floor's `populate()` running each registered populator once per room
## of its type on the host.
##
## Sync: none — static pure logic plus a locally painted floor. Populators run
## on the host; the host gate is `Floor.populate()`'s own is-server check.

## SPEC-floor-generation, "Room types and placement rules" — one row each
## (MINI_BOSS and BOSS share the arena row).
const SPEC_ROOM_TYPES: Array[StringName] = [
	&"START", &"EXIT", &"COMBAT", &"ELITE_COMBAT", &"TREASURE", &"SHRINE",
	&"RUNE", &"ANVIL", &"SHOP", &"CURSED_ALTAR", &"CHALLENGE", &"LORE",
	&"REST", &"SECRET", &"ROPE", &"MINI_BOSS", &"BOSS",
]

const WIRING_SEED: int = 42

## The populate-order record. Named methods, not lambdas (GUT: a lambda connect
## never fires; here the registry calls the Callable directly, but the recorder
## stays a named method so the assertions read the one member array).
var _order: Array[String] = []

## The rooms the wiring test's TREASURE populator was handed.
var _populated_rooms: Array[Node] = []

## The wiring test's ROPE-populator call count (floor 1 has no rope room).
var _rope_calls: int = 0


func before_each() -> void:
	FloorGenerator.clear_populators()
	_order.clear()
	_populated_rooms.clear()
	_rope_calls = 0


func after_each() -> void:
	FloorGenerator.clear_populators()


func _on_first(_room: Node) -> void:
	_order.append("first")


func _on_second(_room: Node) -> void:
	_order.append("second")


func _on_treasure_room(room: Node) -> void:
	_populated_rooms.append(room)


func _on_rope_room(_room: Node) -> void:
	_rope_calls += 1


## A stand-in room: `run_populators` reads the type off `room.get(&"type")`,
## exactly what a scene `Room` node carries (a script property, so `get` sees
## it — `Object.set` on a foreign property would be a silent no-op).
class TypedRoom extends Node2D:
	var type: int = 0


func _room_of_type(type: int) -> TypedRoom:
	var room := TypedRoom.new()
	room.type = type
	autofree(room)
	return room


# --- register ----------------------------------------------------------------


func test_register_keeps_one_list_per_room_type() -> void:
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, Callable(self, &"_on_first"))
	FloorGenerator.register_populator(FloorGenerator.RoomType.TREASURE, Callable(self, &"_on_second"))
	assert_eq(FloorGenerator.populator_count(FloorGenerator.RoomType.COMBAT), 1, "the combat entry")
	assert_eq(FloorGenerator.populator_count(FloorGenerator.RoomType.TREASURE), 1, "the treasure entry")
	assert_eq(FloorGenerator.populator_count(FloorGenerator.RoomType.SHRINE), 0,
		"a type nobody registered reads 0, not a missing key")


func test_registering_the_same_callable_twice_is_idempotent() -> void:
	var populator: Callable = Callable(self, &"_on_first")
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, populator)
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, populator)
	assert_eq(FloorGenerator.populator_count(FloorGenerator.RoomType.COMBAT), 1,
		"the same (type, callable) twice is one entry — a startup re-registration stays a no-op")


func test_two_distinct_callables_for_one_type_are_both_kept() -> void:
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, Callable(self, &"_on_first"))
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, Callable(self, &"_on_second"))
	assert_eq(FloorGenerator.populator_count(FloorGenerator.RoomType.COMBAT), 2,
		"the registry is a list per type, not a single slot")


# --- lookup ------------------------------------------------------------------


func test_lookup_runs_only_the_rooms_own_type() -> void:
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, Callable(self, &"_on_first"))
	FloorGenerator.register_populator(FloorGenerator.RoomType.TREASURE, Callable(self, &"_on_second"))
	FloorGenerator.run_populators(_room_of_type(FloorGenerator.RoomType.COMBAT))
	assert_eq(_order, ["first"] as Array[String], "a combat room ran the combat populator only")
	_order.clear()
	FloorGenerator.run_populators(_room_of_type(FloorGenerator.RoomType.TREASURE))
	assert_eq(_order, ["second"] as Array[String], "a treasure room ran the treasure populator only")


func test_populators_run_in_registration_order() -> void:
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, Callable(self, &"_on_second"))
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, Callable(self, &"_on_first"))
	FloorGenerator.run_populators(_room_of_type(FloorGenerator.RoomType.COMBAT))
	assert_eq(_order, ["second", "first"] as Array[String],
		"registration order, not callable sort order — 'second' was registered first here on purpose")


func test_run_populators_skips_an_invalid_callable() -> void:
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, Callable())
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, Callable(self, &"_on_first"))
	FloorGenerator.run_populators(_room_of_type(FloorGenerator.RoomType.COMBAT))
	assert_eq(_order, ["first"] as Array[String],
		"the dead entry is skipped (the is_valid guard), the live one still runs")


func test_clear_populators_empties_the_registry() -> void:
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, Callable(self, &"_on_first"))
	FloorGenerator.clear_populators()
	assert_eq(FloorGenerator.populator_count(FloorGenerator.RoomType.COMBAT), 0, "the list is gone")
	FloorGenerator.run_populators(_room_of_type(FloorGenerator.RoomType.COMBAT))
	assert_true(_order.is_empty(), "nothing runs after the clear (the suite's between-tests reset)")


# --- the room types match SPEC-floor-generation ------------------------------


func test_every_room_type_in_the_spec_table_exists_on_the_generator() -> void:
	for room_type: StringName in SPEC_ROOM_TYPES:
		assert_ne(RoomPopulator.room_type_value(FloorGenerator, room_type), null,
			"RoomType.%s from the spec's room-type table" % room_type)


func test_the_generator_declares_no_room_type_outside_the_spec_table() -> void:
	var generator: Script = RoomPopulator.generator_script()
	assert_not_null(generator, "the constants read needs the script the seam loads")
	var constants: Dictionary = generator.get_script_constant_map()
	var raw_types: Variant = constants.get(RoomPopulator.ROOM_TYPE_CONSTANT)
	assert_true(raw_types is Dictionary, "the generator's constants hold RoomType as a dictionary")
	var declared: Dictionary = raw_types as Dictionary
	assert_eq(declared.size(), SPEC_ROOM_TYPES.size(),
		"no member beyond the spec's table — an extra row needs the spec changed first")
	for room_type: StringName in SPEC_ROOM_TYPES:
		assert_true(declared.has(room_type), "%s is declared" % room_type)


# --- the RoomPopulator seam reads the real registry ---------------------------


func test_the_seam_finds_the_real_generator_script() -> void:
	var generator: Script = RoomPopulator.generator_script()
	assert_not_null(generator, "floor_generator.gd exists — the guarded no-op era is over")
	assert_eq(generator.resource_path, RoomPopulator.GENERATOR_SCRIPT_PATH,
		"at the documented path, the one the guarded registrations read")


func test_the_seam_reads_room_type_values_off_the_generator() -> void:
	assert_eq(RoomPopulator.room_type_value(FloorGenerator, &"ROPE"), FloorGenerator.RoomType.ROPE,
		"the value Rope.register_populator hands the registry")
	assert_eq(RoomPopulator.room_type_value(FloorGenerator, &"COMBAT"), FloorGenerator.RoomType.COMBAT,
		"the value SpawnDirector's registration hands the registry")
	assert_null(RoomPopulator.room_type_value(FloorGenerator, &"NOT_A_SPEC_TYPE"),
		"a name outside the table reads null — the guarded registration stays a no-op")
	assert_null(RoomPopulator.room_type_value(null, &"ROPE"), "no generator script, no value")


func test_the_seam_reads_one_member_off_an_already_read_table() -> void:
	assert_eq(RoomPopulator.room_type_of({&"SHRINE": 102} as Dictionary, &"SHRINE"), 102,
		"the registry-double shape the Shrine registration test drives")


func test_the_blocker_line_names_w3_a3() -> void:
	assert_true(RoomPopulator.blocker_line("test detail").contains("blocked on Dev A (W3-A3)"),
		"the reason a container does not appear is greppable in scripts/run/")


# --- wiring: a painted floor runs the registry on the host --------------------


func test_a_painted_floor_populates_each_registered_room_on_the_host() -> void:
	var world := (load("res://scenes/main/world.tscn") as PackedScene).instantiate() as World
	world.debug_test_floor = false
	add_child_autofree(world)
	var biome: BiomeData = BiomeData.for_index(1)
	var layout: FloorLayout = FloorGenerator.generate(WIRING_SEED, 1, biome, [] as Array[int])
	var floor_node := Floor.new()
	add_child_autofree(floor_node)
	floor_node.paint(layout, biome, world)
	# The registry is empty (before_each cleared it); only what this test
	# registers runs.
	FloorGenerator.register_populator(FloorGenerator.RoomType.TREASURE, Callable(self, &"_on_treasure_room"))
	FloorGenerator.register_populator(FloorGenerator.RoomType.ROPE, Callable(self, &"_on_rope_room"))

	floor_node.populate()

	var treasure_rooms: int = 0
	for spec: RoomSpec in layout.rooms:
		if spec.type == FloorGenerator.RoomType.TREASURE:
			treasure_rooms += 1
	assert_gt(treasure_rooms, 0, "the spec's '1 per floor' treasure is on this floor")
	assert_eq(_populated_rooms.size(), treasure_rooms,
		"the populator ran once per TREASURE room, and for no other type")
	assert_same(_populated_rooms[0], floor_node.room_of_type(FloorGenerator.RoomType.TREASURE),
		"the populator was handed the floor's own Room node")
	assert_eq(_rope_calls, 0, "floor 1 has no ROPE room, so the ROPE populator never ran")


# --- wiring: the live startup registration (main.gd) --------------------------


## G16d's live-caller proof for the startup registrations: `main.gd`'s
## registration block is executed, not read as source — a `Main` instance
## (never in the tree, so its `_ready` never runs) calls
## `Main.register_populators()`, and every module lands its entry in the
## registry. The guarded modules' `_populator_registered` statics may already
## be true from an earlier suite file, which would turn the live call into a
## no-op before this test could watch it register — so they are snapshotted,
## cleared for the call, and put back after (GUT asserts continue a failing
## test, so the restore always runs; the registry itself goes through the
## file's `after_each` clear).
func test_main_startup_registers_the_live_populators() -> void:
	var rope_was: bool = Rope._populator_registered
	var chest_was: bool = Chest._populator_registered
	var shrine_was: bool = Shrine._populator_registered
	var shopkeeper_was: bool = Shopkeeper._populator_registered
	var lore_was: bool = LorePage._populator_registered
	Rope._populator_registered = false
	Chest._populator_registered = false
	Shrine._populator_registered = false
	Shopkeeper._populator_registered = false
	LorePage._populator_registered = false

	var main_node := Main.new()
	autofree(main_node)

	main_node.register_populators()

	assert_gte(FloorGenerator.populator_count(FloorGenerator.RoomType.COMBAT), 1,
		"SpawnDirector and RoomFurniture registered for COMBAT")
	assert_gte(FloorGenerator.populator_count(FloorGenerator.RoomType.ELITE_COMBAT), 1,
		"SpawnDirector registered for ELITE_COMBAT")
	assert_gte(FloorGenerator.populator_count(FloorGenerator.RoomType.ROPE), 1,
		"Rope registered for ROPE")
	assert_gte(FloorGenerator.populator_count(FloorGenerator.RoomType.TREASURE), 1,
		"Chest registered for TREASURE")
	assert_gte(FloorGenerator.populator_count(FloorGenerator.RoomType.SHRINE), 1,
		"Shrine registered for SHRINE")
	assert_gte(FloorGenerator.populator_count(FloorGenerator.RoomType.SHOP), 1,
		"Shopkeeper registered for SHOP")
	assert_gte(FloorGenerator.populator_count(FloorGenerator.RoomType.LORE), 1,
		"LorePage registered for LORE")

	Rope._populator_registered = rope_was
	Chest._populator_registered = chest_was
	Shrine._populator_registered = shrine_was
	Shopkeeper._populator_registered = shopkeeper_was
	LorePage._populator_registered = lore_was
