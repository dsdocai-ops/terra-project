class_name PlayerAttackState
extends PlayerState
## One attack: windup, active window (hitbox live or projectile fired),
## recovery. Movement continues at the attack's speed factor. Owned by
## combat-core (W2-A2, cancel windows C3). Sync: runs on the host and on the
## owning client (like Move); the host's hitbox is the one that damages.
##
## It reports its cancel windows to AttackController: the next combo step or a
## heavy may start once `combo_cancel_at` of recovery has passed, and a dodge
## once `dodge_cancel_at` has. Starting the next attack calls `restart`, which
## skips the rest of recovery.

var _spec: AttackSpec = null
var _dir: Vector2 = Vector2.DOWN
var _charge: float = 0.0
var _heavy: bool = false
var _perfect: bool = false
var _elapsed: float = 0.0
var _swung: bool = false
var _ended: bool = false
var _weapons: WeaponController = null


func _on_setup() -> void:
	super._on_setup()
	_weapons = player.get_node("WeaponController") as WeaponController


func enter(_from: StringName) -> void:
	var pending: Dictionary = player.pending_attack
	_spec = pending.get("spec") as AttackSpec
	_dir = pending.get("dir", Vector2.DOWN)
	_charge = pending.get("charge", 0.0)
	_heavy = pending.get("heavy", false)
	_perfect = pending.get("perfect", false)
	_elapsed = 0.0
	_swung = false
	_ended = false
	_weapons.attack_started()
	player.set_facing(_dir)
	player.play_directional("idle")


func exit(_to: StringName) -> void:
	if _weapons != null:
		_weapons.end_swing()
		_weapons.attack_finished()


## Starts the pending attack from inside this one (a combo cancel): the old swing
## is ended and the rest of its recovery is skipped.
func restart() -> void:
	exit(&"Attack")
	enter(&"Attack")


## Seconds of attack-clock time since this attack began (attack speed applied).
func elapsed() -> float:
	return _elapsed


## True once the next combo step, a heavy or a skill may cancel the recovery.
func can_combo_cancel() -> bool:
	return _spec != null and _elapsed >= _spec.combo_cancel_seconds()


## True once a dodge may cancel the attack.
func can_dodge_cancel() -> bool:
	return _spec != null and _elapsed >= _spec.dodge_cancel_seconds()


func physics_update(delta: float) -> void:
	var speed_scale: float = 1.0
	var stats := player.stat_block as StatBlock
	if stats != null:
		speed_scale = maxf(stats.get_value(StatBlock.Stat.ATTACK_SPEED), StatBlock.ATTACK_SPEED_MIN)
	_elapsed += delta * speed_scale
	_steer(delta)
	if not _swung and _elapsed >= _spec.windup_seconds:
		_swung = true
		_weapons.begin_swing(_spec, _dir, _charge, _heavy, _perfect)
	if _swung and not _ended and _elapsed >= _spec.windup_seconds + _spec.active_seconds:
		_ended = true
		_weapons.end_swing()
	if _elapsed >= _spec.total_seconds():
		var next: StringName = &"Move" if player.move_input != Vector2.ZERO else &"Idle"
		if machine.change_to(next):
			machine.current.physics_update(0.0)


## Walking while attacking, slowed by the spec's factor.
func _steer(delta: float) -> void:
	var target: Vector2 = Vector2.ZERO
	if player.move_input != Vector2.ZERO:
		target = Iso.input_to_world(player.move_input) * player.move_speed() * _spec.move_speed_factor * machine.effective_scale
	player.velocity = player.velocity.move_toward(target, player.move_accel() * delta)
	player.apply_coop_clamp(delta)
	player.move_and_slide()
