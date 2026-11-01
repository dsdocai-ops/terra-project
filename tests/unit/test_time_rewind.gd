extends GutTest
## TimeManager rewind (SPEC-time-manager "Rewind", W4-B9): a registered node is
## sampled every 0.1 s of real time over a 3 s window, and `rewind(node, seconds)`
## restores the newest sample at or before that point. Owned by time-manager. The
## clock is driven by `tick_rewind` so the samples are exact and the physics tick
## does not add frames to the count. Nothing here replicates.

var _node: Node = null
var _value: int = 0
var _restored: Variant = null


func before_each() -> void:
	# The autoload's own physics tick would add real frames to the clock; stop it
	# for these cases and start the clock from zero.
	TimeManager.set_physics_process(false)
	TimeManager._rewind_clock = 0.0
	TimeManager._rewind_next_sample = 0.0
	_node = Node.new()
	add_child_autofree(_node)
	_value = 0
	_restored = null


func after_each() -> void:
	TimeManager.unregister_rewindable(_node)
	TimeManager.set_physics_process(true)


func _sample() -> Variant:
	return _value


func _restore(state: Variant) -> void:
	_restored = state


func _register() -> void:
	TimeManager.register_rewindable(_node, Callable(self, &"_sample"), Callable(self, &"_restore"))


func _track() -> Array:
	return TimeManager._rewind[_node.get_instance_id()].samples


func _tick(seconds: float, steps: int) -> void:
	for step: int in steps:
		_value += 1
		TimeManager.tick_rewind(seconds)


func test_a_registered_node_is_sampled_every_tenth_of_a_second() -> void:
	_register()
	_tick(0.1, 10)
	assert_eq(_track().size(), 10, "one sample per 0.1 s over one second")


## The interval holds when the clock is driven by real physics ticks (1/60 s), not
## by steps that each cover a whole interval: every gap between samples is one
## interval, rounded up to the next physics tick, and 3 s holds about 30 samples.
func test_samples_stay_one_interval_apart_under_physics_sized_ticks() -> void:
	_register()
	var physics_tick: float = 1.0 / 60.0
	_tick(physics_tick, 180)
	var track: Array = _track()
	assert_between(track.size(), 29, 31, "about 30 samples over 3 s of physics ticks")
	for i in range(1, track.size()):
		var gap: float = float(track[i].at) - float(track[i - 1].at)
		assert_gte(gap, TimeManager.REWIND_SAMPLE_SECONDS - 0.0001, "no two samples closer than 0.1 s")
		assert_lte(gap, TimeManager.REWIND_SAMPLE_SECONDS + physics_tick + 0.0001, "no gap wider than 0.1 s plus one tick")


func test_the_window_caps_the_samples_at_three_seconds() -> void:
	_register()
	_tick(0.1, 60)
	var clock: float = TimeManager._rewind_clock
	var oldest: float = float(_track()[0].at)
	assert_gte(oldest, clock - TimeManager.REWIND_WINDOW_SECONDS - 0.0001, "nothing older than the window is kept")
	assert_lte(_track().size(), 31, "about 30 samples in 3 s, never more than 31")


func test_rewind_restores_the_newest_sample_at_or_before_that_point() -> void:
	_register()
	_tick(0.1, 30)
	# 30 ticks of 0.1 s: the clock is 3.0 s and the sample at 2.0 s holds value 20.
	TimeManager.rewind(_node, 1.0)
	assert_eq(_restored, 20, "rewind 1 s goes back to the sample taken at 2.0 s")


func test_rewind_drops_the_samples_newer_than_the_one_it_restored() -> void:
	_register()
	_tick(0.1, 30)
	TimeManager.rewind(_node, 1.0)
	assert_eq(float(_track().back().at) <= 2.0001, true, "nothing newer than the restored sample is kept")


func test_rewind_beyond_the_window_restores_nothing() -> void:
	_register()
	_tick(0.1, 60)
	_restored = "untouched"
	TimeManager.rewind(_node, 10.0)
	assert_eq(_restored, "untouched", "no sample is that old, so nothing is restored")


func test_an_unregistered_node_is_not_sampled_or_restored() -> void:
	_tick(0.1, 10)
	TimeManager.rewind(_node, 1.0)
	assert_null(_restored, "a node that never registered is left alone")


# --- entity time effects broadcast as reliable RPCs (W4-B9) -------------------------


func _rpc_entry(method: StringName) -> Dictionary:
	var script: Script = TimeManager.get_script()
	var config: Variant = script.call(&"get_rpc_config") if script != null and script.has_method(&"get_rpc_config") else {}
	var entry: Variant = (config as Dictionary).get(method, {}) if config is Dictionary else {}
	return entry as Dictionary if entry is Dictionary else {}


func test_entity_time_effects_are_broadcast_as_reliable_rpcs() -> void:
	for method: StringName in [&"time_effect_applied", &"entity_time_applied"]:
		var entry: Dictionary = _rpc_entry(method)
		assert_false(entry.is_empty(), "%s is an RPC" % method)
		assert_eq(entry.get("transfer_mode"), MultiplayerPeer.TRANSFER_MODE_RELIABLE, "%s is reliable" % method)
