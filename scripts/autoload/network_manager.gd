extends Node
## Hosting, joining, peer tracking, and the player registry. Owned by
## networking (SPEC-networking). Player spawning itself is PlayerSpawner
## (W1-B8), driven by player_joined / player_left from here.
## Sync: this module defines the rule. Host decides, clients present. Inputs
## go up through InputSync, state comes down through StateSync, spawns go
## through spawners, requests are validated RPCs named request_*.
##
## Solo play is a host with one peer (OfflineMultiplayerPeer), so there is
## no separate single-player code path.

signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal connection_failed(reason: String)
signal host_disconnected()
## A client asked the host to run a debug console line on its behalf
## (SPEC-debug-tools). The debug console listens and executes; it is absent in
## release exports, where nothing listens and the request is a no-op.
signal debug_command_requested(command_line: String, peer_id: int)

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4
const ENEMY_HP_PER_EXTRA_PLAYER: float = 0.5
const HOST_PEER_ID: int = 1

## True while hosting, in solo, or while joining / joined.
var is_active: bool = false
## True when multiplayer.is_server(); also true in solo.
var is_host: bool = false
var local_peer_id: int = 0
## Every known peer including the host, in join order.
var peer_ids: Array[int] = []
## peer_id -> Player node, filled by PlayerSpawner as spawns complete.
var players: Dictionary[int, Player] = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Opens an ENet server. Refused while a session is active (call
## disconnect_all first); returns the ENet error if the port is taken.
func host(port: int = DEFAULT_PORT) -> Error:
	if is_active:
		push_warning("[net] already in a session; disconnect_all() first")
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		push_warning("[net] could not host on port %d: %s" % [port, error_string(err)])
		return err
	_activate(peer, true)
	print("[net] hosting on port %d as peer %d" % [port, local_peer_id])
	_add_peer(local_peer_id)
	return OK


## Starts connecting. Success or failure arrives later through
## connected_to_server / connection_failed; the return value only covers
## address parsing.
func join(ip: String, port: int = DEFAULT_PORT) -> Error:
	if is_active:
		push_warning("[net] already in a session; disconnect_all() first")
		return ERR_ALREADY_IN_USE
	if not looks_like_address(ip):
		push_warning("[net] '%s' is not an address" % ip)
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_warning("[net] could not start joining %s:%d: %s" % [ip, port, error_string(err)])
		return err
	_activate(peer, false)
	print("[net] joining %s:%d" % [ip, port])
	return OK


## Offline server, same code path as host.
func start_solo() -> void:
	_activate(OfflineMultiplayerPeer.new(), true)
	print("[net] solo session as peer %d" % local_peer_id)
	_add_peer(local_peer_id)


## Closes any session and returns to an inactive offline peer.
func disconnect_all() -> void:
	var current := multiplayer.multiplayer_peer
	if current != null and not (current is OfflineMultiplayerPeer):
		current.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_active = false
	is_host = false
	local_peer_id = 0
	peer_ids.clear()
	players.clear()


func get_player(peer_id: int) -> Player:
	return players.get(peer_id)


func player_count() -> int:
	return peer_ids.size()


func enemy_hp_multiplier() -> float:
	return enemy_hp_multiplier_for(player_count())


## Client -> host: asks the host to run a debug console command line on behalf
## of `peer_id` (SPEC-debug-tools). The host validates that the caller really
## is that peer, then emits debug_command_requested for the local debug
## console to execute. In a release export the console is excluded, so the
## signal has no listener and the request is a no-op.
## Sync: host-authoritative — clients never run commands; the host validates
## the sender and applies.
@rpc("any_peer", "call_remote", "reliable")
func request_debug(command_line: String, peer_id: int) -> void:
	if not is_host:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		push_warning("[net] request_debug refused: sender %d != claimed peer %d" % [multiplayer.get_remote_sender_id(), peer_id])
		return
	debug_command_requested.emit(command_line, peer_id)


## 1.0 + 0.5 per player beyond the first; never below solo.
static func enemy_hp_multiplier_for(count: int) -> float:
	return 1.0 + ENEMY_HP_PER_EXTRA_PLAYER * maxi(count - 1, 0)


## An IP or a hostname (tunnel services like playit.gg hand out hostnames,
## which ENet resolves). Rejects empty strings and anything with whitespace.
static func looks_like_address(ip: String) -> bool:
	var trimmed := ip.strip_edges()
	if trimmed.is_empty() or trimmed != ip:
		return false
	for ch: String in [" ", "\t", "\n"]:
		if ip.contains(ch):
			return false
	return true


func _activate(peer: MultiplayerPeer, as_host: bool) -> void:
	disconnect_all()
	multiplayer.multiplayer_peer = peer
	is_active = true
	is_host = as_host
	local_peer_id = multiplayer.get_unique_id()


func _add_peer(peer_id: int) -> void:
	if peer_ids.has(peer_id):
		return
	peer_ids.append(peer_id)
	print("[net] peer %d joined (%d total)" % [peer_id, peer_ids.size()])
	player_joined.emit(peer_id)


func _remove_peer(peer_id: int) -> void:
	if not peer_ids.has(peer_id):
		return
	peer_ids.erase(peer_id)
	players.erase(peer_id)
	print("[net] peer %d left (%d total)" % [peer_id, peer_ids.size()])
	player_left.emit(peer_id)


func _on_peer_connected(peer_id: int) -> void:
	_add_peer(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	_remove_peer(peer_id)


func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	print("[net] connected to host as peer %d" % local_peer_id)
	_add_peer(HOST_PEER_ID)
	_add_peer(local_peer_id)


func _on_connection_failed() -> void:
	push_warning("[net] connection failed")
	disconnect_all()
	connection_failed.emit("could not reach the host")


func _on_server_disconnected() -> void:
	push_warning("[net] host disconnected")
	disconnect_all()
	host_disconnected.emit()
