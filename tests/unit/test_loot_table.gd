extends GutTest
## `LootTable` — the weighted drop table every chest, breakable, enemy and shop
## rolls through — run-economy, W4-B8 (PLAN G13 / raw G40).
##
## SPEC-run-economy, "Chests, breakables, mining nodes": "`LootTable` Resource:
## weighted entries `{kind, id or rarity, weight, min, max}`. Chest rarity tiers
## common/rare/legendary; ... Luck stat raises rarity rolls: `rarity_roll +=
## LUCK * 0.01`." and, in "Testing": "Unit `test_loot_table.gd`: weights, Luck
## effect, determinism with seed."
##
## The distribution case runs on the committed fixture
## `tests/helpers/loot_table_fixture.tres` — 60/25/10/5 across gold, ore, echo
## and a relic — with a fixed seed, so the shares are a property of the table and
## of the implementation rather than of this machine's luck. The fixture lives
## under `tests/helpers/`, never under `data/`: it is test content, not shipped
## content.
##
## Owned by run-economy. Sync: none (pure logic; the roll itself is host-only).

const TABLE_PATH: String = "res://scripts/data/loot_table.gd"
const FIXTURE_PATH: String = "res://tests/helpers/loot_table_fixture.tres"

## The spec's own roll count for the distribution gate.
const DISTRIBUTION_ROLLS: int = 10000
## The spec's own tolerance: "within 2% of weights".
const DISTRIBUTION_TOLERANCE: float = 0.02
## One fixed seed for every statistical case, so the numbers below are a
## property of the code and not of the wall clock.
const DISTRIBUTION_SEED: int = 20261020
## The `Stat.LUCK` values the Luck cases assert at.
const NO_LUCK: float = 0.0
const LUCK_FIVE: float = 5.0
const LUCK_TEN: float = 10.0
const LUCK_HUGE: float = 10000.0
## A Luck high enough that the shifted rarity roll is pinned to the top of the
## table: 100 points buy exactly the whole 0..1 axis.
const LUCK_PINNED: float = 100.0


func _table() -> LootTable:
	var table := load(FIXTURE_PATH) as LootTable
	assert_not_null(table, "%s loads as a LootTable" % FIXTURE_PATH)
	return table


func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _tally_kinds(table: LootTable, rolls: int, luck: float, seed_value: int) -> Dictionary[StringName, int]:
	var rng := _seeded(seed_value)
	var tally: Dictionary[StringName, int] = {}
	for roll_index: int in range(rolls):
		var result: Dictionary = table.roll(rng, luck)
		var kind: StringName = result.get("kind", &"")
		tally[kind] = int(tally.get(kind, 0)) + 1
	return tally


## The fixture's own entry weights, read back off the table so the expected
## shares have one home (the fixture) instead of a second literal in this file.
func _expected_shares(table: LootTable) -> Dictionary[StringName, float]:
	var shares: Dictionary[StringName, float] = {}
	var total: float = table.total_weight()
	for entry: LootTable.Entry in table.entry_list():
		shares[entry.kind] = entry.weight / total
	return shares


func _sequence(table: LootTable, count: int, seed_value: int, luck: float = 0.0) -> Array[String]:
	var rng := _seeded(seed_value)
	var out: Array[String] = []
	for result: Dictionary in table.roll_many(count, rng, luck):
		out.append("%s|%s|%d|%d" % [
			String(result.get("kind", &"")),
			String(result.get("id", &"")),
			int(result.get("rarity", LootTable.RARITY_NONE)),
			int(result.get("amount", 0)),
		])
	return out


# --- the interface ---------------------------------------------------------

func test_the_loot_table_is_the_specs_own_interface() -> void:
	var script := load(TABLE_PATH) as GDScript
	assert_not_null(script, "%s loads, so every case here runs against the shipped file" % TABLE_PATH)
	if script == null:
		return
	assert_eq(script.get_instance_base_type(), "Resource", "SPEC-run-economy: `LootTable` Resource")
	var names: Array[String] = []
	for method: Dictionary in script.get_script_method_list():
		names.append(String(method["name"]))
	assert_true(names.has("roll"), "`roll(rng, luck)` is the interface the spec names")
	assert_true(names.has("roll_many"), "`roll_many()` rolls a table several times")
	assert_true(names.has("entry_list"), "`entry_list()` converts the exported boundary data")
	assert_true(names.has("shifted_rarity_roll"), "the spec's `rarity_roll += LUCK * 0.01` has one home")
	assert_true(names.has("rarity_for_roll"), "and the tier table behind it")


func test_the_fixture_carries_the_specs_entry_shape() -> void:
	var table := _table()
	if table == null:
		return
	var entries: Array[LootTable.Entry] = table.entry_list()
	assert_eq(entries.size(), 4, "the fixture has the four entries SPEC-run-economy's shape describes")
	for entry: LootTable.Entry in entries:
		assert_true(Pickup.KINDS.has(entry.kind), "%s is one of Pickup's six kinds" % entry.kind)
		assert_gt(entry.weight, 0.0, "%s carries a weight" % entry.kind)
		assert_lte(entry.min_amount, entry.max_amount, "%s has an ordered range" % entry.kind)
		var names_a_fixed_id: bool = entry.id != &""
		var rolls_a_rarity: bool = entry.rarity != LootTable.RARITY_NONE
		assert_false(
			names_a_fixed_id and rolls_a_rarity,
			"%s names `id` or `rarity`, never both" % entry.kind
		)


func test_the_chest_tiers_are_the_specs_three() -> void:
	assert_eq(
		LootTable.CHEST_TIERS,
		[RelicData.Rarity.COMMON, RelicData.Rarity.RARE, RelicData.Rarity.LEGENDARY] as Array[int],
		"SPEC-run-economy: \"Chest rarity tiers common/rare/legendary\""
	)
	assert_true(LootTable.is_chest_tier(RelicData.Rarity.RARE), "rare is a chest tier")
	assert_false(LootTable.is_chest_tier(RelicData.Rarity.CURSED), "cursed is not a chest tier")


func test_the_luck_constant_matches_the_relic_rollers() -> void:
	assert_almost_eq(
		LootTable.LUCK_SHIFT_PER_POINT,
		0.01,
		1e-9,
		"the spec's term is `LUCK * 0.01`"
	)
	assert_almost_eq(
		LootTable.LUCK_SHIFT_PER_POINT,
		RelicRoller.LUCK_SHIFT_PER_POINT,
		1e-9,
		"the same sentence drives the relic roller, so the two cannot drift"
	)


# --- weights and ranges ----------------------------------------------------

func test_the_weighted_distribution_over_ten_thousand_rolls_is_within_two_percent() -> void:
	var table := _table()
	if table == null:
		return
	var tally: Dictionary[StringName, int] = _tally_kinds(table, DISTRIBUTION_ROLLS, NO_LUCK, DISTRIBUTION_SEED)
	var total: int = 0
	for kind: StringName in tally.keys():
		total += tally[kind]
	assert_eq(total, DISTRIBUTION_ROLLS, "every roll returned an entry, so the shares are over the whole 10 000")

	var expected: Dictionary[StringName, float] = _expected_shares(table)
	for kind: StringName in expected.keys():
		var want: float = expected[kind]
		var got: float = float(tally.get(kind, 0)) / float(total)
		assert_almost_eq(
			got,
			want,
			DISTRIBUTION_TOLERANCE,
			"%s rolls at its weight %.3f (got %.3f)" % [kind, want, got]
		)


func test_min_and_max_ranges_are_respected() -> void:
	var table := _table()
	if table == null:
		return
	var rng := _seeded(DISTRIBUTION_SEED)
	var seen: Dictionary[int, bool] = {}
	for roll_index: int in range(1000):
		var result: Dictionary = table.roll(rng, NO_LUCK)
		if StringName(result.get("kind", &"")) != Pickup.KIND_GOLD:
			continue
		var amount: int = int(result.get("amount", 0))
		assert_between(amount, 1, 5, "the gold entry's range is 1 to 5")
		seen[amount] = true
	assert_true(seen.has(1), "the low end of the range is reachable")
	assert_true(seen.has(5), "and so is the high end")


func test_min_equals_max_is_deterministic() -> void:
	var table := _table()
	if table == null:
		return
	var rng := _seeded(DISTRIBUTION_SEED)
	var echo_rolls: int = 0
	for roll_index: int in range(500):
		var result: Dictionary = table.roll(rng, NO_LUCK)
		if StringName(result.get("kind", &"")) != Pickup.KIND_ECHO:
			continue
		echo_rolls += 1
		assert_eq(int(result.get("amount", 0)), 1, "a min == max entry always drops exactly that amount")
	assert_gt(echo_rolls, 0, "the echo entry came up at least once, so the case did not pass vacuously")


func test_a_table_with_nothing_to_roll_returns_nothing() -> void:
	var table := LootTable.new()
	table.entries = [{ "kind": &"gold", "weight": 0.0, "min": 1, "max": 1 }]
	assert_true(table.roll(_seeded(1), NO_LUCK).is_empty(), "a weightless table has no entry to return")
	assert_eq(table.roll_many(3, _seeded(1), NO_LUCK).size(), 0, "and rolls nothing rather than erroring")


# --- Luck ------------------------------------------------------------------

func test_luck_raises_the_rarity_roll_by_exactly_one_percent_per_point() -> void:
	assert_almost_eq(
		LootTable.shifted_rarity_roll(0.25, NO_LUCK),
		0.25,
		1e-6,
		"no Luck moves the roll not at all"
	)
	assert_almost_eq(
		LootTable.shifted_rarity_roll(0.25, LUCK_FIVE),
		0.30,
		1e-6,
		"5 points buy 0.05"
	)
	assert_almost_eq(
		LootTable.shifted_rarity_roll(0.25, LUCK_TEN),
		0.35,
		1e-6,
		"10 points buy 0.10"
	)
	assert_almost_eq(
		LootTable.shifted_rarity_roll(0.99, LUCK_TEN),
		1.0,
		1e-6,
		"the shift is clamped at the top of the table"
	)
	assert_almost_eq(
		LootTable.shifted_rarity_roll(0.25, LUCK_HUGE),
		1.0,
		1e-6,
		"an absurd Luck tops the table out rather than reading past it"
	)


func test_the_rarity_roll_never_exceeds_the_top_tier() -> void:
	assert_eq(LootTable.rarity_for_roll(0.0), RelicData.Rarity.COMMON, "0.0 is the bottom tier")
	assert_eq(LootTable.rarity_for_roll(1.0), RelicData.Rarity.LEGENDARY, "1.0 is the top tier")
	assert_eq(
		LootTable.rarity_for_roll(LootTable.shifted_rarity_roll(1.0, LUCK_HUGE)),
		RelicData.Rarity.LEGENDARY,
		"a clamped shift lands on legendary, never past it"
	)
	assert_ne(
		LootTable.rarity_for_roll(1.0),
		RelicData.Rarity.CURSED,
		"cursed is taken at an altar, never rolled from a loot table"
	)


func test_luck_on_a_drop_rolls_the_rarity_up_to_the_top_tier() -> void:
	var table := _table()
	if table == null:
		return
	var lucky_rng := _seeded(DISTRIBUTION_SEED)
	var unlucky_rng := _seeded(DISTRIBUTION_SEED)
	var saw_below_top: bool = false
	for roll_index: int in range(200):
		var unlucky: Dictionary = table.roll(unlucky_rng, NO_LUCK)
		var lucky: Dictionary = table.roll(lucky_rng, LUCK_PINNED)
		if StringName(lucky.get("kind", &"")) == Pickup.KIND_RELIC:
			assert_eq(
				int(lucky.get("rarity", LootTable.RARITY_NONE)),
				RelicData.Rarity.LEGENDARY,
				"100 Luck pins every rarity roll to the top tier"
			)
		if StringName(unlucky.get("kind", &"")) == Pickup.KIND_RELIC:
			assert_ne(int(unlucky.get("rarity", LootTable.RARITY_NONE)), LootTable.RARITY_NONE, "a rarity entry reports a rarity")
			if int(unlucky.get("rarity", LootTable.RARITY_NONE)) != RelicData.Rarity.LEGENDARY:
				saw_below_top = true
	assert_true(saw_below_top, "at no Luck the same rolls are not all legendary, so the case above is not vacuous")


func test_a_rarity_entry_never_rolls_below_its_floor() -> void:
	var table := LootTable.new()
	table.entries = [{ "kind": &"relic", "rarity": RelicData.Rarity.EPIC, "weight": 1.0, "min": 1, "max": 1 }]
	var rng := _seeded(DISTRIBUTION_SEED)
	for roll_index: int in range(500):
		var rarity: int = int(table.roll(rng, NO_LUCK).get("rarity", LootTable.RARITY_NONE))
		assert_gte(rarity, RelicData.Rarity.EPIC, "the entry's own rarity is a floor")
		assert_lte(rarity, RelicData.Rarity.LEGENDARY, "and the table stops at legendary")
		assert_ne(rarity, RelicData.Rarity.CURSED, "cursed never comes off a loot table")


# --- determinism and the boundary ------------------------------------------

func test_two_runs_with_the_same_seed_produce_the_same_sequence() -> void:
	var table := _table()
	if table == null:
		return
	assert_eq(
		_sequence(table, 100, 4242),
		_sequence(table, 100, 4242),
		"the same seed replays the same drops, kind, id, rarity and amount"
	)
	assert_ne(
		_sequence(table, 100, 4242),
		_sequence(table, 100, 9876),
		"and a different seed is a different sequence, so the case above is not vacuous"
	)


func test_entries_are_converted_from_dictionaries_at_the_boundary() -> void:
	var table := LootTable.new()
	table.entries = [
		{ "kind": &"gold", "min": 5, "max": 2 },
		{ "kind": &"ore", "id": &"copper" },
	]
	var entries: Array[LootTable.Entry] = table.entry_list()
	assert_eq(entries.size(), 2, "both raw dictionaries convert")
	var gold: LootTable.Entry = entries[0]
	assert_eq(String(gold.kind), "gold", "the kind converts to a StringName")
	assert_eq(gold.weight, 1.0, "a missing weight defaults to 1")
	assert_eq(gold.min_amount, 2, "a reversed range is ordered")
	assert_eq(gold.max_amount, 5, "so max is never below min")
	assert_eq(gold.rarity, LootTable.RARITY_NONE, "an entry with no rarity names an id instead")
	var ore: LootTable.Entry = entries[1]
	assert_eq(String(ore.id), "copper", "a fixed id survives the boundary")
	assert_eq(ore.min_amount, 1, "a missing min defaults to 1")
	assert_eq(ore.max_amount, 1, "a missing max defaults to min")
