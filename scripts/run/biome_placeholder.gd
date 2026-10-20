class_name BiomePlaceholder
extends Resource
## The biome a floor belongs to, standing in for Dev A's `BiomeData`
## (SPEC-floor-generation; week 6 content, blocked on Dev A W3-A1/A6 until the
## generator and biome resources land). GameState.floor_changed carries it in
## its Resource-typed `biome` parameter (BRIEF Assumption 17), so the HUD and
## floor generation can read the derived biome today.
## Owned by run-economy (temporary): the swap-in is one line in
## GameState._biome_for() plus deleting this file.
## Sync: none — the biome is derived from the floor number on every peer, so
## host and clients always agree.

const MIN_INDEX: int = 1
const MAX_INDEX: int = 6

## 1..6, the same value as RunState.biome_index.
var id: int = MIN_INDEX


func _init(p_id: int = MIN_INDEX) -> void:
	id = clampi(p_id, MIN_INDEX, MAX_INDEX)


static func from_index(index: int) -> BiomePlaceholder:
	return BiomePlaceholder.new(index)
