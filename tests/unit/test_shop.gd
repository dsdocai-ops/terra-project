extends GutTest
## Shops (SPEC-run-economy "Shops", W5-B3): the stock rules (ShopStock), the
## price modifiers, Vesper, and the Shopkeeper's host-side till.

const PEER_ID: int = 1
const RUN_SEED: int = 4711

var _harness: EffectHarness = null
var _player: Player = null
var _keeper: Shopkeeper = null
var _sales: Array[Array] = []
var _forwarded: Array[int] = []


func before_each() -> void:
	NetworkManager.start_solo()
	_harness = EffectHarness.new(self)
	_harness.setup()
	_player = _harness.make_player()
	_player.peer_id = PEER_ID
	var run: RunState = RunState.new(RUN_SEED, 1)
	run.add_player(RunPlayerState.new(PEER_ID))
	run.shared_gold = 1000
	GameState.run = run
	_keeper = (load(Shopkeeper.SCENE_PATH) as PackedScene).instantiate() as Shopkeeper
	add_child_autofree(_keeper)
	_sales.clear()
	_forwarded.clear()
	_keeper.purchased.connect(_on_purchased)
	_keeper.purchase_forwarded.connect(_on_forwarded)


func after_each() -> void:
	GameState.profile = null
	EffectHarness.reset_globals()


func _on_purchased(peer_id: int, index: int, price: int) -> void:
	_sales.append([peer_id, index, price])


func _on_forwarded(peer_id: int, _index: int) -> void:
	_forwarded.append(peer_id)


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _relic(id: StringName, rarity: int) -> RelicData:
	var data: RelicData = RelicData.new()
	data.id = id
	data.rarity = rarity
	return data


func _pool() -> Array[RelicData]:
	return [
		_relic(&"a", RelicData.Rarity.COMMON),
		_relic(&"b", RelicData.Rarity.RARE),
		_relic(&"c", RelicData.Rarity.LEGENDARY),
		_relic(&"x", RelicData.Rarity.CURSED),
		_relic(&"y", RelicData.Rarity.CURSED),
	]


func _index_of(kind: StringName) -> int:
	var shelf: Array[ShopStock.Item] = _keeper.stock()
	for i: int in range(shelf.size()):
		if shelf[i].kind == kind and not shelf[i].sold:
			return i
	return -1


func _profile_with_slots(slots: int, skill_tree: Dictionary = {}) -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.potions[PlayerProfile.POTION_SLOTS] = slots
	profile.skill_tree = skill_tree
	GameState.profile = profile


# --- prices ------------------------------------------------------------------


func test_base_price_is_unchanged_without_modifiers() -> void:
	assert_eq(ShopStock.price_for(100, 0, false, false), 100)


func test_haggler_takes_ten_percent_per_rank() -> void:
	assert_eq(ShopStock.price_for(100, 1, false, false), 90)
	assert_eq(ShopStock.price_for(100, 2, false, false), 80)


func test_merchants_badge_takes_fifteen_percent() -> void:
	assert_eq(ShopStock.price_for(100, 0, true, false), 85)


func test_haggler_and_badge_stack() -> void:
	assert_eq(ShopStock.price_for(100, 2, true, false), 65)


func test_greed_chain_triples_the_price() -> void:
	assert_eq(ShopStock.price_for(100, 0, false, true), 300)
	assert_eq(ShopStock.price_for(100, 2, false, true), 240, "discounts apply, then x3")


func test_a_price_is_never_below_one() -> void:
	assert_eq(ShopStock.price_for(1, 9, true, false), 1)


func test_relic_prices_rise_with_rarity() -> void:
	assert_lt(ShopStock.relic_price(RelicData.Rarity.COMMON), ShopStock.relic_price(RelicData.Rarity.RARE))
	assert_lt(ShopStock.relic_price(RelicData.Rarity.RARE), ShopStock.relic_price(RelicData.Rarity.LEGENDARY))


# --- stock -------------------------------------------------------------------


func test_a_standard_shelf_has_relic_potion_and_random_slots() -> void:
	var shelf: Array[ShopStock.Item] = ShopStock.build(_rng(), _pool(), [], 1)
	assert_eq(shelf.size(), 3, "the rune slot waits on the abilities module")
	assert_eq(shelf[0].kind, ShopStock.KIND_RELIC)
	assert_eq(shelf[1].kind, ShopStock.KIND_POTION)
	assert_eq(shelf[2].kind, ShopStock.KIND_ORE)


func test_a_rune_slot_appears_when_runes_exist() -> void:
	var runes: Array[StringName] = [&"rune_a"]
	var shelf: Array[ShopStock.Item] = ShopStock.build(_rng(), _pool(), runes, 1)
	assert_eq(shelf.size(), 4, "relic, rune, potion, random")
	assert_eq(shelf[1].kind, ShopStock.KIND_RUNE)
	assert_eq(shelf[1].id, &"rune_a")


func test_merchants_badge_adds_a_fifth_item() -> void:
	var runes: Array[StringName] = [&"rune_a"]
	var shelf: Array[ShopStock.Item] = ShopStock.build(_rng(), _pool(), runes, 1, true)
	assert_eq(shelf.size(), 5)


func test_the_standard_shelf_never_sells_a_cursed_relic() -> void:
	for seed_value: int in range(40):
		var shelf: Array[ShopStock.Item] = ShopStock.build(_rng(seed_value), _pool(), [], 1)
		assert_ne(shelf[0].id, &"x")
		assert_ne(shelf[0].id, &"y")


func test_the_same_seed_gives_the_same_shelf() -> void:
	var first: Array[ShopStock.Item] = ShopStock.build(_rng(9), _pool(), [], 3)
	var second: Array[ShopStock.Item] = ShopStock.build(_rng(9), _pool(), [], 3)
	for i: int in range(first.size()):
		assert_eq(first[i].id, second[i].id)


func test_the_random_slot_sells_the_biomes_ore() -> void:
	var shelf: Array[ShopStock.Item] = ShopStock.build(_rng(), _pool(), [], 2)
	assert_eq(shelf[2].id, &"iron")
	assert_eq(shelf[2].amount, ShopStock.ORE_AMOUNT)


func test_vesper_sells_two_cursed_relics_and_a_legendary() -> void:
	var shelf: Array[ShopStock.Item] = ShopStock.build_vesper(_rng(), _pool())
	assert_eq(shelf.size(), 3)
	assert_eq(shelf[0].id == shelf[1].id, false, "two different cursed relics")
	assert_eq(shelf[2].id, &"c")
	var cursed_ids: Array[StringName] = [&"x", &"y"]
	assert_true(cursed_ids.has(shelf[0].id))
	assert_true(cursed_ids.has(shelf[1].id))


func test_vesper_replaces_the_shopkeeper_one_floor_in_ten() -> void:
	var rng: RandomNumberGenerator = _rng(3)
	var hits: int = 0
	for floor_roll: int in range(2000):
		if ShopStock.roll_vesper(rng):
			hits += 1
	assert_between(hits, 140, 260, "10% of 2000, give or take")


# --- the till ----------------------------------------------------------------


func test_interact_on_the_host_opens_the_shop() -> void:
	_keeper.interact(_player)
	assert_true(_keeper.stock().size() >= 3, "the shelf is rolled")


func test_buying_ore_spends_shared_gold_and_adds_the_ore() -> void:
	var index: int = _index_of(ShopStock.KIND_ORE)
	var price: int = _keeper.price_of(_player, index)
	assert_true(_keeper.buy(_player, index))
	assert_eq(GameState.run.shared_gold, 1000 - price)
	assert_eq(GameState.run.shared_ore[&"copper"], ShopStock.ORE_AMOUNT)
	assert_eq(_sales.size(), 1)


func test_an_item_sells_once() -> void:
	var index: int = _index_of(ShopStock.KIND_ORE)
	_keeper.buy(_player, index)
	assert_false(_keeper.buy(_player, index))
	assert_eq(_keeper.last_refusal, Shopkeeper.REFUSAL_SOLD)


func test_not_enough_gold_refuses_and_changes_nothing() -> void:
	GameState.run.shared_gold = 1
	var index: int = _index_of(ShopStock.KIND_ORE)
	assert_false(_keeper.buy(_player, index))
	assert_eq(_keeper.last_refusal, Shopkeeper.REFUSAL_POOR)
	assert_eq(GameState.run.shared_gold, 1)
	assert_true(GameState.run.shared_ore.is_empty())


func test_a_bad_index_is_refused() -> void:
	assert_false(_keeper.buy(_player, 99))
	assert_eq(_keeper.last_refusal, Shopkeeper.REFUSAL_BAD_INDEX)


func test_a_downed_player_cannot_buy() -> void:
	GameState.run.get_player(PEER_ID).is_downed = true
	assert_false(_keeper.buy(_player, _index_of(ShopStock.KIND_ORE)))
	assert_eq(_keeper.last_refusal, Shopkeeper.REFUSAL_DOWNED)


func test_buying_a_potion_needs_a_free_slot() -> void:
	var index: int = _index_of(ShopStock.KIND_POTION)
	assert_false(_keeper.buy(_player, index), "no Alchemist slots yet")
	assert_eq(_keeper.last_refusal, Shopkeeper.REFUSAL_NO_ROOM)
	assert_eq(GameState.run.shared_gold, 1000, "a refused sale costs nothing")
	_profile_with_slots(1)
	assert_true(_keeper.buy(_player, index))
	assert_eq(GameState.run.get_player(PEER_ID).potions.size(), 1)


func test_buying_a_relic_attaches_it_to_the_buyer() -> void:
	var index: int = _index_of(ShopStock.KIND_RELIC)
	var relic_id: StringName = _keeper.stock()[index].id
	assert_true(_keeper.buy(_player, index), "refusal: %s" % _keeper.last_refusal)
	assert_true(GameState.run.get_player(PEER_ID).relics.has(relic_id))


func test_haggler_lowers_what_the_till_charges() -> void:
	var index: int = _index_of(ShopStock.KIND_ORE)
	var full: int = _keeper.price_of(_player, index)
	_profile_with_slots(0, {"haggler": 2})
	assert_eq(_keeper.price_of(_player, index), ShopStock.price_for(ShopStock.ORE_PRICE, 2, false, false))
	assert_lt(_keeper.price_of(_player, index), full)


func test_greed_chain_triples_the_till_price() -> void:
	var index: int = _index_of(ShopStock.KIND_ORE)
	var plain: int = _keeper.price_of(_player, index)
	EffectHostPlayer.install(_player)
	var host: EffectHost = RelicFlow.effect_host_of(_player)
	var greed: RelicData = RelicData.new()
	greed.id = Shopkeeper.GREED_CHAIN
	greed.effect_script = load("res://tests/helpers/relic_marker_effect.gd") as GDScript
	host.add(greed)
	assert_eq(_keeper.price_of(_player, index), plain * 3)


func test_a_client_forwards_the_purchase() -> void:
	NetworkManager.is_host = false
	assert_false(_keeper.buy(_player, 0))
	NetworkManager.is_host = true
	assert_eq(_forwarded, [PEER_ID] as Array[int])


func test_the_shelf_is_the_same_for_the_same_run_and_floor() -> void:
	var other: Shopkeeper = (load(Shopkeeper.SCENE_PATH) as PackedScene).instantiate() as Shopkeeper
	add_child_autofree(other)
	var a: Array[ShopStock.Item] = _keeper.stock()
	var b: Array[ShopStock.Item] = other.stock()
	assert_eq(a.size(), b.size())
	for i: int in range(a.size()):
		assert_eq(a[i].id, b[i].id)


func test_the_populator_registration_is_a_guarded_noop_without_the_generator() -> void:
	if RoomPopulator.generator_script() != null:
		pending("the generator exists; registration is covered by its own wiring")
		return
	assert_false(Shopkeeper.register_populator())
	assert_eq(Shopkeeper.blocker_warnings(), 1)


func test_a_shop_never_sells_the_shield_potion_yet() -> void:
	for seed_value: int in range(1, 60):
		for item: ShopStock.Item in ShopStock.build(_rng(seed_value), _pool(), [], 1):
			assert_ne(item.id, &"shield", "shield waits on absorb_hit being called")
