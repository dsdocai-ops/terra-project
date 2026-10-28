extends GutTest
## Tests for scenes/player/states/dodge.gd on the real player scene (W2-A8
## wiring half): the i-frames last exactly the roll through the real Hurtbox,
## and only a blocked hit inside the first
## `DodgeClock.PERFECT_DODGE_QUALIFY_SECONDS` of the roll is a perfect dodge.
## Owned by player-controller. The state machine and the combat timers are
## stepped by hand and there are no awaits, so nothing double-steps; the pure
## numbers themselves are `test_dodge_clock.gd`'s.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _player: Player
var _health: Health
var _hurtbox: Hurtbox
var _attacker: Node2D
var _dodges: Array[bool] = []


func before_each() -> void:
	# A global slow leaked from another file must not stretch the roll here.
	TimeManager.clear_source(TimeManager.HIT_STOP_SOURCE)
	TimeManager.clear_source(&"test")
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.state_machine.set_physics_process(false)
	_health = _player.health as Health
	_hurtbox = _player.hurtbox as Hurtbox
	_attacker = Node2D.new()
	add_child_autofree(_attacker)
	_attacker.position = Vector2(100, 0)
	_dodges.clear()
	Events.player_dodged.connect(_on_player_dodged)


func after_each() -> void:
	if Events.player_dodged.is_connected(_on_player_dodged):
		Events.player_dodged.disconnect(_on_player_dodged)
	TimeManager.clear_source(TimeManager.HIT_STOP_SOURCE)
	TimeManager.clear_source(&"test")


func _on_player_dodged(_who: Player, perfect: bool) -> void:
	_dodges.append(perfect)


func _start_roll() -> void:
	assert_true(_player.state_machine.change_to(&"Dodge"), "the roll started")


func _step(delta: float) -> void:
	_player.state_machine.physics_update(delta)
	_player._tick_combat_timers(delta)


func _hit() -> HitInfo:
	var hit := HitInfo.new()
	hit.base_damage = 10.0
	hit.source = _attacker
	return hit


# --- i-frames through the real hurtbox ----------------------------------------


func test_the_hurtbox_ignores_damage_for_exactly_the_roll_length() -> void:
	_start_roll()
	assert_true(_hurtbox.invulnerable, "i-frames are up on entry")
	assert_true(_hurtbox.dodge_invulnerable, "the dodge flag is up with them")
	_step(0.2799)
	assert_eq(_player.state_machine.current_name(), &"Dodge", "one frame before the end")
	assert_false(_hurtbox.receive(_hit()), "a hit one frame before the end is avoided")
	assert_eq(_health.current_hp, _health.max_hp, "and it did no damage")
	_step(0.0002)
	assert_eq(_player.state_machine.current_name(), &"Idle", "the roll ended (no move input)")
	assert_false(_hurtbox.invulnerable, "the i-frames end with the roll")
	assert_false(_hurtbox.dodge_invulnerable)
	assert_true(_hurtbox.receive(_hit()), "the next hit lands")
	assert_lt(_health.current_hp, _health.max_hp, "and it hurts")


func test_a_blocked_hit_during_the_roll_reports_blocked_and_harmless() -> void:
	_start_roll()
	watch_signals(_hurtbox)
	_step(0.05)
	assert_false(_hurtbox.receive(_hit()), "the hit is avoided")
	assert_signal_emitted(_hurtbox, "blocked_during_dodge")
	assert_eq(_health.current_hp, _health.max_hp)


# --- the perfect-dodge qualifying window (first 0.12 s of the roll) ------------


func test_a_blocked_hit_just_inside_the_window_is_a_perfect_dodge() -> void:
	_start_roll()
	_step(0.11)
	assert_false(_hurtbox.receive(_hit()), "the hit is avoided")
	assert_eq(_health.current_hp, _health.max_hp)
	assert_true(_player.is_perfect_dodge_window(), "the perfect-dodge window opened")
	assert_eq(_dodges, [true] as Array[bool], "player_dodged(true) once, at the block")
	_step(0.2)
	assert_eq(_player.state_machine.current_name(), &"Idle", "the roll ended")
	assert_eq(_dodges, [true] as Array[bool], "the ending dodge adds nothing")
	assert_true(_player.is_perfect_dodge_window(), "the 0.5 s skill window outlives the roll")


func test_a_blocked_hit_just_outside_the_window_is_not_a_perfect_dodge() -> void:
	_start_roll()
	_step(0.13)
	assert_false(_hurtbox.receive(_hit()), "the i-frames still avoid the hit")
	assert_eq(_health.current_hp, _health.max_hp)
	assert_false(_player.is_perfect_dodge_window(), "no window for a late blocked hit")
	assert_eq(_dodges, [] as Array[bool], "and no player_dodged(true)")
	_step(0.2)
	assert_eq(_dodges, [false] as Array[bool], "the dodge ends reported as not perfect")


func test_a_second_dodge_restarts_the_window() -> void:
	_start_roll()
	_step(0.3)
	_player.reset_dodge_cooldown()
	_dodges.clear()
	_start_roll()
	assert_almost_eq(_player.dodge_elapsed, 0.0, 0.0001, "the elapsed roll time restarted")
	_step(0.11)
	assert_false(_hurtbox.receive(_hit()), "the hit is avoided")
	assert_true(_player.is_perfect_dodge_window(), "a fresh roll's window is live again")


func test_the_dodge_state_publishes_the_elapsed_roll_time() -> void:
	assert_eq(_player.dodge_elapsed, 0.0)
	_start_roll()
	_step(0.07)
	assert_almost_eq(_player.dodge_elapsed, 0.07, 0.0001, "the gate reads the state's clock")


# --- the 0.5 s skill window ----------------------------------------------------


func test_the_skill_window_closes_on_the_spec_value() -> void:
	_player.open_perfect_dodge_window()
	assert_true(_player.is_perfect_dodge_window())
	_player._tick_combat_timers(0.4999)
	assert_true(_player.is_perfect_dodge_window(), "still open just inside 0.5 s")
	_player._tick_combat_timers(0.0002)
	assert_false(_player.is_perfect_dodge_window(), "closed just outside")


func test_consuming_the_window_closes_it_at_once() -> void:
	_player.open_perfect_dodge_window()
	_player.consume_perfect_dodge_window()
	assert_false(_player.is_perfect_dodge_window())
