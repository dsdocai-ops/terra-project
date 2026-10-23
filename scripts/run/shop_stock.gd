class_name ShopStock
extends RefCounted
## What a shop sells and what it costs (SPEC-run-economy "Shops"). Owned by
## run-economy (W5-B3). Pure: the rng, the pools and the price modifiers are all
## arguments, so a stock is a function of the run seed and nothing else.
##
## A Shopkeeper stocks 4 items: 1 relic, 1 ability rune, 1 potion, 1 random
## (ore, or a rare weapon drop). Merchant's Badge adds a fifth and -15%; Haggler is
## -10% per rank; Greed Chain triples every price. Vesper (10% per floor, replacing
## the shopkeeper) sells 2 cursed relics and 1 legendary.
##
## blocked on Dev A (W5-A): ability runes and weapons live in their lanes. The rune
## slot is filled from an id list the caller passes (empty means the slot is left
## out, not faked), and the random slot's weapon branch is absent until weapon
## drops exist.

const KIND_RELIC: StringName = &"relic"
const KIND_RUNE: StringName = &"rune"
const KIND_POTION: StringName = &"potion"
const KIND_ORE: StringName = &"ore"

## Base gold prices; the spec's open question (prices per rarity) is answered
## here, as constants, in week 5.
const RELIC_PRICES: Dictionary[int, int] = {
	RelicData.Rarity.COMMON: 60,
	RelicData.Rarity.RARE: 110,
	RelicData.Rarity.EPIC: 180,
	RelicData.Rarity.LEGENDARY: 300,
	RelicData.Rarity.CURSED: 90,
}
const RUNE_PRICE: int = 100
const ORE_PRICE: int = 45
const ORE_AMOUNT: int = 3

const HAGGLER_DISCOUNT_PER_RANK: float = 0.10
const BADGE_DISCOUNT: float = 0.15
const GREED_CHAIN_MULTIPLIER: int = 3
## Discounts never take a price below this share of the base.
const MIN_PRICE_FACTOR: float = 0.1

const BASE_ITEM_COUNT: int = 4
const VESPER_CHANCE: float = 0.10
const VESPER_CURSED_COUNT: int = 2


## One slot on the shelf.
class Item extends RefCounted:
	var kind: StringName = &""
	var id: StringName = &""
	## Units handed over on purchase (ore comes in threes).
	var amount: int = 1
	var base_price: int = 0
	var sold: bool = false

	func _init(p_kind: StringName, p_id: StringName, p_price: int, p_amount: int = 1) -> void:
		kind = p_kind
		id = p_id
		base_price = p_price
		amount = p_amount


## The price after modifiers. Never below 1 gold.
static func price_for(base_price: int, haggler_rank: int, has_badge: bool, has_greed_chain: bool) -> int:
	var factor: float = 1.0 - HAGGLER_DISCOUNT_PER_RANK * maxi(haggler_rank, 0)
	if has_badge:
		factor -= BADGE_DISCOUNT
	factor = maxf(factor, MIN_PRICE_FACTOR)
	var price: int = maxi(1, roundi(float(base_price) * factor))
	return price * GREED_CHAIN_MULTIPLIER if has_greed_chain else price


static func relic_price(rarity: int) -> int:
	return int(RELIC_PRICES.get(rarity, RELIC_PRICES[RelicData.Rarity.COMMON]))


## The standing shelf: relic, rune, potion, random, plus one more with the Badge.
## Slots the content cannot fill yet are skipped.
static func build(
	rng: RandomNumberGenerator,
	relic_pool: Array[RelicData],
	rune_ids: Array[StringName],
	biome_index: int,
	has_badge: bool = false,
) -> Array[Item]:
	var shelf: Array[Item] = []
	_append(shelf, _relic_item(rng, relic_pool, false))
	if not rune_ids.is_empty():
		shelf.append(Item.new(KIND_RUNE, rune_ids[rng.randi_range(0, rune_ids.size() - 1)], RUNE_PRICE))
	_append(shelf, _potion_item(rng))
	_append(shelf, _random_item(rng, biome_index))
	if has_badge:
		_append(shelf, _random_item(rng, biome_index))
	return shelf


## True when Vesper replaces the shopkeeper this floor.
static func roll_vesper(rng: RandomNumberGenerator) -> bool:
	return rng.randf() < VESPER_CHANCE


## Vesper's shelf: 2 cursed relics and 1 legendary.
static func build_vesper(rng: RandomNumberGenerator, relic_pool: Array[RelicData]) -> Array[Item]:
	var shelf: Array[Item] = []
	var taken: Array[StringName] = []
	for pick: int in range(VESPER_CURSED_COUNT):
		var cursed: Item = _relic_of_rarity(rng, relic_pool, RelicData.Rarity.CURSED, taken)
		_append(shelf, cursed)
	_append(shelf, _relic_of_rarity(rng, relic_pool, RelicData.Rarity.LEGENDARY, taken))
	return shelf


static func _append(shelf: Array[Item], item: Item) -> void:
	if item != null:
		shelf.append(item)


static func _relic_item(rng: RandomNumberGenerator, pool: Array[RelicData], allow_cursed: bool) -> Item:
	var ids: Array[StringName] = RelicRoller.roll_from_pool(pool, {}, 0.0, 1, allow_cursed, rng)
	if ids.is_empty():
		return null
	for data: RelicData in pool:
		if data.id == ids[0]:
			return Item.new(KIND_RELIC, data.id, relic_price(data.rarity))
	return null


static func _relic_of_rarity(
	rng: RandomNumberGenerator,
	pool: Array[RelicData],
	rarity: int,
	taken: Array[StringName],
) -> Item:
	var candidates: Array[RelicData] = []
	for data: RelicData in pool:
		if data.rarity == rarity and not taken.has(data.id):
			candidates.append(data)
	if candidates.is_empty():
		return null
	var chosen: RelicData = candidates[rng.randi_range(0, candidates.size() - 1)]
	taken.append(chosen.id)
	return Item.new(KIND_RELIC, chosen.id, relic_price(rarity))


static func _potion_item(rng: RandomNumberGenerator) -> Item:
	var kinds: Array[PotionData] = []
	for id: StringName in [&"heal", &"cleanse", &"haste", &"shield"]:
		var data: PotionData = PotionController.data_for(id)
		if data != null:
			kinds.append(data)
	if kinds.is_empty():
		return null
	var picked: PotionData = kinds[rng.randi_range(0, kinds.size() - 1)]
	return Item.new(KIND_POTION, picked.id, picked.price)


## The random slot: ore of the current biome (a rare weapon drop joins it once
## weapons land, blocked on Dev A).
static func _random_item(_rng: RandomNumberGenerator, biome_index: int) -> Item:
	var ore_id: StringName = OrePayout.id_for_biome(biome_index)
	if ore_id == &"":
		return null
	return Item.new(KIND_ORE, ore_id, ORE_PRICE, ORE_AMOUNT)
