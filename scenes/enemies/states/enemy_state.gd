class_name EnemyState
extends State
## Base for every enemy state: resolves the typed Enemy once. Owned by
## enemies-ai. Sync: host-only (clients never step the machine).

var enemy: Enemy


func _on_setup() -> void:
	enemy = actor as Enemy
	assert(enemy != null, "EnemyState must sit under an Enemy's StateMachine")
