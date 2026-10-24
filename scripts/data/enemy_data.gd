class_name EnemyData
extends ContentData
## An enemy type (SPEC-enemies-ai `EnemyData`). Owned by enemies-ai. Sync: none
## (data); every peer loads the same `.tres` by `id` when an enemy spawns.
## Placeholder art: a coloured body polygon sized by `radius`.

enum MoveType { GROUND, FLYING, STATIC }

## Where the `.tres` files live: data/enemies/<biome>/<id>.tres.
const DATA_DIR: String = "res://data/enemies"

@export var base_stats: Dictionary = {}
@export var attacks: Array[AttackPattern] = []
@export var move_type: MoveType = MoveType.GROUND
@export var move_speed: float = 70.0
@export var aggro_range: float = 260.0
## Ranged enemies back away inside this distance (0 = never).
@export var keep_distance: float = 0.0
@export var stagger_resist: float = 0.0
@export var knockback_resist: float = 0.0
@export var can_be_elite: bool = true
@export var loot_table: LootTable = null
@export var echo_shards_on_death: int = 0
@export var biome: StringName = &"collapsed_mines"
## Placeholder look.
@export var color: Color = Color(0.8, 0.3, 0.25, 1.0)
@export var radius: float = 10.0


## The enemy `.tres` for `kind`, searched across the biome folders. Null when
## none matches.
static func find(kind: StringName) -> EnemyData:
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		return null
	for sub: String in dir.get_directories():
		var path: String = "%s/%s/%s.tres" % [DATA_DIR, sub, String(kind)]
		if ResourceLoader.exists(path):
			return load(path) as EnemyData
	return null
