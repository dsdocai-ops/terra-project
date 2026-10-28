extends GutTest

## Tests for `scripts/effects/ground_crack_line.gd` (W2-A7, G16a): the Pickaxe
## heavy's crack decal, mirrored by file name per BRIEF DoD 5. The scene-side
## spawn path (one crack per heavy, the strike's geometry, the RPC broadcast)
## stays covered by `test_pickaxe_attack.gd`; this file is the decal's own
## behaviour — the pure geometry, the fade clock and the self-free.


func _parent() -> Node2D:
	var holder: Node2D = Node2D.new()
	add_child_autofree(holder)
	return holder


# --- the crack geometry ----------------------------------------------------------------------

func test_crack_points_run_from_the_feet_to_the_full_reach() -> void:
	var points: PackedVector2Array = GroundCrackLine.crack_points(Vector2(3.0, 4.0), Vector2.RIGHT, 100.0)
	assert_eq(points.size(), GroundCrackLine.MARK_COUNT, "one mark per MARK_COUNT")
	assert_almost_eq(points[0].x, 3.0, 0.01, "the first mark sits under the feet")
	assert_almost_eq(points[0].y, 4.0, 0.01)
	assert_almost_eq(points[GroundCrackLine.MARK_COUNT - 1].x, 103.0, 0.01, "the last at the swing's full reach")
	assert_almost_eq(points[GroundCrackLine.MARK_COUNT - 1].y, 4.0, 0.01)


func test_a_zero_direction_strikes_along_the_default() -> void:
	var points: PackedVector2Array = GroundCrackLine.crack_points(Vector2.ZERO, Vector2.ZERO, 100.0)
	assert_almost_eq(points[GroundCrackLine.MARK_COUNT - 1].x, 100.0, 0.01,
		"a zero dir falls back to RIGHT instead of striking nowhere")
	assert_almost_eq(points[GroundCrackLine.MARK_COUNT - 1].y, 0.0, 0.01)


func test_the_same_swing_always_draws_the_same_crack() -> void:
	var first: PackedVector2Array = GroundCrackLine.crack_points(Vector2.ZERO, Vector2(1.0, 0.5), 80.0)
	var second: PackedVector2Array = GroundCrackLine.crack_points(Vector2.ZERO, Vector2(1.0, 0.5), 80.0)
	assert_eq(first, second, "no RNG: the same inputs, the same crack")


func test_the_interior_marks_wander_on_both_sides_of_the_line() -> void:
	var points: PackedVector2Array = GroundCrackLine.crack_points(Vector2.ZERO, Vector2.RIGHT, 100.0)
	var seen_positive: bool = false
	var seen_negative: bool = false
	for mark: int in range(1, GroundCrackLine.MARK_COUNT - 1):
		var offset: float = points[mark].y
		assert_lte(absf(offset), GroundCrackLine.MAX_JITTER_PX + 0.01, "inside the jitter corridor")
		seen_positive = seen_positive or offset > 0.0
		seen_negative = seen_negative or offset < 0.0
	assert_true(seen_positive, "the fixed zigzag crosses to both sides")
	assert_true(seen_negative, "so the crack is a crack, not a straight line")


# --- the branch ticks ------------------------------------------------------------------------

func test_the_interior_marks_splinter_in_pairs_on_alternating_sides() -> void:
	var dir: Vector2 = Vector2.RIGHT
	var branches: PackedVector2Array = GroundCrackLine.branch_pairs(dir, 100.0)
	var branch_count: int = branches.size() / 2
	var expected: int = 0
	for mark: int in range(1, GroundCrackLine.MARK_COUNT - 1, GroundCrackLine.BRANCH_STEP):
		expected += 1
	assert_eq(branch_count, expected, "a pair per BRANCH_STEP interior mark")
	var points: PackedVector2Array = GroundCrackLine.crack_points(Vector2.ZERO, dir, 100.0)
	var across: Vector2 = Vector2(0.0, 1.0)
	var side_sum: float = 0.0
	for branch: int in range(0, branches.size(), 2):
		var start: Vector2 = branches[branch]
		var end: Vector2 = branches[branch + 1]
		var on_a_mark: bool = false
		for mark: int in range(1, GroundCrackLine.MARK_COUNT - 1):
			on_a_mark = on_a_mark or start.distance_to(points[mark]) < 0.01
		assert_true(on_a_mark, "the splint starts on an interior mark")
		assert_gt(end.distance_to(start), 0.0, "the splint has length")
		assert_lte(end.distance_to(start), GroundCrackLine.BRANCH_LENGTH_PX + 0.01, "no longer than BRANCH_LENGTH_PX")
		side_sum += signf((end - start).dot(across))
	assert_lt(absf(side_sum), float(branch_count), "the splints alternate sides, not all one way")


# --- spawn and the fade clock ----------------------------------------------------------------

func test_a_spawned_crack_is_a_grouped_squashed_decal_at_the_strike_origin() -> void:
	var crack: GroundCrackLine = GroundCrackLine.spawn(_parent(), Vector2(7.0, 9.0), Vector2.RIGHT, 60.0)
	autofree(crack)
	assert_almost_eq(crack.global_position.x, 7.0, 0.01, "at the strike origin")
	assert_almost_eq(crack.global_position.y, 9.0, 0.01)
	assert_true(crack.is_in_group(&"ground_cracks"), "in the group the sweep clears")
	assert_almost_eq(crack.scale.y, GroundCrackLine.SQUASH_Y, 0.001, "ground decal, squashed like the other marks")
	assert_true(crack.visible, "play made it visible")


func test_the_crack_fades_over_its_lifetime_then_queues_itself_free() -> void:
	var crack: GroundCrackLine = GroundCrackLine.spawn(_parent(), Vector2.ZERO, Vector2.RIGHT, 60.0)
	autofree(crack)
	assert_almost_eq(crack.seconds_left(), GroundCrackLine.LIFETIME_SECONDS, 0.01, "a full life on spawn")
	crack.step(GroundCrackLine.LIFETIME_SECONDS - 0.1)
	assert_gt(crack.seconds_left(), 0.0, "still fading just short of the end")
	assert_false(crack.is_queued_for_deletion())
	crack.step(0.2)
	assert_true(crack.is_queued_for_deletion(), "gone at the end of its life")


func test_a_step_after_the_fade_ended_is_a_no_op() -> void:
	var crack: GroundCrackLine = GroundCrackLine.spawn(_parent(), Vector2.ZERO, Vector2.RIGHT, 60.0)
	autofree(crack)
	crack.step(GroundCrackLine.LIFETIME_SECONDS + 1.0)
	assert_true(crack.is_queued_for_deletion())
	crack.step(0.5)
	assert_true(crack.is_queued_for_deletion(), "the spent clock does not tick below zero or error")


func test_replaying_a_fading_crack_restarts_its_full_life() -> void:
	var crack: GroundCrackLine = GroundCrackLine.spawn(_parent(), Vector2.ZERO, Vector2.RIGHT, 60.0)
	autofree(crack)
	crack.step(GroundCrackLine.LIFETIME_SECONDS - 0.2)
	crack.play(Vector2.DOWN, 40.0)
	assert_almost_eq(crack.seconds_left(), GroundCrackLine.LIFETIME_SECONDS, 0.01, "a fresh clock")
	assert_almost_eq(crack.points()[GroundCrackLine.MARK_COUNT - 1].y, 40.0, 0.01, "along the new swing")
	assert_false(crack.is_queued_for_deletion())
