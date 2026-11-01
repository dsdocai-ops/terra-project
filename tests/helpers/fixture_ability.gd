class_name FixtureAbility
extends RefCounted
## Builds the fixture ability the cast tests slot: a 2-second cooldown, one charge,
## 10 base damage, and three ranks whose damage steps up (rank 2 deals 1.5x). Its
## cast scene is FixtureCast. Owned by abilities (test helper). Sync: none.


static func make() -> AbilityData:
	var data := AbilityData.new()
	data.id = &"fixture_nova"
	data.cooldown = 2.0
	data.charges = 1
	data.base_damage = 10.0
	data.element = HitInfo.Element.FROST
	data.cast_scene = load("res://tests/helpers/fixture_cast.tscn") as PackedScene
	data.ranks = [_rank(1.0), _rank(1.5), _rank(2.0)]
	return data


static func _rank(damage_mult: float) -> AbilityRank:
	var rank := AbilityRank.new()
	rank.damage_mult = damage_mult
	rank.duration = 0.5
	return rank
