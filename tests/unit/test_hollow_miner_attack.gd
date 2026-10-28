extends GutTest
## The Hollow Miner (W2-A10): its authored data attached to the G7b
## `enemy_base.tscn`, and its swing run through the G3 `AttackDriver` —
## windup, active and recovery in order, with nothing armed before the
## telegraph completes. Owned by enemies-ai.

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy_base.tscn")
const MINER_PATH: String = "res://data/enemies/collapsed_mines/hollow_miner.tres"
const SWING_PATH: String = "res://data/enemies/attacks/miner_swing.tres"
const MIN_RECOVERY_SECONDS: float = 0.3
const FRAME: float = 1.0 / 60.0

var _driver: AttackDriver = null
var _phase_log: Array[int] = []


func before_each() -> void:
	_driver = AttackDriver.new()
	_driver.windup_started.connect(_on_phase.bind(AttackDriver.Phase.WINDUP))
	_driver.active_started.connect(_on_phase.bind(AttackDriver.Phase.ACTIVE))
	_driver.recovery_started.connect(_on_phase.bind(AttackDriver.Phase.RECOVERY))
	_driver.attack_finished.connect(_on_phase.bind(AttackDriver.Phase.DONE))


func after_each() -> void:
	_driver = null
	_phase_log.clear()


func _on_phase(phase: int) -> void:
	_phase_log.append(phase)


func test_the_miners_data_loads_with_its_swing() -> void:
	var miner: EnemyData = load(MINER_PATH) as EnemyData
	assert_not_null(miner, "hollow_miner.tres loads as EnemyData")
	if miner == null:
		return
	assert_eq(miner.id, &"hollow_miner", "id matches the file name")
	assert_ne(miner.display_name, "", "display name set")
	assert_true(miner.base_stats.has(StatBlock.Stat.MAX_HP), "MAX_HP present")
	assert_eq(miner.attacks.size(), 1, "one attack: the swing")
	var swing: AttackPattern = load(SWING_PATH) as AttackPattern
	assert_not_null(swing, "miner_swing.tres loads as AttackPattern")
	if swing == null:
		return
	assert_eq(miner.attacks[0].id, swing.id, "the miner's attack is the swing")
	assert_eq(swing.kind, AttackPattern.Kind.MELEE, "the miner is melee (design doc, biome 1)")
	assert_gte(swing.windup_seconds, AttackPattern.MIN_WINDUP, "windup meets the attack contract")
	assert_gte(swing.recovery_seconds, MIN_RECOVERY_SECONDS, "recovery leaves the miner punishable")
	assert_gt(swing.damage, 0.0, "the swing deals damage")
	assert_gt(swing.trigger_range, 0.0, "the swing has a trigger range")


## The G8a attack test: the real `miner_swing.tres` through the G3 driver,
## stepped a physics frame at a time.
func test_the_swing_runs_windup_active_recovery_in_order_through_the_driver() -> void:
	var swing: AttackPattern = load(SWING_PATH) as AttackPattern
	_driver.start(swing)
	var total: float = swing.windup_seconds + swing.active_seconds + swing.recovery_seconds + 4.0 * FRAME
	var windup_frames := 0
	var active_frames := 0
	var recovery_frames := 0
	var hit_outside_active := 0
	for _step_index: int in int(ceil(total / FRAME)):
		_driver.advance(FRAME)
		match _driver.phase():
			AttackDriver.Phase.WINDUP:
				windup_frames += 1
				assert_gte(_driver.telegraph_progress(), 0.0, "the telegraph fills over the windup")
				assert_false(_driver.may_hit(), "nothing is armed during the windup")
			AttackDriver.Phase.ACTIVE:
				active_frames += 1
				assert_eq(_driver.telegraph_progress(), -1.0, "the telegraph hides at the hit")
				if not _driver.may_hit():
					hit_outside_active += 1
			AttackDriver.Phase.RECOVERY:
				recovery_frames += 1
				assert_false(_driver.may_hit(), "nothing is armed through the recovery")
			AttackDriver.Phase.DONE:
				pass
	assert_false(_driver.may_hit(), "nothing is armed after the swing")
	assert_gt(windup_frames, 0, "the telegraph was on screen before the hit")
	assert_gt(active_frames, 0, "the active window ran")
	assert_gt(recovery_frames, 0, "the recovery ran")
	assert_eq(hit_outside_active, 0, "may_hit only while the active window runs")
	var expected: Array[int] = [
		AttackDriver.Phase.WINDUP,
		AttackDriver.Phase.ACTIVE,
		AttackDriver.Phase.RECOVERY,
		AttackDriver.Phase.DONE,
	]
	assert_eq(_phase_log, expected, "the phases ran once each, in order")


func test_the_miner_attaches_to_enemy_base_with_its_states() -> void:
	var enemy: Enemy = ENEMY_SCENE.instantiate() as Enemy
	assert_true(enemy.setup(&"hollow_miner"), "the base scene sets up from the miner data")
	add_child_autofree(enemy)
	assert_eq(enemy.data.id, &"hollow_miner", "the enemy carries the miner data")
	assert_eq(enemy.data.attacks[0].id, &"miner_swing", "the machine's attack is the swing")
	var machine: Node = enemy.get_node("StateMachine")
	for state_name: String in ["Idle", "Chase", "Attack", "HitStun", "Stagger"]:
		assert_not_null(machine.get_node_or_null(NodePath(state_name)), "state %s" % state_name)
	assert_eq((enemy.get_node("Sprite") as AnimatedSprite2D).sprite_frames, enemy.data.sprite_frames,
			"the miner's placeholder frames are linked")
