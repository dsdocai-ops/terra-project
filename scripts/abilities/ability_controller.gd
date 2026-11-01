class_name AbilityController
extends Node
## Holds a player's three ability slots (Q, R, V): the ability in each slot, its
## rank, its charges and its cooldown, plus the rank-up that a duplicate pickup
## triggers (SPEC-abilities "AbilityController"). Owned by abilities. Sync:
## host-authoritative. Only the host spends charges and starts cooldowns. Every
## peer runs tick() in TimeManager-scaled time, but a client never has a cooldown
## running, so its copy stays at zero. A cast from a client is refused by
## request_cast; ask_cast sends it to the host as an RPC, and the host checks the
## sender owns the player before it casts.
##
## A host cast spawns the slot's cast_scene under the FX layer (host-local, like
## the ground cracks) and tells every other peer, which shows a visual-only copy.
## Hits come only from the host's copy. Each cast is named from a counter that
## every peer advances in the same order, so a node path inside a cast (a clone's
## position RPC, FriendlyUnit) resolves to the same node on both screens.
##
## Charge model: a cast spends one charge. The cooldown runs only while the
## slot holds fewer charges than its maximum, and each time it ends it gives
## one charge back. A one-charge ability is therefore a plain cooldown.

signal rank_changed(slot: int, rank: int)
## A duplicate of a rank-3 ability was picked up. Run-economy pays the gold.
signal gold_converted(amount: int)

const SLOT_COUNT: int = 3
const REFUSE_NONE: StringName = &""
const REFUSE_NOT_HOST: StringName = &"not_host"
const REFUSE_NOT_OWNER: StringName = &"not_owner"
const REFUSE_EMPTY: StringName = &"empty"
const REFUSE_COOLING: StringName = &"cooling"
const REFUSE_NO_CHARGE: StringName = &"no_charge"
## An aim with a NaN or infinite axis. It would make aim_dir non-finite, so the
## cast is refused before anything is spent.
const REFUSE_NOT_FINITE: StringName = &"not_finite"
## rank_up() returns this when the ability is not slotted; the caller assigns it.
const RANK_NOT_HELD: int = 0
## rank_up() returns this for a duplicate at max rank, which converts to gold.
const RANK_TO_GOLD: int = -1
const GOLD_PER_MAX_RANK_DUPLICATE: int = 25

var slots: Array[AbilityData] = [null, null, null]
## Why the last request_cast was refused, or REFUSE_NONE after an accepted cast.
var last_refusal: StringName = REFUSE_NONE
## Aim of the last accepted cast. The cast node reads it once it spawns.
var last_aim_point: Vector2 = Vector2.ZERO
## The cast node the last accepted cast spawned on the host, or on a client for a
## broadcast cast. Null when the slot's ability has no cast_scene.
var last_cast: AbilityCast = null
## Owner's StatBlock, for COOLDOWN_REDUCTION. Null (no reduction) when the
## controller is not on a player with a StatBlock child.
var stat_block: StatBlock = null

var _player: Player = null
var _ranks: Array[int] = [0, 0, 0]
var _charges: Array[int] = [0, 0, 0]
## Seconds of cooldown left on each slot, and the full length it started at.
var _cooldown_left: Array[float] = [0.0, 0.0, 0.0]
var _cooldown_total: Array[float] = [0.0, 0.0, 0.0]
## Counts the casts this controller has spawned, to name each one (see the top of
## this file). Every peer runs the same count for the same casts.
var _next_cast_id: int = 0


func _ready() -> void:
	_player = get_parent() as Player
	if _player != null:
		stat_block = _player.get_node_or_null("StatBlock") as StatBlock


func _physics_process(delta: float) -> void:
	tick(delta)


## Runs every cooldown for `delta` seconds of this player's TimeManager-scaled
## time. Called from _physics_process on the host; tests call it directly.
func tick(delta: float) -> void:
	var scaled: float = delta * TimeManager.scale_for(_timed_node())
	for slot: int in SLOT_COUNT:
		if _cooldown_left[slot] <= 0.0:
			continue
		_cooldown_left[slot] = maxf(_cooldown_left[slot] - scaled, 0.0)
		if _cooldown_left[slot] <= 0.0:
			_charges[slot] += 1
			_start_cooldown_if_idle(slot)


## Puts `data` on `slot` at rank 1 with full charges and no cooldown. A null
## `data` empties the slot. Host-only in effect: the host calls it when it
## hands out a loadout.
func assign(slot: int, data: AbilityData) -> void:
	if not _valid_slot(slot):
		return
	slots[slot] = data
	_ranks[slot] = 1 if data != null else 0
	_charges[slot] = data.charges if data != null else 0
	_cooldown_left[slot] = 0.0
	_cooldown_total[slot] = 0.0


## The rank of the ability in `slot` (1 to 3), or 0 for an empty slot.
func rank(slot: int) -> int:
	if not _valid_slot(slot):
		return 0
	return _ranks[slot]


## Charges left in `slot`.
func charges(slot: int) -> int:
	if not _valid_slot(slot):
		return 0
	return _charges[slot]


## How much of the cooldown is still left, from 1.0 (just started) down to 0.0
## (ready or no cooldown). The HUD draws its sweep from this.
func cooldown_fraction(slot: int) -> float:
	if not _valid_slot(slot) or _cooldown_total[slot] <= 0.0:
		return 0.0
	return clampf(_cooldown_left[slot] / _cooldown_total[slot], 0.0, 1.0)


## Casts the ability in `slot` if the host allows it: the slot holds an ability
## and a charge is left, and the aim is finite. Spends the charge, starts the
## cooldown if it is needed, spawns the cast, announces it, and returns true. A
## refusal returns false and sets `last_refusal`. Host only.
func request_cast(slot: int, aim_point: Vector2) -> bool:
	last_refusal = REFUSE_NONE
	if not multiplayer.is_server():
		last_refusal = REFUSE_NOT_HOST
		return false
	if not is_finite(aim_point.x) or not is_finite(aim_point.y):
		last_refusal = REFUSE_NOT_FINITE
		return false
	if not _valid_slot(slot) or slots[slot] == null:
		last_refusal = REFUSE_EMPTY
		return false
	if _charges[slot] <= 0:
		last_refusal = REFUSE_COOLING if _cooldown_left[slot] > 0.0 else REFUSE_NO_CHARGE
		return false
	last_aim_point = aim_point
	_charges[slot] -= 1
	_start_cooldown_if_idle(slot)
	_perform_cast(slot, aim_point)
	return true


## Host only. Casts an ultimate that sits outside the three slots (UltimateController's
## press): spawns it, shows it on every other peer and returns true. It does not emit
## ability_cast, which is for the slots; ultimate_used announces the ultimate. A
## non-finite aim is refused and nothing spawns.
func cast_ultimate(data: AbilityData, aim_point: Vector2) -> bool:
	if not multiplayer.is_server() or data == null:
		return false
	if not is_finite(aim_point.x) or not is_finite(aim_point.y):
		return false
	var aim_dir: Vector2 = (aim_point - _origin()).normalized()
	_spawn_cast(data, 1, aim_point, aim_dir)
	_broadcast_cast(data, 1, aim_point, aim_dir)
	return true


## What a player's own input calls. On the host it casts at once. On a client it
## sends the request to the host, which checks the sender and casts, so the return
## value means "sent", not "cast".
func ask_cast(slot: int, aim_point: Vector2) -> bool:
	if multiplayer.is_server():
		return request_cast(slot, aim_point)
	_remote_request_cast.rpc_id(NetworkManager.HOST_PEER_ID, slot, aim_point)
	return true


## Client -> host. Refused unless the sender is the peer that owns this player;
## a request with no sender (a local call) is refused too.
@rpc("any_peer", "call_remote", "reliable")
func _remote_request_cast(slot: int, aim_point: Vector2) -> void:
	if not multiplayer.is_server():
		return
	if _player == null or multiplayer.get_remote_sender_id() != _player.peer_id:
		last_refusal = REFUSE_NOT_OWNER
		return
	request_cast(slot, aim_point)


## Host -> client: the same cast, shown as a visual-only copy. Only the host's
## copy deals hits.
@rpc("any_peer", "call_remote", "reliable")
func _remote_show_cast(ability_path: String, cast_rank: int, aim_point: Vector2, aim_dir: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != NetworkManager.HOST_PEER_ID:
		return
	var data := load(ability_path) as AbilityData
	if data == null:
		return
	_spawn_cast(data, cast_rank, aim_point, aim_dir)


## A duplicate pickup of an ability that is already slotted raises its rank by
## one, up to MAX_RANK. Returns the new rank. Returns RANK_NOT_HELD (0) when the
## ability is not slotted, and RANK_TO_GOLD (-1) at max rank, where the duplicate
## is converted through `gold_converted` and no rank changes.
func rank_up(data: AbilityData) -> int:
	var slot: int = _slot_of(data)
	if slot < 0:
		return RANK_NOT_HELD
	if _ranks[slot] >= AbilityData.MAX_RANK:
		gold_converted.emit(GOLD_PER_MAX_RANK_DUPLICATE)
		return RANK_TO_GOLD
	_ranks[slot] += 1
	rank_changed.emit(slot, _ranks[slot])
	return _ranks[slot]


## Cooldown length for `slot` after COOLDOWN_REDUCTION from the owner's StatBlock.
func effective_cooldown(slot: int) -> float:
	if not _valid_slot(slot) or slots[slot] == null:
		return 0.0
	return slots[slot].cooldown * (1.0 - _cooldown_reduction())


## Host only: spawns the slot's cast, shows it on every other peer, and announces
## it on Events.ability_cast once.
func _perform_cast(slot: int, aim_point: Vector2) -> void:
	var data: AbilityData = slots[slot]
	var cast_rank: int = _ranks[slot]
	var aim_dir: Vector2 = (aim_point - _origin()).normalized()
	_spawn_cast(data, cast_rank, aim_point, aim_dir)
	_broadcast_cast(data, cast_rank, aim_point, aim_dir)
	Events.ability_cast.emit(_player, data, cast_rank)


## Makes and places one cast node from `data`'s cast_scene. Null when the ability
## has no cast scene, in which case nothing is shown.
func _spawn_cast(data: AbilityData, cast_rank: int, aim_point: Vector2, aim_dir: Vector2) -> AbilityCast:
	if data == null or data.cast_scene == null:
		last_cast = null
		return null
	var cast := data.cast_scene.instantiate() as AbilityCast
	if cast == null:
		last_cast = null
		return null
	cast.setup(_player, data, cast_rank, aim_point, aim_dir)
	# The player's name keeps two players' casts apart under one FX layer.
	var owner_name: String = String(_player.name) if _player != null else "Solo"
	cast.name = "%s_Cast%d" % [owner_name, _next_cast_id]
	_next_cast_id += 1
	_cast_parent().add_child(cast)
	last_cast = cast
	return cast


## Host -> other peers, one RPC each. The ability is sent by its resource path,
## which every peer loads from the same data folder.
func _broadcast_cast(data: AbilityData, cast_rank: int, aim_point: Vector2, aim_dir: Vector2) -> void:
	if data == null or data.cast_scene == null or data.resource_path.is_empty():
		return
	for peer_id: int in multiplayer.get_peers():
		_remote_show_cast.rpc_id(peer_id, data.resource_path, cast_rank, aim_point, aim_dir)


## The FX layer of the world when there is one (host-local presentation), or this
## controller in tests and scene-less setups, so the cast is always in the tree.
func _cast_parent() -> Node:
	var world: World = GameState.world
	if world != null and is_instance_valid(world) and world.fx != null:
		return world.fx
	return self


## Where the aim starts: the player's position, or the origin with no player.
func _origin() -> Vector2:
	if _player != null and _player.is_inside_tree():
		return _player.global_position
	return Vector2.ZERO


## Starts a cooldown on `slot` when it is missing a charge and none is running.
## A cooldown of 0 gives every charge back at once.
func _start_cooldown_if_idle(slot: int) -> void:
	if _cooldown_left[slot] > 0.0 or _charges[slot] >= _max_charges(slot):
		return
	_cooldown_total[slot] = effective_cooldown(slot)
	if _cooldown_total[slot] <= 0.0:
		_charges[slot] = _max_charges(slot)
		return
	_cooldown_left[slot] = _cooldown_total[slot]


func _max_charges(slot: int) -> int:
	return slots[slot].charges if slots[slot] != null else 0


func _slot_of(data: AbilityData) -> int:
	if data == null:
		return -1
	for slot: int in SLOT_COUNT:
		if slots[slot] != null and slots[slot].id == data.id:
			return slot
	return -1


func _cooldown_reduction() -> float:
	if stat_block == null:
		return 0.0
	return stat_block.get_value(StatBlock.Stat.COOLDOWN_REDUCTION)


func _valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < SLOT_COUNT


## The node whose TimeManager scale runs the cooldowns: the player, or this
## controller when it is not under one.
func _timed_node() -> Node:
	if _player != null:
		return _player
	return self
