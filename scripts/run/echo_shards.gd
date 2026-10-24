class_name EchoShards
extends RefCounted
## The Echo Shard payout table and its four multipliers — the whole of "Echo
## Shards" in SPEC-run-economy's currency table. Owned by run-economy (W4-B8,
## goal G14; the depth factor is W6-B5, goal G8).
##
## SPEC-run-economy, "Currencies": "Echo Shards | 1 per floor cleared (2 in
## biomes 4 to 6), 1 to 2 per elite, 10 per mini-boss, 20 per biome boss,
## bounties; Echo Collector +50%, Echo Resonance +10%/rank, Heat multipliers |
## per player". SPEC-run-economy, "Testing": "Unit `test_echo_shards.gd`:
## payouts per floor/elite/boss by biome with multipliers."
##
## Echo Shards are the one currency that is **per player** rather than shared, so
## every function here takes the earning `Player` and `award()` writes that
## player's own `RunPlayerState.echo_shards_earned` — never `RunState.shared_gold`
## or `shared_ore`.
##
## **The multipliers multiply.** The spec lists them with commas and says
## "multipliers", and the alternative reading (a sum of bonuses) would make a
## build's income fall as it stacked more of them; so
## `amount = base x (1 + Collector) x (1 + Resonance) x Heat x Depth`, rounded
## once at the end, in the spec's own order plus the depth curve's. The order
## does not change a product — it is stated so the reading is pinned rather than
## incidental, and a case asserts the product against the additive alternative.
## Depth is the fourth factor (W6-B5, goal G8): `CurrencyScaler`'s echo curve on
## the live run's biome, applied in `award()` where the run is at hand, never
## folded into the per-player factors above it.
##
## **Three of the four multipliers are other modules' and arrive as arguments.**
## Echo Collector is a relic (`ECHO_COLLECTOR_ID`, read off the holder's
## `EffectHost` the way every cross-module relic read in this lane is — an id,
## never a class and never a player flag). Echo Resonance is a rank in the Abyss
## branch of the skill tree (`progression-trees`, week 7) and Heat is an endgame
## modifier total (`endgame`, week 11), so neither has a home in this module
## today: they arrive as `resonance_ranks` and `heat_multiplier` parameters, and
## their owners pass their own numbers when they land. Nothing is invented for
## them here — a run with no tree and no Heat level passes 0 and 1.0 and reads
## the spec's bare table.
##
## Sync: host only. SPEC-run-economy, "Multiplayer ownership": "Run state, votes,
## loot rolls, currency totals ... host". `award()` refuses off-host, and a
## client learns its total from the replicated `RunPlayerState` rather than by
## paying itself.

## Shards for finishing a floor, and what a biome from `DEEP_BIOME` on pays
## instead. SPEC-run-economy: "1 per floor cleared (2 in biomes 4 to 6)".
const PER_FLOOR: int = 1
const PER_FLOOR_DEEP: int = 2
const DEEP_BIOME: int = 4
## Shards for an elite kill: "1 to 2 per elite".
const PER_ELITE_MIN: int = 1
const PER_ELITE_MAX: int = 2
## Shards for a mini-boss and for a biome boss.
const PER_MINI_BOSS: int = 10
const PER_BIOME_BOSS: int = 20

## The biome range the floor payout is defined over, matching
## `RunState.MIN_BIOME` / `MAX_BIOME`.
const MIN_BIOME: int = 1
const MAX_BIOME: int = 6

## Echo Collector, design doc 9.1 no. 51 ("+50% Echo Shards this run"). The id
## is the relic's snake_case file name; the relic itself is week-11 content this
## lane does not author, so the read is by id and a run without it reads 0.
const ECHO_COLLECTOR_ID: StringName = &"echo_collector"
const ECHO_COLLECTOR_BONUS: float = 0.5
## Echo Resonance, design doc's Abyss branch: "+10% Echo Shard gain" per rank.
const ECHO_RESONANCE_PER_RANK: float = 0.10
## The Heat multiplier a run without a Heat level carries (SPEC-endgame's ten
## stackable modifiers are week 11's).
const NO_HEAT_MULTIPLIER: float = 1.0
## The biome depth multiplier a call without a run's biome carries: the flat
## spec tables, unscaled. `award()` always passes the live run's curve.
const NO_DEPTH_MULTIPLIER: float = 1.0

## The currency id every echo payout is announced under,
## `Events.currency_gained(player, currency, amount)`.
const CURRENCY_ID: StringName = &"echo"

## The node a player's effects are read from (`player.EffectHost`).
const EFFECT_HOST_NODE: NodePath = ^"EffectHost"


# --- the table --------------------------------------------------------------


## Shards for clearing one floor of `biome_index`: 1, or 2 from biome 4 on.
## Clamped at both ends, so a caller outside the biome range reads the nearest
## biome's number rather than an extrapolated one.
static func for_floor_cleared(biome_index: int) -> int:
	if clampi(biome_index, MIN_BIOME, MAX_BIOME) >= DEEP_BIOME:
		return PER_FLOOR_DEEP
	return PER_FLOOR


## Shards for one elite: uniform in 1..2, drawn from `rng`. A null generator
## falls back to `RelicRoller.seeded_rng()`, which is seeded from the live run —
## never the clock — so an elite's payout replays from the run's seed.
static func for_elite(rng: RandomNumberGenerator = null) -> int:
	var generator: RandomNumberGenerator = rng
	if generator == null:
		generator = RelicRoller.seeded_rng()
	return generator.randi_range(PER_ELITE_MIN, PER_ELITE_MAX)


## Shards for a mini-boss.
static func for_mini_boss() -> int:
	return PER_MINI_BOSS


## Shards for a biome boss.
static func for_biome_boss() -> int:
	return PER_BIOME_BOSS


# --- the multipliers --------------------------------------------------------


## `player`'s Echo Collector bonus as a fraction: the spec's 0.5 while the relic
## is attached, 0.0 otherwise. Read as an id off the holder's `EffectHost` — the
## one registry of what a player holds — so a player with no host (a client
## copy, or a fixture without one) reads no bonus, the same answer as holding the
## wrong relic.
static func collector_bonus(player: Player) -> float:
	if player == null:
		return 0.0
	var host: EffectHost = player.get_node_or_null(EFFECT_HOST_NODE) as EffectHost
	if host == null:
		return 0.0
	if not host.has_effect(ECHO_COLLECTOR_ID):
		return 0.0
	return ECHO_COLLECTOR_BONUS


## Echo Resonance's bonus as a fraction: 10% per rank. A rank count below zero
## adds nothing rather than subtracting, so a bad read cannot turn a payout into
## a penalty.
static func resonance_bonus(resonance_ranks: int) -> float:
	return ECHO_RESONANCE_PER_RANK * float(maxi(resonance_ranks, 0))


## The whole multiplier for `player`: the four factors multiplied, in the
## spec's own order (Echo Collector, Echo Resonance, Heat) and then the biome
## depth curve's (W6-B5, goal G8). `heat_multiplier` is clamped at zero so a
## caller cannot hand back a negative payout; `depth_multiplier` is clamped the
## same way, though `CurrencyScaler`'s own curve never dips below 1.0.
static func multiplier_for(
	player: Player,
	resonance_ranks: int = 0,
	heat_multiplier: float = NO_HEAT_MULTIPLIER,
	depth_multiplier: float = NO_DEPTH_MULTIPLIER,
) -> float:
	var collector: float = 1.0 + collector_bonus(player)
	var resonance: float = 1.0 + resonance_bonus(resonance_ranks)
	var heat: float = maxf(heat_multiplier, 0.0)
	var depth: float = maxf(depth_multiplier, 0.0)
	return collector * resonance * heat * depth


## `base` shards for `player`, with all four multipliers applied and the result
## rounded once. The one place a payout amount is computed, so every caller
## pays the same number.
static func amount_for(
	base: int,
	player: Player,
	resonance_ranks: int = 0,
	heat_multiplier: float = NO_HEAT_MULTIPLIER,
	depth_multiplier: float = NO_DEPTH_MULTIPLIER,
) -> int:
	return maxi(roundi(float(base) * multiplier_for(player, resonance_ranks, heat_multiplier, depth_multiplier)), 0)


# --- the award --------------------------------------------------------------


## Host only. Pays `base` shards to `player`, announces it on
## `Events.currency_gained` once, and returns what was paid. 0 — with nothing
## written and nothing announced — when this peer is not the host, when there is
## no run, when there is no player, or when that player has no slice in the run:
## a client never pays itself (SPEC-run-economy, "Multiplayer ownership").
##
## The announcement is what the HUD's currency row and the effect overlay listen
## to; the write is the run's own record and what `RunResult` reads at the end of
## the run. The base pays through the live run's biome depth curve
## (`CurrencyScaler`, W6-B5, goal G8), so the same elite pays more the deeper
## the run stands — and a floor-clear payout would pay through this one seam
## too, when its caller lands.
static func award(
	run: RunState,
	player: Player,
	base: int,
	resonance_ranks: int = 0,
	heat_multiplier: float = NO_HEAT_MULTIPLIER,
) -> int:
	if not NetworkManager.is_host:
		push_warning("[echo] payout refused: the host owns currency totals")
		return 0
	if run == null or player == null:
		return 0
	var slice: RunPlayerState = run.get_player(player.peer_id)
	if slice == null:
		push_warning("[echo] peer %d is not in this run; its payout is dropped" % player.peer_id)
		return 0
	var paid: int = amount_for(
		base, player, resonance_ranks, heat_multiplier,
		CurrencyScaler.multiplier_for(CurrencyScaler.ECHO_ID, run.biome_index),
	)
	if paid <= 0:
		return 0
	slice.echo_shards_earned += paid
	Events.currency_gained.emit(player, CURRENCY_ID, paid)
	return paid
