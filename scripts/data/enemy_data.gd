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
## Poise pool (combat v2): hits drain it by their poise damage and breaking it
## staggers the enemy. 0 means fodder that staggers on every hit.
@export var poise: float = 0.0
## How long a poise break (or any hit on a 0-poise enemy) staggers it.
@export var stagger_seconds: float = 0.8
## Scales poise damage taken: 0 takes it all, 1 is immune.
@export var stagger_resist: float = 0.0
@export var knockback_resist: float = 0.0
@export var can_be_elite: bool = true
## False for fixed-HP test enemies (the debug grub): skips biome and co-op HP scaling.
@export var scales_hp: bool = true
@export var loot_table: LootTable = null
@export var echo_shards_on_death: int = 0
@export var biome: StringName = &"collapsed_mines"
## Placeholder look, used while `sprite_frames` is null.
@export var color: Color = Color(0.8, 0.3, 0.25, 1.0)
@export var radius: float = 10.0
## Art (art-audio): 8-facing `idle_<dir>` / `walk_<dir>` frames built by
## tools/make_sprite_frames.gd. Null keeps the placeholder body polygon.
@export var sprite_frames: SpriteFrames = null


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
