class_name AttackController
extends Node
## The player's attack input layer (SPEC-combat-core `AttackController`): light
## combo, heavy charge and release, weapon swap, dodge, and one unified input
## buffer. Owned by combat-core. Sync: the owning client reads hardware and runs
## the action locally for feel, then sends it to the host, which validates the
## sender and runs it too; the host's copy is the source of truth for damage
## (`Hurtbox.receive` and the projectile spawner are host-only). A heavy sends
## two messages: HEAVY_PRESS when the button goes down (so the host slows the
## charging player the same way the owner does) and HEAVY on release with the
## charge, which the host clamps to what it saw plus a latency allowance.
##
## The buffer holds one action, the last press, for BUFFER_SECONDS. LIGHT,
## HEAVY_PRESS, DODGE and SKILL wait in it until the first frame that is legal
## for that action: a fresh start from Idle or Move, the combo-cancel window of
## an Attack for the next light, heavy or skill, the dodge-cancel window for a
## dodge. A heavy released while busy stays buffered instead of being dropped.
## Both the owner and the host run their own buffer, so a press that reaches the
## host a little early still fires.

## SWAP, HEAVY (the release) and the four buffered kinds. New kinds go at the
## end: they travel over the wire as ints.
enum Kind { LIGHT, HEAVY, SWAP, DODGE, HEAVY_PRESS, SKILL }

## A heavy released sooner than this fires uncharged.
const TAP_SECONDS: float = 0.15
## One slot, last press wins, this long.
const BUFFER_SECONDS: float = 0.2
## How much more hold time than the host measured it believes from a client.
const CHARGE_SLACK_SECONDS: float = 0.3

var _player: Player = null
var _weapons: WeaponController = null
## {kind, aim, age, released, charge, perfect}, or empty.
var _buffer: Dictionary = {}
## Owner only: the heavy button went down and has not come back up.
var _heavy_down: bool = false


func _ready() -> void:
	_player = get_parent() as Player
	_weapons = _player.get_node_or_null("WeaponController") as WeaponController


func _physics_process(delta: float) -> void:
	tick_buffer(delta)
	if _player == null or not _player.is_local or _player.is_downed or _player.is_dead:
		_heavy_down = false
		return
	if Input.is_action_just_pressed(&"attack_light"):
		send(Kind.LIGHT, 0.0)
	if Input.is_action_just_pressed(&"attack_heavy"):
		_heavy_down = true
		send(Kind.HEAVY_PRESS, 0.0)
	if _heavy_down and not Input.is_action_pressed(&"attack_heavy"):
		_heavy_down = false
		release_heavy()
	if Input.is_action_just_pressed(&"swap_weapon"):
		send(Kind.SWAP, 0.0)
	if Input.is_action_just_pressed(&"dodge"):
		send(Kind.DODGE, 0.0)


# --- the buffer -------------------------------------------------------------------


## What is waiting in the buffer, or -1 when it is empty.
func buffered_kind() -> int:
	return int(_buffer["kind"]) if not _buffer.is_empty() else -1


func clear_buffer() -> void:
	_buffer.clear()


## Ages the buffered action and fires it at the first legal frame. Public so
## tests can step it.
func tick_buffer(delta: float) -> void:
	if _buffer.is_empty():
		return
	_buffer["age"] = float(_buffer["age"]) + delta
	if _player == null or _player.is_downed or _player.is_dead or float(_buffer["age"]) > BUFFER_SECONDS:
		_buffer.clear()
		return
	var kind: int = int(_buffer["kind"])
	if _is_legal(kind):
		var item: Dictionary = _buffer
		_buffer = {}
		_run(kind, item["aim"], item)


func _store(kind: int, aim: Vector2) -> void:
	_buffer = {"kind": kind, "aim": aim, "age": 0.0, "released": false, "charge": 0.0, "perfect": false}


## Runs `kind` now when it is legal, otherwise keeps it as the one buffered
## action (replacing whatever was there).
func _act_or_buffer(kind: int, aim: Vector2) -> void:
	if _is_legal(kind):
		_buffer.clear()
		_run(kind, aim, {})
	else:
		_store(kind, aim)


func _is_legal(kind: int) -> bool:
	match kind:
		Kind.LIGHT, Kind.HEAVY_PRESS, Kind.SKILL:
			return _can_start_attack()
		Kind.DODGE:
			return _can_dodge_now()
	return false


## A fresh attack may start from Idle or Move, or from an Attack that has passed
## its combo-cancel window.
func _can_start_attack() -> bool:
	var current: StringName = _player.state_machine.current_name()
	if current == &"Idle" or current == &"Move":
		return true
	if current == &"Attack":
		var attack: PlayerAttackState = _player.state_machine.current as PlayerAttackState
		return attack != null and attack.can_combo_cancel()
	return false


## A dodge may start unless one is running or the player is stunned; it cancels
## a heavy charge at any time and an attack once its dodge-cancel window opens.
func _can_dodge_now() -> bool:
	if not _player.can_dodge():
		return false
	var current: StringName = _player.state_machine.current_name()
	if current == &"Dodge" or current == &"HitStun":
		return false
	if current == &"Attack":
		var attack: PlayerAttackState = _player.state_machine.current as PlayerAttackState
		return attack != null and attack.can_dodge_cancel()
	return true


func _run(kind: int, aim: Vector2, item: Dictionary) -> void:
	match kind:
		Kind.LIGHT:
			_begin_attack(_weapons.take_light(), aim, 0.0, false, false)
		Kind.HEAVY_PRESS:
			if item.get("released", false):
				_fire_heavy(aim, float(item["charge"]), bool(item["perfect"]))
			else:
				_enter_charge(float(item.get("age", 0.0)))
		Kind.DODGE:
			_begin_dodge(aim)


# --- input entry points ---------------------------------------------------------------


## Owner: the heavy button came back up. Reads the charge off the HeavyCharge
## state (or the hold so far, when the press is still buffered) and sends it.
func release_heavy() -> void:
	var charge: float = 0.0
	var perfect: bool = false
	var charging: PlayerHeavyChargeState = _charge_state()
	if charging != null:
		charge = charging.charge()
		perfect = charging.is_perfect()
	elif not _buffer.is_empty() and int(_buffer["kind"]) == Kind.HEAVY_PRESS:
		charge = charge_for_hold(float(_buffer["age"]))
	send(Kind.HEAVY, charge, perfect)


## Charge 0..1 for a hold of `held` seconds: nothing for a tap, linear after.
func charge_for_hold(held: float) -> float:
	if held < TAP_SECONDS:
		return 0.0
	return clampf(held / _weapons.heavy_charge_seconds(), 0.0, 1.0)


## Local entry point: runs the action here and, on a client, asks the host to
## run it too.
func send(kind: int, charge: float, perfect: bool = false) -> void:
	var aim: Vector2 = _aim_direction()
	apply(kind, aim, charge, perfect)
	if not multiplayer.is_server():
		_request.rpc_id(NetworkManager.HOST_PEER_ID, kind, aim, charge, perfect)


@rpc("any_peer", "call_remote", "reliable")
func _request(kind: int, aim: Vector2, charge: float, perfect: bool) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _player.peer_id:
		push_warning("[combat] action from peer %d refused for player %d" % [multiplayer.get_remote_sender_id(), _player.peer_id])
		return
	if kind == Kind.HEAVY:
		charge = validated_charge(charge)
		perfect = perfect and charge >= 1.0
	apply(kind, aim, charge, perfect)


## The host's check on a client-reported charge: within 0..1, and no more than
## the host saw the player hold plus a latency allowance.
func validated_charge(reported: float) -> float:
	var charge: float = clampf(reported, 0.0, 1.0)
	var charging: PlayerHeavyChargeState = _charge_state()
	if charging != null:
		var cap: float = (charging.held() + CHARGE_SLACK_SECONDS) / maxf(_weapons.heavy_charge_seconds(), 0.01)
		charge = minf(charge, cap)
	return charge


## Runs an action on this copy of the player (host, or the predicting owner).
func apply(kind: int, aim: Vector2, charge: float, perfect: bool = false) -> void:
	if _player == null or _player.is_downed or _player.is_dead:
		return
	match kind:
		Kind.LIGHT, Kind.HEAVY_PRESS, Kind.DODGE, Kind.SKILL:
			_act_or_buffer(kind, aim)
		Kind.HEAVY:
			_release_heavy(aim, charge, perfect)
		Kind.SWAP:
			_weapons.swap()


# --- heavy --------------------------------------------------------------------------------


func _charge_state() -> PlayerHeavyChargeState:
	if _player == null or _player.state_machine.current_name() != &"HeavyCharge":
		return null
	return _player.state_machine.current as PlayerHeavyChargeState


func _enter_charge(credit: float) -> void:
	_player.pending_charge_credit = credit
	_player.state_machine.change_to(&"HeavyCharge")


## The button came up. While charging, that fires the heavy. If the press is
## still waiting in the buffer, the release is stored with it so the heavy fires
## (uncharged or partly charged) at the first legal frame instead of being lost.
## With no press in sight it fires directly when legal, and is dropped when the
## charge was interrupted (a hit, a dodge).
func _release_heavy(aim: Vector2, charge: float, perfect: bool) -> void:
	if _charge_state() != null:
		_fire_heavy(aim, charge, perfect)
	elif not _buffer.is_empty() and int(_buffer["kind"]) == Kind.HEAVY_PRESS:
		_buffer["released"] = true
		_buffer["charge"] = charge
		_buffer["perfect"] = perfect
		_buffer["aim"] = aim
	elif _is_legal(Kind.HEAVY_PRESS):
		_fire_heavy(aim, charge, perfect)


func _fire_heavy(aim: Vector2, charge: float, perfect: bool) -> void:
	var spec: AttackSpec = _weapons.take_heavy()
	if spec == null:
		return
	_begin_attack(spec, aim, charge, true, perfect)
	if multiplayer.is_server():
		Events.heavy_attack_released.emit(_player, charge)


# --- starting actions ---------------------------------------------------------------------


func _begin_attack(spec: AttackSpec, aim: Vector2, charge: float, heavy: bool, perfect: bool) -> void:
	if spec == null:
		return
	_player.pending_attack = {"spec": spec, "dir": aim, "charge": charge, "heavy": heavy, "perfect": perfect}
	var attack: PlayerAttackState = _player.state_machine.current as PlayerAttackState
	if attack != null:
		attack.restart()
		return
	_player.state_machine.change_to(&"Attack")


func _begin_dodge(aim: Vector2) -> void:
	if not _can_dodge_now():
		return
	_player.pending_dodge_dir = aim
	_player.state_machine.change_to(&"Dodge")


## Screen-space direction from the player to the cursor; for a remote owner the
## host uses the aim it was sent.
func _aim_direction() -> Vector2:
	var to_cursor: Vector2 = _player.get_global_mouse_position() - _player.global_position
	if to_cursor.length() < 4.0:
		return _player.facing if _player.facing != Vector2.ZERO else Vector2.DOWN
	return to_cursor.normalized()
