class_name FloorGeneratorStub
extends RefCounted
## Test double for Dev A's `FloorGenerator` (`scripts/generation/floor_generator.gd`,
## SPEC-floor-generation: `static func generate(run_seed, floor_index, biome,
## modifiers) -> FloorLayout`), so the floor-sync seam's real-generator path can
## be exercised before that script exists. Owned by tests.
## blocked on Dev A (W3-A1): the real generator replaces this stub name for
## name and argument for argument; `FloorGeneratorSeam` calls either one through
## the same `generate()` call.
## Sync: none — a test double, never run in a live game.

## The source name this stub stamps on its layouts.
const SOURCE: StringName = &"FloorGeneratorStub"

## Every generate() call this stub received, in order, as
## {run_seed, floor_index, biome, modifiers} — so a test can prove the seam
## handed the spec's arguments through unchanged.
var calls: Array[Dictionary] = []


## The `FloorGenerator.generate` signature the seam calls. Returns a layout with
## the spec's `layout_hash`, marked with its own source so a test can tell it
## apart from the lane-B placeholder.
func generate(run_seed: int, floor_index: int, biome: Resource, modifiers: Array) -> RefCounted:
	calls.append({
		"run_seed": run_seed,
		"floor_index": floor_index,
		"biome": biome,
		"modifiers": modifiers,
	})
	var layout := FloorLayoutPlaceholder.new(run_seed, floor_index, biome_id_of(biome), modifier_ids_of(modifiers))
	layout.source = SOURCE
	layout.layout_hash = stub_hash(run_seed, floor_index)
	return layout


## A deterministic hash in the stub's own formula, so a test can prove the seam
## returned this stub's layout rather than the lane-B placeholder's.
static func stub_hash(run_seed: int, floor_index: int) -> int:
	return absi(run_seed * 31 + floor_index * 17) + 1


## The biome id behind a biome resource, or 0 when there is none.
static func biome_id_of(biome: Resource) -> int:
	var placeholder: BiomePlaceholder = biome as BiomePlaceholder
	if placeholder != null:
		return placeholder.id
	return 0


## The `FloorModifier` ids in an untyped modifiers array.
static func modifier_ids_of(modifiers: Array) -> Array[int]:
	var ids: Array[int] = []
	for value: Variant in modifiers:
		if value is int:
			ids.append(int(value))
	return ids
