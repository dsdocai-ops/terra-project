class_name StateMachine
extends Node
## Node-based state machine shared by the player, enemies, and bosses.
## Owned by player-controller (shared component, both lanes review changes).
## Sync: none itself. The owning entity replicates whatever state name it
## needs through its own synchronizer.
##
## Children of type State are the states, looked up by node name. Set
## `initial_state` to enter one on ready. States may refuse transitions with
## can_exit() / can_enter(). `time_scale` scales the delta passed to the
## current state so TimeManager can slow or stop an entity (week 2).

signal state_changed(from: StringName, to: StringName)

@export var initial_state: StringName = &""

## Multiplier applied to delta before it reaches the current state.
var time_scale: float = 1.0
var current: State = null

var _states: Dictionary = {}


func _ready() -> void:
	var actor := get_parent()
	for child in get_children():
		var state := child as State
		if state == null:
			continue
		state.machine = self
		state.actor = actor
		_states[state.name] = state
	if initial_state == &"":
		return
	# Children are ready before their parent, so the actor's @onready
	# references do not exist yet. Enter the initial state once the actor is
	# ready (immediately if the machine was added to an already-ready actor).
	if actor.is_node_ready():
		change_to(initial_state)
	else:
		actor.ready.connect(change_to.bind(initial_state), CONNECT_ONE_SHOT)


func _physics_process(delta: float) -> void:
	physics_update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current != null:
		current.handle_input(event)


## Drives the current state. Public so tests and owners can step manually.
func physics_update(delta: float) -> void:
	if current != null:
		current.physics_update(delta * time_scale)


## Returns true when the transition happened. Refused when the state is
## unknown, is already current, the current state refuses to exit, or the
## target refuses to enter.
func change_to(state_name: StringName) -> bool:
	var target := _states.get(state_name) as State
	if target == null:
		push_warning("StateMachine: unknown state %s" % state_name)
		return false
	if target == current:
		return false
	var from := current_name()
	if current != null and not current.can_exit(state_name):
		return false
	if not target.can_enter(from):
		return false
	if current != null:
		current.exit(state_name)
	current = target
	current.enter(from)
	state_changed.emit(from, state_name)
	return true


func current_name() -> StringName:
	return current.name if current != null else &""


func has_state(state_name: StringName) -> bool:
	return _states.has(state_name)
