extends GutTest
## Potions (SPEC-run-economy "Potions", W5-B3): slots from the Alchemist level,
## the four types, starting potions, refill, and the `potion` action.

const PEER_ID: int = 1

var _harness: EffectHarness = null
var _player: Player = null
var _controller: PotionController = null
var _used: Array[StringName] = []
var _forwarded: Array[int] = []


func before_each() -> void:
	NetworkManager.start_solo()
	_harness = EffectHarness.new(self)
	_harness.setup()
	_player = _harness.make_player()
	_player.peer_id = PEER_ID
	var run: RunState = RunState.new(7, 1)
	run.add_player(RunPlayerState.new(PEER_ID))
	GameState.run = run
	_controller = PotionController.new()
	_controller.player = _player
	add_child_autofree(_controller)
	_used.clear()
	_forwarded.clear()
	_controller.potion_used.connect(_on_used)
	_controller.interaction_forwarded.connect(_on_forwarded)


func after_each() -> void:
	EffectHarness.reset_globals()


func _on_used(_peer_id: int, potion_id: StringName) -> void:
	_used.append(potion_id)


func _on_forwarded(peer_id: int) -> void:
	_forwarded.append(peer_id)


func _slice() -> RunPlayerState:
	return GameState.run.get_player(PEER_ID)


func _block() -> StatBlock:
	return _player.get_node(^"StatBlock") as StatBlock


# --- data and pure rules -----------------------------------------------------


func test_the_four_potion_types_load() -> void:
	for id: StringName in [&"heal", &"cleanse", &"haste", &"shield"]:
		var data: PotionData = PotionController.data_for(id)
		assert_not_null(data, "%s loads" % id)
		assert_eq(data.id, id)


func test_potion_numbers_match_the_spec() -> void:
	assert_almost_eq(PotionController.data_for(&"heal").heal_fraction, 0.35, 0.0001)
	assert_almost_eq(PotionController.data_for(&"haste").speed_bonus, 0.3, 0.0001)
	assert_almost_eq(PotionController.data_for(&"haste").duration, 10.0, 0.0001)
	assert_eq(PotionController.data_for(&"shield").absorb_hits, 3)


func test_slots_follow_the_alchemist_level() -> void:
	assert_eq(PotionController.slots_for_alchemist_level(0), 0)
	assert_eq(PotionController.slots_for_alchemist_level(1), 1)
	assert_eq(PotionController.slots_for_alchemist_level(3), 3)
	assert_eq(PotionController.slots_for_alchemist_level(9), 3, "capped at three")


func test_heal_is_thirty_five_percent_plus_mastery() -> void:
	assert_eq(PotionController.heal_amount(100.0, 0.35, 0), 35)
	assert_eq(PotionController.heal_amount(100.0, 0.35, 2), 65)


func test_starting_potions_respect_slots_and_unlocked_types() -> void:
	var potions: Dictionary = {
		PlayerProfile.POTION_SLOTS: 2,
		PlayerProfile.POTION_TYPES: ["heal", "haste"],
		PlayerProfile.POTION_STARTING: ["heal", "shield", "haste", "heal"],
	}
	var belt: Array[StringName] = PotionController.starting_potions(potions)
	assert_eq(belt, [&"heal", &"haste"] as Array[StringName], "shield is locked, and two slots fill")


func test_default_profile_starts_with_no_potions() -> void:
	assert_true(PotionController.starting_potions(PlayerProfile.defaults().potions).is_empty())


func test_add_to_belt_stops_at_the_slot_count() -> void:
	var belt: Array[StringName] = []
	assert_true(PotionController.add_to_belt(belt, 1, &"heal"))
	assert_false(PotionController.add_to_belt(belt, 1, &"haste"), "belt full")
	assert_false(PotionController.add_to_belt(belt, 3, &"not_a_potion"))
	assert_eq(belt.size(), 1)


func test_refill_restores_the_starting_loadout() -> void:
	var belt: Array[StringName] = []
	var starting: Array[StringName] = [&"heal", &"cleanse"]
	PotionController.refill(belt, 2, starting)
	assert_eq(belt, starting)
	belt.clear()
	PotionController.refill(belt, 1, starting)
	assert_eq(belt.size(), 1, "never past the slots")


# --- the action --------------------------------------------------------------


func test_use_with_an_empty_belt_does_nothing() -> void:
	assert_eq(_controller.use(), &"")
	assert_true(_used.is_empty())


func test_heal_restores_thirty_five_percent_and_consumes_the_potion() -> void:
	_block().current_hp_ratio = 0.5
	_slice().potions = [&"heal"]
	assert_eq(_controller.use(), &"heal")
	assert_almost_eq(_block().current_hp_ratio, 0.85, 0.0001)
	assert_true(_slice().potions.is_empty())
	assert_eq(_used, [&"heal"] as Array[StringName])


func test_heal_never_overfills() -> void:
	_block().current_hp_ratio = 0.9
	_slice().potions = [&"heal"]
	_controller.use()
	assert_almost_eq(_block().current_hp_ratio, 1.0, 0.0001)


func test_mastery_raises_the_heal() -> void:
	_block().current_hp_ratio = 0.0
	_controller.mastery_rank = 1
	_slice().potions = [&"heal"]
	_controller.use()
	assert_almost_eq(_block().current_hp_ratio, 0.5, 0.0001)


func test_haste_adds_thirty_percent_move_speed() -> void:
	var before: float = _block().get_value(StatBlock.Stat.MOVE_SPEED)
	_slice().potions = [&"haste"]
	_controller.use()
	assert_almost_eq(_block().get_value(StatBlock.Stat.MOVE_SPEED), before * 1.3, 0.001)


func test_haste_ends_when_its_source_is_removed() -> void:
	var before: float = _block().get_value(StatBlock.Stat.MOVE_SPEED)
	_slice().potions = [&"haste"]
	_controller.use()
	_controller._end_haste(_block(), _controller._haste_serial)
	assert_almost_eq(_block().get_value(StatBlock.Stat.MOVE_SPEED), before, 0.001)


func test_a_stale_haste_timer_does_not_end_a_renewed_haste() -> void:
	var before: float = _block().get_value(StatBlock.Stat.MOVE_SPEED)
	_slice().potions = [&"haste", &"haste"]
	_controller.use()
	var first_serial: int = _controller._haste_serial
	_controller.use()
	_controller._end_haste(_block(), first_serial)
	assert_almost_eq(_block().get_value(StatBlock.Stat.MOVE_SPEED), before * 1.3, 0.001, "first timer is stale")
	_controller._end_haste(_block(), _controller._haste_serial)
	assert_almost_eq(_block().get_value(StatBlock.Stat.MOVE_SPEED), before, 0.001)


func test_shield_absorbs_exactly_three_hits() -> void:
	_slice().potions = [&"shield"]
	_controller.use()
	assert_true(_controller.absorb_hit())
	assert_true(_controller.absorb_hit())
	assert_true(_controller.absorb_hit())
	assert_false(_controller.absorb_hit(), "the fourth hit lands")


func test_cleanse_is_consumed() -> void:
	_slice().potions = [&"cleanse"]
	assert_eq(_controller.use(), &"cleanse")
	assert_true(_slice().potions.is_empty())


func test_potions_are_drunk_in_belt_order() -> void:
	_slice().potions = [&"cleanse", &"shield"]
	_controller.use()
	assert_eq(_slice().potions, [&"shield"] as Array[StringName])


func test_a_downed_player_cannot_drink() -> void:
	_slice().potions = [&"heal"]
	_slice().is_downed = true
	assert_eq(_controller.use(), &"")
	assert_eq(_slice().potions.size(), 1, "the potion is kept")


func test_a_client_forwards_instead_of_drinking() -> void:
	_slice().potions = [&"heal"]
	NetworkManager.is_host = false
	assert_eq(_controller.use(), &"")
	NetworkManager.is_host = true
	assert_eq(_forwarded, [PEER_ID] as Array[int])
	assert_eq(_slice().potions.size(), 1)
