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
	block.base = {StatBlock.Stat.MAX_HP: MAX_HP}
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