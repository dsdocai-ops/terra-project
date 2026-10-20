extends GutTest
## Tests for the `StatusEffects` component (SPEC-stats-status, "Status effects").
## Owned by stats-status.
##
## This file covers the component *core* (W4-B4, goal G20): the eight-row
## `Status` enum against the spec's own table rows, the apply/has/stacks/clear/
## clear_all API, both signals, the per-status tables (stack caps, durations,
## damage per second), the player gate from the spec's last line, the host-only
## gate, and — the point of the component — ticking that multiplies its delta by
## `TimeManager.scale_for(entity)`, so a time stop aimed at the enemies freezes a
## burning enemy's damage with it.
##
## The rows' individual behaviour beyond the core is G21 (BURN, CHILL -> FREEZE,
## MARK) and G22 (SHOCK, TOXIN, BLEED, UNRAVEL); this file pins the core those
## goals extend, so a change there fails here as well as in their own cases.

const STATUS_NODE: NodePath = ^"StatusEffects"
const STATUS_NAME: StringName = &"StatusEffects"
const HEALTH_NODE: NodePath = ^"Health"
const HEALTH_NAME: StringName = &"Health"
const STAT_BLOCK_NODE: NodePath = ^"StatBlock"
const STAT_BLOCK_NAME: StringName = &"StatBlock"
const SPEC_PATH: String = "res://specs/SPEC-stats-status.md"

## Every time source this file uses, cleared in after_each: autoload state is
## shared across the whole GUT run (LESSONS).
const SOURCES: Array[StringName] = [&"status-stop", &"status-slow"]
## The stop source, named once so the stop and the clear cannot drift.
const STOP_SOURCE: StringName = &"status-stop"

const TPS: int = 60
const MAX_HP: float = 100.0
## The fixture's speed bases, so a CHILL/FREEZE read of `StatBlock.get_value()`
## has a non-zero number to be a fraction of. A zero base would read 0 whether or
## not a penalty landed.
const BASE_MOVE_SPEED: float = 120.0
const BASE_ATTACK_SPEED: float = 1.0
## BURN at 5 stacks on a 100 HP target: 4 % per stack per second (SPEC table).
const BURN_STACKS: int = 5
const BURN_5_STACK_DPS: float = 20.0
## Damage over one second of frames is that rate plus/minus a frame or two of
## physics jitter; every window assertion is bounded rather than exact.
const DPS_TOLERANCE: float = 0.45

var _entity: CharacterBody2D
var _status: StatusEffects
var _health: StatusHealthStub
var _block: StatBlock

## The last `Events.status_applied` this file's listener saw.
var _bus_target: Node = null
var _bus_status: int = -1
var _bus_stacks: int = 0
var _bus_source: Node = null


## A double that flips the host-only seam in one process — the same shape
## `EffectHost`'s `_can_spawn()` client double uses (tests/unit/test_effect_spawn.gd).
## `resolves` is a field on the double, never on the production component.
class StatusClientStub extends StatusEffects:
	var resolves: bool = true

	func _resolves_statuses() -> bool:
		return resolves


func before_each() -> void:
	# The host branch is the one on trial; a solo session makes it explicit
	# rather than an accident of whatever the previous file left behind.
	NetworkManager.start_solo()
	_bus_target = null
	_bus_status = -1
	_bus_stacks = 0
	_bus_source = null
	Events.status_applied.connect(_on_bus_status_applied)
	_spawn()


func after_each() -> void:
	if Events.status_applied.is_connected(_on_bus_status_applied):
		Events.status_applied.disconnect(_on_bus_status_applied)
	_bus_target = null
	_bus_source = null
	for source: StringName in SOURCES:
		TimeManager.clear_source(source)
	NetworkManager.disconnect_all()


## Builds the entity every case drives: a body with a real `StatBlock`, the
## `Health` double and `component` — the component under test. Returns the
## component so a case can name its own double.
func _spawn(component: StatusEffects = null) -> StatusEffects:
	var node := CharacterBody2D.new()
	node.name = "Target"
	var block := StatBlock.new()
	block.name = STAT_BLOCK_NAME
	node.add_child(block)
	var health := StatusHealthStub.new()
	health.name = HEALTH_NAME
	health.max_hp = int(MAX_HP)
	health.current_hp = int(MAX_HP)
	node.add_child(health)
	var statuses: StatusEffects = StatusEffects.new() if component == null else component
	statuses.name = STATUS_NAME
	node.add_child(statuses)
	add_child_autofree(node)
	block.base = {
		StatBlock.Stat.MAX_HP: MAX_HP,
		StatBlock.Stat.MOVE_SPEED: BASE_MOVE_SPEED,
		StatBlock.Stat.ATTACK_SPEED: BASE_ATTACK_SPEED,
	}
	_entity = node
	_block = block
	_health = health
	_status = statuses
	return statuses


## Puts the fixture entity in the ENEMY time group, so `stop_enemies()` reaches
## it (`TimeManager.scale_for()` only walks the group a node joined).
func _register_enemy() -> void:
	TimeManager.set_group(_entity, TimeManager.Group.ENEMY)


func _on_bus_status_applied(target: Node, status: int, stacks: int, source: Node) -> void:
	_bus_target = target
	_bus_status = status
	_bus_stacks = stacks
	_bus_source = source


# --- the enum and the tables ---------------------------------------------

func test_the_status_enum_names_match_the_specs_table_rows() -> void:
	var spec := FileAccess.get_file_as_string(SPEC_PATH)
	assert_gt(spec.length(), 0, "SPEC-stats-status is readable")
	var names: Array = StatusEffects.Status.keys()
	assert_eq(names.size(), 8, "the seven spec rows plus FREEZE, which the spec lists as a row")
	for expected: String in ["BURN", "CHILL", "FREEZE", "SHOCK", "TOXIN", "MARK", "BLEED", "UNRAVEL"]:
		assert_true(names.has(expected), "%s is a member of Status" % expected)
		assert_true(spec.contains("| `%s` |" % expected), "and SPEC-stats-status lists a %s row" % expected)


func test_every_status_has_named_table_entries() -> void:
	for status: int in StatusEffects.Status.values():
		assert_true(StatusEffects.STATUS_NAMES.has(status), "%d has a table name" % status)
		assert_ne(StatusEffects.STATUS_NAMES[status], &"", "and it is not empty")
		assert_true(StatusEffects.STATUS_ELEMENT.has(status), "%d has an element" % status)
		assert_true(StatusEffects.STATUS_MAX_STACKS.has(status), "%d has a stack cap" % status)
		assert_true(StatusEffects.STATUS_DURATION.has(status), "%d has a duration" % status)


func test_the_documented_caps_match_the_specs_stacking_column() -> void:
	assert_eq(_status.max_stacks(StatusEffects.Status.BURN), StatusEffects.BURN_MAX_STACKS)
	assert_eq(StatusEffects.BURN_MAX_STACKS, 5, "BURN: stacks add DPS, max 5")
	assert_eq(StatusEffects.CHILL_MAX_STACKS, 5, "CHILL: stacks to 5")
	assert_eq(StatusEffects.BLEED_MAX_STACKS, 10, "BLEED: stacks to 10")
	assert_eq(StatusEffects.UNRAVEL_MAX_STACKS, 5, "UNRAVEL: stacks to 5")
	assert_eq(StatusEffects.TOXIN_MAX_STACKS, StatusEffects.UNLIMITED_STACKS, "TOXIN: unlimited stacks")
	assert_eq(StatusEffects.MARK_MAX_STACKS, 1, "MARK: single")
	assert_eq(StatusEffects.FREEZE_MAX_STACKS, 1, "FREEZE: single")
	assert_eq(StatusEffects.BURN_DURATION, 4.0, "BURN: 4 s")
	assert_eq(StatusEffects.TOXIN_DURATION, 6.0, "TOXIN: 6 s each")
	assert_eq(StatusEffects.FREEZE_DURATION, 2.0, "FREEZE: immobile 2 s")


func test_the_component_looks_for_the_scene_nodes_it_documents() -> void:
	assert_eq(StatusEffects.STAT_BLOCK_NODE, STAT_BLOCK_NODE, "the StatBlock child the fixture used")
	assert_eq(StatusEffects.HEALTH_NODE, HEALTH_NODE, "the Health child the fixture used")
	assert_eq(StatusEffects.HEALTH_METHOD, &"apply_damage", "Health's one entry point")


# --- apply / has / stacks / clear ----------------------------------------

func test_every_status_can_be_applied_seen_and_cleared() -> void:
	for status: int in StatusEffects.Status.values():
		# Single-stack rows (MARK, FREEZE, SHOCK) clamp the two that were asked
		# for; the cap is the StatusEffects table's own, not a literal here.
		var cap: int = _status.max_stacks(status)
		var expected: int = 2 if cap == StatusEffects.UNLIMITED_STACKS else mini(2, cap)
		assert_true(_status.apply_status(status, 2), "status %d applies" % status)
		assert_true(_status.has(status), "status %d is present" % status)
		assert_eq(_status.stacks(status), expected, "status %d holds %d stack(s)" % [status, expected])
		_status.clear(status)
		assert_false(_status.has(status), "status %d is gone" % status)
		assert_eq(_status.stacks(status), 0, "status %d reads no stacks" % status)


func test_apply_status_emits_status_applied_with_the_resulting_stack_count() -> void:
	watch_signals(_status)
	_status.apply_status(StatusEffects.Status.BURN, 1)
	assert_signal_emitted_with_parameters(_status, "status_applied", [StatusEffects.Status.BURN, 1])
	_status.apply_status(StatusEffects.Status.BURN, 2)
	assert_signal_emitted_with_parameters(_status, "status_applied", [StatusEffects.Status.BURN, 3], -1)


func test_reapplying_adds_stacks_up_to_the_cap_and_refreshes_the_duration() -> void:
	_status.apply_status(StatusEffects.Status.BURN, 3)
	_status.apply_status(StatusEffects.Status.BURN, 3)
	assert_eq(_status.stacks(StatusEffects.Status.BURN), StatusEffects.BURN_MAX_STACKS,
		"stacks stop at the cap")
	await wait_physics_frames(30)
	var aged := _status.remaining(StatusEffects.Status.BURN)
	assert_lt(aged, StatusEffects.BURN_DURATION, "the duration had started running down")
	_status.apply_status(StatusEffects.Status.BURN, 1)
	assert_eq(_status.stacks(StatusEffects.Status.BURN), StatusEffects.BURN_MAX_STACKS,
		"a re-apply at the cap adds nothing")
	assert_almost_eq(_status.remaining(StatusEffects.Status.BURN), StatusEffects.BURN_DURATION, 0.05,
		"but it refreshes the duration rather than stacking it")


func test_uncapped_statuses_keep_stacking() -> void:
	_status.apply_status(StatusEffects.Status.TOXIN, 8)
	assert_eq(_status.stacks(StatusEffects.Status.TOXIN), 8, "TOXIN is unlimited")


func test_single_stack_statuses_do_not_stack() -> void:
	_status.apply_status(StatusEffects.Status.MARK, 1)
	_status.apply_status(StatusEffects.Status.MARK, 3)
	assert_eq(_status.stacks(StatusEffects.Status.MARK), 1, "MARK stays single")
	_status.apply_status(StatusEffects.Status.FREEZE, 2)
	assert_eq(_status.stacks(StatusEffects.Status.FREEZE), 1, "FREEZE stays single")


func test_clear_reports_the_expiry_and_clear_all_empties_every_status() -> void:
	_status.apply_status(StatusEffects.Status.BURN, 1)
	_status.apply_status(StatusEffects.Status.CHILL, 2)
	watch_signals(_status)
	_status.clear(StatusEffects.Status.BURN)
	assert_signal_emitted_with_parameters(_status, "status_expired", [StatusEffects.Status.BURN])
	assert_true(_status.has(StatusEffects.Status.CHILL), "clearing one leaves the rest")
	_status.clear_all()
	assert_false(_status.has(StatusEffects.Status.CHILL))
	assert_eq(_status.active_statuses().size(), 0, "nothing is left active")
	assert_signal_emit_count(_status, "status_expired", 2, "both statuses announced their expiry")


func test_clearing_a_status_that_is_not_there_does_nothing() -> void:
	watch_signals(_status)
	_status.clear(StatusEffects.Status.BURN)
	assert_signal_emit_count(_status, "status_expired", 0, "no expiry is announced for a status nobody has")


func test_an_unknown_status_id_is_refused() -> void:
	watch_signals(_status)
	for bogus: int in [StatusEffects.Status.values().size(), 99, -1]:
		assert_false(_status.apply_status(bogus, 1), "status id %d is not a Status" % bogus)
		assert_eq(_status.active_statuses().size(), 0, "and nothing was applied")
	assert_signal_emit_count(_status, "status_applied", 0, "and nothing was announced")


func test_non_positive_stacks_are_refused() -> void:
	assert_false(_status.apply_status(StatusEffects.Status.BURN, 0), "0 stacks is not an application")
	assert_false(_status.apply_status(StatusEffects.Status.BURN, -3), "-3 stacks is not an application")
	assert_false(_status.has(StatusEffects.Status.BURN))


func test_remaining_reads_the_scaled_time_left() -> void:
	_status.apply_status(StatusEffects.Status.BURN, 1)
	assert_almost_eq(_status.remaining(StatusEffects.Status.BURN), StatusEffects.BURN_DURATION, 0.01)
	assert_eq(_status.remaining(StatusEffects.Status.MARK), 0.0, "a status nobody has has no time left")
	await wait_physics_frames(30)
	assert_lt(_status.remaining(StatusEffects.Status.BURN), StatusEffects.BURN_DURATION)


# --- the player gate ------------------------------------------------------

func test_a_player_never_receives_mark_unravel_or_freeze() -> void:
	_entity.add_to_group(StatusEffects.PLAYER_TAG)
	assert_true(_status.is_player(), "the entity carries the player tag")
	for allowed: int in [StatusEffects.Status.BURN, StatusEffects.Status.CHILL,
			StatusEffects.Status.TOXIN, StatusEffects.Status.BLEED]:
		assert_true(_status.apply_status(allowed, 1), "a player can be given status %d" % allowed)
	for forbidden: int in [StatusEffects.Status.MARK, StatusEffects.Status.UNRAVEL,
			StatusEffects.Status.FREEZE]:
		assert_false(_status.apply_status(forbidden, 1), "a player is never given status %d" % forbidden)
		assert_false(_status.has(forbidden))


func test_an_entity_without_the_tag_is_treated_as_an_enemy() -> void:
	assert_false(_status.is_player(), "nothing here reads a script class: an untagged entity is not a player")
	for status: int in StatusEffects.Status.values():
		assert_true(_status.apply_status(status, 1), "so it can be given status %d" % status)
		assert_true(_status.allows(status))
		_status.clear_all()


# --- ticking on scaled time -----------------------------------------------

func test_burn_ticks_damage_through_health_in_proportion_to_stacks() -> void:
	_status.apply_status(StatusEffects.Status.BURN, BURN_STACKS)
	await wait_physics_frames(TPS)
	var dealt := float(_health.total_damage())
	assert_between(dealt, BURN_5_STACK_DPS * (1.0 - DPS_TOLERANCE), BURN_5_STACK_DPS * (1.0 + DPS_TOLERANCE),
		"5 stacks of BURN on 100 HP deal 20 damage a second")
	assert_eq(_health.last_element(), HitData.Element.FIRE, "the tick is tagged with the status's element")
	assert_true(_health.hits[_health.hit_count() - 1].tags.has(StatusEffects.STATUS_TAG),
		"and marked as a status tick rather than a connecting hit")


func test_the_tick_fraction_is_taken_from_the_stat_blocks_max_hp() -> void:
	_block.base = {StatBlock.Stat.MAX_HP: MAX_HP / 2.0}
	_status.apply_status(StatusEffects.Status.BURN, 1)
	await wait_physics_frames(TPS)
	# 4 % of 50 HP is 2 damage a second, half of the same status on the fixture's 100 HP.
	assert_between(float(_health.total_damage()), 4.0 * 0.5 * (1.0 - DPS_TOLERANCE),
		4.0 * 0.5 * (1.0 + DPS_TOLERANCE), "max HP is read from the StatBlock, not assumed")


func test_a_stopped_enemy_takes_no_status_damage_and_keeps_its_stacks() -> void:
	_register_enemy()
	TimeManager.stop_enemies(3.0, STOP_SOURCE)
	_status.apply_status(StatusEffects.Status.BURN, BURN_STACKS)
	await wait_physics_frames(TPS)
	assert_eq(_health.total_damage(), 0, "scaled time is 0, so no status damage is dealt")
	assert_eq(_status.stacks(StatusEffects.Status.BURN), BURN_STACKS, "and the status did not age")
	assert_true(_status.has(StatusEffects.Status.BURN))
	TimeManager.clear_source(STOP_SOURCE)
	await wait_physics_frames(TPS)
	assert_gt(_health.total_damage(), 0, "clearing the stop resumes the ticks")


func test_a_slow_cuts_the_status_damage_in_proportion() -> void:
	_register_enemy()
	TimeManager.slow_enemies(0.5, 3.0, &"status-slow")
	_status.apply_status(StatusEffects.Status.BURN, BURN_STACKS)
	await wait_physics_frames(TPS)
	assert_between(float(_health.total_damage()), BURN_5_STACK_DPS * 0.5 * (1.0 - DPS_TOLERANCE),
		BURN_5_STACK_DPS * 0.5 * (1.0 + DPS_TOLERANCE), "half speed halves the damage over the same window")


func test_a_status_expires_after_its_duration_of_scaled_time() -> void:
	_status.apply_status(StatusEffects.Status.FREEZE, 1)
	watch_signals(_status)
	await wait_physics_frames(int(StatusEffects.FREEZE_DURATION * float(TPS)) + 20)
	assert_signal_emitted_with_parameters(_status, "status_expired", [StatusEffects.Status.FREEZE])
	assert_false(_status.has(StatusEffects.Status.FREEZE), "2 s of scaled time ends a freeze")
	assert_eq(_status.remaining(StatusEffects.Status.FREEZE), 0.0)


func test_a_status_with_no_expiry_waits_for_the_hit_that_consumes_it() -> void:
	_status.apply_status(StatusEffects.Status.MARK, 1)
	await wait_physics_frames(int(StatusEffects.FREEZE_DURATION * float(TPS)) + 20)
	assert_true(_status.has(StatusEffects.Status.MARK), "MARK has no timer: it is consumed, not expired (G21)")


func test_a_peer_that_does_not_resolve_statuses_deals_none() -> void:
	var client := _spawn(StatusClientStub.new()) as StatusClientStub
	assert_true(client.apply_status(StatusEffects.Status.BURN, BURN_STACKS))
	assert_true(client.has(StatusEffects.Status.BURN), "the stacks a peer displays are its own business")
	client.resolves = false
	await wait_physics_frames(TPS)
	assert_eq(_health.total_damage(), 0, "but only a peer that resolves statuses deals the damage")
	assert_eq(client.stacks(StatusEffects.Status.BURN), BURN_STACKS, "the tracked status is untouched")


func test_a_client_peers_component_applies_nothing() -> void:
	var client := _spawn(StatusClientStub.new()) as StatusClientStub
	client.resolves = false
	assert_false(client.apply_status(StatusEffects.Status.BURN, 1), "application is the host's decision")
	assert_false(client.has(StatusEffects.Status.BURN))


# --- the Events bus -------------------------------------------------------

func test_applying_a_status_reaches_the_events_bus() -> void:
	var applicator := Node.new()
	add_child_autofree(applicator)
	_status.apply_status(StatusEffects.Status.BURN, 2, applicator)
	assert_eq(_bus_target, _entity, "the bus names the entity the status landed on")
	assert_eq(_bus_status, StatusEffects.Status.BURN)
	assert_eq(_bus_stacks, 2)
	assert_eq(_bus_source, applicator, "and the effect that applied it")


func test_a_refused_application_reaches_the_events_bus_not_at_all() -> void:
	_entity.add_to_group(StatusEffects.PLAYER_TAG)
	_status.apply_status(StatusEffects.Status.MARK, 1)
	assert_eq(_bus_status, -1, "the bus heard nothing at all")


# --- G21: BURN, CHILL -> FREEZE, and MARK ---------------------------------
#
# The four spec rows the Week 4 relics drive (Ember Boots burns, Frostwalkers
# chill, Assassin's Mark marks). The core above pins the tables; this section
# pins each row's own behaviour: BURN's per-stack DPS and expiry, CHILL's
# StatBlock slow and its 5th-stack conversion, FREEZE's immobility, action lock,
# one-shot double and Chill clear, and MARK's single stack consumed by the next
# hit. 4 % / -12 % / 2 s / single are the spec table's numbers, read from the
# component's constants rather than repeated here.

## The damage a window of frames dealt, with one frame or two of physics jitter
## allowed either way — the same bound the core's ticking cases use.
func _assert_dps(expected: float, note: String) -> void:
	var dealt := float(_health.total_damage())
	assert_between(dealt, expected * (1.0 - DPS_TOLERANCE), expected * (1.0 + DPS_TOLERANCE), note)


func test_burn_deals_four_percent_of_max_hp_per_second_per_stack() -> void:
	assert_almost_eq(_status.damage_per_second(StatusEffects.Status.BURN, 1), MAX_HP * 0.04, 0.001,
		"BURN's rate is 4 % of max HP per second per stack")
	assert_almost_eq(_status.damage_per_second(StatusEffects.Status.BURN, 5), MAX_HP * 0.04 * 5.0, 0.001,
		"and five stacks deal five times that")
	_status.apply_status(StatusEffects.Status.BURN, 1)
	await wait_physics_frames(TPS)
	_assert_dps(MAX_HP * 0.04, "one stack of BURN on 100 HP deals 4 damage over a second")


func test_burn_stacks_add_dps_and_stop_at_five() -> void:
	_status.apply_status(StatusEffects.Status.BURN, 3)
	_status.apply_status(StatusEffects.Status.BURN, 4)
	assert_eq(_status.stacks(StatusEffects.Status.BURN), StatusEffects.BURN_MAX_STACKS,
		"BURN's stacks cap at 5")
	assert_almost_eq(_status.damage_per_second(StatusEffects.Status.BURN, 5), MAX_HP * 0.04 * 5.0, 0.001,
		"and each stack adds 4 % of max HP per second on top of the last")


func test_burn_reapplying_refreshes_the_duration_rather_than_stacking_it() -> void:
	_status.apply_status(StatusEffects.Status.BURN, 1)
	await wait_physics_frames(int(StatusEffects.BURN_DURATION * float(TPS)) * 3 / 4)
	assert_lt(_status.remaining(StatusEffects.Status.BURN), StatusEffects.BURN_DURATION * 0.5,
		"the clock is most of the way through its 4 s")
	_status.apply_status(StatusEffects.Status.BURN, 1)
	assert_almost_eq(_status.remaining(StatusEffects.Status.BURN), StatusEffects.BURN_DURATION, 0.05,
		"a re-apply resets the 4 s clock instead of adding a second one")
	assert_eq(_status.stacks(StatusEffects.Status.BURN), 2, "and does add its stack of DPS")


func test_burn_expires_after_four_seconds_of_scaled_time() -> void:
	_status.apply_status(StatusEffects.Status.BURN, StatusEffects.BURN_MAX_STACKS)
	watch_signals(_status)
	await wait_physics_frames(int(StatusEffects.BURN_DURATION * float(TPS)) + 20)
	assert_signal_emitted_with_parameters(_status, "status_expired", [StatusEffects.Status.BURN])
	assert_false(_status.has(StatusEffects.Status.BURN), "4 s of scaled time ends a burn")
	assert_eq(_status.remaining(StatusEffects.Status.BURN), 0.0)


func test_chill_slows_move_and_attack_speed_by_twelve_percent_per_stack() -> void:
	var chill_slow: float = StatusEffects.CHILL_SLOW_PER_STACK
	assert_almost_eq(chill_slow, 0.12, 0.001, "the spec row is -12 % per stack")
	_status.apply_status(StatusEffects.Status.CHILL, 2)
	assert_almost_eq(_block.get_value(StatBlock.Stat.MOVE_SPEED), BASE_MOVE_SPEED * (1.0 - 2.0 * chill_slow),
		0.001, "two stacks read -24 % move speed through the StatBlock")
	assert_almost_eq(_block.get_value(StatBlock.Stat.ATTACK_SPEED), BASE_ATTACK_SPEED * (1.0 - 2.0 * chill_slow),
		0.001, "and the same penalty on attack speed")
	assert_almost_eq(float(_block.base[StatBlock.Stat.MOVE_SPEED]), BASE_MOVE_SPEED, 0.001,
		"the base value was never written -- the penalty is a modifier")
	assert_almost_eq(float(_block.base[StatBlock.Stat.ATTACK_SPEED]), BASE_ATTACK_SPEED, 0.001,
		"attack speed's base is untouched too")


func test_chill_slow_follows_the_stack_count_and_lifts_with_the_status() -> void:
	_status.apply_status(StatusEffects.Status.CHILL, 1)
	var one_stack := _block.get_value(StatBlock.Stat.MOVE_SPEED)
	assert_almost_eq(one_stack, BASE_MOVE_SPEED * 0.88, 0.001, "one stack is -12 %")
	_status.apply_status(StatusEffects.Status.CHILL, 3)
	assert_eq(_status.stacks(StatusEffects.Status.CHILL), 4, "four stacks, below the conversion point")
	assert_almost_eq(_block.get_value(StatBlock.Stat.MOVE_SPEED), BASE_MOVE_SPEED * (1.0 - 4.0 * 0.12), 0.001,
		"a re-apply widens the slow to the new stack count")
	_status.clear(StatusEffects.Status.CHILL)
	assert_almost_eq(_block.get_value(StatBlock.Stat.MOVE_SPEED), BASE_MOVE_SPEED, 0.001,
		"clearing CHILL removes exactly its modifiers")


func test_the_fifth_chill_converts_the_entity_to_freeze_instead() -> void:
	_status.apply_status(StatusEffects.Status.CHILL, 4)
	assert_true(_status.has(StatusEffects.Status.CHILL), "four stacks are still CHILL")
	assert_false(_status.has(StatusEffects.Status.FREEZE))
	_status.apply_status(StatusEffects.Status.CHILL, 1)
	assert_false(_status.has(StatusEffects.Status.CHILL), "the 5th stack is FREEZE instead of CHILL")
	assert_true(_status.has(StatusEffects.Status.FREEZE), "the entity is frozen")
	assert_eq(_status.stacks(StatusEffects.Status.FREEZE), StatusEffects.FREEZE_MAX_STACKS, "single stack")
	assert_eq(_status.stacks(StatusEffects.Status.CHILL), 0, "no Chill is left behind")
	assert_almost_eq(_status.remaining(StatusEffects.Status.FREEZE), StatusEffects.FREEZE_DURATION, 0.05,
		"and it carries the full freeze duration")


func test_five_chill_applied_at_once_converts_the_same_way() -> void:
	_status.apply_status(StatusEffects.Status.CHILL, StatusEffects.CHILL_MAX_STACKS)
	assert_true(_status.has(StatusEffects.Status.FREEZE), "one call of 5 lands as FREEZE")
	assert_false(_status.has(StatusEffects.Status.CHILL))
	assert_almost_eq(_block.get_value(StatBlock.Stat.MOVE_SPEED), 0.0, 0.001,
		"and the Chill slow gives way to the freeze's immobility")


func test_a_player_caps_chill_at_five_without_freezing() -> void:
	_entity.add_to_group(StatusEffects.PLAYER_TAG)
	_status.apply_status(StatusEffects.Status.CHILL, StatusEffects.CHILL_MAX_STACKS)
	assert_true(_status.has(StatusEffects.Status.CHILL), "a player can be chilled")
	assert_eq(_status.stacks(StatusEffects.Status.CHILL), StatusEffects.CHILL_MAX_STACKS, "to the cap")
	assert_false(_status.has(StatusEffects.Status.FREEZE),
		"but never frozen: FREEZE is one of the three a player never receives")


func test_freeze_makes_the_entity_immobile_and_unable_to_act() -> void:
	_status.apply_status(StatusEffects.Status.FREEZE, 1)
	assert_almost_eq(_block.get_value(StatBlock.Stat.MOVE_SPEED), 0.0, 0.001, "move speed reads 0")
	assert_false(_status.can_act(), "and the entity cannot act")
	assert_almost_eq(float(_block.base[StatBlock.Stat.MOVE_SPEED]), BASE_MOVE_SPEED, 0.001,
		"again through a modifier, never a base write")
	await wait_physics_frames(int(StatusEffects.FREEZE_DURATION * float(TPS)) + 20)
	assert_false(_status.has(StatusEffects.Status.FREEZE), "2 s of scaled time ends the freeze")
	assert_almost_eq(_block.get_value(StatBlock.Stat.MOVE_SPEED), BASE_MOVE_SPEED, 0.001,
		"and the entity moves again")
	assert_true(_status.can_act(), "and acts again")


func test_freeze_doubles_the_next_hit_exactly_once() -> void:
	_status.apply_status(StatusEffects.Status.FREEZE, 1)
	assert_true(_status.freeze_double_ready(), "a frozen entity holds the pending double")
	assert_true(_status.consume_freeze_double(), "the next hit consumes it")
	assert_false(_status.freeze_double_ready(), "and no second hit is doubled")
	assert_false(_status.consume_freeze_double(), "consuming again finds nothing")
	assert_true(_status.has(StatusEffects.Status.FREEZE), "the freeze itself is still running")


func test_consuming_the_freeze_double_clears_all_chill() -> void:
	_status.apply_status(StatusEffects.Status.FREEZE, 1)
	_status.apply_status(StatusEffects.Status.CHILL, 2)
	assert_true(_status.has(StatusEffects.Status.CHILL), "Chill can build on a frozen entity")
	assert_true(_status.consume_freeze_double())
	assert_false(_status.has(StatusEffects.Status.CHILL), "the double clears all Chill as it lands")
	assert_almost_eq(_block.get_value(StatBlock.Stat.MOVE_SPEED), 0.0, 0.001,
		"the Chill slow goes with it -- the freeze alone is what holds the entity still")


func test_mark_forces_the_next_hit_to_crit_and_is_consumed() -> void:
	_status.apply_status(StatusEffects.Status.MARK, 1)
	assert_true(_status.mark_forces_crit(), "the mark guarantees a crit")
	assert_true(_status.consume_mark(), "the next damaging hit consumes it")
	assert_false(_status.mark_forces_crit(), "so the one after that is a normal roll")
	assert_false(_status.has(StatusEffects.Status.MARK))
	assert_false(_status.consume_mark(), "there is nothing left to consume")


func test_reapplying_mark_does_not_stack_or_rearm() -> void:
	_status.apply_status(StatusEffects.Status.MARK, 1)
	_status.apply_status(StatusEffects.Status.MARK, 3)
	assert_eq(_status.stacks(StatusEffects.Status.MARK), 1, "MARK is a single stack however many are applied")
	assert_true(_status.mark_forces_crit())
	_status.apply_status(StatusEffects.Status.MARK, 2)
	assert_true(_status.has(StatusEffects.Status.MARK), "a re-apply is still just the one mark")
	assert_true(_status.consume_mark(), "and it is still consumed exactly once")