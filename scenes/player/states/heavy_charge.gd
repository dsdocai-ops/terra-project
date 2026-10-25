class_name PlayerHeavyChargeState
extends PlayerState
## Holding the heavy button: the player walks at the weapon's
## `charge_move_factor` while a ring around them fills over
## `heavy_charge_seconds`. Entered on a heavy press, or from the input buffer at
## the first legal frame. Owned by combat-core (combat v2 C3). Sync: runs on the
## owning client (prediction) and on the host, which learns of the press through
## AttackController's request RPC so both slow the player alike; the release
## sends the charge with it and the host clamps it to what it saw.
##
## Tiers: a hold under TAP_SECONDS releases uncharged; otherwise the charge is
## linear 0..1. Releasing within PERFECT_WINDOW_SECONDS after full is a perfect
## release. Holding longer keeps the full charge and loses the bonus.

signal charge_full

const TAP_SECONDS: float = 0.15
const PERFECT_WINDOW_SECONDS: float = 0.15
## Played on the owning peer when the charge fills. Borrows the crit accent from the
## SFX bank until a charge_full clip exists (art-audio); swapping it is one id.
const FULL_SFX: StringName = &"crit"

var _held: float = 0.0
var _full_reached: bool = false
var _weapons: WeaponController = null
var _ring: ChargeRing = null


func _on_setup() -> void:
	super._on_setup()
	_weapons = player.get_node("WeaponController") as WeaponController


## The ring is a child of the player made on first use: the machine sets its
## states up while the player is still adding its own children.
func _ensure_ring() -> void:
	if _ring != null:
		return
	_ring = player.get_node_or_null("ChargeRing") as ChargeRing
	if _ring == null:
		_ring = ChargeRing.new()
		_ring.name = "ChargeRing"
		player.add_child(_ring)


func enter(_from: StringName) -> void:
	_ensure_ring()
	_held = maxf(player.pending_charge_credit, 0.0)
	player.pending_charge_credit = 0.0
	_full_reached = false
	_ring.show_ring()
	player.play_directional("idle")
	_refresh()


func exit(_to: StringName) -> void:
	if _ring != null:
		_ring.hide_ring()


## Seconds the button has been held (including any credit from a buffered press).
func held() -> float:
	return _held


## Charge 0..1 as it would release now: 0 for a tap, linear after that.
func charge() -> float:
	if _held < TAP_SECONDS:
		return 0.0
	return clampf(_held / _full_seconds(), 0.0, 1.0)


func is_full() -> bool:
	return _held >= _full_seconds()


## True when a release now lands within the perfect window after full charge.
func is_perfect() -> bool:
	var past_full: float = _held - _full_seconds()
	return past_full >= 0.0 and past_full <= PERFECT_WINDOW_SECONDS


func physics_update(delta: float) -> void:
	_held += delta
	_steer(delta)
	_refresh()


func _full_seconds() -> float:
	return maxf(_weapons.heavy_charge_seconds(), 0.01)


func _refresh() -> void:
	_ring.fill = clampf(_held / _full_seconds(), 0.0, 1.0)
	if not _full_reached and is_full():
		_full_reached = true
		_ring.flash()
		charge_full.emit()
		if player.is_local:
			AudioManager.play_sfx(FULL_SFX)


## Walking while charging, at the weapon's charge move factor; facing follows
## the aim.
func _steer(delta: float) -> void:
	var target: Vector2 = Vector2.ZERO
	if player.move_input != Vector2.ZERO:
		target = Iso.input_to_world(player.move_input) * player.move_speed() * _weapons.charge_move_factor() * machine.effective_scale
	player.velocity = player.velocity.move_toward(target, player.move_accel() * delta)
	var to_aim: Vector2 = player.aim_position - player.global_position
	if to_aim.length() > 4.0:
		player.set_facing(to_aim.normalized())
	player.apply_coop_clamp(delta)
	player.move_and_slide()
