extends GutTest
## Unit checks for ClassSkill (SPEC-classes-characters "class skill on Shift"): the
## skill has its own cooldown, a use starts it and performs once, a refused use
## performs nothing, and the cooldown runs in TimeManager-scaled time. Owned by
## classes-characters. Sync: host-authoritative; ClassController refuses a client
## request before the skill is asked. The TimeManager source is cleared after each
## test.

const TIME_SOURCE: StringName = &"test_class_skill_slow"
const COOLDOWN: float = 6.0

var _skill: FixtureClassSkill


func before_each() -> void:
	_skill = FixtureClassSkill.new()
	_skill.cooldown_seconds = COOLDOWN
	add_child_autofree(_skill)


func after_each() -> void:
	TimeManager.clear_source(TIME_SOURCE)


func test_a_new_skill_is_ready_with_no_cooldown() -> void:
	assert_true(_skill.is_ready())
	assert_eq(_skill.cooldown_left(), 0.0)


func test_a_use_performs_once_and_starts_the_cooldown() -> void:
	assert_true(_skill.use())
	assert_eq(_skill.performs, 1)
	assert_false(_skill.is_ready())
	assert_eq(_skill.cooldown_left(), COOLDOWN)


func test_a_use_while_cooling_is_refused_and_performs_nothing() -> void:
	_skill.use()
	assert_false(_skill.use())
	assert_eq(_skill.performs, 1, "a refused use performs nothing")
	assert_eq(_skill.cooldown_left(), COOLDOWN, "a refused use does not restart the cooldown")


func test_tick_counts_the_cooldown_down_and_stops_at_zero() -> void:
	_skill.use()
	_skill.tick(COOLDOWN / 2.0)
	assert_almost_eq(_skill.cooldown_left(), COOLDOWN / 2.0, 0.0001)
	assert_false(_skill.is_ready())
	_skill.tick(COOLDOWN)
	assert_eq(_skill.cooldown_left(), 0.0, "the cooldown stops at zero, never below")
	assert_true(_skill.is_ready(), "the skill is ready on the tick that ends the cooldown")


func test_a_zero_or_negative_cooldown_skill_is_ready_again_at_once() -> void:
	_skill.cooldown_seconds = 0.0
	assert_true(_skill.use())
	assert_true(_skill.is_ready())
	assert_true(_skill.use())
	_skill.cooldown_seconds = -1.0
	assert_true(_skill.use(), "a negative cooldown is read as none")
	assert_eq(_skill.cooldown_left(), 0.0)
	assert_eq(_skill.performs, 3)


func test_the_cooldown_runs_in_time_manager_scaled_time() -> void:
	TimeManager.set_entity_scale(_skill, 0.5, 10.0, TIME_SOURCE)
	_skill.use()
	_skill.tick(2.0)
	assert_almost_eq(_skill.cooldown_left(), COOLDOWN - 1.0, 0.0001,
		"at half speed, 2 s of real time is 1 s of cooldown")
