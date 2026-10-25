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
## This peer generated a floor that does not match the host's hash, and asked the
## host for its layout as the fallback (SPEC-networking "Seed sync", W3-B3b).
## Emitted on the client that asked, before the request travels, so the request
## is observable where a single process cannot reach a real host.
signal floor_layout_requested(floor_index: int)
## A floor layout is ready to paint: this peer generated it, or applied the
## host's fallback copy. World builds the live Floor from it.
signal floor_layout_ready(layout: RefCounted)
## A server turned this client away at the door (LobbyAuth); `reason` is one of
## the REFUSED_* ids. The session is closed before this fires.
signal join_refused(reason: StringName)
## A client asked the host to revive a downed teammate (W3-B4b). Emitted on the
## asking peer before the request travels, the same way floor_layout_requested
## is, so the client half of the revive is observable where a single process
## cannot reach a real host.
signal revive_requested(target_peer_id: int)
## A client asked the host to pick the relic at `index` from the offer it
## received at a shrine (W4-B5, G10). Emitted on the asking peer before the
## request travels, the same shape as revive_requested, so the UI's call is
## observable where a single process cannot reach a real host.
signal relic_pick_requested(index: int)
## A host's `relic_choice_offered` broadcast landed on this peer: `peer_id` was
## offered `ids` at a shrine. The choice popup (ui-hud) listens; the host itself
## hears the Shrine's own node signal, so this is the client's copy of it.
signal relic_offer_received(peer_id: int, ids: Array[StringName])
## A client asked the host to use the active relic in `slot` (SPEC-relics
## "Active relics"; W4-B7, G11). Emitted on the asking peer before the request
## travels, the same shape as relic_pick_requested, so the client half is
## observable where a single process cannot reach a real host.
signal relic_activate_requested(slot: int)
## A host's `relic_activated` broadcast landed on this peer: `peer_id` used the
## active relic `relic_id` in `slot`. The HUD's cooldown sweep (G19) listens; the
## host's own screen hears the controller's node signal as well, so this is the
## other peers' copy.
signal relic_activated_received(peer_id: int, slot: int, relic_id: StringName)

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4
const REFUSED_WRONG_PASSWORD: StringName = &"wrong_password"
## How long the password handshake may take before the peer is dropped.
const AUTH_TIMEOUT_SECONDS: float = 4.0
const ENEMY_HP_PER_EXTRA_PLAYER: float = 0.5
const HOST_PEER_ID: int = 1

## The revive contract, SPEC-player-controller "Downed and revive": teammates
## hold interact within 48 px for 3 s, and the revived player comes back at 40%
## of its max HP. The numbers live here because networking owns the host revive
## rule (SPEC-run-economy: a client never revives on its own authority), while
## the hold-F input path and the `Downed`/`Dead` states are player-controller's
## (blocked on Dev A W3-A5). When that lands it calls `revive_seconds_for()` and
## `revive_hp_for()` here rather than keeping a second copy of the numbers.
const REVIVE_RANGE: float = 48.0
const REVIVE_SECONDS: float = 3.0
const REVIVE_HP_FRACTION: float = 0.4
## Smallest revive_speed_mult a hold may be scaled by. StatBlock clamps the stat
## itself; this guards the division, so a zeroed or negative modifier cannot
## stretch the hold to infinity.
const REVIVE_SPEED_MULT_MIN: float = 0.1

## Why the most recent revive request was refused, mirroring GameState's
## last_advance_refusal (W3-B1c): a refusal is a readable value as well as a log
## line, so the HUD, the debug console and the tests can all say why a teammate
## did not stand up.
const REVIVE_REFUSAL_NONE: StringName = &""
const REVIVE_REFUSAL_NOT_HOST: StringName = &"not_host"
const REVIVE_REFUSAL_NOT_A_REQUEST: StringName = &"not_a_request"
const REVIVE_REFUSAL_NO_TARGET: StringName = &"no_target"
const REVIVE_REFUSAL_TARGET_NOT_DOWNED: StringName = &"target_not_downed"
const REVIVE_REFUSAL_TARGET_DEAD: StringName = &"target_dead"
const REVIVE_REFUSAL_NO_REVIVER: StringName = &"no_reviver"
const REVIVE_REFUSAL_SELF: StringName = &"self"
const REVIVE_REFUSAL_OUT_OF_RANGE: StringName = &"out_of_range"

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
## The name this host advertises in the lobby list ("" when not hosting).
var server_name: String = ""
## Host: the hash a joiner must present. Client: the hash it presents. Empty
## means no password.
var password_hash: PackedByteArray = PackedByteArray()
var floor_seed: int = 0
## The layout this peer generated locally for that floor, or null before the
## first floor_ready. RefCounted so Dev A's FloorLayout drops in unchanged.
var last_floor_layout: RefCounted = null
## The modifiers the host named for the current floor.
var last_floor_modifiers: Array[int] = []
## The floor the current layout belongs to, so a mismatch can name it and the
## debug console can say where the run is.
var last_floor_index: int = 0
## The hash of that layout, as FloorGeneratorSeam.layout_hash_of reads it. The
## host asserts this value to every client; a client compares it with its own and
## falls back to the host's layout when they differ (W3-B3b).
var last_floor_hash: int = 0
## Why the most recent revive request was refused, REVIVE_REFUSAL_NONE when one
## was applied (or when no request has arrived). Reset by every attempt, so it
## is never stale.
var last_revive_refusal: StringName = REVIVE_REFUSAL_NONE
## Simulated latency this peer's outgoing packets should carry, in whole
## milliseconds; 0 means off. Set by the `net_lag` debug console command.
## Placeholder (W3-B5b): nothing reads these yet, so no traffic is delayed —
## W4-B11 owns the delay/drop proxy that consumes them.
## TODO(debug-tools, W4-B11): apply net_lag_ms / net_lag_loss in the packet
## proxy; the field names and units are the contract, so no call site changes.
var net_lag_ms: int = 0
## Simulated packet loss for this peer, as a percentage in 0.0..100.0. See
## net_lag_ms for the W4-B11 swap.
var net_lag_loss: float = 0.0


func _ready() -> void:
	_setup_lobby_auth()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Floor sync (SPEC-networking "Seed sync"): the host picks the run seed, and
	# every floor change sends floor_ready so each peer generates it locally.
	GameState.run_started.connect(_on_run_started)
	GameState.floor_changed.connect(_on_floor_changed)
	# Downed and revive sync (SPEC-networking week 3: "downed and revive
	# synced"). The host owns downed state, so its own bus events are what it
	# announces to the other peers; a client's emit is the broadcast landing on
	# this peer, and its handler stops at the host guard.
	Events.player_downed.connect(_on_player_downed)
	Events.player_revived.connect(_on_player_revived)


## Opens an ENet server. Refused while a session is active (call
## disconnect_all first); returns the ENet error if the port is taken.
func host(port: int = DEFAULT_PORT, p_server_name: String = "", password: String = "") -> Error:
	if is_active:
		push_warning("[net] already in a session; disconnect_all() first")
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		push_warning("[net] could not host on port %d: %s" % [port, error_string(err)])
		return err
	_activate(peer, true)
	server_name = p_server_name
	password_hash = LobbyAuth.hash_password(password)
	print("[net] hosting on port %d as peer %d" % [port, local_peer_id])
	_add_peer(local_peer_id)
	return OK


## Starts connecting. Success or failure arrives later through
## connected_to_server / connection_failed; the return value only covers
## address parsing.
func join(ip: String, port: int = DEFAULT_PORT, password: String = "") -> Error:
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
	password_hash = LobbyAuth.hash_password(password)
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
	server_name = ""
	password_hash = PackedByteArray()
	peer_ids.clear()
	players.clear()
	floor_seed = 0
	last_floor_layout = null
	last_floor_modifiers = [] as Array[int]
	last_floor_index = 0
	last_floor_hash = 0


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


# --- the relic pick flow (W4-B5, G10) ---------------------------------------

## Client -> host: pick the relic at `index` from the offer this peer received
## at a shrine (SPEC-relics "Shrine flow": "`request_pick_relic(index)`; host
## attaches via `EffectHost.add`, emits `relic_picked`, updates codex").
## The index is the only value a client contributes; the host resolves it against
## the offer that peer was actually given, so a client cannot name a relic it was
## not offered (SPEC-networking: "Never trust client values beyond ids and
## indices"). The body validates `multiplayer.get_remote_sender_id()` first, as
## every request_* does.
## Sync: host-authoritative. `RelicFlow.apply_pick_request()` is the whole rule.
@rpc("any_peer", "call_remote", "reliable")
func request_pick_relic(index: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not RelicFlow.apply_pick_request(sender, index):
		push_warning("[net] request_pick_relic refused (%s): sender %d index %d" % [
			RelicFlow.last_refusal, sender, index])


## Host -> the offered peer: the three ids a shrine rolled for `peer_id`
## (SPEC-relics "Shrine flow"). Sent to that one peer, not every peer: an offer
## is that player's choice. The host hears its shrine's own node signal; this
## broadcast is the client's copy, which the choice popup shows.
## Sync: host-authoritative, validated like every other host broadcast.
@rpc("authority", "call_local", "reliable")
func relic_choice_offered(peer_id: int, ids: Array[StringName]) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not can_accept_host_broadcast(sender):
		push_warning("[net] relic_choice_offered refused: sender %d may not offer a relic here" % sender)
		return
	apply_relic_offer(peer_id, ids)


## Host -> every peer: `peer_id` picked `relic_id` at a shrine (SPEC-relics
## "Shrine flow": "host attaches via `EffectHost.add`, emits `relic_picked`").
## The host's own `Events.relic_picked` already fired where the pick was applied;
## this is the other peers' copy, so the HUD and the synergy panel (week 8) see
## the pick on every screen.
## Sync: host-authoritative, validated like every other host broadcast.
@rpc("authority", "call_local", "reliable")
func relic_picked(peer_id: int, relic_id: StringName) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not can_accept_host_broadcast(sender):
		push_warning("[net] relic_picked refused: sender %d may not announce a pick here" % sender)
		return
	apply_relic_pick_broadcast(peer_id, relic_id)


## The client-side entry point the choice popup calls: ask the host to take the
## relic at `index`. On the host the same call applies directly, because solo and
## a hosting peer are the same code path (SPEC-networking "Solo play is a host
## with one peer"). A session with no remote host records the request and says so
## rather than faking one, exactly like `send_revive_request`.
## Sync: the host applies; a client's own call never attaches anything.
func send_pick_relic_request(index: int) -> bool:
	relic_pick_requested.emit(index)
	if is_host:
		return RelicFlow.apply_pick_request(local_peer_id, index)
	if not can_send_request():
		push_warning("[net] relic pick %d not sent: this session has no remote host to ask" % index)
		return false
	print("[net] asked the host for relic %d of the offer" % index)
	request_pick_relic.rpc_id(HOST_PEER_ID, index)
	return true


## Host only. Sends an offer to the peer it belongs to. Returns true when it went
## out; a solo host, the offering peer itself, and an unknown peer have nobody to
## tell and send nothing.
func route_relic_choice_offered(peer_id: int, ids: Array[StringName]) -> bool:
	if not _announces_player_state():
		return false
	if peer_id <= 0 or peer_id == local_peer_id or not peer_ids.has(peer_id):
		return false
	relic_choice_offered.rpc_id(peer_id, peer_id, ids)
	return true


## Host only. Announces a pick to every remote peer, the same one rpc_id per peer
## shape `route_player_downed` uses. The host's own bus event already fired in
## `RelicFlow.apply_pick_request`, so this never loops back to the host.
func route_relic_picked(player: Player, data: RelicData) -> bool:
	if not _announces_player_state() or player == null or data == null:
		return false
	var targets: Array[int] = remote_peer_ids()
	if targets.is_empty():
		return false
	for peer_id: int in targets:
		relic_picked.rpc_id(peer_id, player.peer_id, data.id)
	return true


## The receiving half of an offer: puts it on `relic_offer_received` for the
## choice popup. Returns false for an empty offer, which is not something a
## shrine produces.
func apply_relic_offer(peer_id: int, ids: Array[StringName]) -> bool:
	if ids.is_empty():
		push_warning("[net] relic offer for peer %d is empty, ignored" % peer_id)
		return false
	relic_offer_received.emit(peer_id, ids)
	print("[net] peer %d was offered %d relics" % [peer_id, ids.size()])
	return true


## The receiving half of a pick: resolves the id to its data and emits
## `Events.relic_picked` for this peer's presentation layer. The player may be
## unknown here (a payload for a peer this machine has not spawned), in which
## case the event still fires with a null player, because the id is the fact the
## HUD needs; an unknown id is refused. Returns true when emitted.
func apply_relic_pick_broadcast(peer_id: int, relic_id: StringName) -> bool:
	var data: RelicData = RelicFlow.data_for(relic_id)
	if data == null:
		push_warning("[net] relic_picked for unknown relic %s, ignored" % relic_id)
		return false
	var player: Player = get_player(peer_id)
	Events.relic_picked.emit(player, data)
	print("[net] peer %d picked %s" % [peer_id, relic_id])
	return true


# --- the active relic use (W4-B7, G11) --------------------------------------


## Client -> host: use the active relic in `slot` (SPEC-relics "Active relics":
## "slot 1 on `relic_active_1`", "`request_activate_relic(slot)`"). The slot is
## the only value a client contributes, and the host validates it against **that
## peer's own controller** — it must hold an active in the slot, have a charge and
## not be on cooldown — so a client can neither name a relic it does not hold nor
## spend a teammate's charge (SPEC-networking: "Never trust client values beyond
## ids and indices"). The body reads `multiplayer.get_remote_sender_id()` first,
## as every `request_*` does.
## Sync: host-authoritative. `ActiveRelicController.apply_activate_request()` is
## the whole rule.
@rpc("any_peer", "call_remote", "reliable")
func request_activate_relic(slot: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not ActiveRelicController.apply_activate_request(sender, slot):
		push_warning("[net] request_activate_relic refused (%s): sender %d slot %d" % [
			ActiveRelicController.last_refusal, sender, slot])


## Host -> every peer: `peer_id` used the active relic `relic_id` in `slot`. The
## host's own screen already heard the controller's `slot_activated`; this is the
## other peers' copy, so the HUD's cooldown sweep (G19) shows the use on every
## screen (SPEC-relics "Testing": "active relic use visible to both"). It
## announces a use that already happened, so it carries no charge or cooldown
## state — the host is the only peer that keeps those.
## Sync: host-authoritative, validated like every other host broadcast.
@rpc("authority", "call_local", "reliable")
func relic_activated(peer_id: int, slot: int, relic_id: StringName) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not can_accept_host_broadcast(sender):
		push_warning("[net] relic_activated refused: sender %d may not announce a use here" % sender)
		return
	apply_relic_activation(peer_id, slot, relic_id)


## The client-side entry point a press goes through: ask the host to use the
## active relic in `slot`. On the host the same call applies directly, because
## solo and a hosting peer are the same code path (SPEC-networking "Solo play is
## a host with one peer"). A session with no remote host records the request and
## says so rather than faking one, exactly like `send_pick_relic_request`.
## Sync: the host applies; a client's own call never spends a charge.
func send_activate_request(slot: int) -> bool:
	relic_activate_requested.emit(slot)
	if is_host:
		return ActiveRelicController.apply_local_activation(slot)
	if not can_send_request():
		push_warning("[net] relic activation %d not sent: this session has no remote host to ask" % slot)
		return false
	print("[net] asked the host to use the relic in slot %d" % slot)
	request_activate_relic.rpc_id(HOST_PEER_ID, slot)
	return true


## Host only. Announces a use to every remote peer, the same one rpc_id per peer
## shape `route_relic_picked` uses. The host's own screen already heard the
## controller's node signal, so this never loops back to the host.
func route_relic_activated(player: Player, slot: int, relic_id: StringName) -> bool:
	if not _announces_player_state() or player == null or relic_id == &"":
		return false
	var targets: Array[int] = remote_peer_ids()
	if targets.is_empty():
		return false
	for peer_id: int in targets:
		relic_activated.rpc_id(peer_id, player.peer_id, slot, relic_id)
	return true


## The receiving half of an activation: puts it on `relic_activated_received` for
## this peer's presentation layer. The slot and the id are the host's word, so no
## relic data is resolved here — a peer may not hold that relic's data at all, and
## the HUD needs the slot it fired from, not the relic's stats. Returns false for
## a payload that is not an activation (an empty id or a slot no controller has).
func apply_relic_activation(peer_id: int, slot: int, relic_id: StringName) -> bool:
	if relic_id == &"" or slot < 1:
		push_warning("[net] relic_activated for slot %d id %s, ignored" % [slot, relic_id])
		return false
	relic_activated_received.emit(peer_id, slot, relic_id)
	print("[net] peer %d used %s in slot %d" % [peer_id, relic_id, slot])
	return true


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
	return can_accept_floor_broadcast(sender)


## True when a host broadcast about the floor may be applied on this peer. The
## same rule covers every one of them — floor_ready, layout_asserted and the
## floor_layout fallback: the host accepts only its own local call (sender 0),
## a client accepts only the host's (peer 1). The host is the floor of record,
## so a client's call is never accepted anywhere.
func can_accept_floor_broadcast(sender: int) -> bool:
	return can_accept_host_broadcast(sender)


## True when a host -> everyone broadcast may be applied on this peer. The host
## accepts only its own local call — Godot reports sender 0 for a call_local
## invocation — and a client accepts only the host's, so a client's call is
## never accepted anywhere. One rule for every authority broadcast, the floor
## ones and the player-state ones alike.
func can_accept_host_broadcast(sender: int) -> bool:
	if is_host:
		return sender == 0
	return sender == HOST_PEER_ID


## Host -> every peer: the hash of the layout the host generated for the floor it
## just sent (SPEC-networking "Seed sync": "host hashes the layout and clients
## assert the same hash"). Every peer generates that floor locally from
## floor_ready's inputs, so the two hashes must be equal.
## Sync: host-authoritative. The host is the layout of record, so its own
## call_local invocation asserts nothing; only a client compares, and it does so
## in apply_layout_assertion.
@rpc("authority", "call_local", "reliable")
func layout_asserted(layout_hash: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not can_accept_floor_broadcast(sender):
		push_warning("[net] layout_asserted refused: sender %d may not assert a layout here" % sender)
		return
	apply_layout_assertion(layout_hash)


## Client side of the hash assertion. Agreement is a log line and nothing else:
## the peer already holds the right floor, so nothing is regenerated and no floor
## is re-announced. A mismatch logs an error, records the divergence in GameState
## and asks the host for its layout (request_floor_layout) — SPEC-networking's
## fallback. There is no retry: regenerating from the same inputs would produce
## the same wrong layout. Returns true when the hashes agreed.
func apply_layout_assertion(layout_hash: int) -> bool:
	if is_host:
		return true
	var local_hash: int = last_floor_hash
	if local_hash == layout_hash:
		print("[floor] layout asserted: floor %d layout_hash %d agrees with the host on peer %d" % [
			last_floor_index, local_hash, local_peer_id])
		return true
	push_error("[floor] layout hash mismatch on floor %d: local %d, host %d — asking the host for its layout" % [
		last_floor_index, local_hash, layout_hash])
	GameState.note_floor_divergence(last_floor_index, local_hash, layout_hash)
	_request_host_layout(last_floor_index)
	return false


## Client -> host: this peer's floor does not match the hash the host asserted, so
## it asks for the host's layout to hold instead of its own (SPEC-networking
## "Seed sync": "mismatch logs an error and requests the host's layout as a
## fallback"). The request carries no trusted value beyond the floor index.
## Sync: host-authoritative. The host validates the sender, then answers with the
## layout it generated, which is the layout of record.
@rpc("any_peer", "call_remote", "reliable")
func request_floor_layout(floor_index: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not can_serve_floor_layout_request(sender):
		push_warning("[net] request_floor_layout refused: sender %d cannot be served a layout here" % sender)
		return
	var layout: RefCounted = last_floor_layout
	if layout == null:
		push_warning("[net] request_floor_layout for floor %d refused: no layout to send" % floor_index)
		return
	var wire: Dictionary = FloorGeneratorSeam.serialize_layout(layout)
	if wire.is_empty():
		push_warning("[net] request_floor_layout for floor %d refused: the layout has no wire form" % floor_index)
		return
	if floor_index != last_floor_index:
		push_warning("[net] request_floor_layout named floor %d; this peer is on floor %d and sends that one" % [
			floor_index, last_floor_index])
	floor_layout.rpc_id(sender, last_floor_index, last_floor_hash, wire)


## Host -> the asking client: the host's own layout for the floor it is on, so a
## client whose generation diverged plays the host's floor instead of its own
## (SPEC-networking "Seed sync" fallback).
## Sync: host-authoritative. The host is the layout of record; a client only ever
## applies what it is sent, and never regenerates to get there.
@rpc("authority", "call_local", "reliable")
func floor_layout(floor_index: int, layout_hash: int, layout: Dictionary) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not can_accept_floor_broadcast(sender):
		push_warning("[net] floor_layout refused: sender %d may not send a layout here" % sender)
		return
	apply_host_layout(floor_index, layout_hash, layout)


## Client side of the fallback: holds the host's layout and its hash, so this
## peer's floor is the host's floor. Nothing is generated here — the wire form
## carries the host's rooms — and no floor is re-announced, because the client
## already followed that floor from floor_ready. An unusable payload leaves the
## peer exactly where it was rather than crashing the run.
func apply_host_layout(floor_index: int, layout_hash: int, layout: Dictionary) -> RefCounted:
	if is_host:
		push_warning("[net] apply_host_layout refused: the host is the layout of record")
		return null
	var applied: RefCounted = FloorGeneratorSeam.deserialize_layout(layout)
	if applied == null:
		push_warning("[net] floor %d arrived without a usable layout; keeping the local one" % floor_index)
		return null
	last_floor_layout = applied
	last_floor_hash = layout_hash
	last_floor_index = floor_index
	print("[floor] applied the host's layout for floor %d — layout_hash %d on peer %d" % [
		floor_index, layout_hash, local_peer_id])
	floor_layout_ready.emit(applied)
	return applied


## Client side. Asks the host for its layout. Sent as an RPC rather than a local
## call, because the local call would run this peer's own host-side handler. A
## session with no remote host (solo, a single-process test) cannot send one, so
## the request is recorded and reported instead.
func _request_host_layout(floor_index: int) -> void:
	floor_layout_requested.emit(floor_index)
	if not can_send_request():
		push_warning("[floor] layout request for floor %d not sent: this session has no remote host to ask" % floor_index)
		return
	print("[floor] requested the host's layout for floor %d" % floor_index)
	rpc_id(HOST_PEER_ID, &"request_floor_layout", floor_index)


## Host only. Sends the floor every peer generates locally, then the hash of the
## layout it produced so each client can assert its own against it (W3-B3b). The
## host applies the floor here too, so solo and co-op run the identical one-call
## path; remote peers get it through rpc_id, so the host never generates the same
## floor twice.
func broadcast_floor_ready(seed: int, floor_index: int, biome_id: int, modifiers: Array[int] = []) -> bool:
	if not is_host:
		push_warning("[net] broadcast_floor_ready refused: only the host declares a floor")
		return false
	apply_floor_ready(seed, floor_index, biome_id, modifiers)
	for peer_id: int in peer_ids:
		if peer_id == local_peer_id:
			continue
		floor_ready.rpc_id(peer_id, seed, floor_index, biome_id, modifiers)
		layout_asserted.rpc_id(peer_id, last_floor_hash)
	return true


## Generates `floor_index` locally from the host's seed and records it. Every
## peer runs this on the same inputs, which is what makes one seed one floor.
## On a client it also tells GameState which floor the host is on — a client has
## no RunState, so that signal is how the HUD follows — while the host has
## already emitted floor_changed from its own run state.
func apply_floor_ready(seed: int, floor_index: int, biome_id: int, modifiers: Array[int]) -> RefCounted:
	floor_seed = seed
	last_floor_index = floor_index
	last_floor_modifiers.assign(modifiers)
	var layout: RefCounted = FloorGeneratorSeam.generate(seed, floor_index, biome_id, modifiers)
	last_floor_layout = layout
	last_floor_hash = FloorGeneratorSeam.layout_hash_of(layout)
	print("[floor] ready seed %d floor %d biome %d — layout_hash %d from %s on peer %d" % [
		seed, floor_index, biome_id, last_floor_hash,
		FloorGeneratorSeam.source_of(layout), local_peer_id])
	if not is_host:
		GameState.apply_remote_floor(floor_index, biome_id, modifiers)
	floor_layout_ready.emit(layout)
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


## True when a floor-layout request from `sender` may be served on this peer:
## this peer hosts, and the request arrived from a remote client. A direct local
## call has sender 0 and is not a client's request — the host has no reason to
## ask itself for its own layout — so it is refused like every other request_*.
func can_serve_floor_layout_request(sender: int) -> bool:
	return is_host and sender != 0


# --- downed and revive sync (W3-B4a) ----------------------------------------

## Host -> every peer: peer `peer_id` went down (SPEC-player-controller's downed
## state; SPEC-networking's week 3 row "downed and revive synced"). The downed
## flag also replicates through StateSync, but a flag flip tells a client nothing
## about *when* it happened — this broadcast is what puts the down on a client's
## Events bus, so its HUD marks the teammate downed and run-economy's all-downed
## rule sees it.
## Sync: host-authoritative. A client never announces a down; the sender is
## validated first, so a client's own local call applies nothing.
@rpc("authority", "call_local", "reliable")
func broadcast_player_downed(peer_id: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not can_accept_host_broadcast(sender):
		push_warning("[net] broadcast_player_downed refused: sender %d may not be applied on this peer" % sender)
		return
	apply_player_downed(peer_id)


## Host -> every peer: peer `peer_id` stood back up, revived by `by_peer_id`.
## `by_peer_id` is 0 when nobody is named (a self-revive, a Second Wind, a
## next-floor revive), which is why it travels as an id rather than as an
## argument a client could not resolve.
## Sync: host-authoritative, validated exactly like the down above.
@rpc("authority", "call_local", "reliable")
func broadcast_player_revived(peer_id: int, by_peer_id: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not can_accept_host_broadcast(sender):
		push_warning("[net] broadcast_player_revived refused: sender %d may not be applied on this peer" % sender)
		return
	apply_player_revived(peer_id, by_peer_id)


## The receiving half of a down: sets the downed flag on this peer's copy of the
## player and emits Events.player_downed, so this peer reacts to the host's
## decision through the same bus signal the host reacted to. Returns false when
## this peer knows no such player.
func apply_player_downed(peer_id: int) -> bool:
	var player: Player = get_player(peer_id)
	if player == null:
		push_warning("[net] player_downed for peer %d: no such player on this peer" % peer_id)
		return false
	player.is_downed = true
	Events.player_downed.emit(player)
	print("[net] peer %d is downed" % peer_id)
	return true


## The receiving half of a revive. `by_peer_id` 0 means no reviver is named, and
## the event then carries no `by` player. `is_downed` is the single flag, so
## every route a revive can arrive by — the host applying a request (W3-B4b), a
## client taking the host's broadcast — stands the player up the same way and at
## the same moment. Adding a new route is what would be the bug: a peer with a
## downed-looking teammate that already stands.
func apply_player_revived(peer_id: int, by_peer_id: int) -> bool:
	var player: Player = get_player(peer_id)
	if player == null:
		push_warning("[net] player_revived for peer %d: no such player on this peer" % peer_id)
		return false
	var reviver: Player = get_player(by_peer_id)
	player.is_downed = false
	# The player's own signal names who did it; only a revive knows that, which
	# is why the downed setter leaves it to this path (W3-B4a's note).
	player.revived.emit(reviver)
	Events.player_revived.emit(player, reviver)
	if by_peer_id == 0:
		print("[net] peer %d is standing again" % peer_id)
	else:
		print("[net] peer %d is standing again, revived by peer %d" % [peer_id, by_peer_id])
	return true


## Host only. Announces `player`'s down to every remote peer. The host's own copy
## is already down — it is where the event came from — so the broadcast targets
## the remotes only, one rpc_id per peer exactly like broadcast_floor_ready, and
## the host never applies its own down twice. Returns true when it went out; a
## solo host has nobody to tell and sends nothing, silently.
func route_player_downed(player: Player) -> bool:
	if not _can_route_player_state(player):
		return false
	var targets: Array[int] = remote_peer_ids()
	if targets.is_empty():
		return false  # solo host: the peer that went down is the only one there
	for peer_id: int in targets:
		broadcast_player_downed.rpc_id(peer_id, player.peer_id)
	return true


## Host only. The revive's route to every remote peer, the same shape as the
## down's. `by` is the player that did the reviving, or null when nobody is
## named.
func route_player_revived(player: Player, by: Player) -> bool:
	if not _can_route_player_state(player):
		return false
	var by_peer_id: int = 0
	if by != null:
		by_peer_id = by.peer_id
	var targets: Array[int] = remote_peer_ids()
	if targets.is_empty():
		return false
	for peer_id: int in targets:
		broadcast_player_revived.rpc_id(peer_id, player.peer_id, by_peer_id)
	return true


## Every known peer except this one: exactly the peers a host broadcast has to
## reach. Solo and an inactive session both give an empty list, which is what
## makes "nobody to tell" one code path across every session shape.
func remote_peer_ids() -> Array[int]:
	var targets: Array[int] = []
	for peer_id: int in peer_ids:
		if peer_id != local_peer_id:
			targets.append(peer_id)
	return targets


## True when this peer announces player state to the others: the host role and
## the transport behind it both have to say so (an authority RPC sent from
## anywhere else is refused by every receiver).
func _announces_player_state() -> bool:
	return is_host and multiplayer.is_server()


## True when this peer may announce a player's downed state: this peer is the
## host (SPEC-player-controller "Multiplayer ownership"), and the event has to
## name a player. A refusal warns, because a silent no-op here would look like a
## broadcast that nobody received.
func _can_route_player_state(player: Player) -> bool:
	if not _announces_player_state():
		push_warning("[net] player state not broadcast: the host owns downed state")
		return false
	if player == null:
		push_warning("[net] player state not broadcast: the event named no player")
		return false
	return true


## The host's own downed event. Only the host announces one: on a client this
## signal is the broadcast landing here, and echoing it back up would loop. The
## guard is silent for that reason — the refusal warning belongs to the public
## route, which a direct caller uses.
func _on_player_downed(player: Player) -> void:
	if _announces_player_state():
		route_player_downed(player)


## The host's own revived event, routed like the down above.
func _on_player_revived(player: Player, by: Player) -> void:
	if _announces_player_state():
		route_player_revived(player, by)


# --- the revive request (W3-B4b) --------------------------------------------

## Client -> host: peer `target_peer_id`'s downed teammate is being revived by
## the caller (SPEC-player-controller's `request_revive`, the client half of
## "teammates hold interact within 48 px for 3 s to revive to 40% HP"). The
## request carries ids only: the host decides whether the revive happens, and a
## client never revives on its own authority (SPEC-run-economy).
## Sync: host-authoritative. The sender is validated first, so a peer cannot
## revive by calling this on itself; the host then applies through
## apply_revive_request, which is the rule this RPC is a thin wrapper around.
@rpc("any_peer", "call_remote", "reliable")
func request_revive(target_peer_id: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	var target: Player = get_player(target_peer_id)
	if not apply_revive_request(sender, target):
		_log_revive_refusal(last_revive_refusal, sender, target_peer_id)


## The client half. The acting client asks the host to revive `target_peer_id`,
## which is SPEC-player-controller's `Player.request_revive(target)` by the time
## it reaches here. Sent as an RPC rather than a local call, because a local call
## would run this peer's own host-side handler; a session with no remote host
## (solo, a hosting peer, a single-process test) cannot send one, so the request
## is recorded and reported instead of being dropped silently. Returns true when
## it travelled.
func send_revive_request(target_peer_id: int) -> bool:
	revive_requested.emit(target_peer_id)
	if not can_send_request():
		push_warning("[net] revive request for peer %d not sent: this session has no remote host to ask" % target_peer_id)
		return false
	print("[net] asked the host to revive peer %d" % target_peer_id)
	request_revive.rpc_id(HOST_PEER_ID, target_peer_id)
	return true


## True when a revive request from `sender` may be applied on this peer. The
## readable form of that answer is revive_refusal_reason(); this seam is the
## one-line predicate every caller reads.
func can_apply_revive_request(sender: int, target: Player) -> bool:
	return revive_refusal_reason(sender, target) == REVIVE_REFUSAL_NONE


## Host only. Applies a revive request that passed the rule: the target stands
## up through apply_player_revived, which sets the flag, emits the target's own
## `revived(by)` and puts Events.player_revived on the bus — that bus event is
## what routes the revive to every other peer (W3-B4a's router) and what clears
## the run slice's downed flag (GameState). So a revive reaches a client by
## exactly the path a down does, and the host is the only peer that starts it.
## Records why in `last_revive_refusal` and returns false when the request is
## refused. `sender` is the reviver's peer id; 0 means nobody.
func apply_revive_request(sender: int, target: Player) -> bool:
	var reason: StringName = revive_refusal_reason(sender, target)
	last_revive_refusal = reason
	if reason != REVIVE_REFUSAL_NONE:
		return false
	apply_player_revived(target.peer_id, sender)
	print("[net] peer %d revived peer %d" % [sender, target.peer_id])
	return true


## Why a revive request from `sender` for `target` cannot be applied here, or
## REVIVE_REFUSAL_NONE when it can. The whole host revive rule in one place, so
## the RPC, the seam and the tests share it rather than each restating it:
##  * the host owns the revive, and only a request that arrived from a remote
##    peer is a client's request (a direct local call reports sender 0);
##  * the target has to exist and be downed — a standing teammate has nothing to
##    revive, and a teammate already dead is dead for the rest of the floor
##    (SPEC-player-controller; the next-floor revive is week 5);
##  * the caller needs a player of its own, has to be a teammate rather than the
##    downed player itself, and has to be standing within REVIVE_RANGE — the
##    spec's 48 px hold.
func revive_refusal_reason(sender: int, target: Player) -> StringName:
	if not is_host:
		return REVIVE_REFUSAL_NOT_HOST
	if sender == 0:
		return REVIVE_REFUSAL_NOT_A_REQUEST
	if target == null:
		return REVIVE_REFUSAL_NO_TARGET
	if not target.is_downed:
		return REVIVE_REFUSAL_TARGET_NOT_DOWNED
	if _run_slice_is_dead(target):
		return REVIVE_REFUSAL_TARGET_DEAD
	var reviver: Player = get_player(sender)
	if reviver == null:
		return REVIVE_REFUSAL_NO_REVIVER
	if reviver == target:
		return REVIVE_REFUSAL_SELF
	if revive_distance(reviver, target) > REVIVE_RANGE:
		return REVIVE_REFUSAL_OUT_OF_RANGE
	return REVIVE_REFUSAL_NONE


## The distance between a reviver and the teammate it is reviving, in the space
## players share: every player is a child of World/Players, so their local
## positions are already comparable, and a player double that never entered the
## tree has no global transform to read (and reading one would be an error).
func revive_distance(reviver: Player, target: Player) -> float:
	return reviver.position.distance_to(target.position)


## True when the live run already has `player` down as dead this floor. A run is
## host-only, so this reads the host's own slices; with no run live there is
## nothing recorded and the answer is false.
func _run_slice_is_dead(player: Player) -> bool:
	if player == null or GameState.run == null:
		return false
	var slice: RunPlayerState = GameState.run.get_player(player.peer_id)
	return slice != null and slice.is_dead


## How long the revive hold lasts for a given reviver: the spec's 3 s divided by
## the holder's revive_speed_mult (Field Medic, Sanctuary). The floor keeps a
## zeroed or negative multiplier from dividing the hold into infinity, and a
## missing reviver gets the base hold.
static func revive_seconds_for(reviver: Player) -> float:
	if reviver == null:
		return REVIVE_SECONDS
	return REVIVE_SECONDS / maxf(reviver.revive_speed_mult, REVIVE_SPEED_MULT_MIN)


## The HP a revive restores for an entity with `max_hp`: the spec's 40%, rounded
## to a whole HP and never below 1, so a revive cannot come back at 0. The write
## itself is Dev A's Health (blocked on Dev A W2-A1): this is the number their
## revive path applies.
static func revive_hp_for(max_hp: int) -> int:
	return maxi(1, int(roundf(float(max_hp) * REVIVE_HP_FRACTION)))


## One readable line naming who asked, what for and why not. A refusal that
## leaves no reason behind is indistinguishable from a request nobody sent.
func _log_revive_refusal(reason: StringName, sender: int, target_peer_id: int) -> void:
	push_warning("[net] revive refused (%s): peer %d asked to revive peer %d" % [
		reason, sender, target_peer_id])


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
## that peer rather than making it wait for the next floor. The hash assertion
## travels with it, because a late joiner generates the floor the same way
## everyone else did and must be able to check it.
func _send_floor_to_late_joiner(peer_id: int) -> void:
	if not is_host or GameState.run == null or floor_seed == 0:
		return
	var modifiers: Array[int] = FloorGeneratorSeam.roll_modifiers(floor_seed, GameState.run.floor_index)
	floor_ready.rpc_id(peer_id, floor_seed, GameState.run.floor_index, GameState.run.biome_index, modifiers)
	layout_asserted.rpc_id(peer_id, last_floor_hash)
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


# --- lobby password handshake (LobbyAuth) ---------------------------------------


func _setup_lobby_auth() -> void:
	var scene_mp := multiplayer as SceneMultiplayer
	if scene_mp == null:
		return
	scene_mp.auth_callback = _on_auth_data
	scene_mp.auth_timeout = AUTH_TIMEOUT_SECONDS
	scene_mp.peer_authenticating.connect(_on_peer_authenticating)


## A peer is mid-handshake. The joining client speaks first with its password
## hash; the host only answers.
func _on_peer_authenticating(peer_id: int) -> void:
	if is_host:
		return
	(multiplayer as SceneMultiplayer).send_auth(peer_id, password_hash)


## Handshake data from `peer_id`. Host: check the presented hash, answer ok or
## no. Client: the host's answer.
func _on_auth_data(peer_id: int, data: PackedByteArray) -> void:
	var scene_mp := multiplayer as SceneMultiplayer
	if is_host:
		if LobbyAuth.accepts(password_hash, data):
			print("[net] peer %d passed the password check" % peer_id)
			scene_mp.send_auth(peer_id, LobbyAuth.OK)
			scene_mp.complete_auth(peer_id)
		else:
			print("[net] peer %d refused: wrong password" % peer_id)
			scene_mp.send_auth(peer_id, LobbyAuth.DENY)
		return
	if data == LobbyAuth.OK:
		scene_mp.complete_auth(peer_id)
	else:
		join_refused_pending(REFUSED_WRONG_PASSWORD)


## Client: the door was shut. Closes the session next frame (this runs inside
## the engine's auth callback) and tells the lobby why.
func join_refused_pending(reason: StringName) -> void:
	call_deferred(&"_finish_refusal", reason)


func _finish_refusal(reason: StringName) -> void:
	disconnect_all()
	join_refused.emit(reason)
