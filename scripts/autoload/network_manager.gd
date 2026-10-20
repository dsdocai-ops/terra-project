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
## The seed every peer generated the current floor from: the last floor_ready.
var floor_seed: int = 0
## The layout this peer generated locally for that floor, or null before the
## first floor_ready. RefCounted so Dev A's FloorLayout drops in unchanged.
var last_floor_layout: RefCounted = null
## The modifiers the host named for the current floor.
var last_floor_modifiers: Array[int] = []


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Floor sync (SPEC-networking "Seed sync"): the host picks the run seed, and
	# every floor change sends floor_ready so each peer generates it locally.
	GameState.run_started.connect(_on_run_started)
	GameState.floor_changed.connect(_on_floor_changed)


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
	floor_seed = 0
	last_floor_layout = null
	last_floor_modifiers = [] as Array[int]


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


## Client -> host: the acting client used the extraction rope and votes yes.
## Week 3 ships the transport the rope needs; the tally itself (every living
## player agrees, a `no` cancels, the rope_vote_updated broadcast) is the week-5
## vote prompt (SPEC-run-economy), so the host records the vote through
## GameState.request_extract_vote, which is still the week-5 deferral.
## Sync: host-authoritative — clients never extract. The host validates the
## sender against the transport and applies; a client's own call applies nothing.
@rpc("any_peer", "call_remote", "reliable")
func request_vote_rope(yes: bool) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not can_apply_rope_request(sender):
		push_warning("[net] request_vote_rope refused: sender %d cannot apply a rope use here" % sender)
		return
	GameState.request_extract_vote(sender, yes)


## Host -> every peer: the floor about to be played, and the seed it comes from
## (SPEC-networking "Seed sync"). Every peer runs FloorGenerator.generate()
## locally with these inputs and must produce the same layout; the hash
## assertion that follows is W3-B3b. Sent when the run starts — floor 1 is ready
## before anyone moves — and again on every floor change, on the same run seed.
## Sync: host-authoritative. The sender is validated first: on the host only its
## own local authority call may apply (Godot reports sender 0 for a call_local
## invocation, so a client's floor_ready is refused), and on a client only the
## host's broadcast may.
@rpc("authority", "call_local", "reliable")
func floor_ready(seed: int, floor_index: int, biome_id: int, modifiers: Array[int]) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not can_accept_floor_ready(sender):
		push_warning("[net] floor_ready refused: sender %d may not declare a floor here" % sender)
		return
	apply_floor_ready(seed, floor_index, biome_id, modifiers)


## True when a floor_ready may be applied on this peer. The host accepts only
## its own local broadcast (sender 0); a client accepts only the host's (peer 1).
func can_accept_floor_ready(sender: int) -> bool:
	if is_host:
		return sender == 0
	return sender == HOST_PEER_ID


## Host only. Sends the floor every peer generates locally. The host applies it
## here too, so solo and co-op run the identical one-call path; remote peers get
## it through rpc_id, so the host never generates the same floor twice.
func broadcast_floor_ready(seed: int, floor_index: int, biome_id: int, modifiers: Array[int] = []) -> bool:
	if not is_host:
		push_warning("[net] broadcast_floor_ready refused: only the host declares a floor")
		return false
	apply_floor_ready(seed, floor_index, biome_id, modifiers)
	for peer_id: int in peer_ids:
		if peer_id == local_peer_id:
			continue
		floor_ready.rpc_id(peer_id, seed, floor_index, biome_id, modifiers)
	return true


## Generates `floor_index` locally from the host's seed and records it. Every
## peer runs this on the same inputs, which is what makes one seed one floor.
## On a client it also tells GameState which floor the host is on — a client has
## no RunState, so that signal is how the HUD follows — while the host has
## already emitted floor_changed from its own run state.
func apply_floor_ready(seed: int, floor_index: int, biome_id: int, modifiers: Array[int]) -> RefCounted:
	floor_seed = seed
	last_floor_modifiers.assign(modifiers)
	var layout: RefCounted = FloorGeneratorSeam.generate(seed, floor_index, biome_id, modifiers)
	last_floor_layout = layout
	print("[floor] ready seed %d floor %d biome %d — layout_hash %d from %s on peer %d" % [
		seed, floor_index, biome_id, FloorGeneratorSeam.layout_hash_of(layout),
		FloorGeneratorSeam.source_of(layout), local_peer_id])
	if not is_host:
		GameState.apply_remote_floor(floor_index, biome_id, modifiers)
	return layout


## The host's run began, so floor 1 is ready. A client never runs this: it never
## owns a run and gets floor 1 from the broadcast like every other floor.
func _on_run_started(run_seed: int) -> void:
	if not is_host or GameState.run == null:
		return
	broadcast_floor_ready(run_seed, GameState.run.floor_index, GameState.run.biome_index)


## The host advanced a floor, so it goes out to every peer on the same run seed.
## A client's own floor_changed (from the host's broadcast) stops at the host
## guard, so the client cannot echo a floor back up.
func _on_floor_changed(floor_index: int, _biome: Resource) -> void:
	if not is_host or GameState.run == null:
		return
	var modifiers: Array[int] = FloorGeneratorSeam.roll_modifiers(GameState.run.seed, floor_index)
	broadcast_floor_ready(GameState.run.seed, floor_index, GameState.run.biome_index, modifiers)


## True when this peer is a joined client, so a request_* RPC actually travels
## to the host. Solo, a hosting peer, and a session with no real remote peer
## (an offline peer, a single-process test) all report false: there is no
## remote host to ask, and sending to the local peer with call_remote would be
## an error rather than a request.
func can_send_request() -> bool:
	return is_active and not is_host and not multiplayer.is_server()


## True when a rope request from `sender` may be applied on this peer: this peer
## hosts, and the request arrived from a remote client. A direct local call has
## sender 0 and is not a client's request, so it is refused — the host's own
## rope use goes through Rope._apply_use, never through the client request path.
func can_apply_rope_request(sender: int) -> bool:
	return is_host and sender != 0


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
	_send_floor_to_late_joiner(peer_id)


## A peer that joined after the run started missed the floor broadcast, and
## deterministic generation means the floor is fully described by
## (seed, floor_index, biome_id, modifiers) — so the host just sends it again to
## that peer rather than making it wait for the next floor.
func _send_floor_to_late_joiner(peer_id: int) -> void:
	if not is_host or GameState.run == null or floor_seed == 0:
		return
	var modifiers: Array[int] = FloorGeneratorSeam.roll_modifiers(floor_seed, GameState.run.floor_index)
	floor_ready.rpc_id(peer_id, floor_seed, GameState.run.floor_index, GameState.run.biome_index, modifiers)
	print("[floor] sent floor %d to late-joining peer %d" % [GameState.run.floor_index, peer_id])


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
