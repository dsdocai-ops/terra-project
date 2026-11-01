class_name UltimateController
extends Node
## One player's ultimate meter and the ultimate press (SPEC-abilities
## "UltimateController", W5-G6). Owned by abilities. Sync: host-authoritative.
## The host alone charges the meter: from Events.hit_landed (damage this player
## dealt to a non-player target) and Events.player_damaged (damage this player
## took). The host also spends it, writes it into the owner's RunPlayerState slice
## (D-P7) and sends every change to the owning peer on a reliable RPC, so the
## owner's copy reads the host's value. A press on a client goes to the host with
## ask_ultimate; the host checks the sender owns the player before it spends.

signal meter_changed(value: float)

const METER_MAX: float = 100.0
## Meter per 1% of an enemy's max HP this player dealt.
const DEAL_PER_PERCENT: float = 0.5
## Meter per 1% of this player's own max HP taken.
const TAKE_PER_PERCENT: float = 2.0
const REFUSE_NONE: StringName = &""
const REFUSE_NOT_HOST: StringName = &"not_host"
const REFUSE_NOT_OWNER: StringName = &"not_owner"
const REFUSE_NOT_FULL: StringName = &"not_full"
const REFUSE_NO_ULTIMATE: StringName = &"no_ultimate"
const HEALTH_NODE: NodePath = ^"Health"
const ABILITY_CONTROLLER_NODE: NodePath = ^"AbilityController"

## The meter, 0 to METER_MAX. The host writes it; a client's copy follows the host.
var meter: float = 0.0
## The character's ultimate, an AbilityData with is_ultimate set. Null until one
## is assigned (Cave-In arrives in W5-G7).
var ultimate: AbilityData = null
## Why the last request_ultimate was refused, or REFUSE_NONE after an accepted one.
var last_refusal: StringName = REFUSE_NONE

var _player: Player = null


func _enter_tree() -> void:
	_player = get_parent() as Player
	if not Events.hit_landed.is_connected(_on_hit_landed):
		Events.hit_landed.connect(_on_hit_landed)
	if not Events.player_damaged.is_connected(_on_player_damaged):
		Events.player_damaged.connect(_on_player_damaged)


func _exit_tree() -> void:
	if Events.hit_landed.is_connected(_on_hit_landed):
		Events.hit_landed.disconnect(_on_hit_landed)
	if Events.player_damaged.is_connected(_on_player_damaged):
		Events.player_damaged.disconnect(_on_player_damaged)


## Puts `data` in the ultimate slot. Only an ability marked is_ultimate fits there;
## a null `data` clears the slot. Host only in effect: the host hands out the loadout.
func assign_ultimate(data: AbilityData) -> void:
	if data != null and not data.is_ultimate:
		return
	ultimate = data


## Adds `amount` to the meter, clamped to METER_MAX. A non-finite or non-positive
## amount is ignored. Host only.
func charge(amount: float) -> void:
	if not multiplayer.is_server() or not is_finite(amount) or amount <= 0.0:
		return
	_set_meter(meter + amount)


## Spends a full meter on the ultimate and returns true: the meter goes to 0, the
## ultimate is cast from the owner's AbilityController, and ultimate_used is
## emitted once. A refusal returns false, sets `last_refusal` and keeps the meter.
## Host only.
func request_ultimate() -> bool:
	last_refusal = REFUSE_NONE
	if not multiplayer.is_server():
		last_refusal = REFUSE_NOT_HOST
		return false
	if ultimate == null:
		last_refusal = REFUSE_NO_ULTIMATE
		return false
	if meter < METER_MAX:
		last_refusal = REFUSE_NOT_FULL
		return false
	_set_meter(0.0)
	_cast_ultimate()
	Events.ultimate_used.emit(_player, ultimate)
	return true


## What the owner's press calls. On the host it spends at once. On a client it
## sends the press to the host, so the return value means "sent", not "spent".
func ask_ultimate() -> bool:
	if multiplayer.is_server():
		return request_ultimate()
	_remote_request_ultimate.rpc_id(NetworkManager.HOST_PEER_ID)
	return true


## Client -> host. Refused unless the sender is the peer that owns this player.
@rpc("any_peer", "call_remote", "reliable")
func _remote_request_ultimate() -> void:
	if not multiplayer.is_server():
		return
	if _player == null or multiplayer.get_remote_sender_id() != _player.peer_id:
		last_refusal = REFUSE_NOT_OWNER
		return
	request_ultimate()


## Host -> owning client: the host's meter after each change. A value that is not
## finite is dropped, so one bad packet cannot poison the client's copy.
@rpc("any_peer", "call_remote", "reliable")
func _remote_set_meter(value: float) -> void:
	if multiplayer.get_remote_sender_id() != NetworkManager.HOST_PEER_ID:
		return
	if not is_finite(value):
		return
	meter = clampf(value, 0.0, METER_MAX)
	meter_changed.emit(meter)


## Host only: the one place the meter changes. Writes the owner's slice and sends
## the value to the owner.
func _set_meter(value: float) -> void:
	meter = clampf(value, 0.0, METER_MAX)
	meter_changed.emit(meter)
	_write_slice()
	_push_to_owner()


## Host only. Damage this player dealt to a non-player target. Only a hit the
## player is credited with (owner_player) counts, so an unattributed hit is inert.
func _on_hit_landed(hit: HitInfo) -> void:
	if _player == null or hit == null:
		return
	if hit.owner_player != _player or hit.target is Player:
		return
	charge(_percent_of(hit.final_damage, _max_hp_of(hit.target)) * DEAL_PER_PERCENT)


## Host only. Damage this player took, read against its own max HP.
func _on_player_damaged(player: Player, hit: HitInfo) -> void:
	if _player == null or hit == null:
		return
	if player != _player:
		return
	charge(_percent_of(hit.final_damage, _max_hp_of(player)) * TAKE_PER_PERCENT)


## Host only: casts the ultimate through the owner's AbilityController, aimed at
## the owner's cursor. Nothing is cast with no ultimate, no player, or no controller.
func _cast_ultimate() -> void:
	if _player == null or ultimate == null:
		return
	var ability := _player.get_node_or_null(ABILITY_CONTROLLER_NODE) as AbilityController
	if ability == null:
		return
	ability.cast_ultimate(ultimate, _player.aim_position)


## Host only: the owner's RunPlayerState slice carries the meter, when a run is live.
func _write_slice() -> void:
	if _player == null or GameState.run == null:
		return
	var slice: RunPlayerState = GameState.run.get_player(_player.peer_id)
	if slice != null:
		slice.ultimate_meter = meter


## Host only: sends the meter to the owning peer. Skipped for a player with no peer
## yet, and for a peer that is not connected (the host never lists itself as a peer).
func _push_to_owner() -> void:
	if _player == null:
		return
	var peer_id: int = _player.peer_id
	if not multiplayer.get_peers().has(peer_id):
		return
	_remote_set_meter.rpc_id(peer_id, meter)


## The share of `max_hp` that `amount` is, in percent. Zero when either side is
## empty, so a target with no HP pool charges nothing.
func _percent_of(amount: int, max_hp: float) -> float:
	if amount <= 0 or max_hp <= 0.0:
		return 0.0
	return float(amount) / max_hp * 100.0


## Max HP of a node with a Health child, or 0 when it has none.
func _max_hp_of(node: Node) -> float:
	if not is_instance_valid(node):
		return 0.0
	var health := node.get_node_or_null(HEALTH_NODE) as Health
	if health == null:
		return 0.0
	return float(health.max_hp)
