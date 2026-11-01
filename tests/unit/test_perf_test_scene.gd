extends GutTest
## The W4-B11 perf scene (G10a): the unit, player and emitter counts after spawn,
## the proc relics on each fake player, and the FPS summary the 30 s log reports.
## Owned by debug-tools. Single-instance, no network.

const PERF_SCENE: PackedScene = preload("res://scenes/debug/perf_test.tscn")

var _scene: PerfTest


func before_each() -> void:
	_scene = PERF_SCENE.instantiate() as PerfTest
	add_child_autofree(_scene)


func after_each() -> void:
	# The scene sets a global frame cap in _ready. Clear it so other files see the default.
	Engine.max_fps = 0


func test_scene_spawns_four_fake_players_and_128_emitters() -> void:
	assert_eq(_scene.player_count(), 4, "four fake players after spawn")
	assert_eq(_scene.emitter_count(), 128, "128 VFX emitters after spawn")


func test_scene_spawns_sixty_plain_hollow_miners() -> void:
	assert_eq(_scene.unit_count(), 60, "60 units after spawn (the spec's count)")
	var plain: int = 0
	for child: Node in _scene.get_children():
		if child is Enemy:
			var unit: Enemy = child as Enemy
			if unit.kind == &"hollow_miner" and not unit.elite and unit.affix == EliteAffix.Affix.NONE:
				plain += 1
	assert_eq(plain, 60, "every unit is a plain hollow_miner: no elite, affix NONE")


func test_unknown_unit_kind_falls_back_to_the_default_data() -> void:
	# Enemy.setup returns false only when the fallback kind has no data too, which the
	# shipped data never does; a bad kind therefore still yields a set-up unit.
	var unit: Enemy = _scene._make_unit(0, &"no_such_kind")
	assert_not_null(unit, "setup falls back and the unit is built")
	if unit != null:
		assert_not_null(unit.data, "the fallback kind's data is set")
		unit.free()


func test_a_failed_setup_drops_the_unit_and_returns_null() -> void:
	# setup() returns false only when no data exists for the kind or the fallback
	# (see test_unknown_unit_kind_falls_back_to_the_default_data), so the failed result
	# is passed in directly; the helper's own branch is what this test covers.
	var unit := Enemy.new()
	var kept: Enemy = PerfTest.keep_if_set_up(unit, false, 0, &"no_such_kind")
	assert_push_error("setup failed for 'no_such_kind'")
	assert_null(kept, "a failed setup returns no unit")


func test_a_successful_setup_keeps_the_unit() -> void:
	var unit := Enemy.new()
	var kept: Enemy = PerfTest.keep_if_set_up(unit, true, 0, &"hollow_miner")
	assert_true(kept == unit, "a successful setup returns the same unit")
	unit.free()


func test_each_fake_player_carries_the_proc_relics() -> void:
	var hosts: int = 0
	for child: Node in _scene.get_children():
		if child is Player:
			var host: EffectHost = child.get_node_or_null(NodePath(EffectHost.NODE_NAME)) as EffectHost
			assert_not_null(host, "%s has an EffectHost" % child.name)
			if host != null:
				assert_eq(host.effect_count(), PerfTest.PROC_RELICS.size(), "%s holds every proc relic" % child.name)
				hosts += 1
	assert_eq(hosts, 4, "all four players checked")


func test_scene_sets_the_sixty_fps_cap() -> void:
	assert_eq(Engine.max_fps, PerfTest.FPS_CAP, "the scene sets Engine.max_fps to the cap")
	assert_eq(PerfTest.FPS_CAP, 60, "the cap is 60 FPS")


func test_frame_cap_is_the_sixty_fps_cap_unless_uncapped() -> void:
	assert_eq(PerfTest.frame_cap(false), PerfTest.FPS_CAP, "the default run keeps the 60 FPS cap")
	assert_eq(PerfTest.frame_cap(true), 0, "the uncapped control sets Engine.max_fps to 0 (no cap)")


func test_summary_reports_lowest_frame_and_frames_over_seconds() -> void:
	var samples: PackedFloat64Array = PackedFloat64Array([60.0, 30.0, 60.0])
	var result: Dictionary = PerfTest.summarise(samples, 0.1)
	assert_almost_eq(float(result["min"]), 30.0, 0.001, "min is the lowest per-frame reading")
	assert_almost_eq(float(result["avg"]), 30.0, 0.001, "avg is 3 frames over 0.1 s")
	assert_eq(int(result["frames"]), 3, "frame count carried through")


func test_summary_of_an_empty_sample_is_zero() -> void:
	var result: Dictionary = PerfTest.summarise(PackedFloat64Array(), 30.0)
	assert_eq(float(result["min"]), 0.0, "no samples, min is zero")
	assert_eq(float(result["avg"]), 0.0, "no samples, avg is zero")


func test_worst_frames_lists_the_slowest_first_up_to_count() -> void:
	var frame_ms: PackedFloat64Array = PackedFloat64Array([16.0, 166.7, 33.0, 50.0, 8.0])
	var stamps: PackedFloat64Array = PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0])
	var worst: Array[Dictionary] = PerfTest.worst_frames(frame_ms, stamps, 3)
	assert_eq(worst.size(), 3, "three entries for a count of three")
	assert_almost_eq(float(worst[0]["ms"]), 166.7, 0.001, "slowest frame first")
	assert_almost_eq(float(worst[0]["at_s"]), 2.0, 0.001, "its stamp is the second at its end")
	assert_almost_eq(float(worst[1]["ms"]), 50.0, 0.001, "second slowest next")
	assert_almost_eq(float(worst[2]["ms"]), 33.0, 0.001, "third slowest last")
	assert_almost_eq(float(worst[2]["at_s"]), 3.0, 0.001, "third slowest keeps its own stamp")


func test_worst_frames_count_above_the_sample_returns_every_frame() -> void:
	var frame_ms: PackedFloat64Array = PackedFloat64Array([20.0, 40.0, 10.0])
	var stamps: PackedFloat64Array = PackedFloat64Array([0.5, 1.0, 1.5])
	var worst: Array[Dictionary] = PerfTest.worst_frames(frame_ms, stamps, 5)
	assert_eq(worst.size(), 3, "a count above the sample gives every frame, no more")
	assert_almost_eq(float(worst[2]["ms"]), 10.0, 0.001, "the fastest frame comes last")


func test_worst_frames_of_empty_input_or_zero_count_is_empty() -> void:
	assert_eq(PerfTest.worst_frames(PackedFloat64Array(), PackedFloat64Array(), 5).size(), 0, "no frames, no entries")
	var frame_ms: PackedFloat64Array = PackedFloat64Array([20.0, 40.0])
	var stamps: PackedFloat64Array = PackedFloat64Array([0.5, 1.0])
	assert_eq(PerfTest.worst_frames(frame_ms, stamps, 0).size(), 0, "a count of zero gives no entries")


func test_worst_entry_carries_its_frame_index() -> void:
	var frame_ms: PackedFloat64Array = PackedFloat64Array([16.0, 166.7, 33.0])
	var stamps: PackedFloat64Array = PackedFloat64Array([1.0, 2.0, 3.0])
	var worst: Array[Dictionary] = PerfTest.worst_frames(frame_ms, stamps, 2)
	assert_eq(int(worst[0]["index"]), 1, "the slowest frame is index 1 in the sample")
	assert_eq(int(worst[1]["index"]), 2, "the second slowest is index 2")


func test_worst_frames_a_tie_keeps_the_earlier_frame() -> void:
	# Frames 1 and 2 tie at 9.0 ms: the earlier one (index 1) must rank first, and
	# the later one (index 2) second. Flipping the comparison to >= ranks index 2 first.
	var frame_ms: PackedFloat64Array = PackedFloat64Array([5.0, 9.0, 9.0, 3.0])
	var stamps: PackedFloat64Array = PackedFloat64Array([1.0, 2.0, 3.0, 4.0])
	var worst: Array[Dictionary] = PerfTest.worst_frames(frame_ms, stamps, 2)
	assert_eq(worst.size(), 2, "two entries for a count of two")
	assert_eq(int(worst[0]["index"]), 1, "the tie's earlier frame ranks first")
	assert_eq(int(worst[1]["index"]), 2, "the tie's later frame ranks second")


func test_worst_frames_stops_at_the_shorter_array() -> void:
	# Five frame values but only three stamps: the sample is the shorter array, so
	# a count of ten gives three entries, and every index is below three.
	var frame_ms: PackedFloat64Array = PackedFloat64Array([16.0, 50.0, 33.0, 80.0, 90.0])
	var stamps: PackedFloat64Array = PackedFloat64Array([1.0, 2.0, 3.0])
	var worst: Array[Dictionary] = PerfTest.worst_frames(frame_ms, stamps, 10)
	assert_eq(worst.size(), 3, "three entries, the length of the shorter array")
	for entry: Dictionary in worst:
		assert_lt(int(entry["index"]), 3, "every index is inside the shorter array")


func test_breakdown_follows_the_frame_index_after_sorting() -> void:
	var frame_ms: PackedFloat64Array = PackedFloat64Array([16.0, 166.7, 33.0])
	var stamps: PackedFloat64Array = PackedFloat64Array([1.0, 2.0, 3.0])
	var process_ms: PackedFloat64Array = PackedFloat64Array([1.0, 9.0, 2.0])
	var physics_ms: PackedFloat64Array = PackedFloat64Array([0.1, 0.4, 0.2])
	var draws: PackedFloat64Array = PackedFloat64Array([100.0, 980.0, 300.0])
	var nodes: PackedFloat64Array = PackedFloat64Array([400.0, 412.0, 410.0])
	var worst: Array[Dictionary] = PerfTest.worst_frames(frame_ms, stamps, 2)
	var slowest: Dictionary = PerfTest.frame_breakdown(int(worst[0]["index"]), process_ms, physics_ms, draws, nodes)
	assert_almost_eq(float(slowest["proc_ms"]), 9.0, 0.001, "slowest frame's process time")
	assert_almost_eq(float(slowest["physics_ms"]), 0.4, 0.001, "slowest frame's physics time")
	assert_almost_eq(float(slowest["draws"]), 980.0, 0.001, "slowest frame's draw calls")
	assert_almost_eq(float(slowest["nodes"]), 412.0, 0.001, "slowest frame's node count")
	var second: Dictionary = PerfTest.frame_breakdown(int(worst[1]["index"]), process_ms, physics_ms, draws, nodes)
	assert_almost_eq(float(second["proc_ms"]), 2.0, 0.001, "second slowest frame keeps its own process time")
	assert_almost_eq(float(second["nodes"]), 410.0, 0.001, "second slowest frame keeps its own node count")


func test_breakdown_reads_zero_past_a_short_array() -> void:
	var process_ms: PackedFloat64Array = PackedFloat64Array([5.0])
	var physics_ms: PackedFloat64Array = PackedFloat64Array()
	var draws: PackedFloat64Array = PackedFloat64Array([10.0, 20.0, 30.0])
	var nodes: PackedFloat64Array = PackedFloat64Array([1.0, 2.0, 3.0])
	var detail: Dictionary = PerfTest.frame_breakdown(2, process_ms, physics_ms, draws, nodes)
	assert_eq(float(detail["proc_ms"]), 0.0, "process time past its array reads zero")
	assert_eq(float(detail["physics_ms"]), 0.0, "an empty physics array reads zero")
	assert_eq(float(detail["draws"]), 30.0, "a full draw-call array still reads its own index")
	assert_eq(float(PerfTest.frame_breakdown(-1, process_ms, physics_ms, draws, nodes)["nodes"]), 0.0, "a negative index reads zero")


func test_frame_with_every_monitor_at_zero_is_not_monitored() -> void:
	# The first sampled frame reads zero in process, physics and draws (G3, G26).
	var process_ms: PackedFloat64Array = PackedFloat64Array([0.0, 1.4])
	var physics_ms: PackedFloat64Array = PackedFloat64Array([0.0, 0.3])
	var draws: PackedFloat64Array = PackedFloat64Array([0.0, 110.0])
	var nodes: PackedFloat64Array = PackedFloat64Array([276.0, 276.0])
	assert_false(PerfTest.is_monitored(0, process_ms, physics_ms, draws), "an all-zero frame is not monitored")
	assert_eq(PerfTest.breakdown_label(0, process_ms, physics_ms, draws, nodes), "not monitored, nodes 276", "the label says so and keeps the node count")


func test_frame_with_any_nonzero_monitor_is_monitored() -> void:
	var process_ms: PackedFloat64Array = PackedFloat64Array([1.4])
	var physics_ms: PackedFloat64Array = PackedFloat64Array([0.0])
	var draws: PackedFloat64Array = PackedFloat64Array([0.0])
	var nodes: PackedFloat64Array = PackedFloat64Array([276.0])
	assert_true(PerfTest.is_monitored(0, process_ms, physics_ms, draws), "a frame with process time is monitored")
	assert_eq(PerfTest.breakdown_label(0, process_ms, physics_ms, draws, nodes), "proc 1.4, phys 0.0, draws 0, nodes 276", "the label prints the four costs")
	var zero_process: PackedFloat64Array = PackedFloat64Array([0.0])
	var physics_hit: PackedFloat64Array = PackedFloat64Array([0.6])
	assert_true(PerfTest.is_monitored(0, zero_process, physics_hit, draws), "physics alone also counts as measured")
	assert_false(PerfTest.is_monitored(0, zero_process, draws, draws), "zero process, physics and draws is not a measurement")


func test_index_past_the_arrays_is_not_monitored() -> void:
	var zeros: PackedFloat64Array = PackedFloat64Array([5.0])
	assert_false(PerfTest.is_monitored(3, zeros, zeros, zeros), "an index past every array is not monitored")
	assert_false(PerfTest.is_monitored(-1, zeros, zeros, zeros), "a negative index is not monitored")


func test_startup_gap_is_the_time_from_ready_to_the_first_frame() -> void:
	assert_almost_eq(PerfTest.startup_gap_ms(1000000, 1135000), 135.0, 0.001, "135 ms between the two stamps")


func test_process_work_is_the_gap_between_the_frame_stamps() -> void:
	assert_almost_eq(PerfTest.process_work_ms(1000, 51000), 50.0, 0.001, "50 ms between a start and an end 50000 us later")


func test_process_work_without_a_start_or_with_reversed_stamps_is_zero() -> void:
	assert_eq(PerfTest.process_work_ms(0, 500000), 0.0, "no start stamp, no work")
	assert_eq(PerfTest.process_work_ms(9000, 5000), 0.0, "an end before the start gives no work")


func test_startup_gap_without_a_ready_stamp_is_zero() -> void:
	assert_eq(PerfTest.startup_gap_ms(0, 500000), 0.0, "no _ready stamp, no gap")
	assert_eq(PerfTest.startup_gap_ms(900000, 500000), 0.0, "a first frame before _ready gives no gap")


func test_run_totals_sums_every_frame() -> void:
	var frame_ms: PackedFloat64Array = PackedFloat64Array([10.0, 20.0, 30.0])
	var process_ms: PackedFloat64Array = PackedFloat64Array([1.0, 2.0, 3.0])
	var physics_ms: PackedFloat64Array = PackedFloat64Array([0.5, 0.5, 0.5])
	var draws: PackedFloat64Array = PackedFloat64Array([100.0, 200.0, 300.0])
	var totals: Dictionary = PerfTest.run_totals(frame_ms, process_ms, physics_ms, draws)
	assert_eq(int(totals["frames"]), 3, "three frames counted")
	assert_almost_eq(float(totals["frame_ms"]), 60.0, 0.001, "frame time summed over the run")
	assert_almost_eq(float(totals["proc_ms"]), 6.0, 0.001, "process time summed over the run")
	assert_almost_eq(float(totals["physics_ms"]), 1.5, 0.001, "physics time summed over the run")
	assert_almost_eq(float(totals["draws"]), 600.0, 0.001, "draw calls summed over the run")


func test_run_totals_adds_zero_past_a_short_array() -> void:
	var frame_ms: PackedFloat64Array = PackedFloat64Array([10.0, 20.0, 30.0])
	var process_ms: PackedFloat64Array = PackedFloat64Array([5.0])
	var totals: Dictionary = PerfTest.run_totals(frame_ms, process_ms, PackedFloat64Array(), PackedFloat64Array())
	assert_almost_eq(float(totals["proc_ms"]), 5.0, 0.001, "only the frame that has process time adds to the total")
	assert_almost_eq(float(totals["frame_ms"]), 60.0, 0.001, "frame time still covers every frame")


func test_run_totals_of_an_empty_sample_is_zero() -> void:
	var totals: Dictionary = PerfTest.run_totals(PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array())
	assert_eq(int(totals["frames"]), 0, "no frames")
	assert_eq(float(totals["frame_ms"]), 0.0, "no frame time")
	assert_eq(float(totals["proc_ms"]), 0.0, "no process time")


func test_totals_label_gives_each_share_and_the_largest_cost() -> void:
	var totals: Dictionary = {"frames": 3, "frame_ms": 60.0, "proc_ms": 6.0, "physics_ms": 1.5, "draws": 600.0}
	var label: String = PerfTest.totals_label(totals)
	assert_string_contains(label, "process 6.0 ms (10.0%", "process share of frame time is 10 percent")
	assert_string_contains(label, "physics 1.5 ms (2.5%, avg 0.500 ms)", "physics share of frame time is 2.5 percent, with its per-frame average")
	assert_string_contains(label, "draw calls 600 (avg 200.0 per frame)", "draw calls and their per-frame average")
	assert_string_contains(label, "largest timed cost process", "process is the larger timed cost")


func test_totals_label_names_physics_when_it_is_larger() -> void:
	var totals: Dictionary = {"frames": 2, "frame_ms": 40.0, "proc_ms": 1.0, "physics_ms": 4.0, "draws": 0.0}
	assert_string_contains(PerfTest.totals_label(totals), "largest timed cost physics", "physics is named when it exceeds process")


func test_totals_label_of_an_empty_sample_has_no_nan() -> void:
	var label: String = PerfTest.totals_label(PerfTest.run_totals(PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array()))
	assert_false(label.contains("nan"), "no frames, no NaN share or average")
	assert_string_contains(label, "0 frames", "the empty label still says there are no frames")


func test_steady_worst_frames_leaves_out_the_startup_sample() -> void:
	# Index 0 is the startup delta (136 ms here). It is the slowest sample but must not rank.
	var frame_ms: PackedFloat64Array = PackedFloat64Array([136.0, 16.0, 33.0, 20.0])
	var stamps: PackedFloat64Array = PackedFloat64Array([0.1, 1.0, 2.0, 3.0])
	var worst: Array[Dictionary] = PerfTest.steady_worst_frames(frame_ms, stamps, 5)
	assert_eq(worst.size(), 3, "three steady frames, the startup sample is not one of them")
	for entry: Dictionary in worst:
		assert_ne(int(entry["index"]), 0, "no entry points at the startup sample")


func test_steady_worst_frames_keep_their_index_and_stamp() -> void:
	var frame_ms: PackedFloat64Array = PackedFloat64Array([136.0, 16.0, 33.0, 20.0])
	var stamps: PackedFloat64Array = PackedFloat64Array([0.1, 1.0, 2.0, 3.0])
	var worst: Array[Dictionary] = PerfTest.steady_worst_frames(frame_ms, stamps, 2)
	assert_eq(int(worst[0]["index"]), 2, "the slowest steady frame is index 2 in the full sample")
	assert_almost_eq(float(worst[0]["ms"]), 33.0, 0.001, "its frame time is its own")
	assert_almost_eq(float(worst[0]["at_s"]), 2.0, 0.001, "its stamp is its own")
	assert_eq(int(worst[1]["index"]), 3, "the second steady frame is index 3")


func test_steady_breakdown_reads_the_worst_frame_not_the_startup_sample() -> void:
	var frame_ms: PackedFloat64Array = PackedFloat64Array([136.0, 16.0, 33.0])
	var stamps: PackedFloat64Array = PackedFloat64Array([0.1, 1.0, 2.0])
	var process_ms: PackedFloat64Array = PackedFloat64Array([0.0, 1.0, 9.0])
	var physics_ms: PackedFloat64Array = PackedFloat64Array([0.0, 0.2, 0.4])
	var draws: PackedFloat64Array = PackedFloat64Array([0.0, 110.0, 980.0])
	var nodes: PackedFloat64Array = PackedFloat64Array([277.0, 277.0, 412.0])
	var worst: Array[Dictionary] = PerfTest.steady_worst_frames(frame_ms, stamps, 1)
	assert_eq(PerfTest.breakdown_label(int(worst[0]["index"]), process_ms, physics_ms, draws, nodes), "proc 9.0, phys 0.4, draws 980, nodes 412", "the label reads the steady frame's four costs")


func test_first_delta_is_the_index_zero_frame_time() -> void:
	# The startup delta (136 ms) is index 0 and is the value the startup line must print.
	var frame_ms: PackedFloat64Array = PackedFloat64Array([136.0, 16.0, 33.0])
	assert_almost_eq(PerfTest.first_delta_ms(frame_ms), 136.0, 0.001, "the first sample's delta is index 0")
	assert_almost_eq(PerfTest.first_delta_ms(PackedFloat64Array()), 0.0, 0.001, "an empty sample has no first delta")


func test_startup_label_prints_the_first_delta_beside_the_gap() -> void:
	var frame_ms: PackedFloat64Array = PackedFloat64Array([136.0, 16.0, 33.0])
	var label: String = PerfTest.startup_label(71.5, frame_ms)
	assert_string_contains(label, "first frame delta 136.0 ms", "the startup line names the first sample's delta")
	assert_string_contains(label, "71.5 ms from _ready", "the gap from _ready is still printed")


func test_steady_worst_frames_of_only_the_startup_sample_is_empty() -> void:
	var worst: Array[Dictionary] = PerfTest.steady_worst_frames(PackedFloat64Array([136.0]), PackedFloat64Array([0.1]), 5)
	assert_eq(worst.size(), 0, "a sample of one has no steady frame to rank")
	assert_eq(PerfTest.steady_worst_frames(PackedFloat64Array(), PackedFloat64Array(), 5).size(), 0, "an empty sample has none either")


func test_residual_is_frame_time_minus_process_and_physics() -> void:
	assert_almost_eq(PerfTest.residual_ms(33.0, 9.0, 0.4), 23.6, 0.001, "33 ms frame with 9 ms process and 0.4 ms physics leaves 23.6 ms")
	assert_almost_eq(PerfTest.residual_ms(17.0, 0.3, 0.2), 16.5, 0.001, "a 17 ms steady frame at proc 0.3 and phys 0.2 leaves 16.5 ms")


func test_residual_goes_negative_when_the_physics_monitor_lags_in() -> void:
	assert_almost_eq(PerfTest.residual_ms(5.0, 3.0, 4.0), -2.0, 0.001, "physics above the frame time gives a negative residual")


func test_steady_worst_frame_residual_is_its_own_not_the_startup_sample() -> void:
	# The startup sample (136 ms, no process work) would leave a 136 ms residual if it ranked.
	var frame_ms: PackedFloat64Array = PackedFloat64Array([136.0, 16.0, 33.0])
	var stamps: PackedFloat64Array = PackedFloat64Array([0.1, 1.0, 2.0])
	var process_ms: PackedFloat64Array = PackedFloat64Array([0.0, 1.0, 9.0])
	var physics_ms: PackedFloat64Array = PackedFloat64Array([0.0, 0.2, 0.4])
	var residual: PackedFloat64Array = PackedFloat64Array()
	for index: int in frame_ms.size():
		residual.append(PerfTest.residual_ms(frame_ms[index], process_ms[index], physics_ms[index]))
	var worst: Array[Dictionary] = PerfTest.steady_worst_frames(frame_ms, stamps, 5)
	for entry: Dictionary in worst:
		assert_ne(int(entry["index"]), 0, "the startup sample does not rank")
	assert_almost_eq(residual[int(worst[0]["index"])], 23.6, 0.001, "the ranked frame's residual is 23.6 ms")
