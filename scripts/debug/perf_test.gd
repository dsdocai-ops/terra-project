class_name PerfTest
extends Node2D
## The perf test scene (SPEC-debug-tools, "Perf scene"; W4-B11, goals G10a and
## follow-up 3): 60 plain units, four fake players with proc-heavy relics, 128 VFX
## emitters, and a 30 s FPS log to the console and to `user://perf_test_log.txt`.
## Owned by debug-tools.
##
## Debug only: this script and `scenes/debug/perf_test.tscn` stay out of release
## builds. Sync: none. The scene runs solo on the local peer and never joins a
## session, so no RPC or spawner is involved. Every node is built here, once, on
## `_ready()`.
##
## Units: the spec's 60 are "enemies, skeletons, turrets". No skeleton or turret
## kind has data yet, so all 60 are plain `hollow_miner` enemies (decision D9).
## Other enemy kinds have data (`lantern_wisp`, `rock_tick`, and `grub` in debug),
## so the kind is a choice: `hollow_miner` has the top weight (3 of 6) in SpawnDirector's
## `DEFAULT_POOL` (spawn_director.gd:16) and is enemy.gd's fallback kind (enemy.gd:30).
## They spawn in a grid above the players and clear of the
## emitter grid. The units stay idle: an enemy picks its target from
## `NetworkManager.players`, and this scene registers no fake players there, so no
## unit ever aggros. The units add node and render load, not chase or attack load.
## The FPS number is a load measure; this scene does not judge it.
##
## The FPS log samples one reading per process frame (1 / delta). `min` is the
## lowest of those readings. `avg` is frames divided by elapsed seconds, so a
## slow frame counts once and does not skew it. Passing `--perf-quit` after the
## `--` on the command line quits once the log is written, for unattended runs.
## Passing `--perf-uncapped` the same way removes the frame cap for that run only (G12b).
##
## The second log line names the five slowest steady-state frames by their time, the
## elapsed second at each frame's end, and what the engine spent that frame on:
## process time, physics time, draw calls and node count. The ranking covers steady
## frames only: the first sample (the startup delta, index 0) is left out, so a
## startup frame cannot take a worst-frame slot. A low `min` can be traced to
## frames, and the breakdown says which cost made them slow.
##
## Process time is measured per frame: the sample at index N holds the work of frame
## N-1, the frame whose end the delta at N measures. It runs from this scene's
## `_process` to the `_frame_end` node at priority 1000, so it covers the process
## callbacks that run between those two, not nodes that run before this scene.
## The `Performance` monitors are not per frame: Godot's docs say some are updated
## up to 1 s late, so physics time, draw calls and node count are only as fresh as
## that. A frame whose process time, physics time and draw calls all read zero was
## not measured, so the line says "not monitored" instead of printing zeros. The
## first sample has no earlier frame, so its process time reads zero; it is never
## ranked as a worst frame, so "not monitored" only shows for a steady-state frame
## whose monitors read zero.
## Each slowest-frame entry also gives its residual: the frame time minus the stamped
## process time and the physics monitor. It is the part of the frame neither measure
## names: presentation, the frame cap's wait, the GPU, and node work that runs before
## this scene's `_process` (the process stamp starts there, so that work is not in
## the process time and lands in the residual). It can be negative when the
## physics monitor lags into the frame, so a negative residual means the monitor
## over-counted, not that time was saved.
## The third line gives the time from `_ready()` to that first sampled frame, the
## startup cost that the per-frame process measure does not cover, and the first
## sample's own frame time (the startup delta), which the ranking leaves out.
## The fourth line totals every sampled frame: frame time, process time, physics
## time and draw calls, with each cost's share of the frame time and the largest
## of the two timed costs. Its monitor terms carry the same lag as the breakdown.

const PLAYER_COUNT: int = 4
const EMITTER_COUNT: int = 128
const SAMPLE_SECONDS: float = 30.0
const LOG_PATH: String = "user://perf_test_log.txt"
const QUIT_ARG: String = "--perf-quit"
## Passing this after the `--` runs the scene with no frame cap (G12b control), so the
## frame wait the cap adds can be measured. The default run keeps the cap.
const UNCAPPED_ARG: String = "--perf-uncapped"
## Names for the vsync modes, so the log says whether the FPS number is capped.
const VSYNC_NAMES: Array[String] = ["disabled", "enabled", "adaptive", "mailbox"]
## The frame cap the scene sets on `Engine.max_fps` in `_ready()`. G10a reported
## vsync on and still averaged about 1020 FPS, so vsync was not capping the loop.
## The explicit cap is the one that holds, and the log line reports it.
const FPS_CAP: int = 60
## How many of the slowest frames the log names.
const WORST_COUNT: int = 5
## Relics that carry on-hit or on-proc effects, so every fake player runs procs.
const PROC_RELICS: Array[StringName] = [&"spark_plug", &"splitting_shot", &"volatile_core", &"rebound_spring"]
const RELIC_PATH: String = "res://data/relics/%s.tres"
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const PLAYER_SPACING: float = 96.0
const EMITTER_COLUMNS: int = 16
const EMITTER_SPACING: Vector2 = Vector2(72.0, 56.0)
const EMITTER_AMOUNT: int = 12
const EMITTER_LIFETIME: float = 0.6
## The spec's unit count, all of one plain kind (no elite, affix NONE).
const UNIT_COUNT: int = 60
const UNIT_SCENE: PackedScene = preload("res://scenes/enemies/enemy_base.tscn")
const UNIT_KIND: StringName = &"hollow_miner"
const UNIT_COLUMNS: int = 10
## Top-left unit, clear of the players (y = 0) and of the emitter grid (y >= 160).
const UNIT_ORIGIN: Vector2 = Vector2(-120.0, -420.0)
const UNIT_SPACING: Vector2 = Vector2(56.0, 48.0)
## Process priority of the end-stamp node: Godot runs higher values later in a frame.
const FRAME_END_PRIORITY: int = 1000

var _elapsed: float = 0.0
var _frame_fps: PackedFloat64Array = PackedFloat64Array()
## Each frame's time in ms, and the elapsed seconds at that frame's end, index for index.
var _frame_ms: PackedFloat64Array = PackedFloat64Array()
var _frame_stamps: PackedFloat64Array = PackedFloat64Array()
## Per-frame cost breakdown, index for index with `_frame_ms`: process time in ms,
## measured by this script (see the header), then physics time in ms, draw calls
## and node count as read from `Performance`, which may lag.
var _process_ms: PackedFloat64Array = PackedFloat64Array()
var _physics_ms: PackedFloat64Array = PackedFloat64Array()
var _draws: PackedFloat64Array = PackedFloat64Array()
var _nodes: PackedFloat64Array = PackedFloat64Array()
## Per-frame residual in ms, index for index with `_frame_ms` (see `residual_ms`).
var _residual_ms: PackedFloat64Array = PackedFloat64Array()
var _finished: bool = false
## When `_ready()` ran, and the gap from there to the first sampled frame in ms.
## The gap covers the scene build, which the per-frame process measure does not time.
var _ready_usec: int = 0
var _startup_ms: float = 0.0
## The start of the frame in progress, and the end stamp from `_frame_end`.
var _frame_start_usec: int = 0
var _frame_end: FrameEnd = null


func _ready() -> void:
	_ready_usec = Time.get_ticks_usec()
	Engine.max_fps = frame_cap(UNCAPPED_ARG in OS.get_cmdline_user_args())
	_frame_end = FrameEnd.new()
	_frame_end.process_priority = FRAME_END_PRIORITY
	add_child(_frame_end)
	for index: int in PLAYER_COUNT:
		add_child(_make_player(index))
	for index: int in EMITTER_COUNT:
		add_child(_make_emitter(index))
	for index: int in UNIT_COUNT:
		var unit := _make_unit(index, UNIT_KIND)
		if unit != null:
			add_child(unit)


func _process(delta: float) -> void:
	if _finished or delta <= 0.0:
		return
	if _frame_ms.is_empty():
		_startup_ms = startup_gap_ms(_ready_usec, Time.get_ticks_usec())
	# The end stamp from the previous frame closes that frame's work, which this sample records.
	var previous_work_ms: float = process_work_ms(_frame_start_usec, _frame_end.end_usec) if not _frame_ms.is_empty() else 0.0
	_frame_start_usec = Time.get_ticks_usec()
	_elapsed += delta
	_frame_fps.append(1.0 / delta)
	_frame_ms.append(delta * 1000.0)
	_frame_stamps.append(_elapsed)
	_process_ms.append(previous_work_ms)
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_physics_ms.append(physics_ms)
	_residual_ms.append(residual_ms(delta * 1000.0, previous_work_ms, physics_ms))
	_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_nodes.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if _elapsed >= SAMPLE_SECONDS:
		_finished = true
		_report()


## How many fake players the scene holds.
func player_count() -> int:
	var count: int = 0
	for child: Node in get_children():
		if child is Player:
			count += 1
	return count


## How many VFX emitters the scene holds.
func emitter_count() -> int:
	var count: int = 0
	for child: Node in get_children():
		if child is CPUParticles2D:
			count += 1
	return count


## How many units the scene holds.
func unit_count() -> int:
	var count: int = 0
	for child: Node in get_children():
		if child is Enemy:
			count += 1
	return count


## The FPS summary the log line reports: `min` is the lowest per-frame reading,
## `avg` is frames over `seconds`. An empty sample gives zeros, never a NaN.
static func summarise(frame_fps: PackedFloat64Array, seconds: float) -> Dictionary:
	var lowest: float = 0.0
	if not frame_fps.is_empty():
		lowest = INF
		for fps: float in frame_fps:
			lowest = minf(lowest, fps)
	var average: float = float(frame_fps.size()) / seconds if seconds > 0.0 else 0.0
	return {"min": lowest, "avg": average, "frames": frame_fps.size(), "seconds": seconds}


## The value for `Engine.max_fps`: the cap, or 0 (no cap) when `uncapped` is set.
static func frame_cap(uncapped: bool) -> int:
	return 0 if uncapped else FPS_CAP


## The slowest frames in the sample, slowest first, at most `count` of them. Each
## entry is `{"index": frame index, "ms": frame time, "at_s": elapsed seconds at
## that frame's end}`. A tie keeps the earlier frame. Only indices present in both
## arrays are used.
static func worst_frames(frame_ms: PackedFloat64Array, stamps_s: PackedFloat64Array, count: int) -> Array[Dictionary]:
	var worst: Array[Dictionary] = []
	var sample_size: int = mini(frame_ms.size(), stamps_s.size())
	var taken: Array[bool] = []
	taken.resize(sample_size)
	taken.fill(false)
	while worst.size() < count and worst.size() < sample_size:
		var best: int = -1
		for index: int in sample_size:
			if not taken[index] and (best < 0 or frame_ms[index] > frame_ms[best]):
				best = index
		taken[best] = true
		worst.append({"index": best, "ms": frame_ms[best], "at_s": stamps_s[best]})
	return worst


## The slowest steady-state frames: `worst_frames` over every sample after the first,
## with the first (startup) sample left out. Each entry keeps its index in the full
## sample, so `frame_breakdown` reads the same frame. A sample of one or none gives
## an empty list.
static func steady_worst_frames(frame_ms: PackedFloat64Array, stamps_s: PackedFloat64Array, count: int) -> Array[Dictionary]:
	var steady: Array[Dictionary] = worst_frames(frame_ms.slice(1), stamps_s.slice(1), count)
	for entry: Dictionary in steady:
		entry["index"] = int(entry["index"]) + 1
	return steady


## The cost breakdown of the frame at `index`: `{"proc_ms", "physics_ms", "draws",
## "nodes"}`. A field whose array has no entry at `index` reads 0, so a sample
## with mismatched array lengths still reports instead of failing.
static func frame_breakdown(index: int, process_ms: PackedFloat64Array, physics_ms: PackedFloat64Array, draws: PackedFloat64Array, nodes: PackedFloat64Array) -> Dictionary:
	return {
		"proc_ms": _value_at(process_ms, index),
		"physics_ms": _value_at(physics_ms, index),
		"draws": _value_at(draws, index),
		"nodes": _value_at(nodes, index),
	}


## Whether the monitors measured the frame at `index`: true when its process time,
## physics time or draw calls are above zero. Node count is always set, so it does
## not count. Headless draw calls read 0, so process time carries those runs.
static func is_monitored(index: int, process_ms: PackedFloat64Array, physics_ms: PackedFloat64Array, draws: PackedFloat64Array) -> bool:
	return _value_at(process_ms, index) > 0.0 or _value_at(physics_ms, index) > 0.0 or _value_at(draws, index) > 0.0


## Whole-run totals over every sampled frame: `{"frames", "frame_ms", "proc_ms",
## "physics_ms", "draws"}`. Each cost is summed index for index with `frame_ms`, and
## a missing entry adds 0, as in `frame_breakdown`. An empty sample gives zeros.
static func run_totals(frame_ms: PackedFloat64Array, process_ms: PackedFloat64Array, physics_ms: PackedFloat64Array, draws: PackedFloat64Array) -> Dictionary:
	var frame_sum: float = 0.0
	var proc_sum: float = 0.0
	var physics_sum: float = 0.0
	var draw_sum: float = 0.0
	for index: int in frame_ms.size():
		frame_sum += frame_ms[index]
		proc_sum += _value_at(process_ms, index)
		physics_sum += _value_at(physics_ms, index)
		draw_sum += _value_at(draws, index)
	return {"frames": frame_ms.size(), "frame_ms": frame_sum, "proc_ms": proc_sum, "physics_ms": physics_sum, "draws": draw_sum}


## The text the totals line shows: each timed cost in ms with its share of the frame
## time, the average per frame, the draw-call total, and the larger timed cost.
## Shares and averages are zero, never NaN, when there are no frames.
static func totals_label(totals: Dictionary) -> String:
	var frames: int = int(totals["frames"])
	var frame_sum: float = float(totals["frame_ms"])
	var proc_sum: float = float(totals["proc_ms"])
	var physics_sum: float = float(totals["physics_ms"])
	var share_proc: float = proc_sum / frame_sum * 100.0 if frame_sum > 0.0 else 0.0
	var share_physics: float = physics_sum / frame_sum * 100.0 if frame_sum > 0.0 else 0.0
	var per_frame_ms: float = frame_sum / float(frames) if frames > 0 else 0.0
	var proc_avg: float = proc_sum / float(frames) if frames > 0 else 0.0
	var physics_avg: float = physics_sum / float(frames) if frames > 0 else 0.0
	var draw_avg: float = float(totals["draws"]) / float(frames) if frames > 0 else 0.0
	var largest: String = "process" if proc_sum >= physics_sum else "physics"
	return "%d frames, frame time %.1f ms (avg %.2f ms); process %.1f ms (%.1f%%, avg %.3f ms); physics %.1f ms (%.1f%%, avg %.3f ms); draw calls %d (avg %.1f per frame); largest timed cost %s" % [
		frames, frame_sum, per_frame_ms, proc_sum, share_proc, proc_avg, physics_sum, share_physics, physics_avg, int(totals["draws"]), draw_avg, largest]


## The part of a frame's time that neither the process stamps nor the physics monitor
## names: `frame_ms` minus `process_ms` and `physics_ms`, all in ms. It can be
## negative when the physics monitor reads a frame other than this one.
static func residual_ms(frame_ms: float, process_ms: float, physics_ms: float) -> float:
	return frame_ms - process_ms - physics_ms


## Milliseconds of process work between the frame's start stamp and its end stamp.
## Zero when either stamp is missing or the end comes before the start.
static func process_work_ms(start_usec: int, end_usec: int) -> float:
	return float(end_usec - start_usec) / 1000.0 if start_usec > 0 and end_usec >= start_usec else 0.0


## Milliseconds from `_ready()` (at `ready_usec`) to the first sampled frame (at
## `first_usec`), both from `Time.get_ticks_usec()`. Zero when `_ready()` never ran.
static func startup_gap_ms(ready_usec: int, first_usec: int) -> float:
	return float(first_usec - ready_usec) / 1000.0 if ready_usec > 0 and first_usec >= ready_usec else 0.0


## The first sample's frame time in ms (index 0 of `frame_ms`), or 0 when the sample is
## empty. It is the startup delta that `steady_worst_frames` leaves out of the ranking.
static func first_delta_ms(frame_ms: PackedFloat64Array) -> float:
	return _value_at(frame_ms, 0)


## The text the startup line shows: the gap from `_ready()` to the first sampled frame,
## and the first sample's own frame time, so the slowest startup frame can be read.
static func startup_label(startup_ms: float, frame_ms: PackedFloat64Array) -> String:
	return "%.1f ms from _ready to the first sampled frame; first frame delta %.1f ms" % [startup_ms, first_delta_ms(frame_ms)]


## The text the worst-frame line shows for the frame at `index`: the four costs
## when the monitors measured it, otherwise "not monitored" with the node count.
static func breakdown_label(index: int, process_ms: PackedFloat64Array, physics_ms: PackedFloat64Array, draws: PackedFloat64Array, nodes: PackedFloat64Array) -> String:
	var detail: Dictionary = frame_breakdown(index, process_ms, physics_ms, draws, nodes)
	if not is_monitored(index, process_ms, physics_ms, draws):
		return "not monitored, nodes %d" % int(detail["nodes"])
	return "proc %.1f, phys %.1f, draws %d, nodes %d" % [detail["proc_ms"], detail["physics_ms"], int(detail["draws"]), int(detail["nodes"])]


## The value at `index`, or 0 when the array is too short to hold it.
static func _value_at(values: PackedFloat64Array, index: int) -> float:
	return values[index] if index >= 0 and index < values.size() else 0.0


## One player with the proc relics attached through its own `EffectHost`. The
## host is built here the way `EffectHostPlayer.install` builds it in the tests,
## because `player.tscn` does not carry an `EffectHost` yet (W2-A1 wiring).
func _make_player(index: int) -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.name = "FakePlayer%d" % index
	player.position = Vector2(float(index) * PLAYER_SPACING, 0.0)
	var host := EffectHost.new()
	host.name = EffectHost.NODE_NAME
	player.add_child(host)
	for id: StringName in PROC_RELICS:
		var relic: RelicData = load(RELIC_PATH % String(id)) as RelicData
		if relic != null:
			host.add(relic)
	return player


## One plain enemy of `kind` on a grid above the players. `setup` runs before the node
## enters the tree, the way `EnemySpawner` builds an enemy, and it takes no elite or affix.
## Returns null and reports the failure when setup returns false, so no half-built unit
## is added to the scene.
func _make_unit(index: int, kind: StringName) -> Enemy:
	var unit: Enemy = UNIT_SCENE.instantiate() as Enemy
	unit.name = "Unit%d" % index
	unit.position = UNIT_ORIGIN + Vector2(
		float(index % UNIT_COLUMNS) * UNIT_SPACING.x,
		float(index / UNIT_COLUMNS) * UNIT_SPACING.y)
	return keep_if_set_up(unit, unit.setup(kind), index, kind)


## Returns `unit` when its setup succeeded. Otherwise reports the failure, frees the
## half-built unit and returns null, so the scene never holds a unit without its data.
static func keep_if_set_up(unit: Enemy, set_up: bool, index: int, kind: StringName) -> Enemy:
	if set_up:
		return unit
	push_error("[perf_test] unit %d: setup failed for '%s'; not spawned" % [index, kind])
	unit.free()
	return null


## One emitter on a grid, emitting for the whole run.
func _make_emitter(index: int) -> CPUParticles2D:
	var emitter := CPUParticles2D.new()
	emitter.name = "VfxEmitter%d" % index
	emitter.position = Vector2(
		float(index % EMITTER_COLUMNS) * EMITTER_SPACING.x,
		float(index / EMITTER_COLUMNS) * EMITTER_SPACING.y + 160.0)
	emitter.amount = EMITTER_AMOUNT
	emitter.lifetime = EMITTER_LIFETIME
	emitter.direction = Vector2.UP
	emitter.spread = 180.0
	emitter.initial_velocity_min = 20.0
	emitter.initial_velocity_max = 40.0
	emitter.emitting = true
	return emitter


## Prints the summary and writes it to the log file, then quits when asked.
func _report() -> void:
	var result: Dictionary = summarise(_frame_fps, _elapsed)
	var vsync: String = VSYNC_NAMES[DisplayServer.window_get_vsync_mode()]
	var refresh: float = DisplayServer.screen_get_refresh_rate()
	var line: String = "perf_test: %d units, %d players, %d emitters, cap %d fps, vsync %s, refresh %.0f Hz, FPS min %.1f avg %.1f over %.1f s (%d frames)" % [
		unit_count(), player_count(), emitter_count(), Engine.max_fps, vsync, refresh, result["min"], result["avg"], result["seconds"], result["frames"]]
	var worst: Array[Dictionary] = steady_worst_frames(_frame_ms, _frame_stamps, WORST_COUNT)
	var parts: PackedStringArray = PackedStringArray()
	for rank: int in worst.size():
		var index: int = int(worst[rank]["index"])
		var label: String = breakdown_label(index, _process_ms, _physics_ms, _draws, _nodes)
		parts.append("%d) %.1f ms at %.1f s (%s, residual %.1f)" % [rank + 1, worst[rank]["ms"], worst[rank]["at_s"], label, _value_at(_residual_ms, index)])
	if parts.is_empty():
		parts.append("none")
	var worst_line: String = "perf_test worst frames: %s" % "; ".join(parts)
	var startup_line: String = "perf_test startup: %s" % startup_label(_startup_ms, _frame_ms)
	var totals_line: String = "perf_test totals: %s" % totals_label(run_totals(_frame_ms, _process_ms, _physics_ms, _draws))
	print(line)
	print(worst_line)
	print(startup_line)
	print(totals_line)
	var file: FileAccess = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file != null:
		file.store_line(line)
		file.store_line(worst_line)
		file.store_line(startup_line)
		file.store_line(totals_line)
		print("perf_test: log written to %s" % ProjectSettings.globalize_path(LOG_PATH))
	else:
		push_warning("[perf-test] could not write %s" % LOG_PATH)
	if QUIT_ARG in OS.get_cmdline_user_args():
		get_tree().quit()


## The end stamp for each frame. It runs last in the frame (see FRAME_END_PRIORITY)
## and records when the frame's process callbacks finished, so the next sample can
## measure the frame's process work. Owned by the perf scene; the scene is local-only.
class FrameEnd extends Node:
	var end_usec: int = 0


	func _process(_delta: float) -> void:
		end_usec = Time.get_ticks_usec()
