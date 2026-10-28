extends GutTest
## Tests for `scripts/player/revive_hold.gd` — the local hold-F revive driver
## (W3-A5, G13b2a) — and for the downed player's Interactable that the hold
## runs through (wiring in `scenes/player/player.gd`). Owned by
## player-controller.
##
## The whole driver is driven by calling its hold methods with plain bools —
## no input event anywhere in this file (the input half is G13b2b's): `held`
## is the state the reviver's machine reads off the `interact` action, and
## manual `downed_clock.tick` calls stand in for the host's `Player.tick_downed`
## banking. The spec numbers (SPEC-player-controller "Downed and revive"):
## teammates hold interact within 48 px for 3 s to revive to 40% HP, scaled by
## the reviver's revive_speed_mult.
##
## after_each ends any live run so no autoload state leaks into the next file.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

## Physics frames to let a freshly attached Area2D register in the space.
const REGISTRATION_FRAMES: int = 2


class CompletedRecorder:
	## Named-method receiver for the driver's `completed` signal (a lambda
	## connect never fires in GUT).
	var revived: Array[Player] = []
	var by: Array[Player] = []

	func record(stood_up: Player, holder: Player) -> void:
		revived.append(stood_up)
		by.append(holder)


var _recorder := CompletedRecorder.new()
var _scene: PackedScene

# The bare-driver fixtures, (re)built by `_pair` and freed with the test.
var _reviver: Player = null
var _target: Player = null
var _hold: ReviveHold = null


func before_each() -> void:
	_scene = load(PLAYER_SCENE) as PackedScene
	GameState.run = null


func after_each() -> void:
	if GameState.run != null and NetworkManager.is_host:
		GameState.end_run(RunEndReason.Reason.ABORT)
	GameState.run = null
	_recorder.revived.clear()
	_recorder.by.clear()


## A player that is not in the tree: every driver rule reads flags and
## positions, so the hold can be driven with no scene at all.
func _bare_player(peer_id: int = 0) -> Player:
	var player: Player = Player.new()
	player.peer_id = peer_id
	autofree(player)
	return player


## Builds a bound pair: a standing reviver and a downed teammate, out of the
## tree, `distance` px apart, the reviver at `mult` speed.
func _pair(distance: float = 0.0, mult: float = 1.0) -> ReviveHold:
	_reviver = _bare_player(1)
	_target = _bare_player(2)
	_reviver.revive_speed_mult = mult
	_reviver.position = Vector2(distance, 0.0)
	_target.is_downed = true
	_hold = ReviveHold.new()
	autofree(_hold)
	_hold.bind(_reviver, _target)
	return _hold


# --- the numbers ------------------------------------------------------------


func test_the_revive_range_is_the_specs_48_px() -> void:
	assert_eq(ReviveHold.REVIVE_RANGE, 48.0, "SPEC: 'hold interact within 48 px'")
	assert_eq(ReviveHold.REVIVE_RANGE, NetworkManager.REVIVE_RANGE,
		"the driver's reach and the host's revive rule cannot drift apart")


func test_the_hold_driver_never_touches_engine_time_scale() -> void:
	# The project rule: never Engine.time_scale. The driver takes the held
	# state and reads the clock; a TimeManager slow is nobody's business here.
	var file := FileAccess.open("res://scripts/player/revive_hold.gd", FileAccess.READ)
	assert_not_null(file, "the driver source is readable")
	if file == null:
		return
	var source := file.get_as_text()
	assert_eq(source.find("Engine.time_scale"), -1, "no Engine.time_scale in the driver")


# --- is_revivable ------------------------------------------------------------


func test_revivable_means_downed_and_not_dead() -> void:
	var target := _bare_player()
	assert_false(ReviveHold.is_revivable(target), "a standing teammate has nothing to revive")
	target.is_downed = true
	assert_true(ReviveHold.is_revivable(target), "a downed teammate is revivable")
	target.is_dead = true
	assert_false(ReviveHold.is_revivable(target),
		"a teammate that bled out is Dead for the rest of the floor")
	assert_false(ReviveHold.is_revivable(null))


# --- bind --------------------------------------------------------------------


func test_bind_takes_a_standing_reviver_and_a_downed_teammate() -> void:
	var hold := _pair()
	assert_true(_hold.is_bound(), "a valid pair binds")
	assert_eq(_hold.reviver, _reviver)
	assert_eq(_hold.target, _target)
	assert_true(hold.is_bound(), "the fixture itself binds")


func test_bind_refuses_a_player_reviving_itself() -> void:
	var alone := _bare_player(1)
	alone.is_downed = true
	var hold := ReviveHold.new()
	autofree(hold)
	assert_false(hold.bind(alone, alone), "SPEC: 'Teammates hold interact' — not the player itself")
	assert_false(hold.is_bound())


func test_bind_refuses_a_downed_or_dead_reviver() -> void:
	var hold := _pair()
	_reviver.is_downed = true
	assert_false(hold.bind(_reviver, _target), "a downed player cannot revive")
	_reviver.is_downed = false
	_reviver.is_dead = true
	assert_false(hold.bind(_reviver, _target), "nor can a dead one")
	assert_false(hold.is_bound())


func test_bind_refuses_a_target_that_cannot_be_revived_and_drops_the_old_pair() -> void:
	var hold := _pair()
	var standing := _bare_player(3)
	assert_false(hold.bind(_reviver, standing), "a standing teammate has nothing to revive")
	assert_false(hold.is_bound(), "the refusal drops the pair rather than half-binding")
	standing.is_downed = true
	standing.is_dead = true
	assert_false(hold.bind(_reviver, standing), "a dead teammate is not revivable this floor")
	assert_false(hold.is_bound())


# --- in_range ----------------------------------------------------------------


func test_in_range_reads_the_revive_range_at_both_edges() -> void:
	_pair(ReviveHold.REVIVE_RANGE)
	assert_true(_hold.in_range(), "exactly at the 48 px is inside it")
	_pair(ReviveHold.REVIVE_RANGE + 0.1)
	assert_false(_hold.in_range(), "a step past it is out")


func test_in_range_measures_global_positions_like_the_query_does() -> void:
	# `find_target`'s physics query filters on global positions — the space
	# knows no parents — so `in_range` reads the same measure. Here the pair is
	# exactly 48 px apart in the world but 148 px apart in local coordinates,
	# because the two players sit under parents at different origins.
	var reviver: Player = _scene.instantiate() as Player
	var reviver_parent := Node2D.new()
	reviver_parent.position = Vector2(100.0, 0.0)
	add_child_autofree(reviver_parent)
	reviver_parent.add_child(reviver)
	autofree(reviver)
	reviver.peer_id = 0
	reviver.position = Vector2.ZERO
	var target: Player = _scene.instantiate() as Player
	add_child_autofree(target)
	target.peer_id = 0
	target.position = Vector2(100.0 + ReviveHold.REVIVE_RANGE, 0.0)
	target.is_downed = true
	var hold := ReviveHold.new()
	autofree(hold)
	assert_true(hold.bind(reviver, target), "a valid pair binds")
	assert_almost_eq(reviver.global_position.distance_to(target.global_position),
		ReviveHold.REVIVE_RANGE, 0.001, "the world distance is the 48 px")
	assert_true(hold.in_range(),
		"in_range reads the world distance, like the query that found the target")


# --- start_hold and release_hold ----------------------------------------------


func test_start_hold_banks_on_the_targets_clock_at_the_revivers_speed() -> void:
	_pair()
	assert_true(_hold.start_hold(), "a bound, in-range pair starts a hold")
	assert_true(_target.downed_clock.holding(), "the hold runs on the teammate's clock")
	assert_eq(_target.downed_clock.hold_seconds, 3.0, "the base hold is the spec's 3 s")


func test_start_hold_scales_with_the_revivers_speed_multiplier() -> void:
	_pair(0.0, 2.0)
	assert_true(_hold.start_hold())
	assert_eq(_target.downed_clock.hold_seconds, 1.5,
		"Field Medic twice as fast is half the hold, on the teammate's clock")


func test_start_hold_refuses_an_out_of_range_or_running_hold() -> void:
	_pair(ReviveHold.REVIVE_RANGE + 1.0)
	assert_false(_hold.start_hold(), "out of range: no hold begins")
	assert_false(_target.downed_clock.holding())
	_pair()
	assert_true(_hold.start_hold())
	assert_false(_hold.start_hold(), "a hold already running is not begun again")
	assert_eq(_target.downed_clock.hold_seconds, 3.0, "and the running hold keeps its duration")


func test_a_broken_hold_banks_nothing() -> void:
	# The criterion: letting go before 3 s banks nothing.
	_pair()
	assert_true(_hold.start_hold())
	_target.downed_clock.tick(1.0)  # the host's tick, banking one second
	assert_almost_eq(_target.downed_clock.hold_progress(), 1.0 / 3.0, 0.0001)
	_hold.release_hold()
	assert_false(_target.downed_clock.holding(), "the hold is no longer running")
	assert_eq(_target.downed_clock.hold_progress(), 0.0,
		"a hold is a continuous hold: nothing banked")
	assert_true(_hold.start_hold(), "the reviver may try again")
	assert_eq(_target.downed_clock.hold_progress(), 0.0, "and the next attempt starts from zero")


func test_a_reviver_downed_mid_hold_abandons_and_banks_nothing_after() -> void:
	# The judge's case: the reviver takes the hit that downs them mid-hold.
	# Nothing steps the hold while they are down, but the host keeps ticking
	# the downed teammate's clock — and `tick` advances any running hold. The
	# abandon (what `Player._tick_combat_timers` calls) must break the hold,
	# or the banked time completes the revive when the reviver stands up.
	_pair()
	_hold.completed.connect(_recorder.record)
	assert_true(_hold.start_hold())
	_target.downed_clock.tick(1.0)
	_reviver.is_downed = true
	_hold.abandon()
	_target.downed_clock.tick(3.0)  # the host keeps ticking the teammate's clock
	assert_false(_target.downed_clock.holding(), "the hold broke with the reviver down")
	assert_eq(_target.downed_clock.hold_progress(), 0.0, "and banked nothing after")
	assert_false(_hold.is_bound(), "the pair dropped with the hold")
	assert_false(_hold.poll(), "the abandoned hold never completes")
	assert_true(_recorder.revived.is_empty(), "and emitted nothing")
	# Standing back up, a fresh attempt starts from zero.
	_reviver.is_downed = false
	assert_true(_hold.bind(_reviver, _target), "the reviver may bind again")
	assert_true(_hold.start_hold())
	assert_eq(_target.downed_clock.hold_progress(), 0.0, "the fresh hold starts from zero")


# --- poll: the completed hold --------------------------------------------------


func test_a_completed_hold_polls_true_once_and_names_both_players() -> void:
	_pair()
	_hold.completed.connect(_recorder.record)
	assert_true(_hold.start_hold())
	_target.downed_clock.tick(3.0)  # the host's tick banks the full hold
	assert_true(_hold.poll(), "the full hold polls true")
	assert_eq(_recorder.revived.size(), 1, "one hold, one emit")
	assert_eq(_recorder.revived[0], _target, "the emit names who was revived")
	assert_eq(_recorder.by[0], _reviver, "and who did the reviving")
	assert_false(_hold.poll(), "the same hold never polls true twice")
	assert_false(_target.downed_clock.holding(), "and the completed hold is dropped")


func test_a_completed_hold_is_the_revivers_scaled_time() -> void:
	_pair(0.0, 2.0)
	assert_true(_hold.start_hold())
	_target.downed_clock.tick(1.25)
	assert_false(_hold.poll(), "1.25 s of a 1.5 s hold")
	_target.downed_clock.tick(0.25)
	assert_true(_hold.poll(), "the scaled hold finishes in its own time")


# --- step: the per-frame driver, no input event --------------------------------


func _scene_pair(distance: float) -> Array[Player]:
	# The real scene in the tree, so the downed Interactable registers and the
	# query can find it. Neither player is local (peer id 0 against the
	# offline unique id), so nothing steps the hold behind the test's back.
	var reviver: Player = _scene.instantiate() as Player
	add_child_autofree(reviver)
	reviver.peer_id = 0
	var target: Player = _scene.instantiate() as Player
	add_child_autofree(target)
	target.peer_id = 0
	reviver.position = Vector2.ZERO
	target.position = Vector2(distance, 0.0)
	return [reviver, target] as Array[Player]


## Downs an in-tree player the way the Downed state's entry does. The flag
## setter alone is not the live entry: it starts no bleed-out, and the host's
## `tick_downed` — which runs every physics frame in here — counts an
## unstarted clock as expired and kills the player on the first frame.
func _down_in_tree(target: Player) -> void:
	target.is_downed = true
	target.downed_clock.start_bleed_out()


func test_step_with_held_binds_through_the_interactable_and_starts_the_hold() -> void:
	var pair := _scene_pair(45.0)
	var reviver := pair[0]
	var target := pair[1]
	_down_in_tree(target)
	await wait_physics_frames(REGISTRATION_FRAMES)
	assert_false(reviver.revive_hold.step(reviver, true),
		"a fresh hold is not complete, so the first step reports false")
	assert_true(target.downed_clock.holding(), "held: the hold banks on the teammate's clock")
	assert_eq(target.downed_clock.hold_banked, 0.0,
		"the driver never ticks the clock — the host's tick does")


func test_step_letting_go_banks_nothing_and_unbinds() -> void:
	var pair := _scene_pair(45.0)
	var reviver := pair[0]
	var target := pair[1]
	_down_in_tree(target)
	await wait_physics_frames(REGISTRATION_FRAMES)
	reviver.revive_hold.step(reviver, true)
	target.downed_clock.tick(1.0)
	reviver.revive_hold.step(reviver, false)
	assert_false(target.downed_clock.holding(), "let go: the hold broke")
	assert_eq(target.downed_clock.hold_progress(), 0.0, "nothing banked")
	assert_false(reviver.revive_hold.is_bound(), "and the pair is dropped")
	reviver.revive_hold.step(reviver, true)
	assert_eq(target.downed_clock.hold_progress(), 0.0, "a new hold starts from zero")


func test_a_local_reviver_downed_mid_hold_breaks_the_hold_on_the_live_tick() -> void:
	# The wiring half of the abandon, through the caller the game uses: the
	# player's `_tick_combat_timers`, which the reviver's `_physics_process`
	# steps. The reviver is the local player here; a downed reviver must reach
	# the abandon branch, not skip the hold until standing up.
	var pair := _scene_pair(45.0)
	var reviver := pair[0]
	var target := pair[1]
	reviver.peer_id = multiplayer.get_unique_id()
	_down_in_tree(target)
	await wait_physics_frames(REGISTRATION_FRAMES)
	assert_false(reviver.revive_hold.step(reviver, true),
		"a fresh hold is not complete, so the first step reports false")
	assert_true(target.downed_clock.holding(), "but the hold runs on the teammate's clock")
	target.downed_clock.tick(1.0)
	# The reviver takes the hit that downs them, mid-hold: the bleed-out entry
	# the Downed state's `_down_in_tree` mirrors.
	reviver.is_downed = true
	reviver.downed_clock.start_bleed_out()
	reviver._tick_combat_timers(1.0 / 60.0)
	assert_false(target.downed_clock.holding(), "the live tick abandoned the hold")
	assert_eq(target.downed_clock.hold_progress(), 0.0, "and banked nothing")
	assert_false(reviver.revive_hold.is_bound())
	# Standing back up: no completion on time nobody held, and a fresh
	# attempt starts from zero.
	reviver.is_downed = false
	reviver.downed_clock.stop_bleed_out()
	reviver.revive_hold.step(reviver, true)
	assert_eq(target.downed_clock.hold_progress(), 0.0, "the fresh attempt starts from zero")


func test_step_walk_out_breaks_the_hold_and_the_pair_stays_bound() -> void:
	var pair := _scene_pair(45.0)
	var reviver := pair[0]
	var target := pair[1]
	_down_in_tree(target)
	await wait_physics_frames(REGISTRATION_FRAMES)
	reviver.revive_hold.step(reviver, true)
	target.downed_clock.tick(1.0)
	# The teammate stands at 45 px: a step to 94 px is 49 px away, past the reach.
	reviver.position = Vector2(45.0 + ReviveHold.REVIVE_RANGE + 1.0, 0.0)
	reviver.revive_hold.step(reviver, true)
	assert_false(target.downed_clock.holding(), "out of range: the hold broke, nothing banked")
	assert_eq(target.downed_clock.hold_progress(), 0.0)
	assert_true(reviver.revive_hold.is_bound(), "the pair stays bound so stepping back in resumes")
	reviver.position = Vector2(25.0, 0.0)
	reviver.revive_hold.step(reviver, true)
	assert_true(target.downed_clock.holding(), "back in range: the attempt runs again, from zero")
	assert_eq(target.downed_clock.hold_progress(), 0.0)


func test_step_completes_once_when_the_full_hold_banks() -> void:
	var pair := _scene_pair(45.0)
	var reviver := pair[0]
	var target := pair[1]
	_down_in_tree(target)
	await wait_physics_frames(REGISTRATION_FRAMES)
	reviver.revive_hold.completed.connect(_recorder.record)
	reviver.revive_hold.step(reviver, true)
	target.downed_clock.tick(3.0)
	assert_true(reviver.revive_hold.step(reviver, true),
		"the banked hold completes on the next step")
	assert_eq(_recorder.revived.size(), 1, "one emit, naming both players")
	assert_eq(_recorder.revived[0], target)
	assert_eq(_recorder.by[0], reviver)
	assert_false(reviver.revive_hold.is_bound(), "the driver drops the completed pair")


func test_step_drops_a_target_that_is_no_longer_revivable() -> void:
	var pair := _scene_pair(45.0)
	var reviver := pair[0]
	var target := pair[1]
	_down_in_tree(target)
	await wait_physics_frames(REGISTRATION_FRAMES)
	reviver.revive_hold.step(reviver, true)
	# The bleed-out ran out on the host: dead for the floor, no longer revivable.
	target.is_downed = false
	target.is_dead = true
	reviver.revive_hold.step(reviver, true)
	assert_false(target.downed_clock.holding(), "the hold on a dead teammate broke")
	assert_false(reviver.revive_hold.is_bound())


# --- the downed player's Interactable (the player.gd wiring) --------------------


func _downed_interactable_of(player: Player) -> Interactable:
	for child: Node in player.get_children():
		if child is Interactable:
			return child
	return null


func test_a_downed_player_carries_a_revive_interactable() -> void:
	var target: Player = _scene.instantiate() as Player
	add_child_autofree(target)
	assert_null(_downed_interactable_of(target), "a standing player offers nothing")
	target.is_downed = true
	var component := _downed_interactable_of(target)
	assert_not_null(component, "downed: the player carries the revive offer")
	assert_eq(component.prompt_text, ReviveHold.PROMPT_TEXT, "the prompt reads 'Revive'")
	assert_eq(component.hold_seconds, DownedClock.REVIVE_HOLD_SECONDS, "the base 3 s offer")
	assert_eq(component.collision_layer, Interactable.INTERACTABLE_LAYER,
		"the component registered itself on layer 6")


func test_the_downed_interactable_is_reachable_through_the_nearest_query_at_48() -> void:
	var pair := _scene_pair(45.0)
	var reviver := pair[0]
	var target := pair[1]
	_down_in_tree(target)
	await wait_physics_frames(REGISTRATION_FRAMES)
	var component := _downed_interactable_of(target)
	assert_not_null(component)
	assert_eq(Interactable.nearest(reviver, reviver.global_position), null,
		"the default 40 px press radius does not reach it")
	assert_eq(Interactable.nearest(reviver, reviver.global_position, ReviveHold.REVIVE_RANGE),
		component, "the revive reach does")
	assert_eq(ReviveHold.find_target(reviver), target,
		"and the hold's own query resolves the downed teammate through it")


func test_find_target_skips_a_duck_typed_interactable_in_front() -> void:
	# The single-nearest limitation, pinned as v1 behaviour: the query returns
	# the one closest usable area, so a chest standing between the reviver and
	# the teammate wins the scan and the hold finds no target. The lane-B
	# prompt has the same shape.
	var pair := _scene_pair(45.0)
	var reviver := pair[0]
	var target := pair[1]
	_down_in_tree(target)
	var chest: Area2D = InteractableStub.new()
	chest.set(&"prompt_text", "Open")
	chest.collision_layer = Interactable.INTERACTABLE_LAYER
	chest.position = Vector2(10.0, 0.0)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	chest.add_child(shape)
	add_child_autofree(chest)
	await wait_physics_frames(REGISTRATION_FRAMES)
	assert_eq(Interactable.nearest(reviver, reviver.global_position, ReviveHold.REVIVE_RANGE),
		chest, "the chest stands in front and wins the query as the nearest area")
	assert_eq(ReviveHold.find_target(reviver), null,
		"and still resolves to no Player: the hold skips it, no hold")


func test_find_target_ignores_a_teammate_who_is_not_down() -> void:
	var pair := _scene_pair(45.0)
	var reviver := pair[0]
	await wait_physics_frames(REGISTRATION_FRAMES)
	assert_null(_downed_interactable_of(pair[1]), "a standing teammate carries no offer")
	assert_eq(ReviveHold.find_target(reviver), null, "so the query has nothing to resolve")


func test_standing_back_up_drops_the_interactable() -> void:
	var target: Player = _scene.instantiate() as Player
	add_child_autofree(target)
	target.is_downed = true
	var component := _downed_interactable_of(target)
	assert_not_null(component)
	target.is_downed = false
	await wait_physics_frames(REGISTRATION_FRAMES)
	assert_false(is_instance_valid(component), "the offer is freed when the player stands")
	assert_null(_downed_interactable_of(target))


func test_dying_drops_the_interactable() -> void:
	# The bleed-out path: dying clears is_downed before is_dead, so a dead
	# teammate carries no offer either.
	var target: Player = _scene.instantiate() as Player
	add_child_autofree(target)
	target.is_downed = true
	target.is_downed = false
	target.is_dead = true
	await wait_physics_frames(REGISTRATION_FRAMES)
	assert_null(_downed_interactable_of(target), "Dead is Dead for the floor: no offer")


# --- the live prompt's reach (lane B's InteractPrompt, read through, not edited)
# The downed Interactable sits on layer 6, the one layer both the hold's query
# and `scenes/ui/interact_prompt.gd` scan — the component cannot be visible to
# one and hidden from the other. So the prompt offers the revive at its own
# 56 px REACH, the press edge on that offer does nothing (a hold needs the
# held state, which the press cannot carry), and a farther interactable is
# hidden behind the downed body while it is nearer. These tests pin that live
# overlap as it stands; deciding what the prompt should do about it is the
# lane-B decision recorded as BLOCKED-ASK in the run log.


func test_the_prompts_56_px_reach_offers_a_teammate_the_holds_48_cannot() -> void:
	# 52 px is inside the prompt's REACH and outside the hold's REVIVE_RANGE:
	# the band where the prompt shows "[F] Revive" and the hold cannot yet run.
	var pair := _scene_pair(52.0)
	var reviver := pair[0]
	var target := pair[1]
	_down_in_tree(target)
	await wait_physics_frames(REGISTRATION_FRAMES)
	var component := _downed_interactable_of(target)
	assert_not_null(component)
	assert_eq(InteractPrompt.nearest(reviver, reviver.global_position), component,
		"the prompt's own query offers the downed teammate at 52 px")
	assert_eq(ReviveHold.find_target(reviver), null,
		"while the hold's 48 px reach cannot run on the same offer")


func test_the_prompt_press_on_the_revive_offer_does_nothing_yet() -> void:
	# The prompt's press path is `_target.call(&"interact", player)` on the
	# press edge. The base component's `interact` only emits `interacted`, and
	# nothing is connected — so the press is a no-op: the teammate stays down
	# with an untouched clock. (The revive runs on the held action, G13b2b's
	# routing; the press handling is the lane-B decision.)
	var pair := _scene_pair(45.0)
	var reviver := pair[0]
	var target := pair[1]
	_down_in_tree(target)
	await wait_physics_frames(REGISTRATION_FRAMES)
	var component := _downed_interactable_of(target)
	assert_not_null(component)
	component.interact(reviver)
	assert_true(target.is_downed, "the press stood nobody up")
	assert_false(target.downed_clock.holding(), "and started no hold")
	assert_eq(target.downed_clock.hold_banked, 0.0, "and banked nothing")


func test_the_downed_body_hides_a_farther_interactable_from_the_prompt() -> void:
	# The prompt takes the single nearest usable area: with the downed body at
	# 25 px and a chest at 50 px, both inside the 56 px REACH, the chest is
	# not what the prompt offers. Pinned as live behaviour for the lane-B
	# decision; the hold's own duck-typed-in-front shape is the mirror case.
	var pair := _scene_pair(25.0)
	var reviver := pair[0]
	var target := pair[1]
	_down_in_tree(target)
	var chest: Area2D = InteractableStub.new()
	chest.set(&"prompt_text", "Open")
	chest.collision_layer = Interactable.INTERACTABLE_LAYER
	chest.position = Vector2(50.0, 0.0)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	chest.add_child(shape)
	add_child_autofree(chest)
	await wait_physics_frames(REGISTRATION_FRAMES)
	assert_eq(InteractPrompt.nearest(reviver, reviver.global_position),
		_downed_interactable_of(target),
		"the prompt offers the downed body, not the chest behind it")
