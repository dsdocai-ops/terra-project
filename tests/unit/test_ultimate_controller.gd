extends GutTest
## Tests for UltimateController (SPEC-abilities "UltimateController", W5-G6): the
## charge rule (0.5 per 1% of an enemy's max HP dealt, 2 per 1% of the owner's max
## HP taken), the clamp at 100, the refusal below 100, the spend that resets the
## meter and emits ultimate_used once, and the write into the owner's
## RunPlayerState slice. Owned by abilities. The player is the real scene, so the
## controller is the one a live player carries. Offline, the test process is the
## host, so the host-only handlers run. The two-peer case is in
## tests/integration/test_ultimate_two_peer.gd.

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const TARGET_MAX_HP: float = 200.0
const DEAL_HIT: int = 20
const TAKE_HIT: int = 10

var _player: Player
var _ultimate: UltimateController
var _target: Node2D


func before_each() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_ultimate = _player.get_node("UltimateController") as UltimateController
	_ultimate.set_physics_process(false)
	_target = _make_target()
	add_child_autofree(_target)


func after_each() -> void:
	GameState.run = null


## An enemy stand-in: a node with its own StatBlock and Health, so Health reads a
## known max HP. It is not a Player, so the dealt rule counts it.
func _make_target() -> Node2D:
	var target := Node2D.new()
	var stats := StatBlock.new()
	stats.name = "StatBlock"
	stats.base = {StatBlock.Stat.MAX_HP: TARGET_MAX_HP}
	target.add_child(stats)
	var health := Health.new()
	health.name = "Health"
	target.add_child(health)
	return target


func _hit(damage: int, target: Node, attacker: Player) -> HitInfo:
	var hit := HitInfo.new()
	hit.final_damage = damage
	hit.source = attacker
	hit.owner_player = attacker
	hit.target = target
	return hit


func _ultimate_data(is_ultimate: bool = true) -> AbilityData:
	var data := AbilityData.new()
	data.id = &"cave_in_test"
	data.is_ultimate = is_ultimate
	return data


func test_a_dealt_hit_charges_half_a_point_per_percent_of_the_targets_max_hp() -> void:
	Events.hit_landed.emit(_hit(DEAL_HIT, _target, _player))
	# 20 of 200 is 10%, and 0.5 per percent is 5.
	assert_almost_eq(_ultimate.meter, 5.0, 0.0001)


func test_a_taken_hit_charges_two_points_per_percent_of_the_owners_max_hp() -> void:
	var hit := _hit(TAKE_HIT, _player, null)
	Events.player_damaged.emit(_player, hit)
	# 10 of the player's 100 max HP is 10%, and 2 per percent is 20.
	assert_almost_eq(_ultimate.meter, 20.0, 0.0001)


func test_a_hit_the_player_did_not_deal_charges_nothing() -> void:
	Events.hit_landed.emit(_hit(DEAL_HIT, _target, null))
	assert_eq(_ultimate.meter, 0.0)


func test_a_hit_on_another_player_is_not_a_dealt_hit() -> void:
	Events.hit_landed.emit(_hit(DEAL_HIT, _player, _player))
	assert_eq(_ultimate.meter, 0.0, "a player is not an enemy, so hitting one charges nothing")


func test_a_hit_on_a_target_with_no_health_charges_nothing() -> void:
	var bare := Node2D.new()
	add_child_autofree(bare)
	Events.hit_landed.emit(_hit(DEAL_HIT, bare, _player))
	assert_eq(_ultimate.meter, 0.0)


func test_a_zero_damage_hit_charges_nothing() -> void:
	Events.hit_landed.emit(_hit(0, _target, _player))
	assert_eq(_ultimate.meter, 0.0)


func test_a_charge_of_nan_or_infinity_is_ignored() -> void:
	_ultimate.charge(NAN)
	_ultimate.charge(INF)
	_ultimate.charge(-INF)
	assert_eq(_ultimate.meter, 0.0, "a non-finite charge would poison the meter")


func test_the_meter_clamps_at_one_hundred() -> void:
	_ultimate.charge(500.0)
	assert_eq(_ultimate.meter, UltimateController.METER_MAX)


func test_a_request_below_one_hundred_is_refused_and_keeps_the_meter() -> void:
	_ultimate.assign_ultimate(_ultimate_data())
	_ultimate.charge(99.0)
	watch_signals(Events)
	assert_false(_ultimate.request_ultimate())
	assert_eq(_ultimate.last_refusal, UltimateController.REFUSE_NOT_FULL)
	assert_eq(_ultimate.meter, 99.0)
	assert_signal_not_emitted(Events, "ultimate_used")


func test_a_full_meter_with_no_ultimate_is_refused_and_keeps_the_meter() -> void:
	_ultimate.charge(100.0)
	assert_false(_ultimate.request_ultimate())
	assert_eq(_ultimate.last_refusal, UltimateController.REFUSE_NO_ULTIMATE)
	assert_eq(_ultimate.meter, 100.0)


func test_assign_refuses_data_that_is_not_an_ultimate() -> void:
	_ultimate.assign_ultimate(_ultimate_data(false))
	assert_null(_ultimate.ultimate, "a plain ability cannot sit in the ultimate slot")


func test_a_full_meter_spends_to_zero_and_emits_ultimate_used_once() -> void:
	var data := _ultimate_data()
	_ultimate.assign_ultimate(data)
	_ultimate.charge(100.0)
	watch_signals(Events)
	assert_true(_ultimate.request_ultimate())
	assert_eq(_ultimate.meter, 0.0, "the meter resets to 0 after use")
	assert_eq(_ultimate.last_refusal, UltimateController.REFUSE_NONE)
	assert_signal_emit_count(Events, "ultimate_used", 1, "the event is emitted once")
	assert_false(_ultimate.request_ultimate(), "a second press on an empty meter is refused")
	assert_signal_emit_count(Events, "ultimate_used", 1, "the refused press emits nothing")


func test_the_host_writes_the_meter_into_the_owners_run_slice() -> void:
	GameState.run = RunState.new()
	var slice := RunPlayerState.new(_player.peer_id)
	GameState.run.add_player(slice)
	assert_eq(slice.ultimate_meter, 0.0)
	_ultimate.charge(40.0)
	assert_almost_eq(slice.ultimate_meter, 40.0, 0.0001, "the slice reads the host's meter")
	_ultimate.charge(100.0)
	assert_eq(slice.ultimate_meter, 100.0)
	_ultimate.assign_ultimate(_ultimate_data())
	_ultimate.request_ultimate()
	assert_eq(slice.ultimate_meter, 0.0, "the slice follows the spend")


func test_a_negative_finite_charge_is_ignored() -> void:
	_ultimate.charge(20.0)
	_ultimate.charge(-5.0)
	assert_eq(_ultimate.meter, 20.0, "a finite negative charge would drain the meter")


func test_the_share_of_an_hp_pool_is_zero_when_the_pool_or_the_damage_is_empty() -> void:
	assert_almost_eq(_ultimate._percent_of(20, 200.0), 10.0, 0.0001, "20 of 200 is 10 percent")
	assert_eq(_ultimate._percent_of(20, 0.0), 0.0, "an empty HP pool gives no share")
	assert_eq(_ultimate._percent_of(0, 200.0), 0.0, "no damage gives no share")
	assert_eq(_ultimate._percent_of(-5, 200.0), 0.0, "negative damage gives no share")


func test_a_taken_hit_on_another_player_charges_nothing() -> void:
	var other := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(other)
	Events.player_damaged.emit(other, _hit(TAKE_HIT, other, null))
	assert_eq(_ultimate.meter, 0.0, "a hit on someone else's player is not this player's to charge from")


func test_a_null_hit_charges_nothing() -> void:
	Events.hit_landed.emit(null)
	Events.player_damaged.emit(_player, null)
	assert_eq(_ultimate.meter, 0.0)


func test_a_hit_with_no_target_charges_nothing() -> void:
	Events.hit_landed.emit(_hit(DEAL_HIT, null, _player))
	assert_eq(_ultimate.meter, 0.0)


func test_a_controller_with_no_player_charges_nothing_from_an_unattributed_hit() -> void:
	var orphan := UltimateController.new()
	add_child_autofree(orphan)
	Events.hit_landed.emit(_hit(DEAL_HIT, _target, null))
	assert_eq(orphan.meter, 0.0, "with no owner, a hit with no attribution must not match")


func test_a_controller_with_no_player_can_still_spend_a_full_meter() -> void:
	var orphan := UltimateController.new()
	add_child_autofree(orphan)
	orphan.assign_ultimate(_ultimate_data())
	orphan.charge(100.0)
	assert_true(orphan.request_ultimate(), "an orphan spends with no owner to cast for")
	assert_eq(orphan.meter, 0.0)


func test_a_full_meter_casts_the_ultimate_through_the_owners_ability_controller() -> void:
	var data := _ultimate_data()
	data.cast_scene = load("res://tests/helpers/fixture_cast.tscn") as PackedScene
	_ultimate.assign_ultimate(data)
	_ultimate.charge(100.0)
	assert_true(_ultimate.request_ultimate())
	var ability := _player.get_node("AbilityController") as AbilityController
	assert_true(ability.last_cast is FixtureCast, "the spend spawns the ultimate's cast on the owner's controller")


func test_an_ultimate_cast_refuses_a_non_finite_aim_and_null_data() -> void:
	var ability := _player.get_node("AbilityController") as AbilityController
	var data := _ultimate_data()
	data.cast_scene = load("res://tests/helpers/fixture_cast.tscn") as PackedScene
	assert_false(ability.cast_ultimate(data, Vector2(NAN, 0.0)), "a NaN aim is refused")
	assert_false(ability.cast_ultimate(data, Vector2(0.0, INF)), "an infinite aim is refused")
	assert_false(ability.cast_ultimate(null, Vector2.ZERO), "no ultimate data, no cast")
	assert_null(ability.last_cast, "a refused ultimate cast spawns nothing")


func test_a_controller_with_no_player_charges_and_sends_nothing() -> void:
	var orphan := UltimateController.new()
	add_child_autofree(orphan)
	orphan.charge(40.0)
	assert_eq(orphan.meter, 40.0, "the meter still counts with no owner to send it to")


func test_a_charge_with_a_run_that_holds_no_slice_for_the_owner_still_counts() -> void:
	GameState.run = RunState.new()
	_ultimate.charge(30.0)
	assert_eq(_ultimate.meter, 30.0, "a missing slice is skipped, not fatal")
	assert_null(GameState.run.get_player(_player.peer_id))


func test_a_controller_with_no_player_and_a_live_run_still_counts_the_meter() -> void:
	GameState.run = RunState.new()
	var orphan := UltimateController.new()
	add_child_autofree(orphan)
	orphan.charge(40.0)
	assert_eq(orphan.meter, 40.0, "with a run live and no owner, the slice write is skipped")
