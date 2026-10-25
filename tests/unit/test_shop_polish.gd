extends GutTest
## G9 polish tests for the shop: biome-priced relics, the standing shelf's
## rarity cap, and the shopkeeper's purchase/refusal feedback blips.

const ShopStockScript := preload("res://scripts/run/shop_stock.gd")
const ShopkeeperScript := preload("res://scripts/run/shopkeeper.gd")
const RelicDataScript := preload("res://scripts/data/relic_data.gd")

var _keeper: Node = null


func before_each() -> void:
	_keeper = ShopkeeperScript.new()
	add_child_autofree(_keeper)


func after_each() -> void:
	if _keeper != null:
		_keeper.queue_free()
		_keeper = null
	# The host test stands in for NetworkManager; restore the default so a
	# failed assert never leaks host state into the next test.
	NetworkManager.is_host = false


# --- ShopStock.item_price: relic prices scale by biome depth -------------------

func test_item_price_scales_up_with_biome_index() -> void:
	var flat := ShopStockScript.item_price(RelicDataScript.Rarity.RARE, 1)
	var deep := ShopStockScript.item_price(RelicDataScript.Rarity.RARE, 3)
	assert_gt(deep, flat, "a RARE relic should cost more in biome 3 than biome 1")


func test_item_price_is_flat_at_the_biome_range_start() -> void:
	var start := ShopStockScript.item_price(RelicDataScript.Rarity.COMMON, 0)
	var base := ShopStockScript.relic_price(RelicDataScript.Rarity.COMMON)
	assert_eq(start, base, "biome 0 is the clamp start, so the price stays flat")


# --- ShopStock.filtered_items: the standing shelf caps at LEGENDARY ------------

func test_filtered_items_excludes_cursed_relics() -> void:
	var pool := _pool_of([RelicDataScript.Rarity.COMMON, RelicDataScript.Rarity.CURSED])
	var allowed := ShopStockScript.filtered_items(pool, RelicDataScript.Rarity.LEGENDARY)
	assert_eq(allowed.size(), 1, "only the COMMON relic passes the LEGENDARY cap")
	assert_eq(allowed[0].rarity, RelicDataScript.Rarity.COMMON)


func test_filtered_items_includes_everything_below_the_cap() -> void:
	var pool := _pool_of([
		RelicDataScript.Rarity.COMMON,
		RelicDataScript.Rarity.RARE,
		RelicDataScript.Rarity.LEGENDARY,
	])
	var allowed := ShopStockScript.filtered_items(pool, RelicDataScript.Rarity.LEGENDARY)
	assert_eq(allowed.size(), 3, "COMMON, RARE and LEGENDARY all pass")


func _pool_of(rarities: Array) -> Array[RelicData]:
	var pool: Array[RelicData] = []
	for i in rarities.size():
		var data: RelicData = RelicDataScript.new()
		data.id = StringName("relic_%d" % i)
		data.rarity = rarities[i]
		pool.append(data)
	return pool


# --- Shopkeeper feedback: blips recorded on last_sfx ---------------------------

func test_buy_refusal_sets_error_sfx_and_refusal_reason() -> void:
	# A run-less host keeper has no stock to sell, so every buy refuses. Without
	# a session NetworkManager.is_host is false, which reads as a client turn to
	# forward, so the test stands in for the host before buying.
	NetworkManager.is_host = true
	var refused: bool = _keeper.buy(null, 0)
	assert_eq(refused, false, "buy without a run should refuse")
	assert_eq(_keeper.last_refusal, _keeper.REFUSAL_NO_RUN)
	assert_eq(_keeper.last_sfx, ShopkeeperScript.SFX_REFUSAL, "a refusal plays the error blip")


func test_purchase_feedback_plays_confirm_sfx() -> void:
	_keeper._purchase_feedback()
	assert_eq(_keeper.last_sfx, ShopkeeperScript.SFX_PURCHASE, "a sale plays the confirm blip")


func test_refuse_feedback_plays_error_sfx() -> void:
	_keeper._refuse_feedback()
	assert_eq(_keeper.last_sfx, ShopkeeperScript.SFX_REFUSAL, "a refusal plays the error blip")


func test_prompt_text_mentions_browsing() -> void:
	assert_string_contains(_keeper.PROMPT_TEXT.to_lower(), "browse", "the prompt should invite browsing, not just 'Shop'")
