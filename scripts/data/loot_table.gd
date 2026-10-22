class_name LootTable
extends Resource
## A weighted drop table: the one roll every chest, breakable, enemy and shop
## uses. Owned by run-economy (W4-B8, goal G13).
##
## SPEC-run-economy, "Chests, breakables, mining nodes": "`LootTable` Resource:
## weighted entries `{kind, id or rarity, weight, min, max}`. Chest rarity tiers
## common/rare/legendary; ... Luck stat raises rarity rolls: `rarity_roll +=
## LUCK * 0.01`." Those two sentences are the whole of this file.
##
## An entry names its **kind** (`Pickup.KINDS`) and then either a fixed content
## **id** (an ore type, a relic id, a rune) or a **rarity** — never both. `min`
## and `max` bound the amount the drop carries; `min == max` is a fixed amount.
## `weight` decides how often the entry comes up, so the table's shares are the
## entries' weights and nothing else.
##
## A rarity entry's own rarity is a **floor**: the drop's tier is the higher of
## that floor and the table's own rarity roll, so a rare chest can still yield an
## epic and a common entry never downgrades to nothing. The rarity roll is the
## spec's own: `rarity_roll = rng.randf() + LUCK * 0.01`, clamped to 0..1 and
## mapped over `RelicData`'s four Shrine tier weights (common 60, rare 28, epic
## 10, legendary 2). The formula lives in `RelicRoller.shifted_roll()` and
## `RelicRoller.rarity_for_roll()` — the same sentence of SPEC-run-economy drives
## both, so this file delegates rather than keeping a second copy that could
## drift. Cursed is never in the tier table: it is taken at an altar, not rolled.
##
## `entries` is the exported boundary: an `Array[Dictionary]` as authored in a
## `.tres`. It is converted immediately by `entry_list()` into typed `Entry`
## objects (SPEC-project C12: untyped data only at the boundary), which is what
## every roll reads. No caching, because a table is a handful of entries and a
## stale copy would outlive an edit.
##
## Sync: none (data). The rolls themselves are the host's (SPEC-run-economy,
## "Multiplayer ownership": "loot rolls ... host"); a client never rolls a table.

## `Entry.rarity`'s "this entry names an id instead" sentinel.
const RARITY_NONE: int = -1

## How much of the rarity table one point of `Stat.LUCK` buys, from
## SPEC-run-economy's own term: "`rarity_roll += LUCK * 0.01`". Taken from
## `RelicRoller`, which owns the formula, so the two cannot disagree.
const LUCK_SHIFT_PER_POINT: float = RelicRoller.LUCK_SHIFT_PER_POINT

## SPEC-run-economy: "Chest rarity tiers common/rare/legendary", in that order.
const CHEST_TIER_COMMON: int = RelicData.Rarity.COMMON
const CHEST_TIER_RARE: int = RelicData.Rarity.RARE
const CHEST_TIER_LEGENDARY: int = RelicData.Rarity.LEGENDARY
const CHEST_TIERS: Array[int] = [CHEST_TIER_COMMON, CHEST_TIER_RARE, CHEST_TIER_LEGENDARY]

## The raw entries, authored in the `.tres`: `{kind, id or rarity, weight, min,
## max}`. Converted by `entry_list()` before anything reads them.
@export var entries: Array[Dictionary] = []


## One entry after the boundary conversion. Typed so a roll reads fields rather
## than dictionary keys, and so `rarity`/`id` cannot both be set by accident.
class Entry extends RefCounted:
	## One of `Pickup.KINDS`.
	var kind: StringName = &""
	## A fixed content id, or empty when the entry rolls a rarity.
	var id: StringName = &""
	## `LootTable.RARITY_NONE`, or the floor tier of a rarity roll.
	var rarity: int = -1
	## Relative frequency among the table's entries.
	var weight: float = 1.0
	var min_amount: int = 1
	var max_amount: int = 1

	## True when this entry yields a rarity rather than a fixed id.
	func rolls_rarity() -> bool:
		return rarity != LootTable.RARITY_NONE


## `raw` converted to a typed `Entry`. Missing fields take the shape's defaults
## (weight 1, amount 1, no id, no rarity); a reversed amount range is ordered
## rather than rejected, so one bad range cannot make a table unrollable.
static func parse_entry(raw: Dictionary) -> Entry:
	var entry := Entry.new()
	entry.kind = StringName(String(raw.get("kind", "")))
	entry.id = StringName(String(raw.get("id", "")))
	if raw.has("rarity"):
		entry.rarity = int(raw["rarity"])
	entry.weight = float(raw.get("weight", 1.0))
	entry.min_amount = int(raw.get("min", 1))
	entry.max_amount = int(raw.get("max", entry.min_amount))
	if entry.max_amount < entry.min_amount:
		var lower: int = entry.max_amount
		entry.max_amount = entry.min_amount
		entry.min_amount = lower
	return entry


## Every entry, converted. Empty or blank dictionaries are skipped rather than
## turned into weightless entries the roll would have to filter out again.
func entry_list() -> Array[Entry]:
	var out: Array[Entry] = []
	for raw: Dictionary in entries:
		if raw == null or raw.is_empty():
			continue
		out.append(parse_entry(raw))
	return out


## The sum of every positive weight. A table with 0 here has nothing to offer.
func total_weight() -> float:
	var total: float = 0.0
	for entry: Entry in entry_list():
		total += maxf(entry.weight, 0.0)
	return total


# --- the roll --------------------------------------------------------------

## One drop: `{kind, id, rarity, amount}`.
##
## The entry is picked by `weight`; `amount` is uniform in `[min, max]`; `id` is
## the entry's fixed id (or empty on a rarity entry) and `rarity` is
## `RARITY_NONE` on an id entry (or the floored tier on a rarity entry). An
## empty dictionary means the table had nothing to roll.
##
## `rng` null falls back to `RelicRoller.seeded_rng()`, which is seeded from the
## live run — never the clock — so a roll replays from its seed.
func roll(rng: RandomNumberGenerator = null, luck: float = 0.0) -> Dictionary:
	var generator: RandomNumberGenerator = rng
	if generator == null:
		generator = RelicRoller.seeded_rng()
	var candidates: Array[Entry] = entry_list()
	var total: float = 0.0
	for entry: Entry in candidates:
		total += maxf(entry.weight, 0.0)
	if total <= 0.0:
		return {}
	var target: float = generator.randf() * total
	var picked: Entry = null
	var running: float = 0.0
	for entry: Entry in candidates:
		if entry.weight <= 0.0:
			continue
		running += entry.weight
		picked = entry
		if target < running:
			break
	if picked == null:
		return {}
	return _result_for(picked, generator, luck)


## `count` rolls in order. One `roll()` per step, so the sequence is exactly what
## a caller looping `roll()` would get.
func roll_many(count: int, rng: RandomNumberGenerator = null, luck: float = 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for roll_index: int in range(maxi(count, 0)):
		var result: Dictionary = roll(rng, luck)
		if result.is_empty():
			break
		out.append(result)
	return out


## The result dictionary for one picked entry. Draw order is amount first, then
## the rarity roll, so a seeded sequence is stable.
func _result_for(entry: Entry, rng: RandomNumberGenerator, luck: float) -> Dictionary:
	var result: Dictionary = {
		"kind": entry.kind,
		"id": entry.id,
		"rarity": RARITY_NONE,
		"amount": rng.randi_range(entry.min_amount, entry.max_amount),
	}
	if entry.rolls_rarity():
		var rolled: int = rarity_for_roll(shifted_rarity_roll(rng.randf(), luck))
		result["id"] = &""
		result["rarity"] = maxi(entry.rarity, rolled)
	return result


# --- the rarity roll -------------------------------------------------------

## The spec's Luck shift over a 0..1 rarity roll: "`rarity_roll += LUCK *
## 0.01`", clamped so an absurd Luck tops out instead of reading past the table.
## Delegates to `RelicRoller`, where the sentence is also implemented.
static func shifted_rarity_roll(base_roll: float, luck: float) -> float:
	return RelicRoller.shifted_roll(base_roll, luck)


## The tier a 0..1 rarity roll lands in, off the spec's four weights. Cursed is
## never included: a loot table does not hand one out.
static func rarity_for_roll(rarity_roll: float) -> int:
	return RelicRoller.rarity_for_roll(rarity_roll, false)


## True when `rarity` is one of the three chest tiers.
static func is_chest_tier(rarity: int) -> bool:
	return CHEST_TIERS.has(rarity)
