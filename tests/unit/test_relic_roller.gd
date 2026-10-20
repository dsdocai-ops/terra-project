extends GutTest
## `RelicRoller` — the shared relic roll every chest, shop and Shrine uses —
## relics, W4-B5 (PLAN G4 / raw G28).
##
## SPEC-relics, "RelicData": "Rarity weights for Shrine rolls: common 60, rare
## 28, epic 10, legendary 2, adjusted by `Stat.LUCK` and Lucky Find (+5%/rank
## shift to higher tiers). **Cursed never roll at Shrines.**" and, in "Testing":
## "`test_relic_roller.gd`: rarity distribution over 10 000 rolls within 2% of
## weights, Luck shift, no duplicates past `max_stacks`, no cursed at shrines."
## SPEC-run-economy, "Loot tables", fixes the Luck term verbatim: "Luck stat
## raises rarity rolls: `rarity_roll += LUCK * 0.01`."
##
## The distribution, Luck and `max_stacks` cases run on a **synthetic candidate
## pool this test builds itself**, through `roll_from_pool()`, so the numbers are
## a property of the roller and not of how much content has landed. The pool is
## deliberately lopsided — several relics per tier with *different* `weight`
## values — so a lazier implementation that rolled on the relics' own weights and
## ignored the tier stage could not pass the distribution case. The real folder's
## path is covered too, and written so it says the same thing whether the folder
## is empty or full: the real call may only ever offer ids `data/relics/` holds.
##
## The distribution and "a cursed relic can roll when allowed" cases are driven
## by a **fixed seed**, so the shares are the same on every run and the test can
## never flake: the tolerance is a statement about the implementation, not about
## this machine's luck.
##
## Owned by relics. Sync: none (pure logic; the roll itself is host-only).
##

const ROLLER_PATH: String = "res://scripts/relics/relic_roller.gd"
const SPEC_RELICS_PATH: String = "res://specs/SPEC-relics.md"
const SPEC_RUN_ECONOMY_PATH: String = "res://specs/SPEC-run-economy.md"
const RELIC_DIR: String = "res://data/relics"
## Fixture `.tres` files are written here and removed in `after_each()`; never
## into `data/`.
const FIXTURE_DIR: String = "user://_relic_roller_fixtures"

## The spec's own roll count for the distribution gate.
const DISTRIBUTION_ROLLS: int = 10000
## The spec's own tolerance: "within 2% of weights".
const DISTRIBUTION_TOLERANCE: float = 0.02
## One fixed seed for every statistical case, so the numbers below are a
## property of the code and not of the wall clock.
const DISTRIBUTION_SEED: int = 20261020
## How many rolls the "a cursed relic can roll when a caller allows one" case
## makes: the cursed tier's share is a few percent, so a thousand rolls cannot
## miss it.
const CURSED_PROBE_ROLLS: int = 1000
## The `Stat.LUCK` values the Luck cases assert at.
const NO_LUCK: float = 0.0
const LUCK_TEN: float = 10.0
const LUCK_HUGE: float = 10000.0

var _fixture_paths: Array[String] = []
## Every bare node this test builds, freed in `after_each()` — a `Player` and a
## `StatBlock` are `Node`s and leak into the suite's orphan count otherwise
## (the G3a lesson).
var _nodes: Array[Node] = []


func before_each() -> void:
	# The player-seam cases read `GameState.run`, and the host is the only peer
	# allowed to open one. Explicit rather than inherited from the previous
	# file (autoloads are shared across a GUT run).
	NetworkManager.start_solo()


func after_each() -> void:
	for path: String in _fixture_paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_fixture_paths.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_DIR))
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	# Autoload state leaks across GUT files, so the run this test may have
	# started is always ended (LESSONS: reset `GameState.run` in `after_each`).
	# Guarded, because ending a run that was never opened is a warned no-op.
	if GameState.run != null:
		GameState.end_run(RunEndReason.Reason.ABORT)
	NetworkManager.disconnect_all()


## A bare `Player.new()` that is never added to the tree, so Dev A's `_ready`
## never runs (the double shape `test_run_end_defeat.gd` established). Owned by
## `after_each()`.
func _player(peer_id: int) -> Player:
	var player: Player = Player.new()
	player.peer_id = peer_id
	_nodes.append(player)
	return player


## `player` with a real `StatBlock` child installed, the way the player scene
## carries one — the node name `Effect` and `StatusEffects` look it up by.
func _with_stat_block(player: Player, luck: float) -> StatBlock:
	var block := StatBlock.new()
	block.name = String(Effect.STAT_BLOCK_NODE)
	block.base[StatBlock.Stat.LUCK] = luck
	player.add_child(block)
	return block


# --- helpers ---------------------------------------------------------------

func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "could not open %s" % path)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## One hand-built relic: no `.tres`, no effect script, no disk involved. The
## roller reads only `id`, `rarity`, `weight` and `max_stacks` from a candidate,
## which is the whole point of it being a data-driven roll.
func _relic(relic_id: String, rarity: RelicData.Rarity, weight: float = 1.0, max_stacks: int = 1) -> RelicData:
	var data := RelicData.new()
	data.id = StringName(relic_id)
	data.display_name = relic_id.capitalize()
	data.description = "Fixture relic."
	data.rarity = rarity
	data.kind = RelicData.Kind.PASSIVE
	data.max_stacks = max_stacks
	data.weight = weight
	return data


## The synthetic pool the statistical cases roll over: two relics per rollable
## tier, at *different* weights, so the intra-tier weight stage has something to
## do and the tier shares are still the tier shares. The CURSED relic is in the
## pool too, so `allow_cursed` has a candidate to admit or exclude.
func _pool() -> Array[RelicData]:
	var pool: Array[RelicData] = []
	pool.append(_relic("common_heavy", RelicData.Rarity.COMMON, 3.0))
	pool.append(_relic("common_light", RelicData.Rarity.COMMON, 1.0))
	pool.append(_relic("rare_heavy", RelicData.Rarity.RARE, 3.0))
	pool.append(_relic("rare_light", RelicData.Rarity.RARE, 1.0))
	pool.append(_relic("epic_heavy", RelicData.Rarity.EPIC, 3.0))
	pool.append(_relic("epic_light", RelicData.Rarity.EPIC, 1.0))
	pool.append(_relic("legendary_heavy", RelicData.Rarity.LEGENDARY, 3.0))
	pool.append(_relic("legendary_light", RelicData.Rarity.LEGENDARY, 1.0))
	pool.append(_relic("cursed_fixture", RelicData.Rarity.CURSED, 1.0))
	return pool


## `{id: RelicData}` for the pool, so a rolled id can be read back to its tier.
func _by_id(pool: Array[RelicData]) -> Dictionary[StringName, RelicData]:
	var index: Dictionary[StringName, RelicData] = {}
	for data: RelicData in pool:
		index[data.id] = data
	return index


func _seeded(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


## One fixed pool, rolled `rolls` times at `count` relics per roll, tallied by
## rarity. Returns `{rarity: count}`; CURSED is tallied under its own key so the
## "no cursed at a Shrine" case reads the same tally the distribution case does.
func _tally_rolls(
	pool: Array[RelicData],
	rolls: int,
	count: int,
	allow_cursed: bool,
	luck: float,
	seed_value: int,
) -> Dictionary[int, int]:
	var rng := _seeded(seed_value)
	var index := _by_id(pool)
	var tally: Dictionary[int, int] = {}
	var empty: Dictionary[StringName, int] = {}
	for roll_index: int in range(rolls):
		for rolled_id: StringName in RelicRoller.roll_from_pool(pool, empty, luck, count, allow_cursed, rng):
			var data: RelicData = index.get(rolled_id)
			if data == null:
				continue
			tally[data.rarity] = int(tally.get(data.rarity, 0)) + 1
	return tally


## `{rarity: fraction}` from a `_tally_rolls()` result.
func _shares(tally: Dictionary[int, int], total: int) -> Dictionary[int, float]:
	var shares: Dictionary[int, float] = {}
	for rarity: int in tally.keys():
		shares[rarity] = float(tally[rarity]) / float(total)
	return shares


# --- the tier table --------------------------------------------------------

func test_the_roller_script_is_the_specs_own_interface() -> void:
	var script := load(ROLLER_PATH) as GDScript
	assert_not_null(script, "%s loads, so every case here runs against the shipped file" % ROLLER_PATH)
	if script == null:
		return
	var names: Array[String] = []
	for method: Dictionary in script.get_script_method_list():
		names.append(String(method["name"]))
	assert_true(names.has("roll"), "`roll(player, count, allow_cursed)` is the interface SPEC-relics provides")
	assert_true(names.has("roll_from_pool"), "and `roll_from_pool()` is the explicit form behind it")


func test_the_rarity_weights_are_the_specs_own_numbers() -> void:
	assert_eq(RelicRoller.rarity_weight(RelicData.Rarity.COMMON, false), 60, "common 60")
	assert_eq(RelicRoller.rarity_weight(RelicData.Rarity.RARE, false), 28, "rare 28")
	assert_eq(RelicRoller.rarity_weight(RelicData.Rarity.EPIC, false), 10, "epic 10")
	assert_eq(RelicRoller.rarity_weight(RelicData.Rarity.LEGENDARY, false), 2, "legendary 2")
	assert_eq(
		RelicRoller.rarity_weight(RelicData.Rarity.CURSED, false),
		0,
		"cursed never rolls when the caller does not allow one (the Shrine's case)"
	)
	assert_eq(RelicRoller.RARITY_WEIGHT_TOTAL, 100, "the Shrine's four tiers total 100")
	assert_gt(
		RelicRoller.rarity_weight(RelicData.Rarity.CURSED, true),
		0,
		"a caller that allows a cursed relic gives its tier a weight of its own"
	)


func test_the_shrine_tier_list_is_the_specs_four_and_leaves_cursed_out() -> void:
	assert_eq(
		RelicRoller.rollable_tiers(false),
		[RelicData.Rarity.COMMON, RelicData.Rarity.RARE, RelicData.Rarity.EPIC, RelicData.Rarity.LEGENDARY] as Array[int],
		"the Shrine rolls the spec's four tiers, cursed last and unreachable"
	)
	assert_eq(
		RelicRoller.rollable_tiers(true),
		[RelicData.Rarity.COMMON, RelicData.Rarity.RARE, RelicData.Rarity.EPIC, RelicData.Rarity.LEGENDARY, RelicData.Rarity.CURSED] as Array[int],
		"a caller that allows a cursed relic gets the fifth tier"
	)


# --- the distribution gate -------------------------------------------------

func test_the_rarity_distribution_over_ten_thousand_rolls_is_within_two_percent() -> void:
	var pool: Array[RelicData] = _pool()
	var tally: Dictionary[int, int] = _tally_rolls(pool, DISTRIBUTION_ROLLS, 1, false, NO_LUCK, DISTRIBUTION_SEED)
	var total: int = 0
	for rarity: int in tally.keys():
		total += tally[rarity]
	assert_eq(total, DISTRIBUTION_ROLLS, "every roll returned a relic, so the shares are over the whole 10 000")

	var shares: Dictionary[int, float] = _shares(tally, total)
	var expected: Dictionary[int, float] = {
		RelicData.Rarity.COMMON: 0.60,
		RelicData.Rarity.RARE: 0.28,
		RelicData.Rarity.EPIC: 0.10,
		RelicData.Rarity.LEGENDARY: 0.02,
	}
	for rarity: int in expected.keys():
		var want: float = expected[rarity]
		var got: float = float(shares.get(rarity, 0.0))
		assert_almost_eq(
			got,
			want,
			DISTRIBUTION_TOLERANCE,
			"%s rolls %.4f of the time, the spec's %.2f within %.2f" % [
				RelicData.Rarity.keys()[rarity], got, want, DISTRIBUTION_TOLERANCE,
			]
		)
	assert_almost_eq(
		float(shares.get(RelicData.Rarity.CURSED, 0.0)),
		0.0,
		1.0e-9,
		"and not one of the 10 000 rolls came back cursed"
	)
	print("[relic-roller] 10 000 rolls, seed %d: %s" % [DISTRIBUTION_SEED, str(tally)])
	pass_test("10 000 rolls: %s" % str(tally))


func test_ten_thousand_rolls_reach_every_one_of_the_specs_four_tiers() -> void:
	# A share case can pass with a tier at exactly its expected fraction and a
	# tier that never fires at all, so the count per tier is asserted too.
	var tally: Dictionary[int, int] = _tally_rolls(_pool(), DISTRIBUTION_ROLLS, 1, false, NO_LUCK, DISTRIBUTION_SEED)
	for rarity: int in RelicRoller.rollable_tiers(false):
		assert_gt(int(tally.get(rarity, 0)), 0, "%s is reachable" % RelicData.Rarity.keys()[rarity])


func test_the_weight_inside_a_tier_decides_which_relic_rolls() -> void:
	# A weight of 0 is a relic that cannot come up, and a weight of 1 is one that
	# can: a deterministic proof that the second stage reads `weight` at all.
	var pool: Array[RelicData] = [
		_relic("never", RelicData.Rarity.COMMON, 0.0),
		_relic("always", RelicData.Rarity.COMMON, 1.0),
	]
	var empty: Dictionary[StringName, int] = {}
	var rng := _seeded(7)
	var seen: Dictionary[StringName, int] = {}
	for roll_index: int in range(200):
		var rolled: Array[StringName] = RelicRoller.roll_from_pool(pool, empty, NO_LUCK, 1, false, rng)
		assert_eq(rolled.size(), 1, "roll %d returned a relic" % roll_index)
		if rolled.size() == 1:
			seen[rolled[0]] = int(seen.get(rolled[0], 0)) + 1
	assert_eq(int(seen.get(&"never", 0)), 0, "a weight of 0 never rolls")
	assert_eq(int(seen.get(&"always", 0)), 200, "and the only weighted relic rolls every time")

	# And proportionally: 9 to 1 over 1 000 seeded rolls.
	var lopsided: Array[RelicData] = [
		_relic("heavy", RelicData.Rarity.COMMON, 9.0),
		_relic("light", RelicData.Rarity.COMMON, 1.0),
	]
	var count_rng := _seeded(DISTRIBUTION_SEED)
	var heavy: int = 0
	for roll_index: int in range(CURSED_PROBE_ROLLS):
		for rolled_id: StringName in RelicRoller.roll_from_pool(lopsided, empty, NO_LUCK, 1, false, count_rng):
			if rolled_id == &"heavy":
				heavy += 1
	assert_almost_eq(float(heavy) / float(CURSED_PROBE_ROLLS), 0.9, DISTRIBUTION_TOLERANCE, \
		"9:1 within the tier reads as a 90% share")


# --- Luck ------------------------------------------------------------------

func test_the_luck_shift_is_the_specs_own_term() -> void:
	var text: String = _read_text(SPEC_RUN_ECONOMY_PATH)
	var re := RegEx.new()
	re.compile("rarity_roll \\+= LUCK \\* ([0-9.]+)")
	var m: RegExMatch = re.search(text)
	assert_not_null(m, "SPEC-run-economy states the Luck term")
	if m == null:
		return
	assert_almost_eq(
		RelicRoller.LUCK_SHIFT_PER_POINT,
		float(m.get_string(1)),
		1.0e-9,
		"`LUCK_SHIFT_PER_POINT` is the spec's own `LUCK * 0.01`"
	)
	assert_almost_eq(RelicRoller.LUCK_SHIFT_PER_POINT, 0.01, 1.0e-9, "one Luck point is one percent of the roll")


func test_luck_shifts_the_rarity_roll_upward_and_never_off_the_table() -> void:
	assert_almost_eq(RelicRoller.shifted_roll(0.20, NO_LUCK), 0.20, 1.0e-9, "no Luck shifts nothing")
	assert_almost_eq(RelicRoller.shifted_roll(0.20, LUCK_TEN), 0.30, 1.0e-9, "10 Luck adds 0.10")
	assert_almost_eq(RelicRoller.shifted_roll(0.20, 10.5), 0.305, 1.0e-9, "and it is per point, not per rank")
	assert_almost_eq(RelicRoller.shifted_roll(1.0, LUCK_HUGE), 1.0, 1.0e-9, "the top of the table is the cap")
	assert_eq(RelicRoller.shifted_roll(0.0, LUCK_HUGE) >= 0.0, true, "and it never goes below the table")


func test_luck_promotes_the_tier_a_roll_lands_in() -> void:
	# The shift is only worth anything if it moves the tier, so the same base
	# roll is read at three Luck values.
	assert_eq(RelicRoller.rarity_for_roll(0.55, false), RelicData.Rarity.COMMON, "0.55 is a common roll")
	assert_eq(
		RelicRoller.rarity_for_roll(RelicRoller.shifted_roll(0.55, LUCK_TEN), false),
		RelicData.Rarity.RARE,
		"the same roll at 10 Luck lands in the rare tier"
	)
	assert_eq(
		RelicRoller.rarity_for_roll(RelicRoller.shifted_roll(0.55, 40.0), false),
		RelicData.Rarity.EPIC,
		"at 40 Luck it reaches epic"
	)
	assert_eq(
		RelicRoller.rarity_for_roll(RelicRoller.shifted_roll(0.55, LUCK_HUGE), false),
		RelicData.Rarity.LEGENDARY,
		"and an absurd Luck still tops out at legendary, never off the end of the table"
	)
	# The tier boundaries are the cumulative weights, at the spec's own numbers.
	assert_eq(RelicRoller.rarity_for_roll(0.0, false), RelicData.Rarity.COMMON, "the bottom of the table is common")
	assert_eq(RelicRoller.rarity_for_roll(0.599, false), RelicData.Rarity.COMMON, "0.60 is where common ends")
	assert_eq(RelicRoller.rarity_for_roll(0.60, false), RelicData.Rarity.RARE, "0.60 is the first rare roll")
	assert_eq(RelicRoller.rarity_for_roll(0.879, false), RelicData.Rarity.RARE, "0.88 is where rare ends")
	assert_eq(RelicRoller.rarity_for_roll(0.88, false), RelicData.Rarity.EPIC, "0.88 is the first epic roll")
	assert_eq(RelicRoller.rarity_for_roll(0.979, false), RelicData.Rarity.EPIC, "0.98 is where epic ends")
	assert_eq(RelicRoller.rarity_for_roll(0.98, false), RelicData.Rarity.LEGENDARY, "0.98 is the first legendary")


func test_luck_raises_the_share_of_the_top_tiers_over_a_real_roll() -> void:
	# The arithmetical cases above read the roll; this one reads the relic that
	# comes out, so a shift that is computed and then thrown away fails here.
	var pool: Array[RelicData] = _pool()
	var dry: Dictionary[int, int] = _tally_rolls(pool, DISTRIBUTION_ROLLS, 1, false, NO_LUCK, DISTRIBUTION_SEED)
	# 20 Luck shifts every roll by 0.20: everything the shift pushes past 0.60
	# comes back rare or better.
	var lucky: Dictionary[int, int] = _tally_rolls(pool, DISTRIBUTION_ROLLS, 1, false, 20.0, DISTRIBUTION_SEED)
	var dry_common: int = int(dry.get(RelicData.Rarity.COMMON, 0))
	var lucky_common: int = int(lucky.get(RelicData.Rarity.COMMON, 0))
	assert_almost_eq(
		float(dry_common),
		float(DISTRIBUTION_ROLLS) * 0.60,
		float(DISTRIBUTION_ROLLS) * DISTRIBUTION_TOLERANCE,
		"with no Luck, 60% of rolls are common"
	)
	assert_almost_eq(
		float(lucky_common),
		float(DISTRIBUTION_ROLLS) * 0.40,
		float(DISTRIBUTION_ROLLS) * DISTRIBUTION_TOLERANCE,
		"at 20 Luck the common share falls to 40%, so Luck really moved the roll"
	)


# --- cursed ----------------------------------------------------------------

func test_a_shrine_roll_never_returns_a_cursed_relic() -> void:
	var pool: Array[RelicData] = _pool()
	var tally: Dictionary[int, int] = _tally_rolls(pool, DISTRIBUTION_ROLLS, 3, false, NO_LUCK, DISTRIBUTION_SEED)
	assert_eq(int(tally.get(RelicData.Rarity.CURSED, 0)), 0, "not one cursed relic in 30 000 offered ids")

	# And with nothing but a cursed relic in the pool, the Shrine offers nothing
	# at all rather than falling back onto it.
	var only_cursed: Array[RelicData] = [_relic("only_cursed", RelicData.Rarity.CURSED)]
	var empty: Dictionary[StringName, int] = {}
	var rng := _seeded(DISTRIBUTION_SEED)
	assert_eq(
		RelicRoller.roll_from_pool(only_cursed, empty, NO_LUCK, 3, false, rng),
		[] as Array[StringName],
		"a cursed relic is not offered when the caller does not allow one"
	)


func test_a_caller_that_allows_a_cursed_relic_can_get_one() -> void:
	var pool: Array[RelicData] = _pool()
	var tally: Dictionary[int, int] = _tally_rolls(pool, CURSED_PROBE_ROLLS, 1, true, NO_LUCK, DISTRIBUTION_SEED)
	assert_gt(
		int(tally.get(RelicData.Rarity.CURSED, 0)),
		0,
		"the cursed tier is reachable when `allow_cursed` is true"
	)
	# The same pool at the same seed, with the caller disallowing one, offers none.
	var shrine: Dictionary[int, int] = _tally_rolls(pool, CURSED_PROBE_ROLLS, 1, false, NO_LUCK, DISTRIBUTION_SEED)
	assert_eq(int(shrine.get(RelicData.Rarity.CURSED, 0)), 0, "and the Shrine's own roll still offers none")

	var only_cursed: Array[RelicData] = [_relic("only_cursed", RelicData.Rarity.CURSED)]
	var empty: Dictionary[StringName, int] = {}
	var rng := _seeded(DISTRIBUTION_SEED)
	assert_eq(
		RelicRoller.roll_from_pool(only_cursed, empty, NO_LUCK, 1, true, rng),
		[&"only_cursed"] as Array[StringName],
		"a pool of one cursed relic returns it when the caller allows one"
	)


# --- max_stacks ------------------------------------------------------------

func test_a_relic_at_its_max_stacks_is_never_offered() -> void:
	var pool: Array[RelicData] = [_relic("stacker", RelicData.Rarity.COMMON, 1.0, 3)]
	var empty: Dictionary[StringName, int] = {}
	var rng := _seeded(DISTRIBUTION_SEED)

	assert_eq(
		RelicRoller.roll_from_pool(pool, empty, NO_LUCK, 1, false, rng),
		[&"stacker"] as Array[StringName],
		"held zero times, a three-stack relic is offered"
	)
	var two: Dictionary[StringName, int] = {&"stacker": 2}
	assert_eq(
		RelicRoller.roll_from_pool(pool, two, NO_LUCK, 1, false, rng),
		[&"stacker"] as Array[StringName],
		"held twice, a three-stack relic is still offered — the boundary is `>=`"
	)
	var three: Dictionary[StringName, int] = {&"stacker": 3}
	assert_eq(
		RelicRoller.roll_from_pool(pool, three, NO_LUCK, 1, false, rng),
		[] as Array[StringName],
		"held at max_stacks, it is not offered"
	)
	assert_eq(
		RelicRoller.held_at_max(&"stacker", three, pool),
		true,
		"and the helper the filter is built from agrees"
	)
	assert_eq(RelicRoller.held_at_max(&"stacker", empty, pool), false, "a relic held zero times is not at max")
	assert_eq(
		RelicRoller.held_at_max(&"not_in_the_pool", three, pool),
		false,
		"an id the pool does not hold is never at max, which is not the filter's question"
	)
	# A one-stack relic at one held is done too.
	var single: Array[RelicData] = [_relic("single", RelicData.Rarity.COMMON, 1.0, 1)]
	var one: Dictionary[StringName, int] = {&"single": 1}
	assert_eq(
		RelicRoller.roll_from_pool(single, one, NO_LUCK, 1, false, rng),
		[] as Array[StringName],
		"a max_stacks of 1 is exclusive once held once"
	)


func test_a_tier_with_nothing_left_falls_back_to_the_nearest_one_that_has_something() -> void:
	# Every common relic is held at max and the rare tier is empty, so a common
	# roll has to land somewhere real: the nearest tier with a candidate.
	var pool: Array[RelicData] = [
		_relic("held_common", RelicData.Rarity.COMMON, 1.0, 1),
		_relic("free_legendary", RelicData.Rarity.LEGENDARY, 1.0, 1),
	]
	var held: Dictionary[StringName, int] = {&"held_common": 1}
	var rng := _seeded(DISTRIBUTION_SEED)
	assert_eq(
		RelicRoller.roll_from_pool(pool, held, NO_LUCK, 1, false, rng),
		[&"free_legendary"] as Array[StringName],
		"the roll still returns the one relic that can be offered"
	)
	# The search order is nearest first, and the lower tier wins a tie.
	assert_eq(
		RelicRoller.nearest_tiers(RelicData.Rarity.COMMON, false),
		[RelicData.Rarity.COMMON, RelicData.Rarity.RARE, RelicData.Rarity.EPIC, RelicData.Rarity.LEGENDARY] as Array[int],
		"from the bottom tier the search only walks up"
	)
	assert_eq(
		RelicRoller.nearest_tiers(RelicData.Rarity.LEGENDARY, false),
		[RelicData.Rarity.LEGENDARY, RelicData.Rarity.EPIC, RelicData.Rarity.RARE, RelicData.Rarity.COMMON] as Array[int],
		"from the top tier it only walks down"
	)
	assert_eq(
		RelicRoller.nearest_tiers(RelicData.Rarity.RARE, false),
		[RelicData.Rarity.RARE, RelicData.Rarity.COMMON, RelicData.Rarity.EPIC, RelicData.Rarity.LEGENDARY] as Array[int],
		"from the middle the lower tier is offered first"
	)


# --- the count and the distinctness ----------------------------------------

func test_roll_returns_exactly_count_distinct_ids_when_the_pool_allows() -> void:
	var pool: Array[RelicData] = []
	for index: int in range(20):
		pool.append(_relic("common_%02d" % index, RelicData.Rarity.COMMON, 1.0))
	var empty: Dictionary[StringName, int] = {}
	var rng := _seeded(DISTRIBUTION_SEED)
	var rolled: Array[StringName] = RelicRoller.roll_from_pool(pool, empty, NO_LUCK, 3, false, rng)
	assert_eq(rolled.size(), 3, "three asked for, three returned")
	var distinct: Dictionary[StringName, bool] = {}
	for relic_id: StringName in rolled:
		assert_false(distinct.has(relic_id), "%s is not offered twice in one roll" % relic_id)
		distinct[relic_id] = true
		assert_true(RelicRoller.ids_of(pool).has(relic_id), "%s came out of the pool" % relic_id)

	# The Shrine's own call: three, and a pool too small returns what there is.
	var two: Array[RelicData] = [pool[0], pool[1]]
	assert_eq(
		RelicRoller.roll_from_pool(two, empty, NO_LUCK, 3, false, rng).size(),
		2,
		"a pool of two cannot offer three, so it offers two rather than a duplicate"
	)
	assert_eq(
		RelicRoller.roll_from_pool(pool, empty, NO_LUCK, 0, false, rng),
		[] as Array[StringName],
		"zero asked for is zero returned"
	)


func test_max_stacks_shrink_what_a_multi_roll_can_offer() -> void:
	var pool: Array[RelicData] = [
		_relic("common_a", RelicData.Rarity.COMMON, 1.0, 1),
		_relic("common_b", RelicData.Rarity.COMMON, 1.0, 2),
	]
	var empty: Dictionary[StringName, int] = {}
	var rng := _seeded(DISTRIBUTION_SEED)
	assert_eq(
		RelicRoller.roll_from_pool(pool, empty, NO_LUCK, 3, false, rng).size(),
		2,
		"with a one-stack and a two-stack relic the pool runs out at two distinct ids"
	)


# --- determinism -----------------------------------------------------------

func test_a_seeded_rng_gives_the_same_sequence_on_two_runs() -> void:
	var pool: Array[RelicData] = _pool()
	var empty: Dictionary[StringName, int] = {}
	var first: RandomNumberGenerator = _seeded(4242)
	var second: RandomNumberGenerator = _seeded(4242)
	var first_run: Array[StringName] = []
	var second_run: Array[StringName] = []
	for index: int in range(100):
		first_run.append_array(RelicRoller.roll_from_pool(pool, empty, 5.0, 3, true, first))
		second_run.append_array(RelicRoller.roll_from_pool(pool, empty, 5.0, 3, true, second))
	assert_eq(first_run.size(), 300, "the case really rolled 100 times three")
	assert_eq(first_run, second_run, "one seed replays one sequence")
	assert_gt(first_run.size(), 0, "and the sequence is not empty")


func test_a_roll_with_no_rng_is_deterministic_and_never_takes_the_clock() -> void:
	# The default generator is seeded from the live run, like an effect's, so a
	# roll with nobody watching is still reproducible rather than clock-random.
	assert_eq(RelicRoller.DEFAULT_RNG_SEED, Effect.DEFAULT_RNG_SEED, "the fallback seed is the project's one fixed seed")
	var pool: Array[RelicData] = _pool()
	var empty: Dictionary[StringName, int] = {}
	var first: Array[StringName] = RelicRoller.roll_from_pool(pool, empty, NO_LUCK, 3, false, null)
	var second: Array[StringName] = RelicRoller.roll_from_pool(pool, empty, NO_LUCK, 3, false, null)
	assert_eq(first, second, "the same inputs give the same three ids")


# --- the pool loader -------------------------------------------------------

func test_the_pool_loader_reads_data_relics_and_reports_an_empty_folder() -> void:
	var dir := DirAccess.open(RELIC_DIR)
	assert_not_null(dir, "%s exists, so an empty pool means an empty folder" % RELIC_DIR)
	var pool: Array[RelicData] = RelicRoller.load_pool(RELIC_DIR)
	for data: RelicData in pool:
		assert_not_null(data, "every entry in the pool is a RelicData")
		assert_ne(String(data.id), "", "and carries an id")
	pass_test("%d relics loadable from %s" % [pool.size(), RELIC_DIR])


func test_the_pool_loader_reads_a_written_fixture_folder() -> void:
	var dir := DirAccess.open(FIXTURE_DIR)
	if dir == null:
		assert_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_DIR)), OK, "fixture dir")
	for fixture_name: String in ["pool_a", "pool_b"]:
		var data := _relic(fixture_name, RelicData.Rarity.RARE, 2.0)
		var path := FIXTURE_DIR.path_join("%s.tres" % fixture_name)
		assert_eq(ResourceSaver.save(data, path), OK, "save %s" % path)
		_fixture_paths.append(path)
	var pool: Array[RelicData] = RelicRoller.load_pool(FIXTURE_DIR)
	assert_eq(pool.size(), 2, "both written fixtures load")
	var ids: Array[StringName] = RelicRoller.ids_of(pool)
	assert_true(ids.has(&"pool_a") and ids.has(&"pool_b"), "and the loader keeps their ids")


func test_the_pool_loader_tolerates_a_folder_that_does_not_exist() -> void:
	assert_eq(
		RelicRoller.load_pool("res://_no_such_relic_folder"),
		[] as Array[RelicData],
		"a missing folder is an empty pool, not an error"
	)


# --- the player seam -------------------------------------------------------

func test_held_counts_read_the_players_run_slice() -> void:
	GameState.start_run(4242, 1, [])
	var slice := RunPlayerState.new(1)
	slice.relics = [&"ember_boots", &"ember_boots", &"echo_blade"] as Array[StringName]
	GameState.run.add_player(slice)
	var player: Player = _player(1)

	var held: Dictionary[StringName, int] = RelicRoller.held_counts(player)
	assert_eq(int(held.get(&"ember_boots", 0)), 2, "a relic held twice counts twice, which is what max_stacks needs")
	assert_eq(int(held.get(&"echo_blade", 0)), 1, "and one held once counts once")
	assert_eq(held.size(), 2, "nothing the player does not hold is in the map")

	# A peer with no slice in the live run holds nothing rather than erroring.
	assert_eq(RelicRoller.held_counts(_player(9)).size(), 0, "a peer with no run slice holds nothing")

	slice.relics = [] as Array[StringName]
	assert_eq(RelicRoller.held_counts(player).size(), 0, "and an empty loadout is an empty map")


func test_held_counts_with_no_live_run_is_empty() -> void:
	# `before_each()` opened no run, which is the town case.
	assert_eq(RelicRoller.held_counts(_player(1)).size(), 0, "with no run live there is nothing held")


func test_luck_of_reads_stat_luck_off_the_players_stat_block() -> void:
	var player: Player = _player(1)
	assert_almost_eq(RelicRoller.luck_of(player), 0.0, 1.0e-9, "a player with no StatBlock has no Luck")

	var block: StatBlock = _with_stat_block(player, 4.0)
	assert_almost_eq(RelicRoller.luck_of(player), 4.0, 1.0e-9, "Luck comes off `Stat.LUCK`")

	block.add_modifier(StatBlock.Stat.LUCK, 3.0, 0.0, &"test_luck")
	assert_almost_eq(RelicRoller.luck_of(player), 7.0, 1.0e-9, "and a Luck modifier is read too, never the base alone")


func test_roll_from_a_player_reads_the_luck_and_the_held_ids_it_holds() -> void:
	# The spec's own call shape, end to end: `roll(player, count, allow_cursed)`.
	# The pool this test wrote drives the first half, so the case asserts the
	# player's own state reached the roller.
	GameState.start_run(4242, 1, [])
	var slice := RunPlayerState.new(1)
	slice.relics = [&"pool_a"] as Array[StringName]
	GameState.run.add_player(slice)

	var player: Player = _player(1)
	_with_stat_block(player, 0.0)

	var written: Array[RelicData] = [
		_relic("pool_a", RelicData.Rarity.RARE, 1.0, 1),
		_relic("pool_b", RelicData.Rarity.RARE, 1.0, 3),
	]
	var pool: Array[RelicData] = []
	for data: RelicData in written:
		var path := FIXTURE_DIR.path_join("%s.tres" % data.id)
		var dir := DirAccess.open(FIXTURE_DIR)
		if dir == null:
			assert_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_DIR)), OK, "fixture dir")
		assert_eq(ResourceSaver.save(data, path), OK, "save %s" % path)
		_fixture_paths.append(path)
		pool.append(load(path) as RelicData)

	var rolled: Array[StringName] = RelicRoller.roll(player, 3, false, _seeded(DISTRIBUTION_SEED), pool)
	assert_false(rolled.has(&"pool_a"), "the id held at its max_stacks never comes back")
	assert_true(rolled.has(&"pool_b"), "the three-stack one it holds none of does")
	assert_eq(rolled.size(), 1, "and that is everything the pool can still offer")

	# The real path is `data/relics/` loaded and rolled, nothing else. Written so
	# it holds at any content count rather than pinning the folder's emptiness:
	# every id the real call offers is one the folder holds (it invents nothing),
	# and it offers exactly what the explicit form over that same pool offers.
	var real_pool: Array[RelicData] = RelicRoller.load_pool(RELIC_DIR)
	var content_ids: Array[StringName] = RelicRoller.ids_of(real_pool)
	var real_rolled: Array[StringName] = RelicRoller.roll(player, 3, false, _seeded(DISTRIBUTION_SEED))
	for relic_id: StringName in real_rolled:
		assert_true(content_ids.has(relic_id), "the real pool only offers ids %s holds (%s)" % [RELIC_DIR, relic_id])
	assert_eq(
		real_rolled,
		RelicRoller.roll_from_pool(real_pool, RelicRoller.held_counts(player), RelicRoller.luck_of(player), 3, false, _seeded(DISTRIBUTION_SEED)),
		"the real call is %s loaded and rolled, never a pool of its own" % RELIC_DIR
	)