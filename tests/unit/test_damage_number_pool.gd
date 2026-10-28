extends GutTest
## Tests for DamageNumberPool (SPEC-combat-core "Hit feedback"): labels are
## recycled instead of freed, so a long fight never grows the node count.
## Owned by combat-core. A released or finished label is handed back by its
## DamageNumber; here the tests drive the same entry points.

var _fx: Node2D
var _pool: DamageNumberPool


func before_each() -> void:
	_fx = Node2D.new()
	add_child_autofree(_fx)
	_pool = DamageNumberPool.attach(_fx)


func _labels_under(parent: Node) -> Array[DamageNumber]:
	var labels: Array[DamageNumber] = []
	for child: Node in parent.get_children():
		if child is DamageNumber:
			labels.append(child)
	return labels


# --- attach ---------------------------------------------------------------------------

func test_attach_makes_one_named_pool_under_the_fx_root() -> void:
	assert_same(_fx.get_node("DamageNumberPool"), _pool)
	assert_same(DamageNumberPool.attach(_fx), _pool, "a second attach reuses it")


# --- reuse ------------------------------------------------------------------------------

func test_the_pool_warms_up_and_never_creates_more_than_it_must() -> void:
	var warm: int = _pool.created_count
	assert_eq(warm, DamageNumberPool.WARM_INSTANCES, "the warm set exists before the first hit")
	for _hit in DamageNumberPool.WARM_INSTANCES * 3:
		var number: DamageNumber = _pool.spawn_number(Vector2.ZERO, 5, false, false)
		_pool.release(number)
	assert_eq(_pool.created_count, warm, "spawning past the warm set reuses, no new labels")


func test_a_released_number_comes_back_the_same_instance() -> void:
	var first: DamageNumber = _pool.spawn_number(Vector2(10.0, 10.0), 7, true, false)
	_pool.release(first)
	assert_same(_pool.get_children().back(), first, "it waits hidden under the pool")
	assert_false(first.visible)
	var second: DamageNumber = _pool.spawn_number(Vector2.ZERO, 9, false, false)
	assert_same(second, first, "the same label, not a new one")
	assert_eq(second.text, "9", "restyled for the new hit")
	assert_true(second.visible)


func test_a_finished_number_walks_itself_back_to_the_pool() -> void:
	var number: DamageNumber = _pool.spawn_number(Vector2.ZERO, 3, false, false)
	assert_same(number.get_parent(), _fx, "in flight it lives in the FX root, world-relative")
	number._finish()
	assert_same(number.get_parent(), _pool)
	assert_false(number.visible)


func test_an_empty_pool_grows_on_demand_instead_of_failing() -> void:
	var in_flight: Array[DamageNumber] = []
	for _hit in DamageNumberPool.WARM_INSTANCES + 3:
		in_flight.append(_pool.spawn_number(Vector2.ZERO, 2, false, false))
	assert_eq(_pool.created_count, DamageNumberPool.WARM_INSTANCES + 3, "only the 3 past the warm set are new")
	for number: DamageNumber in in_flight:
		_pool.release(number)
	_pool.spawn_number(Vector2.ZERO, 2, false, false)
	assert_eq(_pool.created_count, DamageNumberPool.WARM_INSTANCES + 3, "and it shrinks back to reuse once they land")


# --- styling rides through the pool ------------------------------------------------------

func test_crit_numbers_are_gold_and_larger_through_the_pool() -> void:
	var crit: DamageNumber = _pool.spawn_number(Vector2.ZERO, 11, true, false)
	var plain: DamageNumber = _pool.spawn_number(Vector2.ZERO, 11, false, false)
	assert_eq(crit.get_theme_color(&"font_color"), DamageNumber.CRIT_COLOR)
	assert_eq(crit.get_theme_font_size(&"font_size"), 16)
	assert_eq(plain.get_theme_color(&"font_color"), DamageNumber.NORMAL_COLOR)
	assert_eq(plain.get_theme_font_size(&"font_size"), 11)
	_pool.release(crit)
	_pool.release(plain)


func test_word_pops_use_the_same_pool() -> void:
	var word: DamageNumber = _pool.spawn_text(Vector2.ZERO, "STAGGER")
	assert_eq(word.text, "STAGGER")
	assert_same(word.get_parent(), _fx)
	_pool.release(word)
	assert_gt(_pool._free.size(), 0, "back in the free list")
