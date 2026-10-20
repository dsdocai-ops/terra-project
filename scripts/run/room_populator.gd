class_name RoomPopulator
extends RefCounted
## The two seams a run-economy container needs from another module before that
## module lands. Owned by run-economy (W4-B8, goal G15).
##
## **Seam 1 — Dev A's populator registry.** SPEC-floor-generation, "Populators":
## "each owning module registers `FloorGenerator.register_populator(RoomType,
## Callable(room: Room) -> void)` at startup." Both halves of that sentence are
## read off whatever `scripts/generation/floor_generator.gd` resolves to — the
## `RoomType` enumeration out of its constants and the registry as a static
## method on it — so this file never names a `RoomType` member that does not
## exist yet, and the swap-in is mechanical. `room_type_value()` is public
## because the registration test drives it with a registry double.
##
## **Seam 2 — the pickup spawner.** `world.tscn` puts run-economy's
## `PickupSpawner` under `Entities`, and `World.pickup_spawner` is the
## documented read (`world.gd`: "Other modules reach these nodes through
## GameState.world, never by path"). A container lives inside a room, so a
## relative path from it would name a node that is not its sibling; this lookup
## is how it finds the spawner instead. Null when there is no world — town, a
## unit case — and a container with no spawner still pays its currency, because
## the coin is only how a player sees a drop that has already been credited.
##
## **blocked on Dev A (W3-A3)**: `scripts/generation/floor_generator.gd` and its
## `RoomType` enumeration are `floor-generation`'s and are not in the tree, so
## `generator_script()` answers null and every guarded registration is a
## recorded no-op. Nothing else here depends on the other lane.
##
## Sync: none — four pure reads. The host gate belongs to the caller.

## Where floor-generation's generator and its populator registry land
## (SPEC-project structure: scripts/generation/floor_generator.gd).
const GENERATOR_SCRIPT_PATH: String = "res://scripts/generation/floor_generator.gd"
## The constant name a room type is registered under, read off the generator
## script at runtime so this file never names an enum that does not exist yet.
const ROOM_TYPE_CONSTANT: StringName = &"RoomType"
## The registry method a module's guarded registration calls.
const REGISTER_METHOD: StringName = &"register_populator"


## Dev A's generator script, or null while it does not exist. Checked with
## `ResourceLoader.exists` first, because loading a missing path logs an engine
## error that would show up as noise in every headless run.
static func generator_script() -> Script:
	if not ResourceLoader.exists(GENERATOR_SCRIPT_PATH):
		return null
	var loaded: Resource = load(GENERATOR_SCRIPT_PATH)
	return loaded as Script


## The room-type value named by `room_type`, out of `generator`'s own constants.
## Null while the script is absent, declares no `RoomType` enumeration, or holds
## no such member.
static func room_type_value(generator: Script, room_type: StringName) -> Variant:
	if generator == null:
		return null
	var constants: Dictionary = generator.get_script_constant_map()
	var raw_types: Variant = constants.get(ROOM_TYPE_CONSTANT)
	if not raw_types is Dictionary:
		return null
	return room_type_of(raw_types as Dictionary, room_type)


## One member out of an already-read `RoomType` dictionary. Split from the call
## above so a case can drive the read against a registry double's constants
## without a script to load.
static func room_type_of(room_types: Dictionary, room_type: StringName) -> Variant:
	return room_types.get(room_type)


## The spawner every pickup is spawned through, or null when there is no world.
static func world_pickup_spawner() -> PickupSpawner:
	var world: World = GameState.world
	if world == null:
		return null
	return world.pickup_spawner


## The one line every blocked placement writes, so the reason a container does
## not appear on a generated floor is greppable in `scripts/run/` rather than
## only in a doc. `detail` names what was missing.
static func blocker_line(detail: String) -> String:
	return "blocked on Dev A (W3-A3): %s" % detail
