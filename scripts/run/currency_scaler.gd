class_name CurrencyScaler
extends RefCounted
## The biome depth curve for the run's currencies: how much more gold, ore and
## Echo Shards the same drop pays on a deeper biome. Owned by run-economy
## (W6-B5, goal G8).
##
## SPEC-run-economy's "Currencies" table prices every payout flat — an elite is
## 1 ore and 1 to 2 Echo Shards on any biome — and the death table settles those
## totals at the end of a run. The depth reward is the other half of the same
## design: the depth paragraph raises enemy HP and damage about 12% per biome
## (`Scaling`, stats-status's curve), so a deeper biome must also pay more, or
## the run's risk climbs and its income does not. This file is that curve.
##
## **The curve is a function of the live biome alone.** SPEC-run-economy's Map
## Room paragraph says "Starting deeper gives no catch-up loot; the design doc
## accepts this (risk vs reward)", so the curve reads `RunState.biome_index` and
## never the start floor: a shortcut run into biome 4 is paid as a biome-4 run
## because it *is* one, not because its party skipped anything. No input here is
## a player, a run or a node: every member is a `const` or a static function,
## the class is never instantiated and holds no state — the same pure shape
## `Scaling` and `RunEconomyRules` keep, and for the same reason (the curves are
## constants, identical on every peer, needing no replication).
##
## **Anchors, then curves.** The plan pins three: biome 1 pays 1.0x of the flat
## tables, biome 4 gold x1.2 and echo x1.4, biome 6 gold x1.5 and echo x2.0.
## Between the anchors each curve steps monotonically, with shallow biomes
## stepping gently and deep biomes stepping harder — the compounding shape of
## `Scaling`'s 12%-per-biome difficulty curve, so income roughly tracks the
## risk that earns it:
##
##   biome     1      2      3      4      5      6
##   gold    1.00   1.05   1.10   1.20   1.35   1.50
##   ore     1.00   1.00   1.05   1.10   1.20   1.30
##   echo    1.00   1.10   1.25   1.40   1.70   2.00
##
## The three currencies ramp differently on purpose. **Gold** rides the run's
## spending money — shops price by rarity, so depth multiplies what a party can
## carry out. **Echo Shards** are the steepest because they are the per-player
## meta currency and a deep run is the way you earn them; x2.0 at biome 6 makes
## the deepest biome worth twice a shallow one per shard. **Ore** is the
## gentlest, flat through biome 2 and topping at x1.3, because depth already
## pays ore in kind — copper gives way to iron, then crystal, pearl, ember_ore
## and heartstone — and the ore amounts are spent at building prices recorded in
## `data/` constants, so quantity scaling stays near flat rather than pricing
## the town twice. Every curve starts at 1.0 and never dips below it, so depth
## scaling can only raise a payout, never shrink one.
##
## Sync: pure statics, host only in practice. Every caller (`LootDrops.credit`,
## `OrePayout.award`, `EchoShards.award`) already refuses off-host, and a client
## learns the totals from the replicated run state rather than by scaling
## anything itself.

## The biome range the curves are defined over, matching `RunState.MIN_BIOME` /
## `MAX_BIOME`. Outside it a caller is clamped to the nearest biome, so an
## index of 0 reads as biome 1 and a pathologically deep index reads as biome 6
## rather than as an extrapolation.
const MIN_BIOME: int = 1
const MAX_BIOME: int = 6

## The multiplier every currency carries on biome 1: the flat spec tables
## themselves. Named once so "the curve never shrinks a payout" is one claim
## with one owner.
const FIRST_MULTIPLIER: float = 1.0

## The currency ids the scaler dispatches on — the same ids the payouts are
## announced under (`LootDrops.CURRENCY_GOLD`, `OrePayout.CURRENCY_ID`,
## `EchoShards.CURRENCY_ID`). A currency this file does not know scales not at
## all, so an unknown id can never turn into a lost payout.
const GOLD_ID: StringName = &"gold"
const ORE_ID: StringName = &"ore"
const ECHO_ID: StringName = &"echo"

## The gold curve, biome 1 to 6. Anchored at biome 4 x1.2 and biome 6 x1.5.
const GOLD_CURVE: Array[float] = [1.0, 1.05, 1.1, 1.2, 1.35, 1.5]

## The ore curve, biome 1 to 6. The gentlest of the three: flat through biome 2
## (the deep-biome reward there is the ore's kind, not its count), topping at
## x1.3.
const ORE_CURVE: Array[float] = [1.0, 1.0, 1.05, 1.1, 1.2, 1.3]

## The Echo Shard curve, biome 1 to 6. The steepest of the three: biome 4 x1.4
## and biome 6 x2.0, the per-player meta currency's depth reward.
const ECHO_CURVE: Array[float] = [1.0, 1.1, 1.25, 1.4, 1.7, 2.0]


# --- the curves -------------------------------------------------------------


## All three multipliers for `biome_index`, in one dictionary keyed by the
## currency ids above. The one whole-curve read; `multiplier_for()` is its
## single-currency view. Clamped at both ends of the biome range.
static func biome_multiplier(biome_index: int) -> Dictionary[StringName, float]:
	var depth: int = clampi(biome_index, MIN_BIOME, MAX_BIOME) - MIN_BIOME
	return {
		GOLD_ID: GOLD_CURVE[depth],
		ORE_ID: ORE_CURVE[depth],
		ECHO_ID: ECHO_CURVE[depth],
	}


## The multiplier `currency` carries on `biome_index`. A currency the curve does
## not name reads 1.0 — the base amount unchanged — rather than raising or
## guessing, so an unknown id pays exactly what the flat tables say.
static func multiplier_for(currency: StringName, biome_index: int) -> float:
	var depth: int = clampi(biome_index, MIN_BIOME, MAX_BIOME) - MIN_BIOME
	match currency:
		GOLD_ID:
			return GOLD_CURVE[depth]
		ORE_ID:
			return ORE_CURVE[depth]
		ECHO_ID:
			return ECHO_CURVE[depth]
	return FIRST_MULTIPLIER


## `base` of `currency` as its run on `biome_index` pays: the base through the
## curve, rounded once. A non-positive base stays 0 — scaling cannot invent a
## payout — and the result is never negative.
static func amount_for(currency: StringName, base: int, biome_index: int) -> int:
	if base <= 0:
		return 0
	return maxi(roundi(float(base) * multiplier_for(currency, biome_index)), 0)
