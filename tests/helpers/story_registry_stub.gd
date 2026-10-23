class_name StoryRegistryStub
extends RefCounted
## Test double for the two things Dev A's `FloorGenerator` will expose to a
## room populator (SPEC-floor-generation: "each owning module registers
## `FloorGenerator.register_populator(RoomType, Callable(room: Room) -> void)`
## at startup"): a `RoomType` enumeration and a `register_populator` registry.
## Owned by story-dialogue (tests), goal G4.
##
## `RoomRegistryStub` (run-economy's) and `ShrineRegistryStub` (relics') are the
## same double with their own modules' room types; this one carries the room
## type `story-dialogue` registers (`LORE`), so a case can tell which type a
## caller looked up without the modules' tests sharing a fixture. One distinct
## value per key, so resolving the wrong key is visible.
##
## blocked on Dev A (W3-A3): the real `FloorGenerator` replaces this stub member
## for member — the lore page reads the enum and the registry off whichever
## script the path resolves to, so the swap-in is mechanical.
## Sync: none — a test double, never run in a live game.

## The room types the registry accepts. Values are arbitrary and distinct.
const RoomType: Dictionary = {
	"LORE": 110,
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
