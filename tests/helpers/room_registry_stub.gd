class_name RoomRegistryStub
extends RefCounted
## Test double for the two things Dev A's `FloorGenerator` will expose to a room
## populator (SPEC-floor-generation: "each owning module registers
## `FloorGenerator.register_populator(RoomType, Callable(room: Room) -> void)` at
## startup"): a `RoomType` enumeration and a `register_populator` registry.
## Owned by run-economy (tests), goal G15.
##
## `ShrineRegistryStub` is the same double with only the two room types
## `relics` registers; this one carries the room types `run-economy`'s
## containers register (`TREASURE`, `ORE`, `SECRET`) beside those, so a case can
## tell which type a caller looked up without the two modules' tests sharing a
## fixture. One distinct value per key, so resolving the wrong key is visible.
##
## blocked on Dev A (W3-A3): the real `FloorGenerator` replaces this stub member
## for member — every container reads the enum and the registry off whichever
## script the path resolves to, so the swap-in is mechanical.
## Sync: none — a test double, never run in a live game.

## The room types the registry accepts. Values are arbitrary and distinct.
const RoomType: Dictionary = {
	"ROPE": 101,
	"SHRINE": 102,
	"TREASURE": 103,
	"ORE": 104,
	"SECRET": 105,
}

## `room type value -> the Callable it was registered with`, so a case can read
## back what a guarded registration handed over.
static var registered: Dictionary = {}


## Drops everything a previous case registered, so one case's registration is
## never another case's starting state.
static func reset() -> void:
	registered.clear()


## The registry method a module's guarded registration calls.
static func register_populator(room_type: Variant, populator: Callable) -> void:
	registered[room_type] = populator
