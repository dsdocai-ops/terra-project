extends GutTest
## The windup / active / recovery driver behind every `AttackPattern`
## (SPEC-combat-core "Enemy attack contract"), including the contract's gate:
## **no hit without a telegraph.** Owned by combat-core. The pure clock is
## tested on a bare driver; the last case proves the real enemy attack state
## runs on it — nothing armed during the windup, armed through `active_started`
## only, disarmed the frame recovery begins. Named-method callbacks only (a
## lambda connect never fires in GUT).

const ENEMY_SCENE := "res://scenes/enemies/enemy.tscn"
const FRAME := 1.0 / 60.0
const WINDUP := 0.3
const ACTIVE := 0.2
const RECOVERY := 0.4

var _driver: AttackDriver
var _pattern: AttackPattern
var _events: Array[String] = []


func before_each() -> void:
	_pattern = AttackPattern.new()
	_pattern.id = &"test_swing"
	_pattern.windup_seconds = WINDUP
	_pattern.active_seconds = ACTIVE
	_pattern.recovery_seconds = RECOVERY
	_driver = AttackDriver.new()
	_driver.windup_started.connect(_on_windup)
	_driver.active_started.connect(_on_active)
	_driver.recovery_started.connect(_on_recovery)
	_driver.attack_finished.connect(_on_finished)
	_events.clear()


func _on_windup() -> void:
	_events.append("windup")


func _on_active() -> void:
	_events.append("active")


func _on_recovery() -> void:
	_events.append("recovery")


func _on_finished() -> void:
	_events.append("finished")


# --- the phase clock ------------------------------------------------------------------


func test_a_started_driver_is_in_the_windup() -> void:
	_driver.start(_pattern)
	assert_eq(_driver.phase(), AttackDriver.Phase.WINDUP)


func test_the_phases_run_windup_active_recovery_in_order() -> void:
	_driver.start(_pattern)
	assert_eq(_driver.advance(WINDUP), AttackDriver.Phase.ACTIVE, "the windup boundary opens the active window")
	assert_eq(_driver.advance(ACTIVE), AttackDriver.Phase.RECOVERY)
	assert_eq(_driver.advance(RECOVERY), AttackDriver.Phase.DONE)
	assert_eq(_events, ["windup", "active", "recovery", "finished"] as Array[String])


func test_the_clock_does_not_cross_a_boundary_early() -> void:
	_driver.start(_pattern)
	assert_eq(_driver.advance(WINDUP - 0.01), AttackDriver.Phase.WINDUP, "still winding up just before the boundary")
	assert_eq(_driver.advance(0.005), AttackDriver.Phase.WINDUP)
	assert_eq(_driver.advance(0.005), AttackDriver.Phase.ACTIVE, "open exactly at the windup")
	assert_eq(_driver.advance(ACTIVE - 0.005), AttackDriver.Phase.ACTIVE)
	assert_eq(_driver.advance(0.005), AttackDriver.Phase.RECOVERY, "recovery exactly at the active end")
	assert_eq(_driver.advance(RECOVERY - 0.005), AttackDriver.Phase.RECOVERY)
	assert_eq(_driver.advance(0.005), AttackDriver.Phase.DONE, "done exactly at the recovery end")


func test_a_hitch_frame_crosses_one_boundary_and_drops_the_leftover() -> void:
	_driver.start(_pattern)
	assert_eq(_driver.advance(100.0), AttackDriver.Phase.ACTIVE, "one boundary per step")
	assert_eq(_driver.advance(0.1), AttackDriver.Phase.ACTIVE, "the active window still has its full duration")
	assert_eq(_driver.advance(0.1), AttackDriver.Phase.RECOVERY, "and it ends at its own boundary")
	assert_eq(_events, ["windup", "active", "recovery"] as Array[String])


func test_a_finished_driver_stays_done() -> void:
	_driver.start(_pattern)
	# One boundary per step, so the attack ends on the third crossing.
	while _driver.advance(10.0) != AttackDriver.Phase.DONE:
		pass
	assert_eq(_driver.phase(), AttackDriver.Phase.DONE)
	assert_eq(_events.size(), 4, "no second set of phase signals")


# --- the telegraph fill ------------------------------------------------------------------


func test_the_telegraph_fills_over_the_windup_and_hides_after() -> void:
	_driver.start(_pattern)
	assert_almost_eq(_driver.telegraph_progress(), 0.0, 0.0001, "empty at the start")
	_driver.advance(WINDUP * 0.5)
	assert_almost_eq(_driver.telegraph_progress(), 0.5, 0.0001, "half way through the windup")
	_driver.advance(WINDUP * 0.5)
	assert_eq(_driver.phase(), AttackDriver.Phase.ACTIVE)
	assert_eq(_driver.telegraph_progress(), -1.0, "hidden once the windup is over")
	_driver.advance(ACTIVE + RECOVERY)
	assert_eq(_driver.telegraph_progress(), -1.0)


func test_the_fill_clamps_a_clock_past_the_boundary() -> void:
	_driver.start(_pattern)
	_driver.advance(WINDUP * 2.0)
	assert_eq(_driver.phase(), AttackDriver.Phase.ACTIVE, "the boundary is crossed")
	assert_eq(_driver.telegraph_progress(), -1.0)


# --- the gate: no hit without a telegraph -----------------------------------------------


func test_nothing_can_hit_during_the_windup() -> void:
	_driver.start(_pattern)
	_driver.advance(WINDUP * 0.9)
	assert_false(_driver.may_hit(), "the active window has not opened")


func test_the_hit_arms_only_once_the_telegraph_has_run() -> void:
	_driver.start(_pattern)
	assert_false(_driver.may_hit())
	_driver.advance(WINDUP)
	assert_eq(_driver.phase(), AttackDriver.Phase.ACTIVE)
	assert_true(_driver.may_hit(), "telegraph complete, active open: the hit is live")
	_driver.advance(ACTIVE)
	assert_false(_driver.may_hit(), "disarmed the frame recovery begins")


func test_a_driver_poked_into_active_without_a_telegraph_cannot_hit() -> void:
	# The gate is not merely the phase check: this driver is forced into ACTIVE
	# the way a bug would, but its windup never ran, so the hit stays dead.
	_driver._phase = AttackDriver.Phase.ACTIVE
	assert_false(_driver.may_hit(), "no telegraph ran")


func test_a_fresh_driver_cannot_hit() -> void:
	assert_eq(_driver.phase(), AttackDriver.Phase.DONE)
	assert_false(_driver.may_hit())


func test_stop_disarms_a_running_attack() -> void:
	_driver.start(_pattern)
	_driver.advance(WINDUP * 0.5)
	_driver.stop()
	assert_false(_driver.may_hit())
	assert_eq(_driver.telegraph_progress(), -1.0, "the telegraph is cleared")
	assert_eq(_driver.advance(10.0), AttackDriver.Phase.DONE, "a stopped driver never resumes")


func test_a_reused_driver_starts_clean() -> void:
	_driver.start(_pattern)
	_driver.advance(WINDUP)
	_driver.advance(ACTIVE + RECOVERY)
	_driver.start(_pattern)
	assert_eq(_driver.phase(), AttackDriver.Phase.WINDUP)
	assert_false(_driver.may_hit(), "the last attack's gate does not carry over")
	assert_almost_eq(_driver.telegraph_progress(), 0.0, 0.0001, "the fill starts over")


func test_a_driver_with_no_pattern_cannot_hit_or_advance() -> void:
	assert_eq(_driver.advance(1.0), AttackDriver.Phase.DONE)
	assert_false(_driver.may_hit())
	_driver.start(null)
	assert_eq(_driver.phase(), AttackDriver.Phase.DONE, "a null pattern is a stopped driver")


# --- the enemy state runs on this driver -----------------------------------------------


func _enemy() -> Enemy:
	var enemy: Enemy = (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	enemy.setup(&"hollow_miner")
	add_child_autofree(enemy)
	return enemy


## Steps the enemy and its state machine `seconds` of game time.
func _step(enemy: Enemy, seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.0:
		var dt: float = minf(FRAME, remaining)
		enemy._physics_process(dt)
		enemy.machine.physics_update(dt)
		remaining -= dt


func test_the_enemy_attack_state_arms_nothing_until_the_windup_ends() -> void:
	var enemy: Enemy = _enemy()
	var miner_windup: float = enemy.data.attacks[0].windup_seconds
	enemy.next_attack = enemy.data.attacks[0]
	enemy.machine.change_to(&"Attack")
	assert_false(enemy.hitbox.active, "entering the attack never arms the hitbox")
	assert_almost_eq(enemy.telegraph_progress, 0.0, 0.0001, "the telegraph starts empty")
	_step(enemy, miner_windup * 0.5)
	assert_almost_eq(enemy.telegraph_progress, 0.5, 0.02, "the fill tracks the driver's clock")
	assert_false(enemy.hitbox.active, "still nothing during the windup")
	_step(enemy, miner_windup * 0.5 + 2.0 * FRAME)
	assert_true(enemy.hitbox.active, "armed the frame the active window opens")
	assert_eq(enemy.telegraph_progress, -1.0, "the telegraph hides at the hit")
	_step(enemy, enemy.data.attacks[0].active_seconds + FRAME)
	assert_false(enemy.hitbox.active, "disarmed the frame recovery begins")
