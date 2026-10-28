extends GutTest
## The Lantern Wisp (W2-A10): its authored data attached to the G7b
## `enemy_base.tscn`, and its fireball run through the G3 `AttackDriver` —
## windup, active and recovery in order, with nothing armed before the
## telegraph completes. The only week 2 enemy whose attack spawns a projectile,
## so the fireball flies the G4 projectile base (the live-fire half is
## `tests/integration/test_wisp_live_fire.gd`). Owned by enemies-ai.

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy_base.tscn")
const WISP_PATH: String = "res://data/enemies/collapsed_mines/lantern_wisp.tres"
const FIREBALL_PATH: String = "res://data/enemies/attacks/wisp_fireball.tres"
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


func test_the_wisps_data_loads_with_its_fireball() -> void:
	var wisp: EnemyData = load(WISP_PATH) as EnemyData
	assert_not_null(wisp, "lantern_wisp.tres loads as EnemyData")
	if wisp == null:
		return
	assert_eq(wisp.id, &"lantern_wisp", "id matches the file name")
	assert_ne(wisp.display_name, "", "display name set")
	assert_true(wisp.base_stats.has(StatBlock.Stat.MAX_HP), "MAX_HP present")
	assert_eq(wisp.attacks.size(), 1, "one attack: the fireball")
	var fireball: AttackPattern = load(FIREBALL_PATH) as AttackPattern
	assert_not_null(fireball, "wisp_fireball.tres loads as AttackPattern")
	if fireball == null:
		return
	assert_eq(wisp.attacks[0].id, fireball.id, "the wisp's attack is the fireball")
	assert_eq(fireball.kind, AttackPattern.Kind.PROJECTILE, "the wisp is the ranged fireball caster (SPEC-enemies-ai, week 2 trio)")
	assert_gte(fireball.windup_seconds, AttackPattern.MIN_WINDUP, "windup meets the attack contract")
	assert_gte(fireball.recovery_seconds, MIN_RECOVERY_SECONDS, "recovery leaves the wisp punishable")
	assert_gt(fireball.damage, 0.0, "the fireball deals damage")
	assert_gt(fireball.trigger_range, wisp.keep_distance, "the wisp opens fire from its hold distance, not inside it")
	assert_gt(fireball.speed, 0.0, "the fireball has a projectile speed (PROJECTILE: projectile speed)")


## The G8b2 attack test: the real `wisp_fireball.tres` through the G3 driver,
## stepped a physics frame at a time.
func test_the_fireball_runs_windup_active_recovery_in_order_through_the_driver() -> void:
	var fireball: AttackPattern = load(FIREBALL_PATH) as AttackPattern
	_driver.start(fireball)
	var total: float = fireball.windup_seconds + fireball.active_seconds + fireball.recovery_seconds + 4.0 * FRAME
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
	assert_false(_driver.may_hit(), "nothing is armed after the fireball")
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


func test_the_wisp_attaches_to_enemy_base_with_its_states() -> void:
	var enemy: Enemy = ENEMY_SCENE.instantiate() as Enemy
	assert_true(enemy.setup(&"lantern_wisp"), "the base scene sets up from the wisp data")
	add_child_autofree(enemy)
	assert_eq(enemy.data.id, &"lantern_wisp", "the enemy carries the wisp data")
	assert_eq(enemy.data.attacks[0].id, &"wisp_fireball", "the machine's attack is the fireball")
	var machine: Node = enemy.get_node("StateMachine")
	for state_name: String in ["Idle", "Chase", "Attack", "HitStun", "Stagger"]:
		assert_not_null(machine.get_node_or_null(NodePath(state_name)), "state %s" % state_name)
	assert_eq((enemy.get_node("Sprite") as AnimatedSprite2D).sprite_frames, enemy.data.sprite_frames,
			"the wisp's placeholder frames are linked")
