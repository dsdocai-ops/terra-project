extends GutTest
## Tests for scripts/components/state_machine.gd and state.gd.
## Shared component, owned by player-controller.


class ReadyActor extends Node2D:
	@onready var marker: Node = $Marker


class SpyState extends State:
	var entered_from: Array[StringName] = []
	var exited_to: Array[StringName] = []
	var updates: Array[float] = []
	var allow_exit: bool = true
	var allow_enter: bool = true
	var setup_actor: Node = null
	var actor_marker_on_enter: Node = null

	func _on_setup() -> void:
		setup_actor = actor

	func enter(from: StringName) -> void:
		entered_from.append(from)
		var ready_actor := actor as ReadyActor
		if ready_actor != null:
			actor_marker_on_enter = ready_actor.marker

	func exit(to: StringName) -> void:
		exited_to.append(to)

	func can_exit(_to: StringName) -> bool:
		return allow_exit

	func can_enter(_from: StringName) -> bool:
		return allow_enter

	func physics_update(delta: float) -> void:
		updates.append(delta)


var _actor: Node2D
var _machine: StateMachine
var _idle: SpyState
var _run: SpyState


func before_each() -> void:
	_actor = Node2D.new()
	_machine = StateMachine.new()
	_machine.name = "StateMachine"
	_idle = SpyState.new()
	_idle.name = "Idle"
	_run = SpyState.new()
	_run.name = "Run"
	_machine.add_child(_idle)
	_machine.add_child(_run)
	_machine.initial_state = &"Idle"
	_actor.add_child(_machine)
	add_child_autofree(_actor)


func test_initial_state_is_entered_on_ready() -> void:
	assert_eq(_machine.current, _idle)
	assert_eq(_idle.entered_from, [&""])


func test_initial_state_enters_after_actor_onready_vars_exist() -> void:
	var actor := ReadyActor.new()
	var marker := Node.new()
	marker.name = "Marker"
	actor.add_child(marker)
	var machine := StateMachine.new()
	var idle := SpyState.new()
	idle.name = "Idle"
	machine.add_child(idle)
	machine.initial_state = &"Idle"
	actor.add_child(machine)
	add_child_autofree(actor)
	assert_eq(idle.actor_marker_on_enter, marker, "actor's @onready marker was set when enter ran")


func test_states_know_their_machine_and_actor() -> void:
	assert_eq(_idle.machine, _machine)
	assert_eq(_idle.actor, _actor)
	assert_eq(_run.actor, _actor)


func test_on_setup_runs_once_with_actor_assigned() -> void:
	assert_eq(_idle.setup_actor, _actor)
	assert_eq(_run.setup_actor, _actor)


func test_change_to_exits_then_enters_and_emits() -> void:
	watch_signals(_machine)
	var ok := _machine.change_to(&"Run")
	assert_true(ok)
	assert_eq(_machine.current, _run)
	assert_eq(_idle.exited_to, [&"Run"])
	assert_eq(_run.entered_from, [&"Idle"])
	assert_signal_emitted_with_parameters(_machine, "state_changed", [&"Idle", &"Run"])


func test_change_to_unknown_state_is_refused() -> void:
	assert_false(_machine.change_to(&"Nope"))
	assert_eq(_machine.current, _idle)


func test_change_to_same_state_is_a_no_op() -> void:
	watch_signals(_machine)
	assert_false(_machine.change_to(&"Idle"))
	assert_eq(_idle.entered_from.size(), 1, "not re-entered")
	assert_signal_not_emitted(_machine, "state_changed")


func test_current_state_can_refuse_exit() -> void:
	_idle.allow_exit = false
	assert_false(_machine.change_to(&"Run"))
	assert_eq(_machine.current, _idle)
	assert_eq(_run.entered_from, [])


func test_target_state_can_refuse_entry() -> void:
	_run.allow_enter = false
	assert_false(_machine.change_to(&"Run"))
	assert_eq(_machine.current, _idle)


func test_physics_update_forwards_scaled_delta() -> void:
	_machine.time_scale = 0.5
	_machine.physics_update(0.1)
	assert_almost_eq(_idle.updates[0], 0.05, 0.0001)


func test_current_name() -> void:
	assert_eq(_machine.current_name(), &"Idle")
	_machine.change_to(&"Run")
	assert_eq(_machine.current_name(), &"Run")
