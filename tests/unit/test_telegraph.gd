extends GutTest
## The ground telegraph (SPEC-combat-core "Telegraph"), including the RING shape
## added in combat v2 C5. Owned by combat-core. The dummy renderer cannot be
## inspected, so the ring is checked through its pure geometry and through the
## Telegraph draw counter, which proves `_draw` ran for that shape.

var _telegraph: Telegraph


func before_each() -> void:
	_telegraph = Telegraph.new()
	add_child_autofree(_telegraph)


func _ring_pattern(outer: float = 80.0, width: float = 24.0) -> AttackPattern:
	var pattern := AttackPattern.new()
	pattern.telegraph_shape = AttackPattern.TelegraphShape.RING
	pattern.telegraph_size = Vector2(outer, width)
	return pattern


func test_ring_geometry_is_a_band_that_fills_outward() -> void:
	var empty: Dictionary = Telegraph.ring_geometry(Vector2(80, 24), 0.0)
	assert_eq(empty["outer"], 80.0)
	assert_eq(empty["inner"], 56.0, "the band is 24 px wide")
	assert_eq(empty["filled_to"], 56.0, "nothing filled yet")
	var half: Dictionary = Telegraph.ring_geometry(Vector2(80, 24), 0.5)
	assert_almost_eq(float(half["filled_to"]), 68.0, 0.001, "half way across the band")
	var full: Dictionary = Telegraph.ring_geometry(Vector2(80, 24), 1.0)
	assert_eq(full["filled_to"], 80.0, "full at the outer edge")
	assert_eq(Telegraph.ring_geometry(Vector2(80, 24), 7.0)["filled_to"], 80.0, "fill is clamped")


func test_a_band_wider_than_the_radius_becomes_a_disc() -> void:
	var disc: Dictionary = Telegraph.ring_geometry(Vector2(30, 90), 1.0)
	assert_eq(disc["inner"], 0.0)
	assert_eq(disc["outer"], 30.0)


func test_configure_reads_the_ring_from_the_pattern() -> void:
	_telegraph.configure(_ring_pattern(), Vector2.RIGHT)
	assert_eq(_telegraph.shape, AttackPattern.TelegraphShape.RING)
	assert_eq(_telegraph.size, Vector2(80, 24))


func test_the_ring_is_drawn_while_a_windup_runs() -> void:
	_telegraph.configure(_ring_pattern(), Vector2.RIGHT)
	assert_false(_telegraph.visible, "hidden before the windup")
	_telegraph.progress = 0.5
	assert_true(_telegraph.visible)
	await wait_process_frames(2)
	assert_gt(_telegraph.draw_count, 0, "_draw ran")
	assert_eq(_telegraph.last_drawn, AttackPattern.TelegraphShape.RING, "and it drew the ring branch")


func test_the_ring_redraws_as_it_fills_and_stops_when_hidden() -> void:
	_telegraph.configure(_ring_pattern(), Vector2.RIGHT)
	_telegraph.progress = 0.25
	await wait_process_frames(2)
	var after_first: int = _telegraph.draw_count
	_telegraph.progress = 0.75
	await wait_process_frames(2)
	assert_gt(_telegraph.draw_count, after_first, "a new fill redraws")
	_telegraph.progress = -1.0
	await wait_process_frames(2)
	var hidden_count: int = _telegraph.draw_count
	await wait_process_frames(2)
	assert_eq(_telegraph.draw_count, hidden_count, "nothing is drawn once the windup ends")
	assert_false(_telegraph.visible)


func test_the_other_shapes_still_draw() -> void:
	for shape: AttackPattern.TelegraphShape in [AttackPattern.TelegraphShape.CIRCLE, AttackPattern.TelegraphShape.CONE, AttackPattern.TelegraphShape.LINE]:
		var pattern := AttackPattern.new()
		pattern.telegraph_shape = shape
		_telegraph.configure(pattern, Vector2.RIGHT)
		_telegraph.progress = -1.0
		_telegraph.progress = 0.6
		await wait_process_frames(2)
		assert_eq(_telegraph.last_drawn, shape)
