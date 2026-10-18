extends GutTest
## Tests for the player's Idle and Move states. Owned by player-controller.
## States read Player.move_input, not Input directly, so they run headless
## without the Input Map.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _player: Player


func before_each() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)


func test_starts_idle() -> void:
	assert_eq(_player.state_machine.current_name(), &"Idle")
	assert_eq(_player.sprite.animation, &"idle_s")


func test_input_moves_to_move_state_and_plays_walk() -> void:
	_player.move_input = Vector2(1, 0)
	_player.state_machine.physics_update(1.0 / 60.0)
	assert_eq(_player.state_machine.current_name(), &"Move")
	assert_true(String(_player.sprite.animation).begins_with("walk_"))


func test_releasing_input_returns_to_idle() -> void:
	_player.move_input = Vector2(0, 1)
	_player.state_machine.physics_update(1.0 / 60.0)
	_player.move_input = Vector2.ZERO
	_player.state_machine.physics_update(1.0 / 60.0)
	assert_eq(_player.state_machine.current_name(), &"Idle")
	assert_true(String(_player.sprite.animation).begins_with("idle_"))


func test_state_machine_is_typed_on_player() -> void:
	assert_true(_player.state_machine is StateMachine)
