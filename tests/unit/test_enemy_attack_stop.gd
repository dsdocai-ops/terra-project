extends GutTest
## A stopped enemy's attack timer does not run (SPEC-time-manager "stop_enemies", W4-B9).
## Enemy._physics_process counts its attack cooldown down by TimeManager-scaled time,
## so under a stop the cooldown holds and the attack cannot start. Owned by
## enemies-ai. Host-side logic; the test runs the server path (the offline peer).

const ENEMY_SCENE := "res://scenes/enemies/enemy_base.tscn"
const SOURCE: StringName = &"g9-attack-stop-test"

var _enemy: Enemy = null


func before_each() -> void:
	_enemy = (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	assert_true(_enemy.setup(&"hollow_miner", false), "the enemy data loads")
	add_child_autofree(_enemy)
	_enemy.set_physics_process(false)


func after_each() -> void:
	TimeManager.clear_source(SOURCE)


func test_a_stopped_enemy_attack_cooldown_does_not_count_down() -> void:
	_enemy.attack_cooldown_left = 0.5
	TimeManager.stop_enemies(1.0, SOURCE)
	_enemy._physics_process(0.5)
	assert_almost_eq(_enemy.attack_cooldown_left, 0.5, 0.0001, "the cooldown holds while time is stopped")


func test_a_running_enemy_attack_cooldown_counts_down() -> void:
	_enemy.attack_cooldown_left = 0.5
	_enemy._physics_process(0.2)
	assert_almost_eq(_enemy.attack_cooldown_left, 0.3, 0.0001, "the cooldown runs when time is normal")


func test_a_slowed_enemy_attack_cooldown_counts_down_slower() -> void:
	_enemy.attack_cooldown_left = 0.5
	TimeManager.slow_enemies(0.5, 1.0, SOURCE)
	_enemy._physics_process(0.2)
	assert_almost_eq(_enemy.attack_cooldown_left, 0.4, 0.0001, "half speed: 0.2 s of time takes 0.1 off")


func test_a_real_enemy_joins_the_enemy_time_group_on_ready() -> void:
	# Without the group a stop or a slow never reaches the enemy: scale_for reads the
	# group, and an unregistered node runs at normal time.
	assert_eq(TimeManager.scale_for(_enemy), 1.0, "normal time before any effect")
	TimeManager.stop_enemies(1.0, SOURCE)
	assert_eq(TimeManager.scale_for(_enemy), 0.0, "a stop reaches the real enemy")


## Movement consumers on the real Enemy (SPEC-time-manager "slow_enemies" and
## "stop_enemies"). move_toward_point sets velocity from the TimeManager scale, so
## the velocity it leaves behind is the per-tick motion. No floor in the test, so
## the steering is a straight line toward the point and the ratio is exact.
func test_a_slowed_enemy_steers_at_half_speed() -> void:
	_enemy.move_toward_point(Vector2(1000.0, 0.0), 100.0, 0.1)
	var normal: float = _enemy.velocity.length()
	TimeManager.slow_enemies(0.5, 1.0, SOURCE)
	_enemy.move_toward_point(Vector2(1000.0, 0.0), 100.0, 0.1)
	assert_gt(normal, 0.0, "a normal enemy moves")
	assert_almost_eq(_enemy.velocity.length(), normal * 0.5, 0.01, "a slowed enemy moves at half the speed")


func test_a_stopped_enemy_does_not_steer() -> void:
	TimeManager.stop_enemies(1.0, SOURCE)
	_enemy.move_toward_point(Vector2(1000.0, 0.0), 100.0, 0.1)
	assert_almost_eq(_enemy.velocity.length(), 0.0, 0.0001, "a stopped enemy leaves no motion behind")


## The state machine does not step the current state while the enemy is stopped,
## so a chase cannot change state (and so cannot reach the Attack gate) until time
## runs again. Normal time does step it.
func test_a_stopped_enemy_does_not_step_its_chase_state() -> void:
	assert_true(_enemy.machine.change_to(&"Chase"), "the chase state exists")
	TimeManager.stop_enemies(1.0, SOURCE)
	_enemy.machine.physics_update(0.1)
	assert_eq(_enemy.machine.current_name(), &"Chase", "a stopped chase is not stepped")
	assert_null(_enemy.next_attack, "a stopped enemy starts no attack")
	TimeManager.clear_source(SOURCE)
	_enemy.machine.physics_update(0.1)
	assert_ne(_enemy.machine.current_name(), &"Chase", "normal time steps the chase, which leaves it with no target")


## The attack-start gate, tested directly (G13 item d). The chase has a target inside
## its trigger range and the cooldown is up, so the Chase gate would start an attack
## on that step. Under a stop the StateMachine does not step the state, so no attack
## starts; with the stop lifted the same setup starts one. The retarget timer is set
## past its first tick so the target is kept and no player is needed.
func test_a_stopped_chase_in_range_with_cooldown_up_starts_no_attack() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	target.global_position = _enemy.global_position
	_enemy.target = target
	_enemy.attack_cooldown_left = 0.0
	assert_true(_enemy.machine.change_to(&"Chase"), "the chase state exists")
	_enemy.machine.current.set(&"_retarget_left", 10.0)
	TimeManager.stop_enemies(1.0, SOURCE)
	_enemy.machine.physics_update(0.1)
	assert_eq(_enemy.machine.current_name(), &"Chase", "a stopped chase stays in Chase")
	assert_null(_enemy.next_attack, "a stopped enemy starts no attack, even in range with the cooldown up")
	TimeManager.clear_source(SOURCE)
	_enemy.machine.physics_update(0.1)
	assert_eq(_enemy.machine.current_name(), &"Attack", "the same setup at normal time starts the attack")
