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
##
## The G22 section below pins the remaining four rows: SHOCK's 30 %-of-trigger
## radius chain and its Lightning Rod bonus, TOXIN's unlimited per-stack tick,
## its halved healing (driven through the heal path, not read as a number) and
## its Plague Doctor's Mask exemption, BLEED's move gate and UNRAVEL's
## taken-damage multiplier as `Damage.compute` reads it.
##
## The G23 section at the end pins the component's own half of the closing
## paragraph — "Bosses have `status_resistance` in `BossData` (duration
## multiplier, Freeze becomes heavy Chill)": the exported field and its 1.0
## default, the multiplier on every row's applied duration, and the 0.0 branch
## where a FREEZE lands as heavy Chill instead (with the Chill-to-FREEZE
## conversion held back so the downgrade cannot be undone) — plus the whole
## target-side `status_mult` in one place, read by `Damage.compute`.

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

## The player scene and the marker effect the two relic cases attach: an
## `EffectHost` only accepts an effect script, and neither `lightning_rod` nor
## `plague_doctors_mask` exists as content until W4-B6 (G32…G35), so the cases
## attach a do-nothing `Effect` under the real relic's id — which is all the
## component's lookup asks about.
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const MARKER_EFFECT_SCRIPT: String = "res://tests/helpers/relic_marker_effect.gd"
const LIGHTNING_ROD: StringName = &"lightning_rod"
const PLAGUE_DOCTORS_MASK: StringName = &"plague_doctors_mask"
## The two attacker-side relics SPEC-stats-status's `status_mult` formula names
## (G23). Marker effects under the real ids, for the same reason.
const KINDLING: StringName = &"kindling"
const PERMAFROST: StringName = &"permafrost"

## A resistance that halves every duration: neither the default 1.0 nor the 0.0
## that downgrades Freeze, so both the multiplier and the downgrade branches stay
## distinguishable from "no resistance at all".
const HALF_RESISTANCE: float = 0.5

## Where the chain cases put their enemy doubles, relative to the shocked
## entity: two inside SHOCK's 96 px radius, one just outside it, and one more
## inside it to prove the two-target cap rather than only the radius.
const CHAIN_NEAR: Vector2 = Vector2(24.0, 0.0)
const CHAIN_SECOND: Vector2 = Vector2(48.0, 0.0)
const CHAIN_THIRD: Vector2 = Vector2(72.0, 0.0)
const CHAIN_FOURTH: Vector2 = Vector2(88.0, 0.0)
const CHAIN_FAR: Vector2 = Vector2(300.0, 0.0)
## The damage of the hit that applied the shock, so 30 % of it is a round number.
const TRIGGER_DAMAGE: int = 1000
const CHAIN_DAMAGE: int = 300

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
## The enemy doubles this case built, in creation order (autofreed with the
## entity they are parented under).
var _enemies: Array[StatusEnemyStub] = []

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
	_enemies.clear()
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


## Adds an enemy double `at` (relative to the fixture entity) and puts it in the
## `enemy` group SHOCK's chain query walks — the source Dev A's `enemies-ai`
## will register in (blocked on Dev A (W4-A1)). Autofreed with the entity it is
## parented under.
func _spawn_enemy(at: Vector2) -> StatusEnemyStub:
	var enemy := StatusEnemyStub.make(_entity, at)
	_enemies.append(enemy)
	return enemy


## A real player carrying one marker relic on its `EffectHost`, so a case can
## assert that the component reads the relic off the host that applied the
## status rather than from a hard-coded number. Returns the attached `Effect`,
## which is what a case passes as `apply_status`'s `source`.
func _holder_with_relic(id: StringName) -> Effect:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	player.name = "RelicHolder"
	add_child_autofree(player)
	return _attach_relic(EffectHostPlayer.install(player), id)


## Attaches one marker relic under `id` to `host` — a no-op `Effect`, since
## neither `lightning_rod` nor `plague_doctors_mask` is content until W4-B6 and
## the component's lookup only asks whether the id is held.
func _attach_relic(host: EffectHost, id: StringName) -> Effect:
	var relic := ContentData.new()
	relic.id = id
	relic.display_name = String(id)
	relic.effect_script = load(MARKER_EFFECT_SCRIPT) as GDScript
	return host.add(relic)


## The attacker side of the formula's two relic terms: a real player carrying
## every id in `ids` on one `EffectHost`, returned directly because that is what
## `incoming_damage_multiplier()` reads the attacker-side terms from.
func _host_with_relics(ids: Array[StringName]) -> EffectHost:
	var first := _holder_with_relic(ids[0])
	for i: int in range(1, ids.size()):
		_attach_relic(first.host, ids[i])
	return first.host


## The *target* half of the relic lookup: a real player carrying `id`, with this
## file's `StatusEffects` component and `Health` double swapped in for
## `player.tscn`'s bare `Node`s (**blocked on Dev A (W2-A1)**: the scene's
## `StatusEffects` and `Health` are placeholders until Dev A composes them, and
## `EffectHost.add()` refuses a host whose parent is not a `Player`). Returns the
## player's `StatusEffects`, so a case applies a status to the entity that holds
## the host and checks the relic was read from it.
func _target_player_with_relic(id: StringName) -> StatusEffects:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	player.name = "RelicTarget"
	add_child_autofree(player)
	for path: NodePath in [STATUS_NODE, HEALTH_NODE]:
		var bare: Node = player.get_node_or_null(path)
		if bare != null:
			player.remove_child(bare)
			bare.free()
	var health := StatusHealthStub.new()
	health.name = HEALTH_NAME
	health.max_hp = int(MAX_HP)
	health.current_hp = int(MAX_HP)
	player.add_child(health)
	var statuses := StatusEffects.new()
	statuses.name = STATUS_NAME
	player.add_child(statuses)
	_attach_relic(EffectHostPlayer.install(player), id)
	return statuses


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


# --- G22: SHOCK, TOXIN, BLEED, and UNRAVEL --------------------------------
#
# The remaining four spec rows. SHOCK carries the element the Storm combos and
# the Storm Sandals relic build on, TOXIN the Poison identity plus the healing
# penalty other systems read, BLEED the Blood identity and its move gate, and
# UNRAVEL the taken-damage multiplier `Damage.compute` folds into `status_mult`.
# Each row's numbers are the spec table's, asserted against the component's own
# constants and against the spec file's sentence.

func test_the_four_g22_rows_carry_the_spec_tables_numbers() -> void:
	var spec := FileAccess.get_file_as_string(SPEC_PATH)
	assert_true(spec.contains("On apply, chains 30% of trigger damage to up to 2 enemies within 96 px; Lightning Rod +2 chains"),
		"SHOCK's row, verbatim from SPEC-stats-status")
	assert_true(spec.contains("1.5% max HP per second per stack; healing received -50%; Plague Doctor's Mask disables expiry"),
		"TOXIN's row, verbatim")
	assert_true(spec.contains("While the target moves, 2% max HP per second per stack"),
		"BLEED's row, verbatim")
	assert_true(spec.contains("+10% all damage taken per stack"), "UNRAVEL's row, verbatim")
	assert_true(spec.contains("(+UNRAVEL stacks * 0.1)"), "and the formula's UNRAVEL term, verbatim")
	assert_almost_eq(StatusEffects.SHOCK_CHAIN_DAMAGE_FRACTION, 0.30, 0.001, "30 % of the trigger damage")
	assert_eq(StatusEffects.SHOCK_CHAIN_TARGETS, 2, "up to 2 enemies")
	assert_almost_eq(StatusEffects.SHOCK_CHAIN_RADIUS, 96.0, 0.001, "within 96 px")
	assert_eq(StatusEffects.LIGHTNING_ROD_CHAIN_BONUS, 2, "Lightning Rod +2 chains")
	assert_almost_eq(StatusEffects.TOXIN_DAMAGE_PER_SECOND, 0.015, 0.0001, "1.5 % max HP per stack per second")
	assert_almost_eq(StatusEffects.TOXIN_HEALING_MULTIPLIER, 0.5, 0.001, "healing received -50 %")
	assert_almost_eq(StatusEffects.BLEED_DAMAGE_PER_SECOND, 0.02, 0.0001, "2 % max HP per stack per second")
	assert_almost_eq(StatusEffects.UNRAVEL_DAMAGE_TAKEN_PER_STACK, 0.10, 0.0001, "+10 % damage taken per stack")


func test_shock_chains_thirty_percent_of_the_trigger_damage_to_the_nearest_two_in_range() -> void:
	var nearest := _spawn_enemy(CHAIN_NEAR)
	var second := _spawn_enemy(CHAIN_SECOND)
	var third := _spawn_enemy(CHAIN_THIRD)
	var far := _spawn_enemy(CHAIN_FAR)
	assert_true(_status.apply_status(StatusEffects.Status.SHOCK, 1, null, TRIGGER_DAMAGE),
		"the shock lands on the entity")
	assert_eq(nearest.health.total_damage(), CHAIN_DAMAGE, "the nearest enemy takes 30 % of the trigger damage")
	assert_eq(second.health.total_damage(), CHAIN_DAMAGE, "and so does the second")
	assert_eq(third.health.total_damage(), 0, "a third enemy inside the radius is past the two-target cap")
	assert_eq(far.health.total_damage(), 0, "300 px away is outside the 96 px radius")
	assert_eq(_health.total_damage(), 0, "the entity that carries the shock never chains to itself")
	assert_eq(nearest.health.last_element(), HitData.Element.STORM, "the chain carries the Storm element")
	assert_true(nearest.health.hits[0].tags.has(StatusEffects.STATUS_TAG),
		"and is marked as a status result rather than a connecting hit")


func test_a_shock_with_no_trigger_damage_chains_no_damage() -> void:
	var nearest := _spawn_enemy(CHAIN_NEAR)
	_status.apply_status(StatusEffects.Status.SHOCK, 1)
	assert_true(_status.has(StatusEffects.Status.SHOCK), "the shock still lands and still refreshes")
	assert_eq(nearest.health.total_damage(), 0, "30 % of nothing is nothing")


func test_reapplying_shock_refreshes_rather_than_stacking_or_redoubling() -> void:
	var nearest := _spawn_enemy(CHAIN_NEAR)
	_status.apply_status(StatusEffects.Status.SHOCK, 1, null, TRIGGER_DAMAGE)
	await wait_physics_frames(30)
	assert_lt(_status.remaining(StatusEffects.Status.SHOCK), StatusEffects.SHOCK_DURATION,
		"the clock had started running down")
	_status.apply_status(StatusEffects.Status.SHOCK, 1, null, TRIGGER_DAMAGE)
	assert_eq(_status.stacks(StatusEffects.Status.SHOCK), 1, "SHOCK is a refresh row: still one stack")
	assert_almost_eq(_status.remaining(StatusEffects.Status.SHOCK), StatusEffects.SHOCK_DURATION, 0.05,
		"and the re-apply resets its clock")
	assert_eq(nearest.health.hit_count(), 2, "each application chains once; neither is doubled")


func test_lightning_rod_adds_two_chains_read_off_the_effect_host() -> void:
	var rod := _holder_with_relic(LIGHTNING_ROD)
	assert_ne(rod, null, "the relic is attached to a player's EffectHost")
	var first := _spawn_enemy(Vector2(20.0, 0.0))
	var second := _spawn_enemy(Vector2(40.0, 0.0))
	var third := _spawn_enemy(Vector2(60.0, 0.0))
	var fourth := _spawn_enemy(Vector2(80.0, 0.0))
	_status.apply_status(StatusEffects.Status.SHOCK, 1, rod, TRIGGER_DAMAGE)
	for enemy: StatusEnemyStub in [first, second, third, fourth]:
		assert_eq(enemy.health.total_damage(), CHAIN_DAMAGE,
			"+2 chains reaches four enemies in range, not the two the base row allows")
	assert_eq(_status.chain_count(rod), StatusEffects.SHOCK_CHAIN_TARGETS + StatusEffects.LIGHTNING_ROD_CHAIN_BONUS,
		"and the count is read off the host, not hard-coded")


func test_the_base_chain_count_needs_no_lightning_rod() -> void:
	assert_eq(_status.chain_count(null), StatusEffects.SHOCK_CHAIN_TARGETS,
		"with no relic anywhere the chain count is the spec's 2")


func test_the_targets_own_effect_host_is_read_for_the_lightning_rod() -> void:
	# The criterion's own wording is "read from the *target's* effect host": the
	# target of the application is the entity that carries the shock, so when
	# that entity holds a host of its own the relic is read from there too. The
	# applier and the target are two different hosts and neither is the only one
	# that works.
	var target := _target_player_with_relic(LIGHTNING_ROD)
	var first := _spawn_enemy(Vector2(20.0, 0.0))
	var second := _spawn_enemy(Vector2(40.0, 0.0))
	var third := _spawn_enemy(Vector2(60.0, 0.0))
	var fourth := _spawn_enemy(Vector2(80.0, 0.0))
	assert_true(target.apply_status(StatusEffects.Status.SHOCK, 1, null, TRIGGER_DAMAGE),
		"a shock applied with no applier at all still lands and still chains")
	for enemy: StatusEnemyStub in [first, second, third, fourth]:
		assert_eq(enemy.health.total_damage(), CHAIN_DAMAGE,
			"and the +2 is read off the target's own host, four enemies deep")


func test_toxin_is_unlimited_and_ticks_one_and_a_half_percent_per_stack() -> void:
	_status.apply_status(StatusEffects.Status.TOXIN, 12)
	assert_eq(_status.stacks(StatusEffects.Status.TOXIN), 12, "TOXIN has no stack cap")
	assert_almost_eq(_status.damage_per_second(StatusEffects.Status.TOXIN, 4), MAX_HP * 0.015 * 4.0, 0.001,
		"four stacks read 6 damage a second on 100 HP")
	_status.clear(StatusEffects.Status.TOXIN)
	_status.apply_status(StatusEffects.Status.TOXIN, 4)
	await wait_physics_frames(TPS)
	_assert_dps(MAX_HP * 0.015 * 4.0, "and four stacks deal that over a second of frames")


func test_toxin_halves_the_healing_received_through_the_heal_path() -> void:
	_status.apply_status(StatusEffects.Status.TOXIN, 1)
	assert_almost_eq(_status.healing_multiplier(), StatusEffects.TOXIN_HEALING_MULTIPLIER, 0.001,
		"a toxic entity heals at half rate")
	_health.current_hp = 50
	assert_eq(_health.heal(20), 10, "and 20 healing lands as 10 -- asserted through the heal, not the number")
	assert_eq(_health.healed_total, 10, "the health component saw exactly the halved amount")
	_status.clear(StatusEffects.Status.TOXIN)
	assert_almost_eq(_status.healing_multiplier(), 1.0, 0.001, "with the toxin gone the penalty is lifted")
	assert_eq(_health.heal(20), 20, "and a clean entity heals in full")


func test_plague_doctors_mask_stops_toxin_expiring() -> void:
	var mask := _holder_with_relic(PLAGUE_DOCTORS_MASK)
	assert_ne(mask, null, "the mask is attached to a player's EffectHost")
	_status.apply_status(StatusEffects.Status.TOXIN, 2, mask)
	watch_signals(_status)
	await wait_physics_frames(int(StatusEffects.TOXIN_DURATION * float(TPS)) + 30)
	assert_true(_status.has(StatusEffects.Status.TOXIN),
		"the mask disables expiry: the toxin is still there after its 6 s clock")
	assert_eq(_status.stacks(StatusEffects.Status.TOXIN), 2, "with its stacks intact")
	assert_signal_not_emitted(_status, "status_expired", "and it never expired")


func test_toxin_expires_after_six_seconds_without_the_mask() -> void:
	_status.apply_status(StatusEffects.Status.TOXIN, 2)
	watch_signals(_status)
	await wait_physics_frames(int(StatusEffects.TOXIN_DURATION * float(TPS)) + 30)
	assert_false(_status.has(StatusEffects.Status.TOXIN),
		"without the mask the same 6 s of scaled time ends it")
	assert_signal_emitted_with_parameters(_status, "status_expired", [StatusEffects.Status.TOXIN])


func test_bleed_ticks_only_while_the_target_is_moving() -> void:
	_status.apply_status(StatusEffects.Status.BLEED, 5)
	_status.apply_status(StatusEffects.Status.BLEED, 8)
	assert_eq(_status.stacks(StatusEffects.Status.BLEED), StatusEffects.BLEED_MAX_STACKS,
		"BLEED stacks to 10 and stops there")
	var ten_stacks: float = MAX_HP * 0.02 * float(StatusEffects.BLEED_MAX_STACKS)
	_entity.velocity = Vector2.ZERO
	assert_false(_status.is_moving(), "a still entity reads as still")
	await wait_physics_frames(TPS)
	assert_eq(_health.total_damage(), 0, "so 60 frames of ten bleed stacks deal no damage at all")
	_entity.velocity = Vector2(60.0, 0.0)
	assert_true(_status.is_moving(), "a moving entity reads as moving")
	assert_almost_eq(_status.damage_per_second(StatusEffects.Status.BLEED, StatusEffects.BLEED_MAX_STACKS),
		ten_stacks, 0.001, "and ten stacks read 20 damage a second on 100 HP")
	await wait_physics_frames(TPS)
	_assert_dps(ten_stacks, "while it moves, ten stacks deal 20 damage over a second")


func test_unravel_stacks_to_five_and_adds_ten_percent_damage_taken_per_stack() -> void:
	assert_almost_eq(_status.damage_taken_multiplier(), 1.0, 0.001, "no UNRAVEL, no multiplier")
	_status.apply_status(StatusEffects.Status.UNRAVEL, 7)
	assert_eq(_status.stacks(StatusEffects.Status.UNRAVEL), StatusEffects.UNRAVEL_MAX_STACKS,
		"UNRAVEL stacks to 5 and stops there")
	assert_almost_eq(_status.damage_taken_multiplier(), 1.5, 0.001, "and adds 10 % damage taken per stack")


func test_damage_compute_reads_the_targets_unravel_multiplier() -> void:
	# `StatBlock` is a `Node`, so a bare `.new()` is an ObjectDB instance that
	# outlives the run: it is handed to GUT to free, the same way every other
	# fixture in this file is. (The suite used to report it as its one orphan.)
	var attacker: StatBlock = autofree(StatBlock.new())
	attacker.base = {StatBlock.Stat.ATTACK: 100.0}
	var plain := HitData.new()
	plain.base_damage = 100.0
	assert_eq(Damage.compute(attacker, _block, plain, null, null), 100,
		"a target with no UNRAVEL takes the raw damage")
	_status.apply_status(StatusEffects.Status.UNRAVEL, 3)
	var unravelled := HitData.new()
	unravelled.base_damage = 100.0
	assert_eq(Damage.compute(attacker, _block, unravelled, null, _status), 130,
		"three stacks take 30 % more, folded into status_mult")
	assert_false(unravelled.is_crit, "and that is the only term the target's statuses contribute so far")


# --- G23: the resistance field and the terms `Damage.compute` reads ----------
#
# SPEC-stats-status's closing paragraph: "Bosses have `status_resistance` in
# `BossData` (duration multiplier, Freeze becomes heavy Chill)". The `BossData`
# resource is bosses' to build; what this component owns is the field a boss
# hands its number to, so both halves of that sentence — the multiplier and the
# downgrade — are pinned here. The same section pins the formula's whole
# target-side term (`incoming_damage_multiplier()`) where the three parts live,
# so a term that is counted twice or dropped fails here as well as in
# test_damage.gd's composed golden row.

func test_status_resistance_is_an_exported_float_defaulting_to_full_duration() -> void:
	assert_almost_eq(StatusEffects.DEFAULT_STATUS_RESISTANCE, 1.0, 0.0001,
		"the default is a full duration: an entity resists nothing until its data says so")
	assert_almost_eq(_status.status_resistance, StatusEffects.DEFAULT_STATUS_RESISTANCE, 0.0001,
		"and a fresh component carries it")
	_status.status_resistance = HALF_RESISTANCE
	assert_almost_eq(_status.status_resistance, HALF_RESISTANCE, 0.0001, "it is settable at run time")
	var named := false
	for property: Dictionary in _status.get_property_list():
		if String(property["name"]) != "status_resistance":
			continue
		named = true
		assert_eq(int(property["type"]), TYPE_FLOAT, "the field is a float")
		assert_ne(int(property["usage"]) & PROPERTY_USAGE_EDITOR, 0,
			"and exported: a boss resource can set it from data, which is what makes it a boss field")
		assert_ne(int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE, 0, "it is this script's own")
	assert_true(named, "status_resistance is a property of the component")


func test_status_resistance_multiplies_every_applied_duration() -> void:
	_status.status_resistance = HALF_RESISTANCE
	var rows: Array[StatusEffects.Status] = [
		StatusEffects.Status.BURN,
		StatusEffects.Status.CHILL,
		StatusEffects.Status.FREEZE,
		StatusEffects.Status.SHOCK,
		StatusEffects.Status.TOXIN,
		StatusEffects.Status.BLEED,
		StatusEffects.Status.UNRAVEL,
	]
	for row: StatusEffects.Status in rows:
		_status.clear_all()
		assert_true(_status.apply_status(row, 1), "%s lands on a resistant entity" % _status.status_name(row))
		assert_almost_eq(_status.remaining(row), _status.duration(row) * HALF_RESISTANCE, 0.001,
			"%s runs for half its table duration" % _status.status_name(row))
	_status.clear_all()
	_status.status_resistance = 2.0
	_status.apply_status(StatusEffects.Status.BURN, 1)
	assert_almost_eq(_status.remaining(StatusEffects.Status.BURN),
		_status.duration(StatusEffects.Status.BURN) * 2.0, 0.001,
		"above 1.0 it lengthens them: the field is a multiplier, not a cap")


func test_the_downgrade_branch_is_resistance_at_or_below_zero() -> void:
	assert_false(_status.degrades_freeze(), "the default 1.0 is not the downgrade branch")
	_status.status_resistance = StatusEffects.NO_STATUS_RESISTANCE
	assert_true(_status.degrades_freeze(), "0.0 is the spec's downgrade branch: 'Freeze becomes heavy Chill'")
	_status.status_resistance = -1.0
	assert_true(_status.degrades_freeze(),
		"and so is anything below 0.0: a malformed resistance cannot smuggle a real freeze through")
	_status.status_resistance = 0.01
	assert_false(_status.degrades_freeze(), "while the smallest positive resistance keeps the real freeze")
	assert_true(_status.allows(StatusEffects.Status.FREEZE),
		"the downgrade is a transformation, not a refusal: the application is not gated out")


func test_a_fully_resistant_entity_takes_heavy_chill_instead_of_a_freeze() -> void:
	_status.status_resistance = StatusEffects.NO_STATUS_RESISTANCE
	assert_true(_status.apply_status(StatusEffects.Status.FREEZE, 1),
		"the application still lands -- 'rather than doing nothing'")
	assert_false(_status.has(StatusEffects.Status.FREEZE), "it is not a freeze")
	assert_true(_status.has(StatusEffects.Status.CHILL), "it is heavy Chill instead")
	assert_eq(_status.stacks(StatusEffects.Status.CHILL), StatusEffects.HEAVY_CHILL_STACKS,
		"at the heavy stack count, which is the Chill table's cap")
	assert_almost_eq(float(StatusEffects.HEAVY_CHILL_STACKS) * StatusEffects.CHILL_SLOW_PER_STACK, 0.6, 0.001,
		"five stacks is the 60 % slow that makes it 'heavy'")
	assert_almost_eq(_block.get_value(StatBlock.Stat.MOVE_SPEED), BASE_MOVE_SPEED * 0.4, 0.01,
		"so the entity is slowed, not stopped")
	assert_true(_status.can_act(), "and it can still act: a downgrade, not the lock a freeze is")
	assert_almost_eq(_status.remaining(StatusEffects.Status.CHILL),
		_status.duration(StatusEffects.Status.CHILL), 0.001,
		"the Chill runs its own full clock, since a 0.0 multiplier on the downgrade would be the doing-nothing the clause exists to avoid")


func test_a_fully_resistant_entity_is_never_converted_into_a_freeze_from_chill() -> void:
	_status.status_resistance = StatusEffects.NO_STATUS_RESISTANCE
	_status.apply_status(StatusEffects.Status.CHILL, StatusEffects.CHILL_MAX_STACKS)
	assert_true(_status.has(StatusEffects.Status.CHILL), "five Chill stay Chill on a fully resistant entity")
	assert_eq(_status.stacks(StatusEffects.Status.CHILL), StatusEffects.CHILL_MAX_STACKS, "at the cap")
	assert_false(_status.has(StatusEffects.Status.FREEZE),
		"and never convert: the downgrade must not be undone by the cap's own conversion")
	assert_true(_status.can_act(), "so the entity is slowed rather than locked")
	_status.clear_all()
	_status.status_resistance = HALF_RESISTANCE
	_status.apply_status(StatusEffects.Status.CHILL, StatusEffects.CHILL_MAX_STACKS)
	assert_true(_status.has(StatusEffects.Status.FREEZE),
		"half resistance still converts at the cap -- the skip is about 0.0, not about resistance generally")
	assert_almost_eq(_status.remaining(StatusEffects.Status.FREEZE),
		_status.duration(StatusEffects.Status.FREEZE) * HALF_RESISTANCE, 0.001,
		"and the converted freeze is scaled like any other application")


func test_the_other_rows_keep_no_clock_on_a_fully_resistant_entity() -> void:
	_status.status_resistance = StatusEffects.NO_STATUS_RESISTANCE
	_status.apply_status(StatusEffects.Status.BURN, 1)
	assert_almost_eq(_status.remaining(StatusEffects.Status.BURN), StatusEffects.NO_EXPIRY, 0.001,
		"every other row's duration is multiplied by 0.0, so it has no clock left")
	await wait_physics_frames(2)
	assert_false(_status.has(StatusEffects.Status.BURN),
		"and the next frame expires it: FREEZE's downgrade clause is the exception, not the rule")
	assert_almost_eq(_status.remaining(StatusEffects.Status.BURN), StatusEffects.NO_EXPIRY, 0.001,
		"with nothing left to read")


func test_the_multiplier_is_a_plain_one_with_neither_statuses_nor_relics() -> void:
	assert_almost_eq(_status.incoming_damage_multiplier(null), 1.0, 0.001,
		"no statuses and no attacking host: the formula's literal 1.0")
	assert_almost_eq(_status.incoming_damage_multiplier(_host_with_relics([KINDLING] as Array[StringName])), 1.0, 0.001,
		"and Kindling alone changes nothing without a burn to burn brighter")


func test_kindling_adds_a_quarter_to_a_burning_target_read_off_the_attacking_host() -> void:
	var kindling := _host_with_relics([KINDLING] as Array[StringName])
	_status.apply_status(StatusEffects.Status.BURN, 1)
	assert_almost_eq(_status.incoming_damage_multiplier(null), 1.0, 0.001,
		"an attacker with no Kindling gets no quarter for the burn")
	assert_almost_eq(_status.incoming_damage_multiplier(kindling),
		1.0 + StatusEffects.KINDLING_BURN_BONUS, 0.001, "with it: 1 + 0.25")
	assert_almost_eq(_status.damage_taken_multiplier(), 1.0, 0.001,
		"and UNRAVEL's own read stays independent of it")


func test_the_frozen_targets_double_is_spent_by_the_read_that_uses_it() -> void:
	_status.apply_status(StatusEffects.Status.FREEZE, 1)
	assert_almost_eq(_status.incoming_damage_multiplier(null), 2.0, 0.001, "the pending double: 1 + 1.0")
	assert_almost_eq(_status.incoming_damage_multiplier(null), 1.0, 0.001,
		"spent by that read, so the hit after it is a plain one")
	assert_true(_status.has(StatusEffects.Status.FREEZE), "the freeze itself is still running")


func test_permafrost_makes_the_freeze_bonus_survive_the_spending() -> void:
	var permafrost := _host_with_relics([PERMAFROST] as Array[StringName])
	_status.apply_status(StatusEffects.Status.FREEZE, 1)
	assert_almost_eq(_status.incoming_damage_multiplier(permafrost), 2.0, 0.001, "the first hit")
	assert_almost_eq(_status.incoming_damage_multiplier(permafrost), 2.0, 0.001,
		"and every hit after it: the relic's whole point")
	assert_almost_eq(_status.incoming_damage_multiplier(null), 1.0, 0.001,
		"while an attacker without it gets nothing -- the one-shot double was spent, not banked")


func test_the_three_terms_compose_on_the_target_side() -> void:
	var both := _host_with_relics([KINDLING, PERMAFROST] as Array[StringName])
	_status.apply_status(StatusEffects.Status.BURN, 1)
	_status.apply_status(StatusEffects.Status.FREEZE, 1)
	_status.apply_status(StatusEffects.Status.UNRAVEL, 5)
	assert_almost_eq(_status.incoming_damage_multiplier(both), 2.75, 0.001,
		"1 + 0.25 Kindling + 1.0 Permafrost + 0.5 for five UNRAVEL stacks")
	var kindling_only := _host_with_relics([KINDLING] as Array[StringName])
	assert_almost_eq(_status.incoming_damage_multiplier(kindling_only), 1.75, 0.001,
		"and with Kindling alone the double is gone: 1 + 0.25 + 0.5, each term read exactly once")