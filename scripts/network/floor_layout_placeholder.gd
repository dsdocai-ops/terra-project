class_name FloorLayoutPlaceholder
extends RefCounted
## The lane-B stand-in for Dev A's `FloorLayout` (SPEC-floor-generation):
## it carries the `layout_hash` floor sync compares between peers, plus the
## inputs that produced it, and is built deterministically from
## (run_seed, floor_index, biome_id, modifiers) through a seeded
## RandomNumberGenerator — never a global roll.
## Owned by networking (temporary).
## blocked on Dev A (W3-A1): the swap-in is nothing on this side —
## FloorGeneratorSeam returns the real `FloorLayout` the moment
## `scripts/generation/floor_generator.gd` lands, and this file plus the seam's
## fallback are deleted with it.
## Sync: none — every peer derives the same layout from the same broadcast
## inputs, which is exactly what the layout_hash assertion compares.

const MIN_ROOMS: int = 8
const MAX_ROOMS: int = 14
const MIN_ROOM_W: int = 9
const MAX_ROOM_W: int = 17
const MIN_ROOM_H: int = 7
const MAX_ROOM_H: int = 13
const GRID_TILES: int = 96
const MIN_SEED: int = 1
## Multiplicative mixing constants: plain integer arithmetic, so the seed and
## the hash cannot depend on anything process-local.
const SEED_MIX: int = 2654435761
const FLOOR_STRIDE: int = 40503
const RECT_MIX: int = 31
const POSITION_MIX: int = 37
const MODIFIER_MIX: int = 43
const HEIGHT_MIX: int = 2
## Which source produced a layout, so the log and the smoke can tell a
## generator's floor from this stand-in.
const SOURCE: StringName = &"placeholder"

var seed: int = 0
var floor_index: int = 1
var biome_id: int = 1
var modifiers: Array[int] = []
var room_count: int = 0
## Room rectangles in tiles. Dev A's generator paints real rooms from its own
## layout; this is the content the placeholder's hash is built from.
var rooms: Array[Rect2i] = []
var layout_hash: int = 0
## Where this layout came from: SOURCE, or the generating class's own name.
var source: StringName = SOURCE


func _init(p_seed: int = 0, p_floor_index: int = 1, p_biome_id: int = 1, p_modifiers: Array[int] = []) -> void:
	seed = p_seed
	floor_index = p_floor_index
	biome_id = p_biome_id
	modifiers.assign(p_modifiers)


## The layout for one floor. Same inputs, same layout, in any process.
static func for_floor(run_seed: int, floor_index: int, biome_id: int, modifiers: Array[int]) -> FloorLayoutPlaceholder:
	var layout := FloorLayoutPlaceholder.new(run_seed, floor_index, biome_id, modifiers)
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed(run_seed, floor_index)
	layout.room_count = rng.randi_range(MIN_ROOMS, MAX_ROOMS)
	for _index: int in layout.room_count:
		var size := Vector2i(rng.randi_range(MIN_ROOM_W, MAX_ROOM_W), rng.randi_range(MIN_ROOM_H, MAX_ROOM_H))
		var offset := Vector2i(rng.randi_range(0, GRID_TILES - 1), rng.randi_range(0, GRID_TILES - 1))
		layout.rooms.append(Rect2i(offset, size))
	layout.layout_hash = hash_rooms(layout.rooms, floor_index, biome_id, modifiers)
	return layout


## The one seed this floor's randomness comes from (SPEC-floor-generation:
## `hash(run_seed, floor_index)`). Integer arithmetic only, so two processes
## agree without relying on engine hashing.
static func layout_seed(run_seed: int, floor_index: int) -> int:
	return absi(run_seed * SEED_MIX + floor_index * FLOOR_STRIDE) + MIN_SEED


## The hash of a floor's rooms and inputs, in the shape SPEC-floor-generation
## describes (`layout_hash` = hash of the room rects, types, corridor cells).
static func hash_rooms(rooms: Array[Rect2i], floor_index: int, biome_id: int, modifiers: Array[int]) -> int:
	var acc: int = floor_index * FLOOR_STRIDE + biome_id
	for rect: Rect2i in rooms:
		acc = acc * RECT_MIX + rect.position.x * POSITION_MIX + rect.position.y * POSITION_MIX
		acc += rect.size.x * MODIFIER_MIX + rect.size.y * HEIGHT_MIX
	for modifier: int in modifiers:
		acc = acc * MODIFIER_MIX + modifier
	return absi(acc)
