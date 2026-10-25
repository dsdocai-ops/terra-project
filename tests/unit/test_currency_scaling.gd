extends GutTest
## W6-B5 (goal G8) — the biome depth curve for the run's currencies. Owned by
## run-economy.
##
## The plan's anchors: biome 1 pays the flat tables (1.0x), biome 4 gold x1.2
## and echo x1.4, biome 6 gold x1.5 and echo x2.0. The cases cover every biome,
## the clamped ends, the three application seams (`LootDrops.credit` for the
## table drops, `OrePayout.award` for the kill table, `EchoShards.award` for the
## per-player shards), the rarity field's untouchability — depth scaling is an
## amount rule and Luck's rarity shift stays `LootTable`'s — and the co-op
## split: a scaled pool splits evenly, its total survives the split, and the
## remainder still hands to the first player.
##
## The player is the real fixture `EffectHarness` builds, the same way
## `test_echo_shards.gd` proves Collector's bonus; the run is a hand-built
## `RunState` and nothing here touches the scene tree beyond a spawner.

const PEER_ID: int = 1
const TEAMMATE_PEER_ID: int = 2
const RUN_SEED: int = 4242
const ALL_BIOMES: Array[int] = [1, 2, 3, 4, 5, 6]
## Biome 4 is the plan's mid anchor (gold x1.2, echo x1.4); floor 16 stands on it.
const BIOME_FOUR_FLOOR: int = 16
## Biome 6 is the deep anchor (gold x1.5, echo x2.0); floor 26 stands on it.
const BIOME_SIX_FLOOR: int = 26

var _harness: EffectHarness = null
var _player: Player = null
var _run: RunState = null
var _container: Node2D = null
var _spawner: PickupSpawner = null
var _gains: Array[Dictionary] = []


func before_each() -> void:
	NetworkManager.start_solo()
	_harness = EffectHarness.new(self)
	_harness.setup()
	_player = _harness.make_player()
	_player.peer_id = PEER_ID
	_run = RunState.new(RUN_SEED, 1)
	_run.add_player(RunPlayerState.new(PEER_ID))
	GameState.run = _run
	_gains.clear()
	Events.currency_gained.connect(_on_currency_gained)
	_container = Node2D.new()
	_container.name = &"Entities"
	add_child_autofree(_container)
	_spawner = PickupSpawner.new()
	_spawner.name = PickupSpawner.NODE_NAME
	_spawner.spawn_path = NodePath("..")
	_container.add_child(_spawner)


func after_each() -> void:
	if Events.currency_gained.is_connected(_on_currency_gained):
		Events.currency_gained.disconnect(_on_currency_gained)
	GameState.run = null
	_run = null
	EffectHarness.reset_globals()


func _on_currency_gained(player: Player, currency: StringName, amount: int) -> void:
	_gains.append({"player": player, "currency": currency, "amount": amount})


## A run standing on `floor`'s biome, with this test's player in it.
func _run_at_floor(floor_index: int) -> RunState:
	_run.floor_index = floor_index
	return _run


## A one-drop dictionary in `LootTable.roll()`'s own result shape.
func _drop(kind: StringName, amount: int, id: StringName = &"") -> Dictionary:
	var drop: Dictionary = {
		"kind": kind,
		"id": id,
		"rarity": LootTable.RARITY_NONE,
		"amount": amount,
	}
	return drop


func _pickups() -> Array[Pickup]:
	var found: Array[Pickup] = []
	for child: Node in _container.get_children():
		var pickup: Pickup = child as Pickup
		if pickup != null:
			found.append(pickup)
	return found


## `RunEconomyRules.settle()` for a hand-built run, the death-rules test's shape.
func _settled(reason: RunEndReason.Reason, run: RunState) -> RunResult:
	var result: RunResult = RunResult.new(reason, run.seed, 0)
	RunEconomyRules.settle(result, run)
	return result


# --- the curves -------------------------------------------------------------


func test_biome_one_pays_the_flat_tables() -> void:
	var multipliers: Dictionary[StringName, float] = CurrencyScaler.biome_multiplier(1)
	assert_eq(multipliers[CurrencyScaler.GOLD_ID], 1.0, "gold unscaled")
	assert_eq(multipliers[CurrencyScaler.ORE_ID], 1.0, "ore unscaled")
	assert_eq(multipliers[CurrencyScaler.ECHO_ID], 1.0, "echo unscaled")
	assert_eq(CurrencyScaler.amount_for(CurrencyScaler.GOLD_ID, 37, 1), 37, "and so does the amount")


func test_the_gold_curve_hits_its_anchors() -> void:
	assert_eq(CurrencyScaler.multiplier_for(CurrencyScaler.GOLD_ID, 1), 1.0, "biome 1: flat tables")
	assert_eq(CurrencyScaler.multiplier_for(CurrencyScaler.GOLD_ID, 4), 1.2, "biome 4: the mid anchor")
	assert_eq(CurrencyScaler.multiplier_for(CurrencyScaler.GOLD_ID, 6), 1.5, "biome 6: the deep anchor")


func test_the_echo_curve_hits_its_anchors() -> void:
	assert_eq(CurrencyScaler.multiplier_for(CurrencyScaler.ECHO_ID, 1), 1.0, "biome 1: flat tables")
	assert_eq(CurrencyScaler.multiplier_for(CurrencyScaler.ECHO_ID, 4), 1.4, "biome 4: the mid anchor")
	assert_eq(CurrencyScaler.multiplier_for(CurrencyScaler.ECHO_ID, 6), 2.0, "biome 6: the deep anchor")


func test_the_ore_curve_is_the_gentlest_and_gold_the_steadiest() -> void:
	for biome: int in ALL_BIOMES:
		var ore: float = CurrencyScaler.multiplier_for(CurrencyScaler.ORE_ID, biome)
		var gold: float = CurrencyScaler.multiplier_for(CurrencyScaler.GOLD_ID, biome)
		var echo: float = CurrencyScaler.multiplier_for(CurrencyScaler.ECHO_ID, biome)
		assert_true(ore <= gold, "biome %d: ore never beats gold" % biome)
		assert_true(gold <= echo, "biome %d: gold never beats echo" % biome)


func test_every_curve_only_ever_raises_a_payout() -> void:
	for currency: StringName in [CurrencyScaler.GOLD_ID, CurrencyScaler.ORE_ID, CurrencyScaler.ECHO_ID]:
		var previous: float = 0.0
		for biome: int in ALL_BIOMES:
			var factor: float = CurrencyScaler.multiplier_for(currency, biome)
			assert_true(factor >= 1.0, "%s biome %d never dips below the flat tables" % [currency, biome])
			assert_true(factor >= previous, "%s never shrinks from biome %d on" % [currency, biome - 1])
			previous = factor


func test_the_curves_are_clamped_at_both_ends_of_the_biome_range() -> void:
	var first: Dictionary[StringName, float] = CurrencyScaler.biome_multiplier(1)
	var last: Dictionary[StringName, float] = CurrencyScaler.biome_multiplier(6)
	for currency: StringName in [CurrencyScaler.GOLD_ID, CurrencyScaler.ORE_ID, CurrencyScaler.ECHO_ID]:
		assert_eq(CurrencyScaler.multiplier_for(currency, 0), first[currency], "below biome 1 reads as biome 1")
		assert_eq(CurrencyScaler.multiplier_for(currency, 99), last[currency], "past biome 6 reads as biome 6")


func test_an_unknown_currency_reads_as_unscaled() -> void:
	assert_eq(CurrencyScaler.multiplier_for(&"souls", 6), 1.0, "a currency off the curve pays the flat table")
	assert_eq(CurrencyScaler.amount_for(&"souls", 10, 6), 10, "and its amount is unchanged")


func test_scaling_rounds_once_and_never_invents_a_payout() -> void:
	assert_eq(CurrencyScaler.amount_for(CurrencyScaler.GOLD_ID, 101, 4), 121, "101 x 1.2 rounds once to 121")
	assert_eq(CurrencyScaler.amount_for(CurrencyScaler.ECHO_ID, 2, 5), 3, "2 x 1.7 rounds once to 3")
	assert_eq(CurrencyScaler.amount_for(CurrencyScaler.GOLD_ID, 0, 6), 0, "no base, no payout")
	assert_eq(CurrencyScaler.amount_for(CurrencyScaler.GOLD_ID, -5, 6), 0, "a negative base invents nothing")


func test_the_multipliers_are_identical_on_every_read() -> void:
	for biome: int in ALL_BIOMES:
		var first: Dictionary[StringName, float] = CurrencyScaler.biome_multiplier(biome)
		var again: Dictionary[StringName, float] = CurrencyScaler.biome_multiplier(biome)
		for currency: StringName in [CurrencyScaler.GOLD_ID, CurrencyScaler.ORE_ID, CurrencyScaler.ECHO_ID]:
			assert_eq(again[currency], first[currency], "biome %d %s is a constant, not a roll" % [biome, currency])


# --- the application seams --------------------------------------------------


func test_a_credited_gold_drop_is_scaled_and_the_pickup_shows_what_was_paid() -> void:
	_run_at_floor(BIOME_FOUR_FLOOR)
	var drop: Dictionary = _drop(Pickup.KIND_GOLD, 10)
	LootDrops.credit(_run, _player, drop)
	assert_eq(_run.shared_gold, 12, "ten gold on biome 4 pays twelve")
	assert_eq(_gains.size(), 1, "announced once")
	assert_eq(_gains[0]["amount"], 12, "the announcement is the paid number")
	assert_eq(int(drop["amount"]), 12, "and the drop itself carries it")
	LootDrops.spawn_drop(drop, Vector2.ZERO, _player, _spawner)
	var pickups: Array[Pickup] = _pickups()
	assert_eq(pickups.size(), 1, "one physical coin")
	assert_eq(pickups[0].amount, 12, "the pickup presents exactly what was credited")


func test_a_credited_ore_drop_is_scaled_at_the_pool_seam() -> void:
	_run_at_floor(BIOME_SIX_FLOOR)
	var drop: Dictionary = _drop(Pickup.KIND_ORE, 10)
	LootDrops.credit(_run, _player, drop)
	assert_eq(int(_run.shared_ore.get(&"heartstone", 0)), 13, "ten ore on biome 6 pays thirteen")
	assert_eq(int(drop["amount"]), 13, "and the drop carries the paid number")


func test_depth_scaling_never_touches_the_rarity_field() -> void:
	_run_at_floor(BIOME_SIX_FLOOR)
	var drop: Dictionary = _drop(Pickup.KIND_GOLD, 10)
	drop["rarity"] = RelicData.Rarity.RARE
	LootDrops.credit(_run, _player, drop)
	assert_eq(drop["rarity"], RelicData.Rarity.RARE, "the rarity roll is not the depth curve's business")
	assert_eq(int(drop["amount"]), 15, "only the amount scaled")


func test_the_luck_rarity_roll_is_never_consulted_by_the_depth_curve() -> void:
	var shifted: int = LootTable.rarity_for_roll(LootTable.shifted_rarity_roll(0.4, 2.0))
	_run_at_floor(BIOME_SIX_FLOOR)
	var drop: Dictionary = _drop(Pickup.KIND_GOLD, 10)
	LootDrops.credit(_run, _player, drop)
	assert_eq(LootTable.rarity_for_roll(LootTable.shifted_rarity_roll(0.4, 2.0)), shifted,
		"crediting a scaled drop moves no rarity roll")
	assert_eq(CurrencyScaler.amount_for(CurrencyScaler.GOLD_ID, 10, 6), 15, "and the curve reads only its own inputs")


func test_the_ore_kill_table_scales_by_depth() -> void:
	_run_at_floor(BIOME_SIX_FLOOR)
	assert_eq(OrePayout.award(_run, _player, OrePayout.KIND_BIOME_BOSS), 8, "the boss's six ore pays eight")
	assert_eq(int(_run.shared_ore.get(&"heartstone", 0)), 8, "in the party's pool")
	assert_eq(OrePayout.award(_run, _player, OrePayout.KIND_ELITE), 1, "the elite's one ore still rounds to one")
	assert_eq(OrePayout.award(_run, _player, OrePayout.KIND_ELITE, 10), 13, "an override of ten pays thirteen")


func test_the_ore_kill_table_stays_flat_in_the_first_two_biomes() -> void:
	_run_at_floor(7)  # biome 2, the pinned deep-floor test floor
	assert_eq(OrePayout.award(_run, _player, OrePayout.KIND_MINI_BOSS), 3, "three ore, unscaled")


func test_the_echo_payout_scales_by_the_runs_biome() -> void:
	_run_at_floor(BIOME_SIX_FLOOR)
	assert_eq(EchoShards.award(_run, _player, 10), 20, "ten shards on biome 6 pay twenty")
	_run_at_floor(BIOME_FOUR_FLOOR)
	assert_eq(EchoShards.award(_run, _player, 10), 14, "ten shards on biome 4 pay fourteen")
	assert_eq(_run.get_player(PEER_ID).echo_shards_earned, 34, "the killer's own total, both awards stacked")


func test_echo_depth_composes_multiplicatively_with_echo_collector() -> void:
	_run_at_floor(BIOME_SIX_FLOOR)
	_harness.attach(_harness.source(EchoShards.ECHO_COLLECTOR_ID, "Echo Collector", RelicMarkerEffect))
	# 2 x 1.5 (Collector) x 2.0 (depth) = 6, rounded once.
	assert_eq(EchoShards.award(_run, _player, 2), 6, "the depth factor multiplies, it does not add")


func test_echo_depth_stays_off_the_flat_tables_in_biome_one() -> void:
	assert_eq(EchoShards.award(_run, _player, 10), 10, "biome 1 pays the spec's own numbers")
	assert_eq(EchoShards.amount_for(10, _player, 0), 10, "and a caller without a depth factor reads them too")


# --- the co-op split --------------------------------------------------------


func test_a_scaled_pool_splits_evenly_in_co_op() -> void:
	var run: RunState = _run_at_floor(BIOME_SIX_FLOOR)
	run.add_player(RunPlayerState.new(TEAMMATE_PEER_ID))
	run.shared_gold = CurrencyScaler.amount_for(CurrencyScaler.GOLD_ID, 100, run.biome_index)
	var result: RunResult = _settled(RunEndReason.Reason.EXTRACT, run)
	assert_eq(run.shared_gold, 150, "the deep pool: 100 through x1.5")
	assert_eq(result.kept[PEER_ID][&"gold"], 75, "one even share")
	assert_eq(result.kept[TEAMMATE_PEER_ID][&"gold"], 75, "the other even share")


func test_an_odd_scaled_pool_hands_the_remainder_to_the_first_player() -> void:
	var run: RunState = _run_at_floor(BIOME_SIX_FLOOR)
	run.add_player(RunPlayerState.new(TEAMMATE_PEER_ID))
	run.shared_gold = CurrencyScaler.amount_for(CurrencyScaler.GOLD_ID, 103, run.biome_index)  # 155
	var result: RunResult = _settled(RunEndReason.Reason.EXTRACT, run)
	assert_eq(result.kept[PEER_ID][&"gold"], 78, "the first player takes the odd coin")
	assert_eq(result.kept[TEAMMATE_PEER_ID][&"gold"], 77, "and nobody's share vanishes")


func test_a_scaled_pool_keeps_its_total_across_the_split() -> void:
	var run: RunState = _run_at_floor(BIOME_SIX_FLOOR)
	run.add_player(RunPlayerState.new(TEAMMATE_PEER_ID))
	run.shared_gold = CurrencyScaler.amount_for(CurrencyScaler.GOLD_ID, 100, run.biome_index)
	var result: RunResult = _settled(RunEndReason.Reason.EXTRACT, run)
	var banked: int = int(result.kept[PEER_ID][&"gold"]) + int(result.kept[TEAMMATE_PEER_ID][&"gold"])
	assert_eq(banked, run.shared_gold, "two players bank together what one pool scaled")


func test_solo_banks_the_same_total_a_pair_would() -> void:
	_run_at_floor(BIOME_SIX_FLOOR)
	_run.shared_gold = CurrencyScaler.amount_for(CurrencyScaler.GOLD_ID, 100, _run.biome_index)
	var solo: RunResult = _settled(RunEndReason.Reason.EXTRACT, _run)
	assert_eq(int(solo.kept[PEER_ID][&"gold"]), 150, "solo keeps the whole scaled pool")


func test_a_scaled_share_still_pays_the_death_rule() -> void:
	var run: RunState = _run_at_floor(BIOME_SIX_FLOOR)
	run.add_player(RunPlayerState.new(TEAMMATE_PEER_ID))
	run.shared_gold = CurrencyScaler.amount_for(CurrencyScaler.GOLD_ID, 100, run.biome_index)  # 150
	var result: RunResult = _settled(RunEndReason.Reason.DEFEAT, run)
	assert_eq(int(result.kept[PEER_ID][&"gold"]), 18, "75 at the death table's 25% is 18")
	assert_eq(int(result.kept[TEAMMATE_PEER_ID][&"gold"]), 18, "and the same for the second player")
