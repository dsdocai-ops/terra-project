class_name State
extends Node
## Base class for StateMachine states. Owned by player-controller (shared).
## Sync: none. Subclass, override the hooks you need, and add the node as a
## child of a StateMachine. `actor` is the machine's parent (Player, Enemy...).

var machine: StateMachine
var actor: Node


## Called once by the machine after `machine` and `actor` are assigned, before
## any state is entered. Cache typed references to the actor here.
func _on_setup() -> void:
	pass


func enter(_from: StringName) -> void:
	pass


func exit(_to: StringName) -> void:
	pass


func can_exit(_to: StringName) -> bool:
	return true


func can_enter(_from: StringName) -> bool:
	return true


func physics_update(_delta: float) -> void:
	pass


func handle_input(_event: InputEvent) -> void:
	pass
