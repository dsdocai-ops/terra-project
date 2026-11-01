extends GutTest
## Integration of the host cast path (SPEC-abilities "AbilityController" and the
## cast flow): a cast spawns its node and runs it once, a second cast inside the
## cooldown is refused, Events.ability_cast fires once per accepted cast, and the
## client request RPC refuses a sender that does not own the player. Owned by
## abilities. The controller has no player here, so the test host owns the cast.
## Physics processing is off, so no frame moves the cooldowns.

const SLOT_Q: int = 0
const TIME_SOURCE: StringName = &"test_cast_flow_slow"

var _controller: AbilityController


func before_each() -> void:
	_controller = AbilityController.new()
	add_child_autofree(_controller)
	_controller.set_physics_process(false)
	_controller.assign(SLOT_Q, FixtureAbility.make())


func after_each() -> void:
	TimeManager.clear_source(TIME_SOURCE)
	if is_instance_valid(_controller.last_cast) and not _controller.last_cast.is_queued_for_deletion():
		_controller.last_cast.queue_free()


func test_a_cast_spawns_its_node_and_the_host_runs_it_once() -> void:
	assert_true(_controller.request_cast(SLOT_Q, Vector2(64, 0)), "the first cast is accepted")
	var cast := _controller.last_cast as FixtureCast
	assert_not_null(cast, "the cast spawned the fixture cast node")
	assert_true(cast.is_inside_tree(), "the cast node is in the tree")
	assert_eq(cast.performs, 1, "the host performs the cast once")
	assert_eq(cast.aim_point, Vector2(64, 0), "the cast gets the aim point")


func test_a_second_cast_inside_the_cooldown_is_refused_and_spawns_nothing() -> void:
	assert_true(_controller.request_cast(SLOT_Q, Vector2.RIGHT))
	var first := _controller.last_cast
	assert_false(_controller.request_cast(SLOT_Q, Vector2.RIGHT), "the second cast is refused")
	assert_eq(_controller.last_refusal, AbilityController.REFUSE_COOLING, "the refusal says cooling")
	assert_same(_controller.last_cast, first, "the refused cast spawns no node")


func test_each_accepted_cast_fires_ability_cast_once() -> void:
	watch_signals(Events)
	_controller.request_cast(SLOT_Q, Vector2.RIGHT)
	assert_signal_emit_count(Events, "ability_cast", 1, "one accepted cast emits once")
	_controller.request_cast(SLOT_Q, Vector2.RIGHT)
	assert_signal_emit_count(Events, "ability_cast", 1, "a refused cast emits nothing")


func test_a_client_request_with_no_sender_is_refused_and_spends_nothing() -> void:
	_controller._remote_request_cast(SLOT_Q, Vector2.RIGHT)
	assert_eq(_controller.last_refusal, AbilityController.REFUSE_NOT_OWNER, "no sender is not the owner")
	assert_eq(_controller.charges(SLOT_Q), 1, "the charge is still there")
	assert_null(_controller.last_cast, "no cast spawns")
