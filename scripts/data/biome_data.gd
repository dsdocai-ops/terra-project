class_name BiomeData
extends ContentData
## One of the six pit biomes (SPEC-biomes, SPEC-floor-generation "Interfaces
## consumed"). Owned by biomes (Dev A lane). Sync: none (data); every peer
## derives the same biome from the floor number.
##
## Phase 1 carries only what the floor generator and spawn director read:
## room size range, the biome-local lore floor, the enemy pool and a
## placeholder tint. Hazards, palette and lighting arrive with W6-A1.

const FLOORS_PER_BIOME: int = 5
const BIOME_COUNT: int = 6
const COLLAPSED_MINES_PATH: String = "res://data/biomes/collapsed_mines.tres"

## 1..6, the same value as RunState.biome_index.
@export var biome_index: int = 1
## Smallest and largest room in tiles (SPEC-floor-generation default 9x7..17x13).
@export var room_size_min: Vector2i = Vector2i(12, 10)
@export var room_size_max: Vector2i = Vector2i(22, 16)
## The floor within this biome (1..5) that holds the LORE room.
@export var lore_floor: int = 4
## EnemyData the spawn director draws from; empty falls back to the code pool.
@export var enemy_pool: Array[Resource] = []
## Placeholder floor tint until the real tileset lands.
@export var tint: Color = Color.WHITE


## The first global floor (1-based) of this biome.
func first_floor() -> int:
	return (biome_index - 1) * FLOORS_PER_BIOME + 1


## 1..5: where `floor_index` sits inside its biome.
static func floor_in_biome(floor_index: int) -> int:
	return (maxi(floor_index, 1) - 1) % FLOORS_PER_BIOME + 1


## The biome for a 1..6 index. Biome 1 comes from its `.tres`; the others are
## built in code with the defaults until their data lands, so a floor can
## always be generated.
static func for_index(index: int) -> BiomeData:
	var clamped: int = clampi(index, 1, BIOME_COUNT)
	if clamped == 1 and ResourceLoader.exists(COLLAPSED_MINES_PATH):
		var loaded: BiomeData = load(COLLAPSED_MINES_PATH) as BiomeData
		if loaded != null:
			return loaded
	var biome := BiomeData.new()
	biome.biome_index = clamped
	biome.id = StringName("biome_%d" % clamped)
	biome.display_name = "Biome %d" % clamped
	return biome
