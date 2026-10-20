extends GutTest
## G14 (raw goals G41 and G42) — the Echo Shard payout table and its three
## multipliers. Owned by run-economy.
##
## SPEC-run-economy, "Currencies": "Echo Shards | 1 per floor cleared (2 in
## biomes 4 to 6), 1 to 2 per elite, 10 per mini-boss, 20 per biome boss,
## bounties; Echo Collector +50%, Echo Resonance +10%/rank, Heat multipliers |
## per player". SPEC-run-economy, "Testing": "Unit `test_echo_shards.gd`:
## payouts per floor/elite/boss by biome with multipliers."
##
## The player is the real fixture `EffectHarness` builds — a `Player` with an
## `EffectHost` — so Echo Collector's "+50%" is proved by attaching a relic
## under its id and reading the host, never by a flag on the payout code.
## Echo Resonance's rank is the skill tree's (week 7, `progression-trees`) and
## Heat's multiplier is the endgame's (week 11, `endgame`), so both arrive as
## arguments today: the spec's numbers are the table's, the two multipliers are
## its consumers'.

const PEER_ID: int = 1
const TEAMMATE_PEER_ID: int = 2
const RUN_SEED: int = 4242
## How many elite draws the range case makes. Fixed seed, so the count is the
## same on every run.
const ELITE_DRAWS: int = 200
## A plausible Heat total: one +25% modifier. SPEC-endgame: "each adds an Echo
## Shard multiplier (+10% to +25%)".
const HEAT_MULTIPLIER: float = 1.25

var _harness: EffectHarness = null
var _player: Player = null
var _run: RunState = null
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


func after_each() -> void:
	if Events.currency_gained.is_connected(_on_currency_gained):
		Events.currency_gained.disconnect(_on_currency_gained)
	GameState.run = null
	_run = null
	EffectHarness.reset_globals()


func _on_currency_gained(player: Player, currency: StringName, amount: int) -> void:
	_gains.append({"player": player, "currency": currency, "amount": amount})


# --- the table --------------------------------------------------------------


func test_a_floor_cleared_pays_one_shard_in_the_first_three_biomes() -> void:
	for biome: int in [1, 2, 3]:
		assert_eq(EchoShards.for_floor_cleared(biome), 1, "biome %d pays one" % biome)


func test_a_floor_cleared_pays_two_shards_in_biomes_four_to_six() -> void:
	for biome: int in [4, 5, 6]:
		assert_eq(EchoShards.for_floor_cleared(biome), 2, "biome %d pays two" % biome)


func test_a_floor_cleared_is_clamped_at_both_ends_of_the_biome_range() -> void:
	assert_eq(EchoShards.for_floor_cleared(0), 1, "below biome 1 reads as biome 1")
	assert_eq(EchoShards.for_floor_cleared(99), 2, "past biome 6 reads as biome 6")


func test_an_elite_pays_one_or_two_shards_and_both_ends_are_reachable() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = RUN_SEED
	var seen: Dictionary[int, bool] = {}
	for draw: int in ELITE_DRAWS:
		var paid: int = EchoShards.for_elite(rng)
		assert_between(paid, 1, 2, "elite draw %d is 1..2" % draw)
		seen[paid] = true
	assert_eq(seen.size(), 2, "both 1 and 2 come up")


func test_a_mini_boss_pays_ten_and_a_biome_boss_twenty() -> void:
	assert_eq(EchoShards.for_mini_boss(), 10, "the spec's ten")
	assert_eq(EchoShards.for_biome_boss(), 20, "the spec's twenty")


# --- the multipliers --------------------------------------------------------


func test_echo_collector_raises_the_payout_by_half() -> void:
	assert_eq(EchoShards.collector_bonus(_player), 0.0, "nothing attached, no bonus")
	_harness.attach(_harness.source(EchoShards.ECHO_COLLECTOR_ID, "Echo Collector", RelicMarkerEffect))
	assert_almost_eq(EchoShards.collector_bonus(_player), 0.5, 0.0001, "the spec's +50%")
	assert_eq(EchoShards.amount_for(10, _player), 15, "ten becomes fifteen")


func test_echo_resonance_adds_ten_percent_per_rank() -> void:
	assert_eq(EchoShards.amount_for(10, _player, 0), 10, "no ranks, no change")
	assert_eq(EchoShards.amount_for(10, _player, 3), 13, "three ranks")
	assert_eq(EchoShards.amount_for(10, _player, 5), 15, "five ranks")


func test_a_negative_rank_reads_as_no_bonus_rather_than_a_discount() -> void:
	assert_eq(EchoShards.amount_for(10, _player, -3), 10, "a rank count below zero adds nothing")


func test_the_three_multipliers_are_multiplicative_and_not_additive() -> void:
	_harness.attach(_harness.source(EchoShards.ECHO_COLLECTOR_ID, "Echo Collector", RelicMarkerEffect))
	# 10 x 1.5 (Collector) x 1.3 (Resonance 3) x 1.25 (Heat) = 24.375 -> 24.
	# The additive reading would be 10 x (1 + 0.5 + 0.3 + 0.25) = 20.5 -> 21.
	assert_almost_eq(
		EchoShards.multiplier_for(_player, 3, HEAT_MULTIPLIER), 1.5 * 1.3 * HEAT_MULTIPLIER, 0.0001,
		"the three factors multiply"
	)
	assert_eq(EchoShards.amount_for(10, _player, 3, HEAT_MULTIPLIER), 24, "and the amount follows")


func test_a_heat_multiplier_alone_raises_the_payout() -> void:
	assert_eq(EchoShards.amount_for(20, _player, 0, 1.1), 22, "a +10% Heat level")


# --- the award --------------------------------------------------------------


func test_award_credits_the_killers_own_total_and_announces_it_once() -> void:
	var paid: int = EchoShards.award(_run, _player, 10)
	assert_eq(paid, 10, "award returns what it paid")
	assert_eq(_run.get_player(PEER_ID).echo_shards_earned, 10, "the killer's own total")
	assert_eq(_gains.size(), 1, "one announcement")
	assert_eq(_gains[0]["currency"], EchoShards.CURRENCY_ID, "under the echo currency id")
	assert_eq(_gains[0]["amount"], 10)
	assert_eq(_gains[0]["player"], _player, "naming the player who earned it")


func test_award_moves_one_players_total_and_not_the_partys_shared_pool() -> void:
	_run.add_player(RunPlayerState.new(TEAMMATE_PEER_ID))
	EchoShards.award(_run, _player, 10)
	assert_eq(_run.get_player(PEER_ID).echo_shards_earned, 10, "the killer earns")
	assert_eq(_run.get_player(TEAMMATE_PEER_ID).echo_shards_earned, 0, "a team-mate earns nothing")
	assert_eq(_run.shared_gold, 0, "echo is per player, never the shared gold pool")
	assert_true(_run.shared_ore.is_empty(), "and never the shared ore pool")


func test_award_stacks_on_the_same_slice() -> void:
	EchoShards.award(_run, _player, 10)
	EchoShards.award(_run, _player, 2)
	assert_eq(_run.get_player(PEER_ID).echo_shards_earned, 12, "the total accumulates")
	assert_eq(_gains.size(), 2, "and announces each time")


func test_award_pays_nothing_without_a_live_run_or_a_player() -> void:
	assert_eq(EchoShards.award(null, _player, 10), 0, "no run, no payout")
	assert_eq(EchoShards.award(_run, null, 10), 0, "no player, no payout")
	assert_eq(_gains.size(), 0, "and nothing announced")


func test_award_pays_nothing_for_a_peer_who_is_not_in_the_run() -> void:
	var stranger: Player = _harness.make_player()
	stranger.peer_id = 99
	assert_eq(EchoShards.award(_run, stranger, 10), 0, "peer 99 has no slice")
	assert_eq(_gains.size(), 0, "and nothing announced")
