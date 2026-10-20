class_name FloorGeneratorSeam
extends RefCounted
## The bridge between networking's floor sync and Dev A's `FloorGenerator`
## (SPEC-floor-generation). Every peer makes the same `generate()` call with the
## inputs the host broadcasts, so one seed is one floor on every screen.
## Owned by networking (temporary).
## blocked on Dev A (W3-A1): `scripts/generation/floor_generator.gd` does not
## exist yet, so `generate()` returns the lane-B `FloorLayoutPlaceholder` and
## says why once. The swap-in is nothing on this side: the moment that script
## exists with a static `generate(run_seed, floor_index, biome, modifiers)` the
## seam calls it (and its `roll_modifiers`, when it has one). The one remaining
## swap is `GameState.biome_for_index`, which returns BiomeData instead of
## BiomePlaceholder then (Dev A W3-A1/A6) — until it does, the generator is
## skipped with a recorded reason rather than called with a biome it would
## reject.
## Sync: none by itself — deterministic from broadcast inputs and never a global
## roll, so the host and every client derive identical layouts.

## Where floor-generation's generator lands (SPEC-project structure).
const GENERATOR_SCRIPT_PATH: String = "res://scripts/generation/floor_generator.gd"
## The source name a layout gets when Dev A's generator produced it.
const SOURCE_FLOOR_GENERATION: StringName = &"floor-generation"
const SOURCE_NONE: StringName = &"none"

## Test injection: while set, generate() calls this object's generate()
## instead of resolving Dev A's script. Tests set FloorGeneratorStub; the game
## never sets it, so production always takes the real-or-placeholder path.
static var _injected_generator: Object = null
## The blocked-on-Dev-A note is worth one line per process, not one per floor.
static var _blocker_logged: bool = false


## Injects the generator generate() should call (tests only).
static func set_injected_generator(generator: Object) -> void:
	_injected_generator = generator


## Drops an injected generator, so the real-or-placeholder path is used again.
static func clear_injected_generator() -> void:
	_injected_generator = null


## Dev A's generator script, or null while it does not exist (or has no
## generate()). Checked with ResourceLoader.exists first, because loading a
## missing path logs an engine error that would be noise in every headless run.
static func real_generator() -> Script:
	if not ResourceLoader.exists(GENERATOR_SCRIPT_PATH):
		return null
	var loaded: Resource = load(GENERATOR_SCRIPT_PATH)
	var script: Script = loaded as Script
	if script == null or not script.has_method(&"generate"):
		return null
	return script


## The layout for one floor, from whichever generator is available. The return
## type is RefCounted because Dev A's `FloorLayout` is not this lane's class:
## the contract is the spec's `layout_hash` field, read through
## `layout_hash_of()`.
static func generate(run_seed: int, floor_index: int, biome_id: int, modifiers: Array[int]) -> RefCounted:
	if _injected_generator != null:
		return _injected_generator.call(&"generate", run_seed, floor_index, GameState.biome_for_index(biome_id), modifiers)
	var script: Script = real_generator()
	if script == null:
		_log_blocker_once("FloorGenerator does not exist yet (%s)" % GENERATOR_SCRIPT_PATH)
		return FloorLayoutPlaceholder.for_floor(run_seed, floor_index, biome_id, modifiers)
	var biome: Resource = GameState.biome_for_index(biome_id)
	if biome is BiomePlaceholder:
		_log_blocker_once("FloorGenerator is present, but its biome parameter is still BiomePlaceholder (Dev A W3-A1/A6)")
		return FloorLayoutPlaceholder.for_floor(run_seed, floor_index, biome_id, modifiers)
	return script.call(&"generate", run_seed, floor_index, biome, modifiers)


## The `layout_hash` of a layout, whatever class produced it. 0 when there is no
## layout at all, so a failed generation is a readable zero rather than a crash.
static func layout_hash_of(layout: RefCounted) -> int:
	if layout == null:
		return 0
	return int(layout.get(&"layout_hash"))


## Which source produced a layout — the layout's own `source` field when it has
## one, else the floor-generation source name. Lets the log, the smoke and the
## tests tell Dev A's generator from the lane-B stand-in.
static func source_of(layout: RefCounted) -> StringName:
	if layout == null:
		return SOURCE_NONE
	var raw: Variant = layout.get(&"source")
	if raw == null:
		return SOURCE_FLOOR_GENERATION
	return StringName(str(raw))


## The floor's modifiers, rolled on the host. Dev A's `FloorGenerator.
## roll_modifiers` owns the roll (SPEC-floor-generation); until it exists a
## floor carries none, and the field still travels in floor_ready so the
## broadcast shape does not change when modifiers land.
static func roll_modifiers(run_seed: int, floor_index: int) -> Array[int]:
	var script: Script = real_generator()
	if script == null or not script.has_method(&"roll_modifiers"):
		return [] as Array[int]
	var rolled: Variant = script.call(&"roll_modifiers", run_seed, floor_index)
	var ids: Array[int] = []
	if rolled is Array:
		for value: Variant in rolled as Array:
			if value is int:
				ids.append(int(value))
	return ids


## Records the blocker once per process: a headless run generates a floor per
## floor change, and the same missing dependency is not news the second time.
static func _log_blocker_once(detail: String) -> void:
	if _blocker_logged:
		return
	_blocker_logged = true
	print("[floor] generation is running on the lane-B placeholder layout — blocked on Dev A (W3-A1): %s" % detail)
