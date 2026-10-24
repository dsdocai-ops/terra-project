class_name AttackController
extends Node
## The player's attack input layer (SPEC-combat-core `AttackController`): light
## combo with a one-press buffer, heavy charge and release, tap heavy, weapon
## swap, dodge. Owned by combat-core. Sync: the owning client reads hardware and
## runs the action locally for feel, then sends it to the host, which validates
## the sender and runs it too; the host's copy is the source of truth for
## damage (`Hurtbox.receive` and the projectile spawner are host-only).

enum Kind { LIGHT, HEAVY, SWAP, DODGE }

## A heavy released sooner than this fires uncharged.
const TAP_SECONDS: float = 0.15
## A light press during an attack is remembered this long.
const BUFFER_SECONDS: float = 0.25

var _player: Player = null
var _weapons: WeaponController = null
var _heavy_held: float = -1.0
var _buffered_light: float = 0.0


func _ready() -> void:
	_player = get_parent() as Player
	_weapons = _player.get_node_or_null("WeaponController") as WeaponController


func _physics_process(delta: float) -> void:
	_buffered_light = maxf(_buffered_light - delta, 0.0)
	if _player == null or not _player.is_local or _player.is_downed or _player.is_dead:
		return
	if Input.is_action_just_pressed(&"attack_light"):
		_press_light()
	if Input.is_action_just_pressed(&"attack_heavy"):
		_heavy_held = 0.0
	if _heavy_held >= 0.0:
		_heavy_held += delta
		if not Input.is_action_pressed(&"attack_heavy"):
			var charge: float = 0.0
			if _heavy_held >= TAP_SECONDS:
				charge = clampf(_heavy_held / _weapons.heavy_charge_seconds(), 0.0, 1.0)
			_heavy_held = -1.0
			send(Kind.HEAVY, charge)
	if Input.is_action_just_pressed(&"swap_weapon"):
		send(Kind.SWAP, 0.0)
	if Input.is_action_just_pressed(&"dodge"):
		send(Kind.DODGE, 0.0)
	if _buffered_light > 0.0 and not _is_busy():
		_buffered_light = 0.0
		send(Kind.LIGHT, 0.0)


## True while an attack, dodge or hit reaction owns the player.
func _is_busy() -> bool:
	var current: StringName = _player.state_machine.current_name()
	return current == &"Attack" or current == &"Dodge" or current == &"HitStun"


func _press_light() -> void:
	if _is_busy():
		_buffered_light = BUFFER_SECONDS
		return
	send(Kind.LIGHT, 0.0)


## Local entry point: runs the action here and, on a client, asks the host to
## run it too.
func send(kind: int, charge: float) -> void:
	var aim: Vector2 = _aim_direction()
	apply(kind, aim, charge)
	if not multiplayer.is_server():
		_request.rpc_id(NetworkManager.HOST_PEER_ID, kind, aim, charge)


@rpc("any_peer", "call_remote", "reliable")
func _request(kind: int, aim: Vector2, charge: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _player.peer_id:
		push_warning("[combat] action from peer %d refused for player %d" % [multiplayer.get_remote_sender_id(), _player.peer_id])
		return
	apply(kind, aim, charge)


## Runs an action on this copy of the player (host, or the predicting owner).
func apply(kind: int, aim: Vector2, charge: float) -> void:
	if _player == null or _player.is_downed or _player.is_dead:
		return
	match kind:
		Kind.LIGHT:
			_begin_attack(_weapons.take_light(), aim, 0.0, false)
		Kind.HEAVY:
			_begin_attack(_weapons.take_heavy(), aim, charge, true)
		Kind.SWAP:
			_weapons.swap()
		Kind.DODGE:
			_begin_dodge(aim)


func _begin_attack(spec: AttackSpec, aim: Vector2, charge: float, heavy: bool) -> void:
	if spec == null:
		return
	var current: StringName = _player.state_machine.current_name()
	if current == &"Attack" or current == &"Dodge" or current == &"HitStun":
		return
	_player.pending_attack = {"spec": spec, "dir": aim, "charge": charge, "heavy": heavy}
	_player.state_machine.change_to(&"Attack")


func _begin_dodge(aim: Vector2) -> void:
	var current: StringName = _player.state_machine.current_name()
	if current == &"Dodge" or current == &"HitStun":
		return
	if not _player.can_dodge():
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
