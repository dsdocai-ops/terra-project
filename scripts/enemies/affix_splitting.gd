class_name AffixSplitting
extends EliteBehavior
## SPLITTING (SPEC-enemies-ai): on death spawns COPY_COUNT non-elite copies of the
## elite's kind at COPY_HP_SHARE of their max HP, through SpawnDirector.spawn_one so
## they replicate with the rest of the room. Owned by enemies-ai; host only.

const COPY_COUNT: int = 2
const COPY_HP_SHARE: float = 0.3
## How far from the dead elite each copy appears, in px.
const SPLIT_RADIUS: float = 24.0


## The HP a copy spawns with, given the elite's max HP. Never below 1.
static func copy_hp_for(max_hp: int) -> int:
	return maxi(roundi(max_hp * COPY_HP_SHARE), 1)


## Where the copies appear: COPY_COUNT points on a circle round `at`.
static func copy_positions(at: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for index: int in COPY_COUNT:
		points.append(at + Vector2.RIGHT.rotated(TAU * float(index) / float(COPY_COUNT)) * SPLIT_RADIUS)
	return points


func on_death(enemy: Enemy, _hit: HitInfo) -> void:
	for point: Vector2 in copy_positions(enemy.global_position):
		var copy := SpawnDirector.spawn_one(enemy.kind, point, false, enemy.room)
		if copy != null and copy.health != null:
			copy.health.current_hp = copy_hp_for(copy.health.max_hp)
