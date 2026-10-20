extends GutTest
## Tests for the six element combos (SPEC-stats-status, "Element combos";
## design doc section 6, "Element combos"). Owned by stats-status.
##
## The spec: "When a status is applied to a target that already has another
## element's status, the combo fires once, consumes the listed stacks, and emits
## `Events.combo_triggered`." This file walks the table's six rows — SHATTER,
## CONDUCT, BLIGHT_EXPLOSION, HEMORRHAGE, SUPERCONDUCT, COLLAPSE — one case
## each, against the real `StatusEffects` component on a `CharacterBody2D`
## double.
##
## What every case asserts, in the spec's own words: the combo fires **once**
## (the bus is counted, and a second emission fails the case), the listed stacks
## are **consumed** (read back off the target's own `StatusEffects`, never off a
## copy), and `Events.combo_triggered` carries the `Combo` payload with the row's
## own numbers. The two seams the world still owes — CONDUCT's connected water
## area and COLLAPSE's pull — are asserted as the *request* the component makes,
## because the providers are Dev A's and do not exist yet (**blocked on Dev A
## (W2-A1/W4-A1)**); a request is not claimed as a pull that moved anything.
##
## Sync: host-only, like the component it drives — a client peer that does not
## resolve statuses fires nothing (that seam is pinned in
## `tests/unit/test_status_effects.gd`).

const STATUS_NODE: NodePath = ^"StatusEffects"
const STATUS_NAME: StringName = &"StatusEffects"
const HEALTH_NODE: NodePath = ^"Health"
const STAT_BLOCK_NODE: NodePath = ^"StatBlock"
const STAT_BLOCK_NAME: StringName = &"StatBlock"
const SPEC_PATH: String = "res://specs/SPEC-stats-status.md"

const TPS: int = 60
const MAX_HP: float = 100.0
## A non-zero DEFENSE base, so SUPERCONDUCT's percent penalty has something to
## be a fraction of.
const BASE_DEFENSE: float = 20.0
const BASE_MOVE_SPEED: float = 120.0
const BASE_ATTACK_SPEED: float = 1.0

## The damage of the hit that applied the second element, so every derived
## number in the table below is a round one.
const TRIGGER_DAMAGE: int = 100

## The numbers this file expects, mirrored from the component's own constants so
## a balance change fails here rather than silently re-baselining the cases.
const SHATTER_BURST: int = 200
const BLIGHT_DAMAGE: int = 120
const BLIGHT_TOXIN_STACKS: int = 3

## Where the SHATTER/BLIGHT targets' neighbours sit: one inside the 64 px burst
## radius, one well outside it.
const NEAR_BURST: Vector2 = Vector2(32.0, 0.0)
const FAR_AWAY: Vector2 = Vector2(300.0, 0.0)

## The enemy doubles this file built, autofreed with the root they hang under.
var _root: Node
var _target: StatusEnemyStub
var _status: StatusEffects
var _health: StatusHealthStub
var _block: StatBlock

## Every `Events.combo_triggered` this file saw, in order, with its target and
## source.
var _combos: Array[Combo] = []
var _combo_targets: Array[Node] = []
var _combo_sources: Array[Node] = []


func before_each() -> void:
	# The host branch is the one on trial; a solo session makes it explicit
	# rather than an accident of the previous file's state.
	NetworkManager.start_solo()
	_combos.clear()
	_combo_targets.clear()
	_combo_sources.clear()
	Events.combo_triggered.connect(_on_combo_triggered)
	_root = Node.new()
	_root.name = &"ComboRoot"
	add_child_autofree(_root)
	_spawn_target()


func after_each() -> void:
	if Events.combo_triggered.is_connected(_on_combo_triggered):
		Events.combo_triggered.disconnect(_on_combo_triggered)
	_combos.clear()
	NetworkManager.disconnect_all()


## Builds the target every case drives: an enemy double at the origin carrying a
## real `StatBlock`, the `Health` double and the `StatusEffects` component under
## test. It is an enemy rather than a player because five of the six rows need a
## target that may hold FREEZE and UNRAVEL, which the spec forbids players.
func _spawn_target() -> void:
	_target = StatusEnemyStub.make(_root, Vector2.ZERO, int(MAX_HP))
	var block := StatBlock.new()
	block.name = STAT_BLOCK_NAME
	_target.add_child(block)
	block.base = {
		StatBlock.Stat.MAX_HP: MAX_HP,
		StatBlock.Stat.DEFENSE: BASE_DEFENSE,
		StatBlock.Stat.MOVE_SPEED: BASE_MOVE_SPEED,
		StatBlock.Stat.ATTACK_SPEED: BASE_ATTACK_SPEED,
	}
	var statuses := StatusEffects.new()
	statuses.name = STATUS_NAME
	_target.add_child(statuses)
	_block = block
	_health = _target.health
	_status = statuses


## Adds another enemy double `at` (world position) carrying a `Health` double,
## and returns it.
func _spawn_enemy(at: Vector2, max_hp: int = 100) -> StatusEnemyStub:
	return StatusEnemyStub.make(_root, at, max_hp)


## The statuses present on the *target* — the "read off the target" half of the
## consumption criterion.
func _target_status() -> StatusEffects:
	return _target.get_node(STATUS_NODE) as StatusEffects


func _on_combo_triggered(target: Node, combo: Combo, source: Node) -> void:
	_combos.append(combo)
	_combo_targets.append(target)
	_combo_sources.append(source)


## Asserts the one emission the spec promises for `kind`, and returns its
## payload. A second emission is a failure of the "fires once" clause, so this
## checks the count rather than searching the list.
func _assert_fired_once(kind: Combo.Kind) -> Combo:
	assert_eq(_combos.size(), 1, "the combo fires once for one application, not %d times" % _combos.size())
	if _combos.is_empty():
		return null
	var combo: Combo = _combos[0]
	assert_eq(combo.kind, kind, "the combo is %s" % Combo.NAMES.get(kind, &"?"))
	assert_eq(_combo_targets[0], _target, "combo_triggered names the target the status landed on")
	return combo


# --- the table itself --------------------------------------------------------

func test_the_combo_enum_names_match_the_specs_table_rows() -> void:
	var spec := FileAccess.get_file_as_string(SPEC_PATH)
	assert_gt(spec.length(), 0, "SPEC-stats-status is readable")
	var names: Array = Combo.Kind.keys()
	assert_eq(names.size(), 6, "the spec's Element combos table names six combos")
	for expected: String in ["SHATTER", "CONDUCT", "BLIGHT_EXPLOSION", "HEMORRHAGE", "SUPERCONDUCT", "COLLAPSE"]:
		assert_true(names.has(expected), "%s is a member of Combo.Kind" % expected)
		assert_true(spec.contains("| `%s` |" % expected), "and SPEC-stats-status lists a %s row" % expected)


func test_the_combo_table_numbers_match_the_specs_rows() -> void:
	assert_eq(StatusEffects.SHATTER_BURST_FRACTION, 2.0, "SHATTER bursts 200% of the trigger damage")
	assert_eq(StatusEffects.SHATTER_RADIUS, 64.0, "SHATTER reaches 64 px")
	assert_eq(StatusEffects.BLIGHT_PER_STACK, 0.4, "BLIGHT_EXPLOSION is 40% per Toxin stack")
	assert_eq(StatusEffects.SUPERCONDUCT_DEFENSE, -0.30, "SUPERCONDUCT is -30% Defense")
	assert_eq(StatusEffects.SUPERCONDUCT_SECONDS, 8.0, "SUPERCONDUCT lasts 8 s")
	assert_eq(StatusEffects.HEMORRHAGE_SECONDS, 4.0, "HEMORRHAGE lasts 4 s")
	assert_eq(StatusEffects.COLLAPSE_RADIUS, 128.0, "COLLAPSE pulls from 128 px")


# --- SHATTER: Fire on Frost, or Frost on Fire --------------------------------

func test_shatter_bursts_for_twice_the_trigger_damage_and_consumes_the_frost() -> void:
	var near := _spawn_enemy(NEAR_BURST)
	var far := _spawn_enemy(FAR_AWAY)

	_status.apply_status(StatusEffects.Status.CHILL, 2)
	assert_true(_target_status().has(StatusEffects.Status.CHILL), "the frost is on the target before the fire lands")
	assert_eq(_combos.size(), 0, "one element on its own is not a combo")

	_status.apply_status(StatusEffects.Status.BURN, 1, null, TRIGGER_DAMAGE)
	var combo: Combo = _assert_fired_once(Combo.Kind.SHATTER)
	assert_not_null(combo)
	if combo == null:
		return
	assert_eq(combo.damage, SHATTER_BURST, "200% of the 100 trigger damage")
	assert_eq(combo.radius, StatusEffects.SHATTER_RADIUS, "the burst reports its 64 px reach")
	assert_eq(combo.stacks, 2, "the two consumed Chill stacks are reported")
	assert_false(_target_status().has(StatusEffects.Status.CHILL), "SHATTER leaves 0 Chill")
	assert_false(_target_status().has(StatusEffects.Status.FREEZE), "and 0 Freeze")
	assert_true(_target_status().has(StatusEffects.Status.BURN), "the fire that triggered it still lands")
	assert_eq(near.health.total_damage(), SHATTER_BURST, "the enemy inside 64 px takes the burst")
	assert_eq(far.health.total_damage(), 0, "the enemy outside it does not")
	assert_eq(_health.total_damage(), SHATTER_BURST, "and the burst is centred on the target itself")


func test_shatter_frost_on_fire_bursts_and_leaves_the_frost_for_the_next_fire() -> void:
	# The row consumes "Chill/Freeze" — the same past tense as the trigger, so the
	# stacks it spends are the ones the target already had. A Frost application on
	# a burning target fires the burst with no frost to spend, so the Chill it
	# brings survives to be shattered by the next Fire hit. Pinned here because
	# reading the consume in the present tense (spending the arriving status)
	# would also forbid BURN and CHILL/FREEZE from ever coexisting on a target,
	# which is the state SPEC-stats-status's own status-term composition needs.
	_status.apply_status(StatusEffects.Status.BURN, 1)
	_status.apply_status(StatusEffects.Status.CHILL, 1, null, TRIGGER_DAMAGE)
	var first: Combo = _assert_fired_once(Combo.Kind.SHATTER)
	assert_not_null(first)
	if first == null:
		return
	assert_eq(first.stacks, 0, "the target held no frost for the burst to consume")
	assert_eq(first.damage, SHATTER_BURST, "the burst is still 200% of the trigger damage")
	assert_true(_target_status().has(StatusEffects.Status.CHILL), "the Chill the application brought stays")
	assert_true(_target_status().has(StatusEffects.Status.BURN), "and the burn is not the consumed half either")

	_health.hits.clear()
	_status.apply_status(StatusEffects.Status.BURN, 1, null, TRIGGER_DAMAGE)
	assert_eq(_combos.size(), 2, "the next Fire hit is a second, separate combo")
	assert_eq(_combos[1].stacks, 1, "and this time there is a Chill stack to spend")
	assert_false(_target_status().has(StatusEffects.Status.CHILL), "SHATTER leaves 0 Chill")
	assert_eq(_health.total_damage(), SHATTER_BURST, "the second burst lands on the target too")


func test_shatter_consumes_a_freeze_the_way_it_consumes_chill() -> void:
	_status.apply_status(StatusEffects.Status.CHILL, 4)
	_status.apply_status(StatusEffects.Status.CHILL, 1)
	assert_true(_target_status().has(StatusEffects.Status.FREEZE), "five Chill stacks converted to FREEZE")
	# FREEZE is Frost, so a fire application shatters it.
	_status.apply_status(StatusEffects.Status.BURN, 1, null, TRIGGER_DAMAGE)
	_assert_fired_once(Combo.Kind.SHATTER)
	assert_false(_target_status().has(StatusEffects.Status.FREEZE), "SHATTER leaves 0 Freeze")


# --- CONDUCT: Storm on a wet target ------------------------------------------

func test_conduct_fires_on_a_wet_target_and_asks_the_water_area_seam() -> void:
	var in_water := _spawn_enemy(FAR_AWAY)
	var also_in_water := _spawn_enemy(FAR_AWAY * 2.0)
	_target.wet = true
	_target.water_targets = [in_water, also_in_water]

	_status.apply_status(StatusEffects.Status.SHOCK, 1, null, TRIGGER_DAMAGE)
	var combo: Combo = _assert_fired_once(Combo.Kind.CONDUCT)
	assert_not_null(combo)
	if combo == null:
		return
	assert_eq(combo.damage, _status.chain_damage(TRIGGER_DAMAGE), "the shock spreads for 30% of the trigger damage")
	assert_eq(_target.water_area_calls, 1, "the component asked the connected-water-area seam once")
	assert_eq(in_water.health.total_damage(), combo.damage, "every enemy in the water area is reached")
	assert_eq(also_in_water.health.total_damage(), combo.damage, "every enemy in the water area is reached")


func test_conduct_does_not_fire_on_a_dry_target() -> void:
	assert_false(_target.wet, "the double is dry by default")
	_status.apply_status(StatusEffects.Status.SHOCK, 1, null, TRIGGER_DAMAGE)
	assert_eq(_combos.size(), 0, "Storm on a dry target is not a combo")
	assert_eq(_target.water_area_calls, 0, "and nothing asks the water seam")


# --- BLIGHT_EXPLOSION: Fire on Toxin -----------------------------------------

func test_blight_explosion_consumes_every_toxin_stack() -> void:
	_status.apply_status(StatusEffects.Status.TOXIN, BLIGHT_TOXIN_STACKS)
	assert_eq(_target_status().stacks(StatusEffects.Status.TOXIN), BLIGHT_TOXIN_STACKS)
	_health.hits.clear()

	_status.apply_status(StatusEffects.Status.BURN, 1, null, TRIGGER_DAMAGE)
	var combo: Combo = _assert_fired_once(Combo.Kind.BLIGHT_EXPLOSION)
	assert_not_null(combo)
	if combo == null:
		return
	assert_eq(combo.damage, BLIGHT_DAMAGE, "40% of the trigger damage per Toxin stack")
	assert_eq(combo.stacks, BLIGHT_TOXIN_STACKS, "the consumed Toxin stacks are reported")
	assert_eq(_target_status().stacks(StatusEffects.Status.TOXIN), 0, "BLIGHT leaves 0 Toxin")
	assert_eq(_health.total_damage(), BLIGHT_DAMAGE, "the explosion lands on the toxined target")


# --- HEMORRHAGE: Shadow (Mark) on Bleed --------------------------------------

func test_hemorrhage_makes_bleed_ticks_crit_for_four_seconds() -> void:
	_target.velocity = Vector2(50.0, 0.0)
	_status.apply_status(StatusEffects.Status.BLEED, 1)
	await wait_physics_frames(TPS)
	assert_gt(_health.hit_count(), 0, "a moving, bleeding target ticks")
	for hit: HitData in _health.hits:
		assert_false(hit.is_crit, "Bleed does not crit on its own")
	var baseline: int = _health.total_damage()
	_health.hits.clear()

	_status.apply_status(StatusEffects.Status.MARK, 1, null, TRIGGER_DAMAGE)
	var combo: Combo = _assert_fired_once(Combo.Kind.HEMORRHAGE)
	assert_not_null(combo)
	if combo == null:
		return
	assert_eq(combo.duration, StatusEffects.HEMORRHAGE_SECONDS, "Bleed ticks crit for 4 s")
	assert_true(_status.bleed_ticks_crit(), "and the component says so")
	assert_true(_target_status().has(StatusEffects.Status.BLEED), "Bleed is not consumed by the combo")
	await wait_physics_frames(TPS)
	assert_gt(_health.hit_count(), 0, "the bleeding target still ticks")
	for hit: HitData in _health.hits:
		assert_true(hit.is_crit, "every Bleed tick in the window is critical")
	assert_almost_eq(float(_health.total_damage()), float(baseline) * 2.0, 1.0, "and the ticks deal double damage")

	await wait_physics_frames(int((StatusEffects.HEMORRHAGE_SECONDS - 1.0) * float(TPS)) + 20)
	assert_false(_status.bleed_ticks_crit(), "the window ends after its 4 s")


# --- SUPERCONDUCT: Frost on Storm, or Storm on Frost -------------------------

func test_superconduct_lowers_defense_for_eight_seconds() -> void:
	var base_defense: float = _block.get_value(StatBlock.Stat.DEFENSE)
	assert_eq(base_defense, BASE_DEFENSE)

	_status.apply_status(StatusEffects.Status.SHOCK, 1, null, TRIGGER_DAMAGE)
	_status.apply_status(StatusEffects.Status.CHILL, 1, null, TRIGGER_DAMAGE)
	var combo: Combo = _assert_fired_once(Combo.Kind.SUPERCONDUCT)
	assert_not_null(combo)
	if combo == null:
		return
	assert_eq(combo.duration, StatusEffects.SUPERCONDUCT_SECONDS)
	assert_almost_eq(_block.get_value(StatBlock.Stat.DEFENSE), base_defense * 0.7, 0.01, "-30% Defense")
	assert_almost_eq(_status.combo_remaining(Combo.Kind.SUPERCONDUCT), StatusEffects.SUPERCONDUCT_SECONDS, 0.2)

	await wait_physics_frames(int(StatusEffects.SUPERCONDUCT_SECONDS * float(TPS)) + 20)
	assert_almost_eq(_block.get_value(StatBlock.Stat.DEFENSE), base_defense, 0.01, "the penalty is released")
	assert_false(_status.combo_active(Combo.Kind.SUPERCONDUCT))


func test_superconduct_also_fires_storm_on_frost() -> void:
	_status.apply_status(StatusEffects.Status.CHILL, 1)
	_status.apply_status(StatusEffects.Status.SHOCK, 1, null, TRIGGER_DAMAGE)
	_assert_fired_once(Combo.Kind.SUPERCONDUCT)


# --- COLLAPSE: Void on any other status --------------------------------------

func test_collapse_pulls_every_enemy_within_128_px_of_the_target() -> void:
	var near := _spawn_enemy(Vector2(120.0, 0.0))
	var far := _spawn_enemy(FAR_AWAY)

	_status.apply_status(StatusEffects.Status.BURN, 1)
	_status.apply_status(StatusEffects.Status.TOXIN, 1)
	_status.apply_status(StatusEffects.Status.UNRAVEL, 1, null, TRIGGER_DAMAGE)
	var combo: Combo = _assert_fired_once(Combo.Kind.COLLAPSE)
	assert_not_null(combo)
	if combo == null:
		return
	assert_eq(combo.radius, StatusEffects.COLLAPSE_RADIUS)
	assert_eq(near.pulls.size(), 1, "the enemy inside 128 px is asked to pull")
	if near.pulls.size() == 1:
		assert_eq(near.pulls[0]["origin"], _target, "toward the target")
		assert_eq(near.pulls[0]["radius"], StatusEffects.COLLAPSE_RADIUS)
	assert_eq(far.pulls.size(), 0, "the enemy outside 128 px is not")


func test_collapse_does_not_fire_on_an_otherwise_bare_target() -> void:
	_status.apply_status(StatusEffects.Status.UNRAVEL, 1, null, TRIGGER_DAMAGE)
	assert_eq(_combos.size(), 0, "Void on nothing is not a combo")


# --- the negative half: re-applies and unlisted pairs ------------------------

func test_the_same_element_reapplied_fires_nothing() -> void:
	var pairs: Array = [
		StatusEffects.Status.BURN,
		StatusEffects.Status.CHILL,
		StatusEffects.Status.SHOCK,
		StatusEffects.Status.TOXIN,
		StatusEffects.Status.BLEED,
		StatusEffects.Status.UNRAVEL,
	]
	for status: int in pairs:
		# Each element gets a clean target, so the pair under test is the
		# re-apply and not a different element the previous iteration left behind.
		_status.clear_all()
		_status.apply_status(status, 1)
		_status.apply_status(status, 1)
		assert_eq(_combos.size(), 0, "re-applying %s is not a combo" % _status.status_name(status))
	# And the Chill cap's own conversion (Frost -> FREEZE) is not a combo either.
	_status.clear_all()
	_status.apply_status(StatusEffects.Status.CHILL, 4)
	_status.apply_status(StatusEffects.Status.CHILL, 1)
	assert_true(_target_status().has(StatusEffects.Status.FREEZE))
	assert_eq(_combos.size(), 0, "the Chill cap's FREEZE conversion fires nothing")


func test_a_pair_the_table_does_not_list_fires_nothing() -> void:
	# The table lists Fire on Toxin; the reverse is not a row, so it is not a
	# combo. Pinned so a well-meaning symmetry change fails here.
	_status.apply_status(StatusEffects.Status.BURN, 1)
	_status.apply_status(StatusEffects.Status.TOXIN, 1, null, TRIGGER_DAMAGE)
	assert_eq(_combos.size(), 0, "Toxin on Fire is not in the Element combos table")


func test_only_one_combo_fires_for_one_application() -> void:
	# The target carries Fire and Storm at once, so both SHATTER (Frost on Fire)
	# and SUPERCONDUCT (Frost on Storm) are *eligible* when the Frost lands. The
	# spec says the combo fires once, so exactly one emission, in the table's own
	# order.
	_status.apply_status(StatusEffects.Status.BURN, 1)
	_status.apply_status(StatusEffects.Status.SHOCK, 1)
	_status.apply_status(StatusEffects.Status.CHILL, 1, null, TRIGGER_DAMAGE)
	var combo: Combo = _assert_fired_once(Combo.Kind.SHATTER)
	assert_not_null(combo)


func test_a_client_peer_fires_no_combo() -> void:
	var client_target := _spawn_enemy(Vector2(700.0, 0.0))
	var client := StatusClientStub.new()
	client.name = STATUS_NAME
	client_target.add_child(client)
	client.apply_status(StatusEffects.Status.CHILL, 1)
	client.apply_status(StatusEffects.Status.BURN, 1, null, TRIGGER_DAMAGE)
	assert_eq(_combos.size(), 0, "a peer that does not resolve statuses fires nothing")


## A double that flips the host-only seam in one process, the same shape
## `test_status_effects.gd` uses: `resolves` is a field on the double, never on
## the production component.
class StatusClientStub extends StatusEffects:
	var resolves: bool = false

	func _resolves_statuses() -> bool:
		return resolves
