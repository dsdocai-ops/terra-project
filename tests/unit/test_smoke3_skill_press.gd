extends GutTest
## Tests for the smoke step-3 client skill-press rule (main.gd
## smoke3_skill_press_due): the press is sent only when every term holds, each
## term on its own. The rule is pure so each term can be removed and seen to
## fail (LESSONS 2). Owned by the foundation lane; the smoke driver lives in
## scenes/main/main.gd and only tools/smoke_two.sh drives it end to end.

const MAIN_SCRIPT := preload("res://scenes/main/main.gd")


func _due(armed: bool = true, is_host_peer: bool = false, active: bool = true, window_open: bool = true, legal: bool = true, already_pressed: bool = false) -> bool:
	return MAIN_SCRIPT.smoke3_skill_press_due(armed, is_host_peer, active, window_open, legal, already_pressed)


func test_the_press_is_due_when_every_term_holds() -> void:
	assert_true(_due(), "armed client in a live session, window open, legal, not yet pressed")


func test_an_unarmed_run_never_presses() -> void:
	assert_false(_due(false), "normal play has no smoke driver armed, so a dodge never auto-presses the skill")


func test_the_host_never_presses_the_client_skill() -> void:
	assert_false(_due(true, true), "the host applies the client's press, it does not send one")


func test_no_press_outside_a_live_session() -> void:
	assert_false(_due(true, false, false), "no session, no press")


func test_no_press_without_the_host_window() -> void:
	assert_false(_due(true, false, true, false), "the press needs the perfect-dodge window")


func test_no_press_before_the_attack_may_start() -> void:
	assert_false(_due(true, false, true, true, false), "a press during the heavy recovery is buffered and can miss the window")


func test_no_second_press_once_sent() -> void:
	assert_false(_due(true, false, true, true, true, true), "one press per run")
