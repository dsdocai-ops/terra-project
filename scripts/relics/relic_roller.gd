class_name RelicRoller
extends RefCounted
## The shared relic roll: rarity tier by weight, the relic by its own `weight`,
## filtered by what the player already holds at `max_stacks`. Owned by relics
## (W4-B5).
##
## SPEC-relics, "RelicData": "Rarity weights for Shrine rolls: common 60, rare
## 28, epic 10, legendary 2, adjusted by `Stat.LUCK` and Lucky Find (+5%/rank
## shift to higher tiers). Cursed never roll at Shrines." SPEC-run-economy,
## "Loot tables", fixes the Luck term: "Luck stat raises rarity rolls:
## `rarity_roll += LUCK * 0.01`." Those two sentences are the whole of the
## rarity stage and every number in this file comes from one of them.
##
## One helper for three callers: "Merchant shops and Treasure chests use the
## same roll helper `RelicRoller.roll(player, count, allow_cursed)`", and the
## Shrine calls it with `allow_cursed = false`, which is the spec's "cursed
## never roll at Shrines" — the only place the ban lives.
##
## Two stages, in this order:
##   1. the **tier**, from `Rarity`'s four weights over a 0..1 roll shifted by
##      Luck — `rarity_roll = rng.randf() + LUCK * 0.01`, so Luck moves the roll
##      up the cumulative axis and every point of it buys one percent of the
##      table;
##   2. the **relic**, a second weighted pick *inside* that tier on `weight`, so
##      `weight` decides which of a tier's relics comes up and never how often
##      the tier itself does. (The distribution gate reads the tiers for exactly
##      that reason: a lopsided pool must still roll 60/28/10/2.)
##
## `count` ids come back, all distinct, none of them a relic the player already
## holds `max_stacks` times. When the tier a roll lands in has nothing left to
## offer — every common held, or no epic in the pool at all — the roll walks to
## the nearest tier that does, nearest first with the lower tier winning a tie,
## rather than coming back empty. When the whole pool is exhausted it returns
## fewer than `count`, which is the honest answer.
##
## Sync: host only. Rolls are the host's (SPEC-relics, "Multiplayer ownership"),
## so a client asks with `request_pick_relic` and never rolls for itself. Both
## of the player's inputs are read from host-authoritative state: the held ids
## from the player's replicated `RunPlayerState` and Luck from the player's
## `StatBlock`. Nothing here writes anything.
##
## The two inputs are read through `held_counts()` and `luck_of()`, and the full
## form `roll_from_pool()` takes both plus the pool and the generator explicitly
## — which is how a shop re-roll can pass its own stock, and how the test drives
## a synthetic pool without a live run. `roll()` is the convenience shape the
## spec names, gathering those four and delegating.

## Where the content lives. SPEC-relics, "Data model": `data/relics/<id>.tres`.
const RELIC_DIR: String = "res://data/relics"

## How much of the rarity table one point of `Stat.LUCK` buys, from
## SPEC-run-economy's own term: "`rarity_roll += LUCK * 0.01`".
const LUCK_SHIFT_PER_POINT: float = 0.01

## The seed a roll with nobody watching takes: the project's one fixed fallback,
## taken from `Effect` so the roller and the effects that spawn from it cannot
## drift. A live run's own seed wins over it.
const DEFAULT_RNG_SEED: int = Effect.DEFAULT_RNG_SEED

## The rarity stage's tiers in ascending order. `CURSED` is deliberately not in
## it: the spec's weight table is the Shrine's, and a cursed relic has no Shrine
## weight at all (`RelicData.roll_weight()` returns 0 for it).
const TIER_ORDER: Array[int] = [
	RelicData.Rarity.COMMON,
	RelicData.Rarity.RARE,
	RelicData.Rarity.EPIC,
	RelicData.Rarity.LEGENDARY,
]

## The cursed tier's weight, used **only** when the caller passes
## `allow_cursed = true`. The spec gives no number for it: cursed relics are
## taken at a Cursed Altar rather than rolled, and the Shrine table simply does
## not include them. 6 is a judgment call, chosen so a cursed relic is genuinely
## reachable when a caller asks for one (about one roll in eighteen) while never
## crowding the four Shrine tiers — recorded as a HANDOFF decision so the human
## can set the real balance number.
const CURSED_RARITY_WEIGHT: int = 6

## The four Shrine tiers' total, read off `RelicData`'s own constants rather
## than written down again, so a weight change there moves this with it.
const RARITY_WEIGHT_TOTAL: int = (
	RelicData.RARITY_WEIGHT_COMMON
	+ RelicData.RARITY_WEIGHT_RARE
	+ RelicData.RARITY_WEIGHT_EPIC
	+ RelicData.RARITY_WEIGHT_LEGENDARY
)

## The node name a player's `StatBlock` lives on, from `Effect` so the roller
## and every effect read the same child.
const STAT_BLOCK_NODE: NodePath = Effect.STAT_BLOCK_NODE


# --- the roll the spec names ------------------------------------------------

## Rolls `count` relic ids for `player`, all distinct, none already held
## `max_stacks` times. `allow_cursed` is `false` at a Shrine and `true` at the
## callers that may hand one out.
##
## `pool` empty means "the whole content folder" (`load_pool()`); a caller with
## its own stock — a shop's re-roll — passes the stock it is allowed to offer.
## `rng` null means a generator seeded from the live run, so a roll is never
## clock-random.
static func roll(
	player: Player,
	count: int,
	allow_cursed: bool = false,
	rng: RandomNumberGenerator = null,
	pool: Array[RelicData] = [],
) -> Array[StringName]:
	var candidates: Array[RelicData] = pool
	if candidates.is_empty():
		candidates = load_pool()
	return roll_from_pool(candidates, held_counts(player), luck_of(player), count, allow_cursed, rng)


## The full form: every input explicit. This is the seam a caller with its own
## stock (a shop, a chest tier) and the test's synthetic pool both use — the
## player's own state is gathered by `roll()` and handed over here, so nothing
## in this function reads the tree.
static func roll_from_pool(
	pool: Array[RelicData],
	held: Dictionary[StringName, int],
	luck: float,
	count: int,
	allow_cursed: bool = false,
	rng: RandomNumberGenerator = null,
) -> Array[StringName]:
	var generator: RandomNumberGenerator = rng
	if generator == null:
		generator = seeded_rng()
	var chosen: Array[StringName] = []
	if count <= 0:
		return chosen
	for roll_index: int in range(count):
		var picked: RelicData = _pick(pool, held, chosen, allow_cursed, luck, generator)
		if picked == null:
			break
		chosen.append(picked.id)
	return chosen


# --- stage 1: the tier ------------------------------------------------------

## The rarity a roll lands in, from the shifted 0..1 `rarity_roll`. The tier
## boundaries are the cumulative weights over `RARITY_WEIGHT_TOTAL`, which at
## the spec's numbers are common [0, 0.60), rare [0.60, 0.88), epic
## [0.88, 0.98) and legendary [0.98, 1.0].
static func rarity_for_roll(rarity_roll: float, allow_cursed: bool) -> int:
	var tiers: Array[int] = rollable_tiers(allow_cursed)
	var total: int = rarity_weight_total(allow_cursed)
	var cumulative: float = 0.0
	for rarity: int in tiers:
		cumulative += float(rarity_weight(rarity, allow_cursed))
		if clampf(rarity_roll, 0.0, 1.0) * float(total) < cumulative:
			return rarity
	return tiers[tiers.size() - 1]


## The spec's Luck shift, applied to a 0..1 roll: "`rarity_roll += LUCK *
## 0.01`". Clamped to the table, so an absurd Luck tops out at the last tier
## rather than reading off the end of it.
static func shifted_roll(base_roll: float, luck: float) -> float:
	return clampf(base_roll + luck * LUCK_SHIFT_PER_POINT, 0.0, 1.0)


## The tiers a roll may land in, in ascending order. Cursed joins them only when
## the caller allows one.
static func rollable_tiers(allow_cursed: bool) -> Array[int]:
	var tiers: Array[int] = TIER_ORDER.duplicate()
	if allow_cursed:
		tiers.append(RelicData.Rarity.CURSED)
	return tiers


## The Shrine weight of `rarity`: the spec's own table, plus the cursed tier's
## weight when the caller allows one and 0 when it does not.
static func rarity_weight(rarity: int, allow_cursed: bool) -> int:
	if rarity == RelicData.Rarity.CURSED:
		return CURSED_RARITY_WEIGHT if allow_cursed else 0
	return RelicData.roll_weight(rarity)


## What the tier weights add up to for this caller. 100 at a Shrine.
static func rarity_weight_total(allow_cursed: bool) -> int:
	var total: int = 0
	for rarity: int in rollable_tiers(allow_cursed):
		total += rarity_weight(rarity, allow_cursed)
	return total


## Every tier with a candidate to offer, nearest to `rolled` first and the lower
## tier winning a tie. This is the order the fallback walks, so a roll that
## lands in an exhausted tier finds the closest one that is not.
##
## "Nearest" is by the `Rarity` enum's own ascending order, which
## `test_relic_data.gd` pins — so this stays correct only as long as rarity
## really is ordered least to most rare, which is what the enum's comment says.
static func nearest_tiers(rolled: int, allow_cursed: bool) -> Array[int]:
	var remaining: Array[int] = rollable_tiers(allow_cursed)
	var ordered: Array[int] = []
	while not remaining.is_empty():
		var best: int = 0
		for index: int in range(1, remaining.size()):
			if absi(remaining[index] - rolled) < absi(remaining[best] - rolled):
				best = index
		ordered.append(remaining[best])
		remaining.remove_at(best)
	return ordered


# --- stage 2: the relic ------------------------------------------------------

## One relic for one roll: roll the tier, walk to the nearest tier with
## something to offer, then pick inside it by `weight`. Null when nothing in the
## pool can be offered at all.
static func _pick(
	pool: Array[RelicData],
	held: Dictionary[StringName, int],
	chosen: Array[StringName],
	allow_cursed: bool,
	luck: float,
	rng: RandomNumberGenerator,
) -> RelicData:
	var rolled: int = rarity_for_roll(shifted_roll(rng.randf(), luck), allow_cursed)
	for rarity: int in nearest_tiers(rolled, allow_cursed):
		var candidates: Array[RelicData] = _offerable(pool, rarity, held, chosen, allow_cursed)
		if not candidates.is_empty():
			return _weighted_pick(candidates, rng)
	return null


## The relics of `rarity` this call may still offer: not held at `max_stacks`
## and not already chosen in this same roll. A cursed relic is offerable only
## when the caller allows one, which is the second half of the Shrine ban — a
## cursed relic cannot come up even if a caller's table were to give its tier a
## weight.
static func _offerable(
	pool: Array[RelicData],
	rarity: int,
	held: Dictionary[StringName, int],
	chosen: Array[StringName],
	allow_cursed: bool,
) -> Array[RelicData]:
	var offerable: Array[RelicData] = []
	for data: RelicData in pool:
		if data == null or data.rarity != rarity:
			continue
		if rarity == RelicData.Rarity.CURSED and not allow_cursed:
			continue
		if chosen.has(data.id):
			continue
		if int(held.get(data.id, 0)) >= data.max_stacks:
			continue
		offerable.append(data)
	return offerable


## One relic out of `candidates`, weighted by `weight`. A candidate at weight 0
## can never come up; when every candidate is at weight 0 the pick falls back to
## a uniform draw rather than returning nothing, so a pool of weightless
## fixtures still rolls.
static func _weighted_pick(candidates: Array[RelicData], rng: RandomNumberGenerator) -> RelicData:
	var total: float = 0.0
	for data: RelicData in candidates:
		total += maxf(data.weight, 0.0)
	if total <= 0.0:
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	var target: float = rng.randf() * total
	var running: float = 0.0
	for data: RelicData in candidates:
		running += maxf(data.weight, 0.0)
		if target < running:
			return data
	return candidates[candidates.size() - 1]


# --- the player's two inputs -------------------------------------------------

## `{relic id: copies}` for `player`, read from the slice the host keeps for its
## peer (SPEC-relics, "Interfaces consumed": `run-economy`'s
## `RunPlayerState.relics`). A player with no slice — a peer the run does not
## know, or town — holds nothing, so the roll offers everything.
##
## Copies and not a set: `max_stacks` asks how many of one relic are held, and
## the slice is the list a duplicate pick appends to.
static func held_counts(player: Player) -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	var slice: RunPlayerState = run_slice(player)
	if slice == null:
		return counts
	for relic_id: StringName in slice.relics:
		counts[relic_id] = int(counts.get(relic_id, 0)) + 1
	return counts


## The `RunPlayerState` the host keeps for `player`'s peer, or null when there
## is no live run or no slice for that peer. One place the run is reached, so
## the roller consumes run-economy at exactly one line.
static func run_slice(player: Player) -> RunPlayerState:
	if player == null:
		return null
	var live: RunState = GameState.run
	if live == null:
		return null
	return live.get_player(player.peer_id)


## `player`'s Luck, off the `StatBlock` the spec puts it on: "adjusted by
## `Stat.LUCK`". 0 when the player carries no `StatBlock` yet, which then shifts
## nothing — the state of the player scene until Dev A's composition lands.
static func luck_of(player: Player) -> float:
	if player == null:
		return 0.0
	var block: StatBlock = player.get_node_or_null(STAT_BLOCK_NODE) as StatBlock
	if block == null:
		return 0.0
	return block.get_value(StatBlock.Stat.LUCK)


## True when `id` is held at least `max_stacks` times, read from the pool's own
## entry for it. False for an id the pool does not hold: whether an unknown relic
## is maxed out is not this function's question.
static func held_at_max(id: StringName, held: Dictionary[StringName, int], pool: Array[RelicData]) -> bool:
	for data: RelicData in pool:
		if data != null and data.id == id:
			return int(held.get(id, 0)) >= data.max_stacks
	return false


# --- the pool ----------------------------------------------------------------

## Every relic `.tres` under `dir_path`, recursively. A folder that does not
## exist is an empty pool rather than an error — the fold is empty until the
## first relic batch lands, and a roll there must return nothing rather than
## fail.
static func load_pool(dir_path: String = RELIC_DIR) -> Array[RelicData]:
	var pool: Array[RelicData] = []
	for path: String in _tres_paths(dir_path):
		var data := load(path) as RelicData
		if data != null:
			pool.append(data)
	return pool


## The ids of a pool, in pool order.
static func ids_of(pool: Array[RelicData]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for data: RelicData in pool:
		if data != null:
			ids.append(data.id)
	return ids


## Every `.tres` under `dir_path`, recursively, as full `res://` paths. The same
## walk `test_relic_data.gd` does, so the loader and the data test scan one set.
static func _tres_paths(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(_tres_paths(full))
		elif entry.ends_with(".tres"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


# --- the generator -----------------------------------------------------------

## A generator seeded from the live run, or from `DEFAULT_RNG_SEED` when there
## is none. Never the clock: a roll has to replay from its seed the way an
## effect's procs do.
static func seeded_rng() -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = _host_seed()
	return generator


static func _host_seed() -> int:
	if GameState.run != null:
		return GameState.run.seed
	return DEFAULT_RNG_SEED