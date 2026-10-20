class_name ShrineRegistryStub
extends RefCounted
## Test double for the two things Dev A's `FloorGenerator` will expose to a
## room populator (SPEC-floor-generation): a `RoomType` enum and a
## `register_populator(type, populator)` registry. Owned by tests.
## blocked on Dev A (W4-A3): the real generator replaces this stub member for
## member; `Shrine.register_populator()` reads the enum and the registry off
## whichever script the path resolves to, so the swap-in is mechanical.
## Sync: none — a test double, never run in a live game.

## The room types the registry accepts. Two keys with different values, so a
## test can tell which one a caller looked up.
const RoomType: Dictionary = {
	"ROPE": 101,
	"SHRINE": 102,
}

## `room type value -> the Callable it was registered with`, so a test can read
## back what the guarded registration handed over.
static var registered: Dictionary = {}


## The registry method a module's guarded registration calls.
static func register_populator(room_type: Variant, populator: Callable) -> void:
	registered[room_type] = populator
