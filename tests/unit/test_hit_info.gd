extends GutTest
## Tests for `HitInfo` (SPEC-combat-core, "HitInfo") and `Team`: the from-behind
## angle math, the per-target copy, and which sides oppose.


func test_front_hit_is_not_from_behind() -> void:
	assert_false(HitInfo.is_from_behind(Vector2.RIGHT, Vector2.RIGHT))


func test_side_hit_is_not_from_behind() -> void:
	assert_false(HitInfo.is_from_behind(Vector2.RIGHT, Vector2.DOWN))


func test_behind_starts_past_120_degrees() -> void:
	assert_false(HitInfo.is_from_behind(Vector2.RIGHT, Vector2.RIGHT.rotated(deg_to_rad(119.0))))
	assert_true(HitInfo.is_from_behind(Vector2.RIGHT, Vector2.RIGHT.rotated(deg_to_rad(121.0))))


func test_rear_hit_is_from_behind_on_both_rotation_sides() -> void:
	assert_true(HitInfo.is_from_behind(Vector2.RIGHT, Vector2.LEFT))
	assert_true(HitInfo.is_from_behind(Vector2.RIGHT, Vector2.RIGHT.rotated(deg_to_rad(-150.0))))


func test_zero_vectors_are_never_behind() -> void:
	assert_false(HitInfo.is_from_behind(Vector2.ZERO, Vector2.LEFT))
	assert_false(HitInfo.is_from_behind(Vector2.RIGHT, Vector2.ZERO))


func test_copy_carries_every_field() -> void:
	var template := HitInfo.new()
	template.base_damage = 12.0
	template.multiplier = 1.5
	template.bonus_crit_chance = 0.1
	template.element = HitInfo.Element.FIRE
	template.statuses = [StatusApplication.make(StatusEffects.Status.BURN, 2)]
	template.knockback = Vector2(30, 0)
	template.hit_stun_seconds = 0.4
	template.is_heavy = true
	template.is_projectile = true
	template.tags = [&"melee", &"pickaxe"]
	template.proc_depth = 2
	template.force_crit = true
	template.scales_with_ability_power = true
	var clone: HitInfo = template.copy()
	assert_ne(clone, template)
	assert_eq(clone.base_damage, 12.0)
	assert_eq(clone.multiplier, 1.5)
	assert_eq(clone.bonus_crit_chance, 0.1)
	assert_eq(clone.element, HitInfo.Element.FIRE)
	assert_eq(clone.statuses.size(), 1)
	assert_eq(clone.statuses[0].stacks, 2)
	assert_eq(clone.knockback, Vector2(30, 0))
	assert_eq(clone.hit_stun_seconds, 0.4)
	assert_true(clone.is_heavy and clone.is_projectile and clone.force_crit and clone.scales_with_ability_power)
	assert_eq(clone.tags, template.tags)
	assert_eq(clone.proc_depth, 2)


func test_copy_does_not_share_arrays_or_results() -> void:
	var template := HitInfo.new()
	template.tags = [&"melee"]
	var clone: HitInfo = template.copy()
	clone.tags.append(&"proc")
	clone.statuses.append(StatusApplication.make(StatusEffects.Status.CHILL))
	clone.final_damage = 9
	clone.prevented = true
	assert_eq(template.tags, [&"melee"] as Array[StringName])
	assert_true(template.statuses.is_empty())
	assert_eq(template.final_damage, 0)
	assert_false(template.prevented)


func test_team_opposes() -> void:
	assert_true(Team.opposes(Team.Kind.PLAYER, Team.Kind.ENEMY))
	assert_true(Team.opposes(Team.Kind.PLAYER, Team.Kind.NEUTRAL))
	assert_false(Team.opposes(Team.Kind.PLAYER, Team.Kind.PLAYER))
	assert_true(Team.opposes(Team.Kind.ENEMY, Team.Kind.PLAYER))
	assert_false(Team.opposes(Team.Kind.ENEMY, Team.Kind.NEUTRAL))
	assert_false(Team.opposes(Team.Kind.ENEMY, Team.Kind.ENEMY))
	assert_false(Team.opposes(Team.Kind.NEUTRAL, Team.Kind.PLAYER))
