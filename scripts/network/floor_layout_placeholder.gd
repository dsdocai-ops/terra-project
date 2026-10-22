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
## Room rectangles in tiles, every one of them inside GRID_TILES x GRID_TILES.
## Dev A's generator paints real rooms from its own layout; this is the content
## the placeholder's hash is built from.
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
		# The offset is bounded by the grid **minus the room**, so every room rect
		# lies inside GRID_TILES x GRID_TILES — a room placed at a flat 0..95
		# origin can run up to 16 tiles past the edge of a 96-tile grid.
		var offset := Vector2i(rng.randi_range(0, GRID_TILES - size.x), rng.randi_range(0, GRID_TILES - size.y))
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


## The layout as a plain Dictionary for the wire, so a peer whose own generation
## diverged can hold the host's layout instead of its own (SPEC-networking
## "Seed sync" fallback). Rooms travel as a flat PackedInt32Array of
## (x, y, w, h) quadruples: no typed-array or Rect2i encoding question on the
## wire, and nothing process-local. `layout_hash` travels with the content, so
## the peer that applies it holds exactly the hash the host asserted.
func to_wire() -> Dictionary:
	var flat := PackedInt32Array()
	for rect: Rect2i in rooms:
		flat.append(rect.position.x)
		flat.append(rect.position.y)
		flat.append(rect.size.x)
		flat.append(rect.size.y)
	return {
		"source": String(SOURCE),
		"seed": seed,
		"floor_index": floor_index,
		"biome_id": biome_id,
		"modifiers": PackedInt32Array(modifiers),
		"room_count": room_count,
		"rooms": flat,
		"layout_hash": layout_hash,
	}


## The layout a `to_wire()` Dictionary describes. Unlike `for_floor()` this does
## not generate anything — it carries the sender's rooms and hash across
## unchanged, which is the whole point of the fallback.
static func from_wire(data: Dictionary) -> FloorLayoutPlaceholder:
	var layout := FloorLayoutPlaceholder.new(
		int(data.get("seed", 0)),
		int(data.get("floor_index", 1)),
		int(data.get("biome_id", 1)),
		modifier_ids_of(data.get("modifiers", PackedInt32Array())))
	layout.room_count = int(data.get("room_count", 0))
	layout.rooms = rooms_from(data.get("rooms", PackedInt32Array()))
	layout.layout_hash = int(data.get("layout_hash", 0))
	return layout


## The modifier ids in a wire value, whatever array type it arrived as.
static func modifier_ids_of(value: Variant) -> Array[int]:
	var ids: Array[int] = []
	if value is Array or value is PackedInt32Array:
		for entry: Variant in value:
			ids.append(int(entry))
	return ids


## The room rectangles in a wire value: a flat (x, y, w, h) quadruple per room,
## ignoring a trailing partial one rather than inventing a room from it.
static func rooms_from(value: Variant) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	if not (value is PackedInt32Array):
		return rects
	var flat: PackedInt32Array = value
	var index: int = 0
	while index + 3 < flat.size():
		rects.append(Rect2i(flat[index], flat[index + 1], flat[index + 2], flat[index + 3]))
		index += 4
	return rects
