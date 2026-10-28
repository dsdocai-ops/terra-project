extends GutTest
## Tests for scenes/player/states/dead.gd on the real player scene (W3-A5's
## state half, G13a2): Dead holds the body still and grey for the rest of the
## floor, refuses every exit but the next floor's fresh run, and
## `reset_for_run` stands the player back up. Owned by player-controller.
##
## The machine is stepped by hand and there are no awaits. The solo lethal hit
## reaches Dead through the real damage path; the Downed half of the flow is
## test_downed_state.gd's.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _player: Player
var _health: Health


func before_each() -> void:
	# A slow or hit-stop leaked from another file must not stretch anything.
	TimeManager.clear_source(TimeManager.HIT_STOP_SOURCE)
	TimeManager.clear_source(&"test")
	GameState.run = null
	NetworkManager.players.clear()
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.state_machine.set_physics_process(false)
	_health = _player.health as Health


func after_each() -> void:
	NetworkManager.players.clear()
	GameState.run = null
	TimeManager.clear_source(TimeManager.HIT_STOP_SOURCE)
	TimeManager.clear_source(&"test")


## Solo (no teammate registered): the lethal hit goes straight to Dead.
func _die_the_player() -> void:
	var hit := HitInfo.new()
	hit.final_damage = 9999
	_health.apply_damage(hit)
	assert_eq(_player.state_machine.current_name(), &"Dead", "setup: the player is Dead")


# --- Dead holds the body ------------------------------------------------------


func test_the_dead_state_holds_the_body_still() -> void:
	_die_the_player()
	_player.velocity = Vector2(90.0, 0.0)
	_player.state_machine.physics_update(1.0 / 60.0)
	assert_eq(_player.velocity, Vector2.ZERO, "a dead player cannot move")


func test_the_dead_sprite_is_greyed_out() -> void:
	_die_the_player()
	assert_eq(_player.sprite.modulate, Color(0.3, 0.3, 0.3, 0.6),
		"the dead tint marks the body for every peer")


# --- the exits ----------------------------------------------------------------


func test_dead_refuses_everything_but_the_fresh_run() -> void:
	_die_the_player()
	assert_false(_player.state_machine.change_to(&"Move"))
	assert_false(_player.state_machine.change_to(&"Attack"))
	assert_false(_player.state_machine.change_to(&"Dodge"))
	assert_false(_player.state_machine.change_to(&"HitStun"))
	assert_false(_player.state_machine.change_to(&"HeavyCharge"))
	assert_false(_player.state_machine.change_to(&"Downed"))
	assert_eq(_player.state_machine.current_name(), &"Dead",
		"the only exit is Idle, and it is the next floor's fresh run that takes it (below)")


func test_the_fresh_run_is_the_one_exit_dead_allows() -> void:
	_die_the_player()
	assert_true(_player.state_machine.change_to(&"Idle"),
		"reset_for_run's door: Idle is the one state Dead lets go")
	assert_eq(_player.state_machine.current_name(), &"Idle")


func test_reset_for_run_stands_a_dead_player_back_up() -> void:
	_die_the_player()
	_player.reset_for_run()
	assert_eq(_player.state_machine.current_name(), &"Idle", "the fresh run stands them up")
	assert_false(_player.is_dead)
	assert_eq(_health.current_hp, _health.max_hp, "back at full HP")
	assert_eq(_player.sprite.modulate, Color.WHITE, "and the tint is cleared")
