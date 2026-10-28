extends GutTest
## The pure `EnemyStateLogic` behind the enemy standard states (SPEC-enemies-ai
## "Standard states"): the Idle scan and aggro check, the Chase keep-distance
## bands and attack gate, the HitStun knockback maths and clock, and the
## Stagger length. The closing cases run the real enemy scene through
## Idle -> Chase -> Attack -> HitStun -> Stagger on that logic. Owned by
## enemies-ai.

const ENEMY_SCENE := "res://scenes/enemies/enemy.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FRAME := 1.0 / 60.0
const ORIGIN := Vector2.ZERO


# --- the shared timer tick ------------------------------------------------------


func test_tick_down_counts_a_timer_down() -> void:
	var tick := EnemyStateLogic.tick_down(0.3, 0.1)
	assert_almost_eq(tick.left, 0.2, 0.0001)
	assert_false(tick.over)


func test_tick_down_is_over_at_the_boundary() -> void:
	var tick := EnemyStateLogic.tick_down(0.1, 0.1)
	assert_almost_eq(tick.left, 0.0, 0.0001)
	assert_true(tick.over, "equal counts as out")


func test_tick_down_runs_past_zero() -> void:
	var tick := EnemyStateLogic.tick_down(0.05, 0.1)
	assert_almost_eq(tick.left, -0.05, 0.0001)
	assert_true(tick.over)


# --- Idle: the scan and the aggro check ------------------------------------------


func test_the_idle_scan_runs_every_quarter_second() -> void:
	assert_eq(EnemyStateLogic.SCAN_SECONDS, 0.25)


func test_in_aggro_at_the_range_edge_is_inside() -> void:
	assert_true(EnemyStateLogic.in_aggro(260.0, 260.0))
	assert_false(EnemyStateLogic.in_aggro(260.1, 260.0), "one tenth past the range is outside")


# --- Chase: keep-distance bands and the attack gate -------------------------------


func test_a_melee_enemy_always_closes() -> void:
	assert_eq(EnemyStateLogic.chase_move(500.0, 0.0), EnemyStateLogic.ChaseMove.APPROACH)
	assert_eq(EnemyStateLogic.chase_move(1.0, 0.0), EnemyStateLogic.ChaseMove.APPROACH)


func test_the_keep_distance_bands() -> void:
	assert_eq(EnemyStateLogic.chase_move(79.0, 100.0), EnemyStateLogic.ChaseMove.BACK_OFF, "inside 0.8x: too close, back away")
	assert_eq(EnemyStateLogic.chase_move(80.0, 100.0), EnemyStateLogic.ChaseMove.HOLD, "exactly 0.8x: hold")
	assert_eq(EnemyStateLogic.chase_move(100.0, 100.0), EnemyStateLogic.ChaseMove.HOLD, "inside the keep distance: hold")
	assert_eq(EnemyStateLogic.chase_move(101.0, 100.0), EnemyStateLogic.ChaseMove.APPROACH, "past it: close again")


func test_the_attack_gate_needs_range_and_a_spent_cooldown() -> void:
	assert_true(EnemyStateLogic.chase_attack(40.0, 40.0, 0.0), "edge of the trigger range, cooldown spent")
	assert_false(EnemyStateLogic.chase_attack(40.1, 40.0, 0.0), "past the trigger range")
	assert_false(EnemyStateLogic.chase_attack(40.0, 40.0, 0.2), "the cooldown is still running")


# --- HitStun: the knockback maths --------------------------------------------------


func test_knockback_decay_kills_the_impulse_over_two_tenths() -> void:
	assert_eq(EnemyStateLogic.KNOCKBACK_DECAY_SECONDS, 0.2)
	var decel := EnemyStateLogic.knockback_decel(120.0)
	assert_almost_eq(decel, 600.0, 0.0001)
	assert_almost_eq(EnemyStateLogic.decayed_knockback(Vector2(120, 0), decel, 0.1).x, 60.0, 0.0001, "half the decay gone at half the time")
	assert_almost_eq(EnemyStateLogic.decayed_knockback(Vector2(120, 0), decel, 0.2).x, 0.0, 0.0001, "gone by 0.2 s")
	assert_almost_eq(EnemyStateLogic.knockback_decel(0.0), 0.0, 0.0001, "no impulse, no decel")


func test_a_wall_kills_the_knockback() -> void:
	assert_eq(EnemyStateLogic.knockback_after_wall(Vector2(60, 0), true), Vector2.ZERO)
	assert_eq(EnemyStateLogic.knockback_after_wall(Vector2(60, 0), false), Vector2(60, 0))


# --- Stagger -----------------------------------------------------------------------


func test_the_stagger_damage_factor() -> void:
	assert_eq(EnemyStateLogic.STAGGER_DAMAGE_TAKEN, 1.25)


func test_the_stagger_length() -> void:
	assert_eq(EnemyStateLogic.stagger_length(true, 1.5), 1.5, "the data's seconds")
	assert_eq(EnemyStateLogic.stagger_length(false, 0.0), EnemyStateLogic.DEFAULT_STAGGER_SECONDS, "no data: the default")
	assert_eq(EnemyStateLogic.DEFAULT_STAGGER_SECONDS, 0.8)


# --- the enemy scene runs on this logic ---------------------------------------------


var _enemy: Enemy
var _player: Player


func before_each() -> void:
	_enemy = (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	assert_true(_enemy.setup(&"hollow_miner"), "hollow_miner data loads")
	add_child_autofree(_enemy)
	_enemy.global_position = ORIGIN
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)


func after_each() -> void:
	NetworkManager.players.erase(1)


## Steps the enemy and its state machine `seconds` of game time.
func _step(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var dt := minf(FRAME, remaining)
		_enemy._physics_process(dt)
		_enemy.machine.physics_update(dt)
		remaining -= dt


func test_the_enemy_starts_idle() -> void:
	assert_eq(_enemy.machine.current_name(), &"Idle")


func test_idle_scans_and_chases_a_player_in_range() -> void:
	NetworkManager.players[1] = _player
	_player.global_position = Vector2(100, 0)
	_enemy.machine.physics_update(FRAME)
	assert_eq(_enemy.machine.current_name(), &"Chase", "the first scan finds the player inside the aggro range")


func test_idle_stays_idle_with_nobody_on_the_floor() -> void:
	_step(1.0)
	assert_eq(_enemy.machine.current_name(), &"Idle", "scanned twice, nobody to find")


func test_idle_ignores_a_player_past_the_aggro_range() -> void:
	NetworkManager.players[1] = _player
	_player.global_position = Vector2(_enemy.data.aggro_range + 50.0, 0)
	_step(0.5)
	assert_eq(_enemy.machine.current_name(), &"Idle")


func test_chase_hands_over_to_attack_in_the_trigger_range() -> void:
	NetworkManager.players[1] = _player
	var pattern: AttackPattern = _enemy.data.attacks[0]
	_player.global_position = Vector2(pattern.trigger_range * 0.5, 0)
	_enemy.machine.physics_update(FRAME)
	assert_eq(_enemy.machine.current_name(), &"Chase")
	_step(FRAME)
	assert_eq(_enemy.machine.current_name(), &"Attack", "the next scan closes the distance on the pure gate")
	assert_eq(_enemy.next_attack, pattern)


func test_chase_returns_to_idle_when_the_target_vanishes() -> void:
	NetworkManager.players[1] = _player
	_player.global_position = Vector2(100, 0)
	_enemy.machine.physics_update(FRAME)
	assert_eq(_enemy.machine.current_name(), &"Chase")
	NetworkManager.players.erase(1)
	_step(FRAME)
	assert_eq(_enemy.machine.current_name(), &"Idle", "the retarget finds nobody and aggro drops")


func test_a_hit_enters_hit_stun_and_returns_to_chase() -> void:
	NetworkManager.players[1] = _player
	# Out of the attack's trigger range but inside aggro, so the Chase the stun
	# returns to is a state that holds.
	_player.global_position = _out_of_trigger_position()
	_enemy.machine.physics_update(FRAME)
	_enemy.apply_knockback(Vector2(100, 0), 0.2)
	assert_eq(_enemy.machine.current_name(), &"HitStun")
	_step(0.3)
	assert_eq(_enemy.machine.current_name(), &"Chase", "the pure clock ran the stun out")
	assert_lte(_enemy.hit_stun_left, 0.0)


func test_the_stagger_state_runs_its_data_seconds_and_refills_poise() -> void:
	NetworkManager.players[1] = _player
	_player.global_position = _out_of_trigger_position()
	var seconds: float = _enemy.data.stagger_seconds
	assert_true(_enemy.machine.change_to(&"Stagger"))
	assert_true(_enemy.staggered)
	_step(seconds * 0.5)
	assert_eq(_enemy.machine.current_name(), &"Stagger", "halfway through the data's seconds")
	_enemy.poise = 1.0
	_step(seconds)
	assert_eq(_enemy.machine.current_name(), &"Chase")
	assert_false(_enemy.staggered)
	assert_eq(_enemy.poise, _enemy.poise_max, "poise refilled on the way out")


## A spot inside the aggro range but well past the attack's trigger range —
## far enough that even the knockback drift cannot close it — so a Chase that
## runs there stays a Chase.
func _out_of_trigger_position() -> Vector2:
	var pattern: AttackPattern = _enemy.data.attacks[0]
	return Vector2(pattern.trigger_range + 200.0, 0)
