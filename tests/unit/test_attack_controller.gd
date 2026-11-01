extends GutTest
## Tests for the attack input layer (SPEC-combat-core "Attack input layer",
## combat v2 C3): the one-slot input buffer, cancel windows, the combo reset
## timer, the HeavyCharge state with its charge tiers and perfect release, and a
## heavy that is released while busy. Owned by combat-core. Steps the player's
## state machine, the buffer and the weapon controller by hand so the physics
## server never runs between asserts.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FRAME := 1.0 / 60.0

var _player: Player
var _controller: AttackController
var _weapons: WeaponController
var _released: Array[float] = []
var _swapped: Array[int] = []


func before_each() -> void:
	# The player sits under a world node the test frees. A swing spawns ground
	# crack lines under the player's parent, and they free themselves only after
	# a fade the tests never run, so they must be freed with the world.
	var world := Node2D.new()
	add_child_autofree(world)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	world.add_child(_player)
	_player.position = Vector2.ZERO
	_controller = _player.get_node("AttackController") as AttackController
	_weapons = _player.get_node("WeaponController") as WeaponController
	_released.clear()
	_swapped.clear()
	Events.heavy_attack_released.connect(_on_heavy_released)


func after_each() -> void:
	if Events.heavy_attack_released.is_connected(_on_heavy_released):
		Events.heavy_attack_released.disconnect(_on_heavy_released)


func _on_heavy_released(_who: Player, charge: float) -> void:
	_released.append(charge)


## Advances the buffer, the state machine, the weapon timers and the player's
## combat timers by `seconds` of game time.
func _tick(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.0:
		var dt: float = minf(FRAME, remaining)
		_controller.tick_buffer(dt)
		_player.state_machine.physics_update(dt)
		_weapons._physics_process(dt)
		_player._tick_combat_timers(dt)
		remaining -= dt


## An attack with a long recovery so the cancel windows are far apart: active
## ends at 0.15 s, the combo cancel opens at 0.55 s, the attack ends at 1.15 s.
func _long_spec(combo_cancel: float = 0.4, dodge_cancel: float = 0.0) -> AttackSpec:
	var spec := AttackSpec.new()
	spec.windup_seconds = 0.05
	spec.active_seconds = 0.1
	spec.recovery_seconds = 1.0
	spec.combo_cancel_at = combo_cancel
	spec.dodge_cancel_at = dodge_cancel
	return spec


func _start_attack(spec: AttackSpec) -> void:
	_player.pending_attack = {"spec": spec, "dir": Vector2.RIGHT, "charge": 0.0, "heavy": false}
	_player.state_machine.change_to(&"Attack")


func _attack_state() -> PlayerAttackState:
	return _player.state_machine.current as PlayerAttackState


func _charge_state() -> PlayerHeavyChargeState:
	return _player.state_machine.current as PlayerHeavyChargeState


func _state() -> StringName:
	return _player.state_machine.current_name()


# --- data -------------------------------------------------------------------------

func test_cancel_windows_default_to_the_spec_values() -> void:
	var spec := AttackSpec.new()
	assert_eq(spec.combo_cancel_at, 0.4, "combo cancel at 40% of recovery")
	assert_eq(spec.dodge_cancel_at, 0.0, "dodge cancel at the end of active")
	assert_almost_eq(spec.dodge_cancel_seconds(), spec.windup_seconds + spec.active_seconds, 0.0001)
	assert_almost_eq(spec.combo_cancel_seconds(), spec.windup_seconds + spec.active_seconds + 0.4 * spec.recovery_seconds, 0.0001)


func test_weapons_carry_the_charge_move_factor() -> void:
	assert_eq((load("res://data/weapons/pickaxe.tres") as WeaponData).charge_move_factor, 0.3)
	assert_eq((load("res://data/weapons/crossbow.tres") as WeaponData).charge_move_factor, 0.3)


# --- the buffer ---------------------------------------------------------------------

func test_the_buffer_keeps_only_the_last_press() -> void:
	_start_attack(_long_spec())
	_controller.apply(AttackController.Kind.LIGHT, Vector2.RIGHT, 0.0)
	assert_eq(_controller.buffered_kind(), AttackController.Kind.LIGHT)
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	assert_eq(_controller.buffered_kind(), AttackController.Kind.HEAVY_PRESS, "the later press replaced it")
	_controller.apply(AttackController.Kind.DODGE, Vector2.RIGHT, 0.0)
	assert_eq(_controller.buffered_kind(), AttackController.Kind.DODGE, "and again")


func test_a_buffered_press_expires_after_two_tenths_of_a_second() -> void:
	_start_attack(_long_spec())
	var step_before: int = _weapons.combo_step
	_controller.apply(AttackController.Kind.LIGHT, Vector2.RIGHT, 0.0)
	_tick(0.3)
	assert_eq(_controller.buffered_kind(), -1, "gone")
	assert_eq(_weapons.combo_step, step_before, "and it never fired")
	assert_eq(_state(), &"Attack")


func test_a_buffered_light_fires_at_the_combo_cancel_frame() -> void:
	_start_attack(_long_spec())
	_tick(0.4)
	var step_before: int = _weapons.combo_step
	_controller.apply(AttackController.Kind.LIGHT, Vector2.RIGHT, 0.0)
	_tick(0.1)
	assert_eq(_weapons.combo_step, step_before, "still before the window at 0.5 s")
	_tick(0.07)
	assert_eq(_weapons.combo_step, (step_before + 1) % 3, "fired once the window opened")
	assert_eq(_controller.buffered_kind(), -1, "and the buffer emptied")
	assert_lt(_attack_state().elapsed(), 0.1, "the next step started fresh, skipping the rest of recovery")


func test_a_buffered_heavy_press_enters_the_charge_at_the_combo_cancel_frame() -> void:
	_start_attack(_long_spec())
	_tick(0.4)
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	_tick(0.1)
	assert_eq(_state(), &"Attack", "not yet legal")
	_tick(0.07)
	assert_eq(_state(), &"HeavyCharge")
	assert_gt(_charge_state().held(), 0.1, "the time spent buffered counts toward the charge")


func test_a_buffered_dodge_fires_at_the_dodge_cancel_frame() -> void:
	_start_attack(_long_spec())
	_tick(0.02)
	_controller.apply(AttackController.Kind.DODGE, Vector2.RIGHT, 0.0)
	assert_eq(_state(), &"Attack", "in windup a dodge waits")
	_tick(0.1)
	assert_eq(_state(), &"Attack", "and through the active window")
	_tick(0.06)
	assert_eq(_state(), &"Dodge", "legal from the end of active")


func test_a_press_from_idle_runs_at_once() -> void:
	_controller.apply(AttackController.Kind.LIGHT, Vector2.RIGHT, 0.0)
	assert_eq(_state(), &"Attack")
	assert_eq(_controller.buffered_kind(), -1, "nothing buffered")


func test_can_start_attack_is_true_only_on_a_legal_frame() -> void:
	assert_true(_controller.can_start_attack(), "idle may start an attack")
	_start_attack(_long_spec())
	_tick(0.1)
	assert_false(_controller.can_start_attack(), "mid-swing, the combo has not opened")
	_tick(0.5)
	assert_true(_controller.can_start_attack(), "at the combo cancel the next attack may start")


# --- cancel windows -------------------------------------------------------------------

func test_the_attack_reports_its_cancel_windows() -> void:
	_start_attack(_long_spec())
	_tick(0.1)
	assert_false(_attack_state().can_dodge_cancel(), "still in the active window")
	assert_false(_attack_state().can_combo_cancel())
	_tick(0.06)
	assert_true(_attack_state().can_dodge_cancel(), "dodge opens at the end of active")
	assert_false(_attack_state().can_combo_cancel())
	_tick(0.4)
	assert_true(_attack_state().can_combo_cancel(), "combo opens at 40% of recovery")


func test_a_later_dodge_cancel_keeps_the_dodge_waiting() -> void:
	_start_attack(_long_spec(0.4, 0.5))
	_tick(0.4)
	assert_false(_attack_state().can_dodge_cancel(), "half of recovery has not passed")
	_tick(0.4)
	assert_true(_attack_state().can_dodge_cancel())


func test_cancelling_into_the_next_step_ends_the_swing() -> void:
	_start_attack(_long_spec())
	_tick(0.6)
	_controller.apply(AttackController.Kind.LIGHT, Vector2.RIGHT, 0.0)
	assert_eq(_state(), &"Attack", "restarted in place")
	assert_lt(_attack_state().elapsed(), 0.02)
	assert_false(_weapons._hitbox.active, "the old swing is not left live")


func test_a_light_press_before_the_window_does_not_start_anything() -> void:
	_start_attack(_long_spec())
	_tick(0.2)
	var step_before: int = _weapons.combo_step
	_controller.apply(AttackController.Kind.LIGHT, Vector2.RIGHT, 0.0)
	assert_eq(_weapons.combo_step, step_before, "the combo did not advance")
	assert_gt(_attack_state().elapsed(), 0.19, "the running attack was not restarted")


# --- the combo reset timer ----------------------------------------------------------------

func test_the_combo_timer_starts_when_the_attack_ends() -> void:
	_weapons.take_light()
	assert_eq(_weapons.combo_step, 1)
	_weapons._physics_process(5.0)
	assert_eq(_weapons.combo_step, 1, "pressing the button does not start the clock")
	_weapons.attack_finished()
	_weapons._physics_process(0.5)
	assert_eq(_weapons.combo_step, 1, "0.5 s after the attack ended")
	_weapons._physics_process(0.2)
	assert_eq(_weapons.combo_step, 0, "0.6 s after it ended the combo resets")


func test_a_slow_attack_does_not_drop_its_own_combo() -> void:
	var slow := _long_spec()
	slow.recovery_seconds = 2.0
	_weapons.take_light()
	_start_attack(slow)
	_tick(2.0)
	assert_eq(_state(), &"Attack", "setup: still attacking after 2 s")
	assert_eq(_weapons.combo_step, 1, "the combo survived a long attack")
	_tick(0.3)
	assert_eq(_state(), &"Idle", "the attack ended")
	_tick(0.3)
	assert_eq(_weapons.combo_step, 1, "and the 0.6 s clock only ran from the end")
	_tick(0.2)
	assert_eq(_weapons.combo_step, 0)


func test_the_timer_stops_again_when_the_next_step_starts() -> void:
	_start_attack(_long_spec())
	_tick(0.6)
	_controller.apply(AttackController.Kind.LIGHT, Vector2.RIGHT, 0.0)
	var step: int = _weapons.combo_step
	_tick(0.9)
	assert_eq(_weapons.combo_step, step, "no reset while the cancelled-into attack plays")


# --- charge tiers ------------------------------------------------------------------------------

func test_a_tap_releases_uncharged_and_a_hold_charges_linearly() -> void:
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	assert_eq(_state(), &"HeavyCharge")
	_tick(0.1)
	assert_eq(_charge_state().charge(), 0.0, "under 0.15 s is a tap")
	_tick(0.1)
	assert_almost_eq(_charge_state().charge(), 0.25, 0.03, "0.2 s of 0.8 s")
	_tick(0.2)
	assert_almost_eq(_charge_state().charge(), 0.5, 0.03, "0.4 s of 0.8 s")


func test_full_charge_flashes_the_ring_once() -> void:
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	var ring: ChargeRing = _player.get_node("ChargeRing") as ChargeRing
	_tick(0.5)
	assert_true(ring.visible, "the ring is up while charging")
	assert_almost_eq(ring.fill, 0.625, 0.03, "and it fills with the charge")
	assert_false(ring.is_flashing())
	_tick(0.35)
	assert_true(ring.is_flashing(), "flashes at full")
	assert_eq(ring.fill, 1.0)
	assert_true(_charge_state().is_full())


func test_the_ring_hides_when_the_charge_ends() -> void:
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	var ring: ChargeRing = _player.get_node("ChargeRing") as ChargeRing
	_tick(0.3)
	_controller.apply(AttackController.Kind.HEAVY, Vector2.RIGHT, 0.3)
	assert_false(ring.visible)


func test_a_release_just_after_full_charge_is_perfect() -> void:
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	_tick(0.79)
	assert_false(_charge_state().is_perfect(), "not full yet")
	_tick(0.04)
	assert_true(_charge_state().is_perfect(), "just past full")
	_tick(0.1)
	assert_true(_charge_state().is_perfect(), "still inside 0.15 s")
	_tick(0.1)
	assert_false(_charge_state().is_perfect(), "past the window")
	assert_eq(_charge_state().charge(), 1.0, "but the full charge is kept")


func test_a_perfect_release_adds_twenty_percent_damage_and_poise() -> void:
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	_tick(0.85)
	_controller.release_heavy()
	assert_eq(_state(), &"Attack", "the heavy fires")
	_tick(0.15)
	var perfect: HitInfo = _weapons._hitbox.template
	_tick(1.0)
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	_tick(1.1)
	_controller.release_heavy()
	_tick(0.15)
	var late: HitInfo = _weapons._hitbox.template
	assert_eq(late.poise_damage, 60.0, "a held-past-full heavy: 30 + 30 x 1.0")
	assert_almost_eq(perfect.base_damage, late.base_damage * 1.2, 0.01, "+20% damage")
	assert_almost_eq(perfect.poise_damage, late.poise_damage * 1.2, 0.01, "+20% poise damage")
	assert_true(perfect.tags.has(&"perfect_release"))
	assert_false(late.tags.has(&"perfect_release"))


func test_a_charged_heavy_scales_with_the_charge() -> void:
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	_tick(0.4)
	_controller.release_heavy()
	_tick(0.15)
	var half: HitInfo = _weapons._hitbox.template
	var heavy: AttackSpec = _weapons.take_heavy()
	assert_almost_eq(half.base_damage, heavy.base_damage * (1.0 + 0.5 * WeaponController.HEAVY_CHARGE_BONUS), 0.5)
	assert_almost_eq(half.poise_damage, heavy.poise_damage + 0.5 * WeaponController.HEAVY_POISE_CHARGE_BONUS, 1.0)


func test_a_tap_fires_an_uncharged_heavy() -> void:
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	_tick(0.08)
	_controller.release_heavy()
	assert_eq(_state(), &"Attack")
	assert_eq(_player.pending_attack["charge"], 0.0)
	assert_true(_player.pending_attack["heavy"])
	assert_eq(_released, [0.0] as Array[float], "heavy_attack_released fired once with charge 0")


func test_heavy_attack_released_carries_the_charge() -> void:
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	_tick(0.4)
	_controller.release_heavy()
	assert_eq(_released.size(), 1)
	assert_almost_eq(_released[0], 0.5, 0.03)


func test_charging_moves_at_the_charge_move_factor() -> void:
	_player.move_input = Vector2(1, 0)
	_player.state_machine.change_to(&"Move")
	_tick(0.5)
	var walking: float = _player.velocity.length()
	_player.velocity = Vector2.ZERO
	_player.state_machine.change_to(&"Idle")
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	_tick(0.5)
	assert_gt(walking, 0.0, "setup: the walk moved")
	assert_almost_eq(_player.velocity.length() / walking, 0.3, 0.03, "30% of walking speed")


# --- a heavy released while busy -------------------------------------------------------------------

func test_a_heavy_released_while_busy_is_buffered_not_dropped() -> void:
	_start_attack(_long_spec())
	_tick(0.4)
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	_tick(0.05)
	_controller.apply(AttackController.Kind.HEAVY, Vector2.RIGHT, 0.0)
	assert_eq(_state(), &"Attack", "released while busy: nothing yet")
	assert_eq(_controller.buffered_kind(), AttackController.Kind.HEAVY_PRESS, "but it is kept")
	assert_eq(_released.size(), 0)
	_tick(0.2)
	assert_eq(_state(), &"Attack", "now the heavy is the running attack")
	assert_true(_player.pending_attack["heavy"], "the cancelled-into attack is the heavy")
	assert_eq(_released.size(), 1, "and it released exactly once")
	assert_eq(_controller.buffered_kind(), -1)


func test_a_light_press_during_a_charge_is_not_legal() -> void:
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	_controller.apply(AttackController.Kind.LIGHT, Vector2.RIGHT, 0.0)
	assert_eq(_state(), &"HeavyCharge")
	assert_eq(_controller.buffered_kind(), AttackController.Kind.LIGHT)


func test_a_dodge_cancels_a_charge() -> void:
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	_tick(0.3)
	_controller.apply(AttackController.Kind.DODGE, Vector2.RIGHT, 0.0)
	assert_eq(_state(), &"Dodge")


func test_a_hit_interrupts_the_charge_and_the_release_is_dropped() -> void:
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	_tick(0.3)
	_player.apply_knockback(Vector2.ZERO, 0.3)
	assert_eq(_state(), &"HitStun")
	_controller.apply(AttackController.Kind.HEAVY, Vector2.RIGHT, 0.4)
	assert_eq(_state(), &"HitStun", "no heavy out of a stun")
	assert_eq(_released.size(), 0)


# --- host validation ----------------------------------------------------------------------------------

func test_the_host_clamps_a_reported_charge_to_what_it_saw() -> void:
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	_tick(0.2)
	var allowed: float = (0.2 + AttackController.CHARGE_SLACK_SECONDS) / 0.8
	assert_almost_eq(_controller.validated_charge(1.0), allowed, 0.03, "a client cannot claim a full charge after 0.2 s")
	assert_almost_eq(_controller.validated_charge(0.3), 0.3, 0.0001, "an honest value passes")
	assert_eq(_controller.validated_charge(7.0) <= 1.0, true, "never above 1")
	assert_eq(_controller.validated_charge(-1.0), 0.0, "never below 0")


# --- swap with lockout ------------------------------------------------------------------

func _on_weapon_changed(slot: int, _weapon: WeaponData) -> void:
	_swapped.append(slot)


func test_a_swap_changes_the_slot_and_resets_the_combo() -> void:
	_weapons.weapon_changed.connect(_on_weapon_changed)
	_weapons.take_light()
	assert_eq(_weapons.combo_step, 1, "setup: a light was taken")
	assert_true(_weapons.can_swap())
	assert_true(_weapons.swap())
	assert_eq(_weapons.active_slot, 1, "the other slot is live")
	assert_ne(_weapons.active_weapon(), _weapons.slots[0], "and it is the other weapon")
	assert_eq(_weapons.combo_step, 0, "a swap resets the combo")
	assert_eq(_swapped, [1] as Array[int], "weapon_changed fired once with the new slot")


func test_the_swap_lockout_blocks_a_second_swap_for_two_tenths_of_a_second() -> void:
	assert_true(_weapons.swap(), "the first swap goes through")
	var slot_after_first: int = _weapons.active_slot
	assert_false(_weapons.can_swap(), "the lockout is running")
	assert_false(_weapons.swap(), "a swap during the lockout does nothing")
	assert_eq(_weapons.active_slot, slot_after_first, "and the slot did not move")
	_tick(WeaponController.SWAP_LOCKOUT_SECONDS - 0.01)
	assert_false(_weapons.swap(), "still locked just inside the 0.2 s")
	assert_eq(_weapons.active_slot, slot_after_first)
	_tick(0.02)
	assert_true(_weapons.can_swap(), "open again at 0.2 s")
	assert_true(_weapons.swap(), "and the next swap goes through")
	assert_ne(_weapons.active_slot, slot_after_first)


func test_a_swap_press_during_the_lockout_is_swallowed_not_buffered() -> void:
	assert_true(_weapons.swap())
	_controller.apply(AttackController.Kind.SWAP, Vector2.RIGHT, 0.0)
	assert_false(_weapons.can_swap())
	assert_eq(_weapons.active_slot, 1, "the locked swap press did nothing")
	assert_eq(_controller.buffered_kind(), -1, "and a swap never waits in the buffer")
	_tick(WeaponController.SWAP_LOCKOUT_SECONDS + 0.01)
	_controller.apply(AttackController.Kind.SWAP, Vector2.RIGHT, 0.0)
	assert_eq(_weapons.active_slot, 0, "once the lockout is over the press swaps at once")


# --- weapon_1 / weapon_2 ----------------------------------------------------------------

func test_the_slot_keys_select_their_slot_through_the_same_lockout() -> void:
	_controller.apply(AttackController.Kind.WEAPON_2, Vector2.RIGHT, 0.0)
	assert_eq(_weapons.active_slot, 1, "weapon_2 equips the crossbow slot")
	assert_false(_weapons.can_swap(), "under the same 0.2 s lockout as a swap")
	_controller.apply(AttackController.Kind.WEAPON_1, Vector2.RIGHT, 0.0)
	assert_eq(_weapons.active_slot, 1, "weapon_1 during the lockout does nothing")
	_tick(WeaponController.SWAP_LOCKOUT_SECONDS + 0.01)
	_controller.apply(AttackController.Kind.WEAPON_1, Vector2.RIGHT, 0.0)
	assert_eq(_weapons.active_slot, 0, "and once it is over it selects at once")


func test_selecting_the_live_slot_is_a_no_op_that_burns_no_lockout() -> void:
	assert_true(_weapons.swap(), "to the crossbow")
	_tick(WeaponController.SWAP_LOCKOUT_SECONDS + 0.01)
	assert_false(_weapons.select_slot(1), "selecting the live slot does nothing")
	assert_eq(_weapons.active_slot, 1)
	_tick(WeaponController.SWAP_LOCKOUT_SECONDS - 0.01)
	assert_true(_weapons.select_slot(0), "and it did not restart the lockout: the swap still fits inside it")


func test_a_slot_key_press_is_never_buffered() -> void:
	_start_attack(_long_spec())
	_controller.apply(AttackController.Kind.WEAPON_1, Vector2.RIGHT, 0.0)
	assert_eq(_controller.buffered_kind(), -1, "like a swap, a slot select waits for nothing")


# --- attack speed -------------------------------------------------------------------------

## Doubles the player's ATTACK_SPEED through a StatBlock modifier (never a base
## edit), the way a relic or a status would.
func _set_attack_speed(percent: float, source: StringName = &"test_haste") -> void:
	(_player.stat_block as StatBlock).add_modifier(StatBlock.Stat.ATTACK_SPEED, 0.0, percent, source)


func test_attack_speed_scales_the_attack_clock_and_the_cancel_windows() -> void:
	_set_attack_speed(1.0)
	_start_attack(_long_spec())
	_tick(0.1)
	assert_almost_eq(_attack_state().elapsed(), 0.2, 0.02, "0.1 s of real time is 0.2 s of attack clock")
	assert_false(_attack_state().can_combo_cancel(), "not yet even so")
	_tick(0.2)
	assert_almost_eq(_attack_state().elapsed(), 0.6, 0.02, "past the 0.55 s cancel point")
	assert_true(_attack_state().can_combo_cancel(), "the combo window opened early on the fast attack")


func test_a_fast_attack_ends_its_full_timeline_in_half_the_real_time() -> void:
	_set_attack_speed(1.0)
	_start_attack(_long_spec())
	_tick(0.55)
	assert_eq(_state(), &"Attack", "1.1 s of clock is not the full 1.15 s yet")
	_tick(0.05)
	assert_eq(_state(), &"Idle", "the 1.15 s attack is over after 0.6 s of real time")


func test_a_slow_attack_stretches_the_same_way() -> void:
	_set_attack_speed(-0.5, &"test_slow")
	_start_attack(_long_spec())
	_tick(0.2)
	assert_almost_eq(_attack_state().elapsed(), 0.1, 0.01, "half speed halves the clock")
	assert_false(_attack_state().can_dodge_cancel(), "the slow attack keeps its dodge window shut")


func test_a_crushing_slow_clamps_to_the_attack_speed_floor() -> void:
	# StatBlock clamps ATTACK_SPEED at 0.2, so a -95% modifier cannot freeze a
	# player in an attack forever.
	assert_gt(StatBlock.ATTACK_SPEED_MIN, 0.0, "the floor is above zero")
	_set_attack_speed(-0.95, &"test_freeze")
	_start_attack(_long_spec())
	_tick(0.1)
	assert_almost_eq(_attack_state().elapsed(), 0.02, 0.01, "0.1 s of real time at the 0.2 floor")
	assert_false(_attack_state().can_combo_cancel())


# --- attack speed: the animation half ---------------------------------------------------
## SPEC-combat-core "Attack speed": animation `speed_scale = StatBlock.ATTACK_SPEED`
## alongside the clock. The player's AnimatedSprite2D runs the attack anim at the
## same scale the attack clock does, and back to normal once the state leaves.

func test_the_attack_anim_plays_at_the_statblock_speed() -> void:
	_set_attack_speed(1.0)
	_start_attack(_long_spec())
	assert_almost_eq(_player.sprite.speed_scale, 2.0, 0.001, "the sprite runs at +100% attack speed")


func test_a_slow_attack_halves_the_anim_speed_too() -> void:
	_set_attack_speed(-0.5, &"test_slow")
	_start_attack(_long_spec())
	assert_almost_eq(_player.sprite.speed_scale, 0.5, 0.001, "the sprite runs at half speed")


func test_leaving_the_attack_state_restores_the_anim_speed() -> void:
	_set_attack_speed(1.0)
	_start_attack(_long_spec())
	_tick(0.6)
	assert_eq(_state(), &"Idle", "setup: the fast attack is over")
	assert_almost_eq(_player.sprite.speed_scale, 1.0, 0.001, "back to normal playback")


func test_a_combo_cancel_restart_keeps_the_anim_scaled() -> void:
	_set_attack_speed(1.0)
	_start_attack(_long_spec())
	_tick(0.6)
	_controller.apply(AttackController.Kind.LIGHT, Vector2.RIGHT, 0.0)
	assert_eq(_state(), &"Attack", "setup: the next step restarted the state")
	assert_almost_eq(_player.sprite.speed_scale, 2.0, 0.001, "the restart re-applied the scale")


func test_a_buff_picked_up_mid_swing_moves_the_anim_with_the_clock() -> void:
	_set_attack_speed(1.0)
	_start_attack(_long_spec())
	_tick(0.01)
	assert_almost_eq(_attack_state().elapsed(), 0.02, 0.005, "setup: one frame at the 2x clock")
	_set_attack_speed(1.0, &"test_second_haste")
	_tick(0.01)
	assert_almost_eq(_player.sprite.speed_scale, 3.0, 0.001, "the animation followed the mid-swing buff")
	assert_almost_eq(_attack_state().elapsed(), 0.05, 0.005, "and so did the clock: 2x for a frame, then 3x")


func test_a_dodge_out_of_the_attack_restores_the_anim_speed() -> void:
	_set_attack_speed(1.0)
	_start_attack(_long_spec())
	_tick(0.2)
	_controller.apply(AttackController.Kind.DODGE, Vector2.RIGHT, 0.0)
	assert_eq(_state(), &"Dodge", "setup: the dodge cancelled the attack")
	assert_almost_eq(_player.sprite.speed_scale, 1.0, 0.001, "the dodge anim is not sped up")
