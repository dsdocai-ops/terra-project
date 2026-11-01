extends GutTest
## Tests for AbilityController (SPEC-abilities "AbilityController"): slot
## assignment, the cooldown tick and refusal while cooling, charges, the
## CDR-shortened cooldown, rank-up on a duplicate, and the gold conversion at
## rank 3. Owned by abilities. The controller stands alone with no player, so
## the tests drive tick() by hand. Physics processing is off, so frames that pass
## between asserts do not move the cooldowns. The TimeManager source is cleared
## after each test.

const SLOT_Q: int = 0
const SLOT_R: int = 1
const SLOT_V: int = 2
const TIME_SOURCE: StringName = &"test_ability_slow"
const CLIENT_PORT: int = 7812

var _controller: AbilityController


func before_each() -> void:
	_controller = AbilityController.new()
	add_child_autofree(_controller)
	_controller.set_physics_process(false)


func after_each() -> void:
	TimeManager.clear_source(TIME_SOURCE)


func _ability(id: StringName, cooldown: float, charges: int = 1) -> AbilityData:
	var data := AbilityData.new()
	data.id = id
	data.cooldown = cooldown
	data.charges = charges
	return data


func test_assign_puts_each_ability_on_its_slot_at_rank_one() -> void:
	var meteor := _ability(&"meteor_call", 4.0)
	var flame := _ability(&"flame_dash", 6.0)
	var chain := _ability(&"chain_lightning", 5.0, 2)
	_controller.assign(SLOT_Q, meteor)
	_controller.assign(SLOT_R, flame)
	_controller.assign(SLOT_V, chain)
	assert_eq(_controller.slots[SLOT_Q], meteor)
	assert_eq(_controller.slots[SLOT_R], flame)
	assert_eq(_controller.slots[SLOT_V], chain)
	assert_eq(_controller.rank(SLOT_Q), 1)
	assert_eq(_controller.rank(SLOT_V), 1)
	assert_eq(_controller.charges(SLOT_V), 2, "a slot starts with the ability's full charges")


func test_assign_ignores_a_slot_that_does_not_exist() -> void:
	_controller.assign(3, _ability(&"meteor_call", 4.0))
	assert_eq(_controller.rank(3), 0)
	assert_eq(_controller.charges(3), 0)
	assert_eq(_controller.cooldown_fraction(3), 0.0)
	for slot: int in AbilityController.SLOT_COUNT:
		assert_null(_controller.slots[slot])


func test_a_cast_spends_the_charge_and_starts_the_cooldown() -> void:
	_controller.assign(SLOT_Q, _ability(&"meteor_call", 4.0))
	assert_true(_controller.request_cast(SLOT_Q, Vector2(10, 20)))
	assert_eq(_controller.charges(SLOT_Q), 0)
	assert_eq(_controller.last_aim_point, Vector2(10, 20))
	assert_eq(_controller.cooldown_fraction(SLOT_Q), 1.0)
	assert_eq(_controller.last_refusal, AbilityController.REFUSE_NONE)


func test_a_cast_is_refused_while_cooling() -> void:
	_controller.assign(SLOT_Q, _ability(&"meteor_call", 4.0))
	_controller.request_cast(SLOT_Q, Vector2.ZERO)
	_controller.tick(1.0)
	assert_false(_controller.request_cast(SLOT_Q, Vector2.ZERO))
	assert_eq(_controller.last_refusal, AbilityController.REFUSE_COOLING)
	assert_eq(_controller.charges(SLOT_Q), 0, "a refused cast spends nothing")


func test_the_cooldown_ticks_down_and_gives_the_charge_back() -> void:
	_controller.assign(SLOT_Q, _ability(&"meteor_call", 4.0))
	_controller.request_cast(SLOT_Q, Vector2.ZERO)
	_controller.tick(2.0)
	assert_almost_eq(_controller.cooldown_fraction(SLOT_Q), 0.5, 0.0001)
	assert_eq(_controller.charges(SLOT_Q), 0)
	_controller.tick(2.0)
	assert_almost_eq(_controller.cooldown_fraction(SLOT_Q), 0.0, 0.0001)
	assert_eq(_controller.charges(SLOT_Q), 1)
	assert_true(_controller.request_cast(SLOT_Q, Vector2.ZERO), "ready again after the cooldown")


func test_the_cooldown_runs_in_time_manager_scaled_time() -> void:
	_controller.assign(SLOT_Q, _ability(&"meteor_call", 4.0))
	_controller.request_cast(SLOT_Q, Vector2.ZERO)
	TimeManager.set_entity_scale(_controller, 0.5, 10.0, TIME_SOURCE)
	_controller.tick(2.0)
	assert_almost_eq(_controller.cooldown_fraction(SLOT_Q), 0.75, 0.0001,
		"at half speed, 2 s of real time is 1 s of cooldown")


func test_cooldown_reduction_from_the_stat_block_shortens_the_cooldown() -> void:
	var stats := StatBlock.new()
	add_child_autofree(stats)
	stats.add_modifier(StatBlock.Stat.COOLDOWN_REDUCTION, 0.5, 0.0, &"test_cdr")
	_controller.stat_block = stats
	_controller.assign(SLOT_Q, _ability(&"meteor_call", 4.0))
	assert_almost_eq(_controller.effective_cooldown(SLOT_Q), 2.0, 0.0001)
	_controller.request_cast(SLOT_Q, Vector2.ZERO)
	_controller.tick(2.0)
	assert_eq(_controller.charges(SLOT_Q), 1, "the reduced cooldown ends after 2 s")


func test_an_empty_slot_refuses_a_cast() -> void:
	assert_false(_controller.request_cast(SLOT_R, Vector2.ZERO))
	assert_eq(_controller.last_refusal, AbilityController.REFUSE_EMPTY)
	assert_false(_controller.request_cast(7, Vector2.ZERO))
	assert_eq(_controller.last_refusal, AbilityController.REFUSE_EMPTY)


func test_a_zero_cooldown_ability_gives_its_charge_straight_back() -> void:
	_controller.assign(SLOT_V, _ability(&"test_instant", 0.0))
	assert_true(_controller.request_cast(SLOT_V, Vector2.ZERO))
	assert_eq(_controller.charges(SLOT_V), 1)
	assert_true(_controller.request_cast(SLOT_V, Vector2.ZERO))


func test_a_two_charge_ability_casts_twice_before_it_cools() -> void:
	_controller.assign(SLOT_V, _ability(&"chain_lightning", 4.0, 2))
	assert_true(_controller.request_cast(SLOT_V, Vector2.ZERO))
	assert_true(_controller.request_cast(SLOT_V, Vector2.ZERO), "the second charge is still there")
	assert_false(_controller.request_cast(SLOT_V, Vector2.ZERO))
	assert_eq(_controller.last_refusal, AbilityController.REFUSE_COOLING)
	_controller.tick(4.0)
	assert_eq(_controller.charges(SLOT_V), 1)
	assert_true(_controller.request_cast(SLOT_V, Vector2.ZERO))


func test_a_duplicate_pickup_raises_the_rank_up_to_three() -> void:
	var meteor := _ability(&"meteor_call", 4.0)
	_controller.assign(SLOT_Q, meteor)
	watch_signals(_controller)
	assert_eq(_controller.rank_up(meteor), 2)
	assert_eq(_controller.rank_up(_ability(&"meteor_call", 4.0)), 3,
		"the match is by id, not by resource instance")
	assert_eq(_controller.rank(SLOT_Q), 3)
	assert_signal_emit_count(_controller, "rank_changed", 2)


func test_a_duplicate_of_a_rank_three_ability_converts_to_gold() -> void:
	var meteor := _ability(&"meteor_call", 4.0)
	_controller.assign(SLOT_Q, meteor)
	_controller.rank_up(meteor)
	_controller.rank_up(meteor)
	watch_signals(_controller)
	assert_eq(_controller.rank_up(meteor), AbilityController.RANK_TO_GOLD)
	assert_eq(_controller.rank(SLOT_Q), 3, "rank 3 does not change")
	assert_signal_emitted_with_parameters(_controller, "gold_converted",
		[AbilityController.GOLD_PER_MAX_RANK_DUPLICATE])
	assert_signal_not_emitted(_controller, "rank_changed")


func test_a_pickup_of_an_ability_not_slotted_is_not_a_rank_up() -> void:
	_controller.assign(SLOT_Q, _ability(&"meteor_call", 4.0))
	watch_signals(_controller)
	assert_eq(_controller.rank_up(_ability(&"flame_dash", 6.0)), AbilityController.RANK_NOT_HELD)
	assert_eq(_controller.rank(SLOT_Q), 1)
	assert_eq(_controller.rank_up(null), AbilityController.RANK_NOT_HELD)
	assert_signal_not_emitted(_controller, "rank_changed")
	assert_signal_not_emitted(_controller, "gold_converted")


func test_a_non_finite_aim_point_is_refused_and_spends_nothing() -> void:
	# The refusal id is written as its string, so a red run fails on the assert.
	watch_signals(Events)
	_controller.assign(SLOT_Q, _ability(&"meteor_call", 4.0))
	var bad_aims: Array[Vector2] = [Vector2(NAN, 0.0), Vector2(0.0, NAN), Vector2(INF, 0.0), Vector2(-INF, 0.0)]
	for aim: Vector2 in bad_aims:
		assert_false(_controller.request_cast(SLOT_Q, aim), "the aim %s is refused" % str(aim))
		assert_eq(_controller.last_refusal, &"not_finite", "the refusal names the non-finite aim")
		assert_eq(_controller.charges(SLOT_Q), 1, "a refused aim spends no charge")
		assert_eq(_controller.cooldown_fraction(SLOT_Q), 0.0, "a refused aim starts no cooldown")
		assert_null(_controller.last_cast, "a refused aim spawns no cast")
	assert_signal_not_emitted(Events, "ability_cast", "a refused aim announces no cast")


func test_a_client_cannot_cast_and_spends_nothing() -> void:
	# Swap in a client API for this test only, as test_affix_host_only.gd does, so
	# the host guard in request_cast is the one that refuses the cast.
	var default_api: MultiplayerAPI = get_multiplayer()
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", CLIENT_PORT), OK, "the client peer opens")
	var client_api := SceneMultiplayer.new()
	client_api.multiplayer_peer = client_peer
	get_tree().set_multiplayer(client_api, get_path())
	_controller.assign(SLOT_Q, _ability(&"meteor_call", 4.0))
	assert_false(_controller.request_cast(SLOT_Q, Vector2.ZERO))
	assert_eq(_controller.last_refusal, AbilityController.REFUSE_NOT_HOST)
	assert_eq(_controller.charges(SLOT_Q), 1, "a refused client cast spends nothing")
	assert_eq(_controller.cooldown_fraction(SLOT_Q), 0.0)
	get_tree().set_multiplayer(default_api, get_path())
	client_peer.close()
