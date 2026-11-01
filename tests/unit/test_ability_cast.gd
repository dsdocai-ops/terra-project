extends GutTest
## Tests for AbilityCast (SPEC-abilities "AbilityCast"): the hit template carries
## the ability id and the "ability" tag, base damage scales with the rank, and the
## cast frees itself when its life ends. Owned by abilities. The cast runs without
## a player, so its life is driven by advance() and physics processing is off.

var _cast: FixtureCast


## Makes the cast, sets it up and puts it in the tree (which runs _perform).
func _spawn(ability_rank: int, aim: Vector2 = Vector2(40, 0), dir: Vector2 = Vector2.ZERO) -> void:
	_cast = FixtureCast.new()
	_cast.set_physics_process(false)
	_cast.setup(null, FixtureAbility.make(), ability_rank, aim, dir)
	add_child_autofree(_cast)


func test_the_hit_is_tagged_with_the_ability_id_and_the_ability_tag() -> void:
	_spawn(1)
	var hit := _cast.build_hit()
	assert_true(hit.tags.has(&"ability"), "the hit carries the ability tag")
	assert_true(hit.tags.has(&"fixture_nova"), "the hit carries the ability id")


func test_the_hit_scales_its_base_damage_by_the_rank() -> void:
	_spawn(2)
	assert_almost_eq(_cast.build_hit().base_damage, 15.0, 0.001, "rank 2 is 1.5x the 10 base")


func test_the_hit_takes_the_ability_element_and_ability_power_scaling() -> void:
	_spawn(1)
	var hit := _cast.build_hit()
	assert_eq(hit.element, HitInfo.Element.FROST, "the hit takes the ability element")
	assert_true(hit.scales_with_ability_power, "an ability hit scales with ability power")


func test_the_hit_applies_its_element_status_through_a_status_application() -> void:
	_spawn(1)
	var hit := _cast.build_hit()
	assert_eq(hit.statuses.size(), 1, "a Frost hit carries one status")
	assert_eq(hit.statuses[0].status, StatusEffects.Status.CHILL, "Frost chills")
	assert_eq(hit.statuses[0].stacks, 1, "one stack per hit")


func test_a_scaled_hit_halves_the_base_damage_and_leaves_the_template_alone() -> void:
	_spawn(1)
	var softer := _cast.scaled_hit(0.5)
	assert_almost_eq(softer.base_damage, 5.0, 0.001, "half of the 10 base")
	assert_almost_eq(_cast.build_hit().base_damage, 10.0, 0.001, "a later full hit is unchanged")


func test_a_zero_aim_direction_falls_back_to_the_right() -> void:
	_spawn(1, Vector2(5, 5), Vector2.ZERO)
	assert_eq(_cast.aim_dir, Vector2.RIGHT, "a zero aim falls back to the right")


func test_the_cast_frees_itself_when_its_life_ends() -> void:
	_spawn(1)
	_cast.advance(0.25)
	assert_false(_cast.is_queued_for_deletion(), "the cast lives for its rank duration")
	_cast.advance(0.3)
	assert_true(_cast.is_queued_for_deletion(), "the cast frees itself after 0.5 s")


func test_the_host_performs_the_cast_once_when_it_enters_the_tree() -> void:
	_spawn(1)
	assert_eq(_cast.performs, 1, "the test instance is the host, so it performs once")
