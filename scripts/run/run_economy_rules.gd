class_name RunEconomyRules
extends RefCounted
## The death and extraction table of SPEC-run-economy, as pure functions: what
## each player keeps and loses when a run ends. Owned by run-economy (week 5).
## Sync: host-only. GameState.end_run() calls it once and sends each peer its
## own row of the result; nothing here reads the scene tree or the network.
##
## Extract (and VICTORY): gold 100%, ore 100%, relics lost (Safe Line keeps one
## random), Echo Shards and class XP kept. Death (DEFEAT and ABORT): gold 25%
## plus 10% per Deep Pockets rank, ore lost (Ore Heart keeps 50%), relics lost.
## Echo Shards and class XP are kept either way; story progress, codex and
## achievements are banked through the profile and never live in these tables.
##
## Shared pools (gold, ore) are split evenly among the party first; the keep
## rule then runs on each share with that player's own skill ranks. With equal
## ranks that is the spec's "death rule once, then split". Integer division
## drops the remainder, so a 3-gold pool split between 2 players banks 1 + 1.

const DEEP_POCKETS: StringName = &"deep_pockets"
const ORE_HEART: StringName = &"ore_heart"
const SAFE_LINE: StringName = &"safe_line"

const EXTRACT_GOLD_PERCENT: int = 100
const DEATH_GOLD_PERCENT: int = 25
const DEEP_POCKETS_PERCENT_PER_RANK: int = 10
const EXTRACT_ORE_PERCENT: int = 100
const ORE_HEART_PERCENT: int = 50


## True for the endings that keep the carried loot: the rope vote passing and
## the final boss dying. DEFEAT and ABORT (a quit counts as death) lose it.
static func keeps_loot(reason: RunEndReason.Reason) -> bool:
	return reason == RunEndReason.Reason.EXTRACT or reason == RunEndReason.Reason.VICTORY


## Percent of a gold share kept at the end of a run, clamped to 100.
static func gold_percent(reason: RunEndReason.Reason, deep_pockets_rank: int) -> int:
	if keeps_loot(reason):
		return EXTRACT_GOLD_PERCENT
	var percent: int = DEATH_GOLD_PERCENT + DEEP_POCKETS_PERCENT_PER_RANK * maxi(0, deep_pockets_rank)
	return mini(percent, 100)


## Percent of an ore share kept at the end of a run.
static func ore_percent(reason: RunEndReason.Reason, ore_heart_rank: int) -> int:
	if keeps_loot(reason):
		return EXTRACT_ORE_PERCENT
	return ORE_HEART_PERCENT if ore_heart_rank > 0 else 0


## Fills `result` with a kept and a lost table for every player in `finished`.
## `ranks` maps peer_id -> {node_id: rank} for the skill-tree nodes the table
## reads; a peer with no entry has every rank at 0. The run's pools and slices
## are read, never written.
static func settle(
	result: RunResult,
	finished: RunState,
	ranks: Dictionary[int, Dictionary] = {},
) -> void:
	var party_size: int = maxi(1, finished.players.size())
	var gold_share: int = finished.shared_gold / party_size
	for peer_id: int in finished.players:
		var slice: RunPlayerState = finished.get_player(peer_id)
		var peer_ranks: Dictionary = ranks.get(peer_id, {})
		var kept: Dictionary = RunResult.empty_table()
		var lost: Dictionary = RunResult.empty_table()

		var kept_gold: int = gold_share * gold_percent(result.reason, _rank(peer_ranks, DEEP_POCKETS)) / 100
		kept[&"gold"] = kept_gold
		lost[&"gold"] = gold_share - kept_gold

		var ore_rate: int = ore_percent(result.reason, _rank(peer_ranks, ORE_HEART))
		var kept_ore: Dictionary = {}
		var lost_ore: Dictionary = {}
		for ore_id: StringName in finished.shared_ore:
			var share: int = int(finished.shared_ore[ore_id]) / party_size
			var kept_amount: int = share * ore_rate / 100
			kept_ore[ore_id] = kept_amount
			lost_ore[ore_id] = share - kept_amount
		kept[&"ore"] = kept_ore
		lost[&"ore"] = lost_ore

		var kept_relics: Array[StringName] = []
		var lost_relics: Array[StringName] = slice.relics.duplicate()
		if keeps_loot(result.reason) and _rank(peer_ranks, SAFE_LINE) > 0 and not lost_relics.is_empty():
			var pick: int = _safe_line_pick(finished.seed, peer_id, lost_relics.size())
			kept_relics.append(lost_relics[pick])
			lost_relics.remove_at(pick)
		kept[&"relics"] = kept_relics
		lost[&"relics"] = lost_relics

		kept[&"echo_shards"] = slice.echo_shards_earned
		kept[&"class_xp"] = slice.class_xp_earned
		result.set_player_tables(peer_id, kept, lost)


## Which relic Safe Line keeps: a roll seeded by the run seed and the peer, so
## the same run settles the same way on every call and in every test.
static func _safe_line_pick(run_seed: int, peer_id: int, relic_count: int) -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([run_seed, peer_id, SAFE_LINE])
	return rng.randi_range(0, relic_count - 1)


static func _rank(peer_ranks: Dictionary, node_id: StringName) -> int:
	return int(peer_ranks.get(node_id, peer_ranks.get(String(node_id), 0)))
