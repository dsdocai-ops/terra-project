class_name AbilityData
extends ContentData
## An ability a player slots on Q, R or V (SPEC-abilities "AbilityData"). Owned
## by abilities. Sync: none (data). The host reads it when a cast spawns.
##
## `ranks` holds rank 1, 2 and 3 in order. `charges` is the maximum: a cast
## spends one, and the cooldown gives one back each time it runs out.
## `is_ultimate` marks the ultimates that UltimateController owns.

enum School { FIRE, FROST, STORM, SHADOW, POISON, EARTH, BLOOD, VOID, UTILITY }
enum AbilityTargeting { SELF, CURSOR_POINT, CURSOR_DIRECTION, NEAREST_ENEMY, SCREEN }

const MAX_RANK: int = 3

@export var school: School = School.FIRE
@export var element: HitInfo.Element = HitInfo.Element.NONE
@export var targeting: AbilityTargeting = AbilityTargeting.SELF
## Seconds of TimeManager-scaled time before a spent charge comes back.
@export var cooldown: float = 0.0
@export var charges: int = 1
@export var base_damage: float = 0.0
## Rank 1, 2 and 3 in order.
@export var ranks: Array[AbilityRank] = []
## The node that performs the ability on the host.
@export var cast_scene: PackedScene
@export var description: String = ""
@export var is_ultimate: bool = false
## Blood Pact and the Infinity Loop path spend this share of max HP per cast.
@export var hp_cost_percent: float = 0.0


## The rank data for `rank` (1 to 3), or null when the ability has no such rank.
func rank_data(rank: int) -> AbilityRank:
	if rank < 1 or rank > ranks.size():
		return null
	return ranks[rank - 1]
