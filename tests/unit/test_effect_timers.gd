extends GutTest
## Tests for `Effect.every_seconds()` — effect-system, W4-B2 (goal G13).
##
## SPEC-effect-system pins this helper to `TimeManager.timer` "in the PLAYER
## group so time stops don't pause it": a relic's own clock must keep counting
## while enemies are frozen (Clockwork Heart's "every 10 s" is the named case),
## which a plain engine `Timer` — or a scaled timer taken on the enemy stack —
## gets wrong. The cases below therefore assert the three claims separately
## rather than as one behaviour:
##
##   1. the loop is armed on the manager's *scaled* timer, on the effect's own
##      player, and the player is in the manager's PLAYER group;
##   2. it fires after the interval in physics frames and repeats;
##   3. a live `stop_enemies` does not delay it, while a per-entity override on
##      the player's own node does — the negative control that would fail for an
##      enemy-group clock, and the positive control that would fail for a plain
##      engine timer.
##
## Sync: none under test. `Effect` is host-only logic and a loop is host-side;
## nothing here is replicated or client-visible.
##
## Hygiene: the armed timer lives in `TimeManager`'s own list, and a timer whose
## node has been freed never decays (see `_tick_scaled_timers`), so `after_each`
## clears that list as well as the effect's loops, keeping this file from
## leaking into the next one (a known GUT behaviour in this project).

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const STAT_BLOCK_SCRIPT_PATH: String = "res://scripts/components/stat_block.gd"
const EFFECT_SCRIPT_PATH: String = "res://scripts/effects/effect.gd"
const STAT_BLOCK_NODE: NodePath = ^"StatBlock"

## One interval of the loop under test, and how many 60 Hz physics frames that
## is. Chosen short so the cases cost well under a second each.
const INTERVAL: float = 0.2
const INTERVAL_FRAMES: int = 12
## A second, longer interval, for the "two loops on one effect" case.
const LONG_INTERVAL: float = 0.4

## Time-effect sources this file starts, so `after_each` leaves the manager's
## stacks empty (autoload state is shared by the whole GUT run).
const SOURCES: Array[StringName] = [&"test-stop", &"test-player-stop", &"test-entity"]

var _player: Player
var _source: ContentData
## Every effect this file attached, so no loop is left armed on the manager.
var _effects: Array[Effect] = []


## The effect under test: an ordinary `Effect` that opens the loops the cases
## ask for. The interval is passed in rather than held as a constant so the
## same class drives both the short and the long loop.
class LoopEffect:
	extends Effect

	## Callables the loops under test run, counting their own invocations and the
	## frame each landed on — the frame is what turns "it fired" into "it fired
	## when it should have".
	var calls: int = 0
	var second_calls: int = 0
	var last_frame: int = -1
	## Set by a case that wants the handler to tear its own effect down.
	var detach_on_first_tick: bool = false

	func start_loop(interval: float) -> void:
		every_seconds(interval, _tick)

	func start_second_loop(interval: float) -> void:
		every_seconds(interval, _tick_two)

	func _tick() -> void:
		calls += 1
		last_frame = Engine.get_physics_frames()
		if detach_on_first_tick:
			detach()

	func _tick_two() -> void:
		second_calls += 1


func before_each() -> void:
	_player = _make_player()
	_source = ContentData.new()
	_source.id = &"test_clock"
	_source.display_name = "Test Clock"


func after_each() -> void:
	for effect: Effect in _effects:
		effect.detach()
	_effects.clear()
	# A scaled timer armed on a node that is about to be freed is dropped by
	# nobody, so it would sit in the manager for the rest of the run. The list
	# is the manager's, not this effect's, hence the direct clear.
	TimeManager._scaled_timers.clear()
	for source: StringName in SOURCES:
		TimeManager.clear_source(source)


## The real player scene with the `StatBlock` component hung on its bare
## `StatBlock` node — the same shape `test_effect_base.gd` uses, so attaching an
## effect here produces no "no StatBlock component" warning.
func _make_player() -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	var component: Node = player.get_node(STAT_BLOCK_NODE)
	component.set_script(load(STAT_BLOCK_SCRIPT_PATH) as Script)
	add_child_autofree(player)
	return player


func _attach(effect: Effect) -> Effect:
	_player.add_child(effect)
	effect.attach(_player, _source, 1)
	_effects.append(effect)
	return effect


## Attach a loop effect and open one loop on it.
func _looping(interval: float = INTERVAL) -> LoopEffect:
	var effect: LoopEffect = _attach(LoopEffect.new()) as LoopEffect
	effect.start_loop(interval)
	return effect


## The instance ids the manager's scaled timers are currently armed on. Reading
## the manager's own list rather than a copy on the effect is the point: it is
## the only place that answers "did this loop really go through
## `TimeManager.timer`, and on whose node".
func _scaled_timer_node_ids() -> Array[int]:
	var ids: Array[int] = []
	for scaled: Variant in TimeManager._scaled_timers:
		ids.append(int(scaled.node_id))
	return ids


func _script_method(name: String) -> Dictionary:
	var script: GDScript = load(EFFECT_SCRIPT_PATH) as GDScript
	for method: Dictionary in script.get_script_method_list():
		if String(method["name"]) == name:
			return method
	return {}


## True when the line declaring `func <name>(` is preceded by a `##` doc line.
func _documented(source: String, method_name: String) -> bool:
	var lines: PackedStringArray = source.split("\n")
	for i: int in range(1, lines.size()):
		if lines[i].begins_with("func %s(" % method_name):
			return lines[i - 1].strip_edges().begins_with("##")
	return false


func test_the_spec_surface_exposes_every_seconds_documented() -> void:
	var script: GDScript = load(EFFECT_SCRIPT_PATH) as GDScript
	assert_not_null(script, "scripts/effects/effect.gd must exist")
	if script == null:
		return
	var source: String = FileAccess.get_file_as_string(EFFECT_SCRIPT_PATH)
	assert_true(source.contains("class_name Effect"), "the base class")
	assert_true(_documented(source, "every_seconds"), "every_seconds carries a doc comment")
	var method: Dictionary = _script_method("every_seconds")
	assert_false(method.is_empty(), "declares every_seconds")
	var args: Array = method.get("args", [])
	assert_eq(args.size(), 2, "the spec's two arguments")
	var names: Array[String] = []
	for argument: Variant in args:
		if argument is Dictionary:
			names.append(String((argument as Dictionary)["name"]))
	assert_eq(names.size(), 2, "two arguments")
	assert_eq(names[0], "interval", "first is the interval, named as the spec declares it")
	assert_eq(names[1], "callable", "second is the callable")


## The clock is `TimeManager.timer` on the effect's own player: the manager's
## list must carry exactly one timer, armed on this player and nobody else.
func test_every_seconds_arms_a_scaled_timer_on_the_effect_player() -> void:
	assert_true(_scaled_timer_node_ids().is_empty(), "no timer before the loop starts")
	_looping()
	var ids: Array[int] = _scaled_timer_node_ids()
	assert_eq(ids.size(), 1, "one armed scaled timer")
	assert_eq(ids[0], _player.get_instance_id(), "armed on the effect's own player")


func test_the_effect_registers_its_player_in_the_player_time_group() -> void:
	assert_false(
		TimeManager._groups.has(_player.get_instance_id()),
		"the real player scene does not register itself (player-controller's lane)"
	)
	_looping()
	var group: Variant = TimeManager._groups.get(_player.get_instance_id(), null)
	assert_eq(group, TimeManager.Group.PLAYER, "the effect put its player in the PLAYER group")
	assert_eq(TimeManager.scale_for(_player), 1.0, "which is normal speed with no effect running")


## A plain engine `Timer` would also pass this one, so it is deliberately paired
## with the scaled-clock cases below: this case pins *when* the tick lands.
func test_the_callback_fires_after_the_interval_and_not_before() -> void:
	var effect: LoopEffect = _looping()
	await wait_physics_frames(INTERVAL_FRAMES - 2)
	assert_eq(effect.calls, 0, "%d frames is not yet %.1f s" % [INTERVAL_FRAMES - 2, INTERVAL])
	await wait_physics_frames(5)
	assert_eq(effect.calls, 1, "fired once the interval elapsed")
	assert_true(effect.last_frame > 0, "on a real physics frame")


func test_the_callback_repeats_every_interval() -> void:
	var effect: LoopEffect = _looping()
	await wait_physics_frames(60)
	# 60 frames is 1 s, so 5 ticks of 0.2 s; the band allows the frame-boundary
	# slack that a timer armed mid-frame carries.
	var first_window: int = effect.calls
	assert_between(first_window, 4, 6, "one 1 s window at 0.2 s is 4 to 6 ticks")
	await wait_physics_frames(60)
	assert_between(effect.calls - first_window, 4, 6, "and the next window ticks the same")


## The negative control SPEC-effect-system names: "time stops don't pause it".
## With the enemies frozen the clock still ticks, because the timer is taken on
## the player's scaled time and not the enemy stack's.
func test_an_active_enemy_time_stop_does_not_delay_the_tick() -> void:
	var enemy := ScaledMover.new()
	add_child_autofree(enemy)
	await wait_physics_frames(1)
	assert_eq(TimeManager.scale_for(enemy), 1.0, "the enemy runs at normal speed to begin with")
	TimeManager.stop_enemies(0.5, &"test-stop")
	assert_eq(TimeManager.scale_for(enemy), 0.0, "the stop is live and freezes enemies")
	var effect: LoopEffect = _looping()
	assert_eq(TimeManager.scale_for(_player), 1.0, "the player is not frozen by an enemy stop")
	await wait_physics_frames(INTERVAL_FRAMES + 3)
	assert_eq(effect.calls, 1, "the relic's own clock kept counting through the stop")


## The positive control for "uses the scaled timer": an override that hits this
## player pauses the clock, which no plain engine timer would honour. It also
## pins the direction of the exemption — players ignore the *enemy* stack, not
## their own scaled time.
func test_a_per_entity_override_on_the_player_pauses_its_own_clock() -> void:
	var effect: LoopEffect = _looping()
	await wait_physics_frames(1)
	TimeManager.set_entity_scale(_player, 0.0, 0.4, &"test-entity")
	assert_eq(TimeManager.scale_for(_player), 0.0, "the player is frozen")
	await wait_physics_frames(INTERVAL_FRAMES + 2)
	assert_eq(effect.calls, 0, "a frozen player's clock does not tick")
	await wait_physics_frames(INTERVAL_FRAMES * 3)
	assert_gte(effect.calls, 1, "and it resumes when the override expires")


func test_a_global_player_group_effect_pauses_the_clock() -> void:
	var effect: LoopEffect = _looping()
	await wait_physics_frames(1)
	TimeManager.time_effect_applied(TimeManager.Group.PLAYER, 0.0, 0.4, &"test-player-stop")
	assert_eq(TimeManager.scale_for(_player), 0.0, "a player-group effect reaches the player")
	await wait_physics_frames(INTERVAL_FRAMES + 2)
	assert_eq(effect.calls, 0, "the clock reads the PLAYER group the effect registered it in")


func test_the_loop_uses_no_engine_timer() -> void:
	var effect: LoopEffect = _looping()
	assert_true(effect._timers.is_empty(), "a plain Timer node would ignore every time effect")


func test_two_loops_on_one_effect_tick_independently() -> void:
	var effect: LoopEffect = _looping()
	effect.start_second_loop(LONG_INTERVAL)
	assert_eq(_scaled_timer_node_ids().size(), 2, "one armed timer per loop")
	await wait_physics_frames(INTERVAL_FRAMES + 3)
	assert_eq(effect.calls, 1, "the short loop ticked")
	assert_eq(effect.second_calls, 0, "the long one has not yet")
	await wait_physics_frames(INTERVAL_FRAMES)
	assert_gte(effect.second_calls, 1, "and the long one ticks on its own interval")


func test_detach_stops_the_loop_and_frees_the_timer() -> void:
	var effect: LoopEffect = _looping()
	assert_eq(effect._periodic.size(), 1, "one loop recorded")
	var entry: Dictionary = effect._periodic.values()[0]
	var sig: Signal = entry["signal"]
	var connection: Callable = entry["connection"]
	assert_true(sig.is_connected(connection), "the armed timer calls this loop")
	effect.detach()
	assert_true(effect._periodic.is_empty(), "the loop is forgotten")
	assert_false(sig.is_connected(connection), "and disarmed, so it holds no reference to the effect")
	var calls_at_detach: int = effect.calls
	await wait_physics_frames(INTERVAL_FRAMES * 3)
	assert_eq(effect.calls, calls_at_detach, "no tick reaches a detached effect")


func test_detaching_one_effect_leaves_another_effects_loop_running() -> void:
	var first: LoopEffect = _looping()
	var second: LoopEffect = _looping()
	await wait_physics_frames(INTERVAL_FRAMES + 3)
	assert_eq(second.calls, 1, "both loops were ticking")
	first.detach()
	await wait_physics_frames(INTERVAL_FRAMES * 2)
	assert_between(second.calls, 2, 3, "the other effect's loop runs on after its neighbour detached")


## A relic that spends its last tick tearing itself down must not resurrect its
## loop: the re-arm is skipped when the handler detached the effect.
func test_a_handler_that_detaches_does_not_re_arm_the_loop() -> void:
	var effect: LoopEffect = _looping()
	effect.detach_on_first_tick = true
	await wait_physics_frames(INTERVAL_FRAMES + 3)
	assert_eq(effect.calls, 1, "the tick ran once")
	assert_false(effect.is_attached(), "and tore the effect down")
	assert_true(effect._periodic.is_empty(), "with no loop left armed")
	await wait_physics_frames(INTERVAL_FRAMES * 2)
	assert_eq(effect.calls, 1, "and no second tick")


func test_a_non_positive_interval_is_refused_without_arming_anything() -> void:
	var effect: LoopEffect = _attach(LoopEffect.new()) as LoopEffect
	effect.start_loop(0.0)
	assert_push_warning("needs a positive interval")
	assert_true(effect._periodic.is_empty(), "no loop recorded")
	assert_true(_scaled_timer_node_ids().is_empty(), "and no timer armed")


func test_an_invalid_callable_is_refused() -> void:
	var effect: LoopEffect = _attach(LoopEffect.new()) as LoopEffect
	effect.every_seconds(INTERVAL, Callable())
	assert_push_warning("needs a callable")
	assert_true(effect._periodic.is_empty(), "no loop recorded")
	assert_true(_scaled_timer_node_ids().is_empty(), "and no timer armed")


func test_every_seconds_before_attach_is_refused() -> void:
	var effect := LoopEffect.new()
	autofree(effect)
	effect.start_loop(INTERVAL)
	assert_push_warning("needs an attached player")
	assert_true(effect._periodic.is_empty(), "nothing armed for an effect with no player")
	assert_true(_scaled_timer_node_ids().is_empty(), "and nothing on the manager")
