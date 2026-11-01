extends GutTest
## Integration: the ultimate meter over a real ENet pair (SPEC-abilities
## "UltimateController", W5-G6). Both peers run in this one process, each on its own
## SceneMultiplayer subtree, joined by a socket, as in test_ability_two_peer.gd. The
## host charges the client's player and the client reads the value over the reliable
## RPC; a client's press reaches the host; a press from a peer that does not own the
## player is refused; a client-side hit charges nothing; a non-finite meter packet is
## dropped. Owned by abilities. One pair serves every case, because a second pair
## built after the first one's teardown logs a synchronizer root_path error.

const PORT: int = 7814
const HOST_ROOT: String = "HostSide"
const CLIENT_ROOT: String = "ClientSide"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const PLAYER_NAME: String = "Fixture"
const CONNECT_FRAMES: int = 300
const STRANGER_PEER_ID: int = 999
const METER_CAP: float = 100.0

var _server: ENetMultiplayerPeer
var _client: ENetMultiplayerPeer
var _host_root: Node
var _client_root: Node
var _host_ultimate: UltimateController
var _client_ultimate: UltimateController
var _host_player: Player
var _client_player: Player
var _default_api: MultiplayerAPI


func before_each() -> void:
	_default_api = get_multiplayer()


## The sides are freed while their own SceneMultiplayer is still set, so the
## synchronizers unhook from the API they registered with. Then the default API
## goes back on each root.
func after_each() -> void:
	GameState.run = null
	var roots: Array[Node] = [_host_root, _client_root]
	for root: Node in roots:
		if is_instance_valid(root):
			var root_path := root.get_path()
			root.free()
			get_tree().set_multiplayer(_default_api, root_path)
	if _client != null:
		_client.close()
	if _server != null:
		_server.close()


## Builds both sides and connects them. Returns false when the socket never comes up.
func _connect_pair() -> bool:
	_server = ENetMultiplayerPeer.new()
	if _server.create_server(PORT) != OK:
		return false
	_client = ENetMultiplayerPeer.new()
	if _client.create_client("127.0.0.1", PORT) != OK:
		return false
	_host_root = _side(HOST_ROOT, _server)
	_client_root = _side(CLIENT_ROOT, _client)
	for _frame: int in CONNECT_FRAMES:
		await get_tree().process_frame
		if _client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
	return _client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## One peer's subtree: a real player.tscn with its UltimateController, under its own
## SceneMultiplayer. Processing is off on the player, so no frame moves the meter
## between the test's awaits.
func _side(root_name: String, peer: MultiplayerPeer) -> Node:
	var root := Node.new()
	root.name = root_name
	add_child(root)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	player.name = PLAYER_NAME
	root.add_child(player)
	player.set_physics_process(false)
	var ultimate := player.get_node("UltimateController") as UltimateController
	ultimate.set_physics_process(false)
	if root_name == HOST_ROOT:
		_host_player = player
		_host_ultimate = ultimate
	else:
		_client_player = player
		_client_ultimate = ultimate
	return root


## A stand-in enemy for the client-side hit: a node with a Health child.
func _make_target() -> Node2D:
	var target := Node2D.new()
	target.add_child(Health.new())
	add_child_autofree(target)
	return target


func _ultimate_data() -> AbilityData:
	var data := AbilityData.new()
	data.id = &"cave_in_fixture"
	data.is_ultimate = true
	return data


## Waits until the client's meter equals `value`, or the frame budget runs out.
func _wait_for_client_meter(value: float) -> void:
	for _frame: int in CONNECT_FRAMES:
		await get_tree().process_frame
		if is_equal_approx(_client_ultimate.meter, value):
			return


## All cases share one connected pair, in this order: the client-side hit charges
## nothing, the host's charge reaches the client, a non-finite RPC is dropped, the
## owner's press spends on both screens, and a stranger's press is refused.
func test_the_meter_crosses_the_wire_and_the_press_is_checked_by_the_host() -> void:
	assert_true(await _connect_pair(), "the client connects to the host in this process")
	_host_player.peer_id = _client.get_unique_id()
	_host_ultimate.assign_ultimate(_ultimate_data())
	watch_signals(Events)

	# A hit the client's own copy is credited with. Only the host may charge, so the
	# client's copy and the host's copy both stay at zero.
	var hit := HitInfo.new()
	hit.final_damage = 50
	hit.source = _client_player
	hit.owner_player = _client_player
	hit.target = _make_target()
	Events.hit_landed.emit(hit)
	await get_tree().process_frame
	assert_eq(_client_ultimate.meter, 0.0, "a client-side hit charges nothing on the client")
	assert_eq(_host_ultimate.meter, 0.0, "the host does not credit a hit owned by the client's player")

	# The client reports connected before the host has registered the join. A push
	# sent in that gap has no peer to go to, so wait until the host's side lists it.
	for _frame: int in CONNECT_FRAMES:
		await get_tree().process_frame
		if _host_player.multiplayer.get_peers().has(_client.get_unique_id()):
			break

	# The host charges the client's player, and the value reaches the client.
	_host_ultimate.charge(40.0)
	await _wait_for_client_meter(40.0)
	assert_eq(_client_ultimate.meter, 40.0, "the host's meter reaches the client over the reliable RPC")

	# A non-finite value from the host is dropped, so the client keeps 40.
	_host_ultimate._remote_set_meter.rpc_id(_client.get_unique_id(), NAN)
	for _frame: int in 30:
		await get_tree().process_frame
	assert_eq(_client_ultimate.meter, 40.0, "a NaN meter packet is dropped on the client")

	# A meter value a client sends to the host is ignored: only the host sets it.
	_client_ultimate._remote_set_meter.rpc_id(NetworkManager.HOST_PEER_ID, 77.0)
	for _frame: int in 30:
		await get_tree().process_frame
	assert_eq(_host_ultimate.meter, 40.0, "the host ignores a meter value a client sends")

	# The spend is host-only: a client that calls request_ultimate directly is refused.
	assert_false(_client_ultimate.request_ultimate(), "a client cannot spend on its own copy")
	assert_eq(_client_ultimate.last_refusal, UltimateController.REFUSE_NOT_HOST)
	assert_eq(_client_ultimate.meter, 40.0)
	_client_ultimate.last_refusal = UltimateController.REFUSE_NONE
	_client_ultimate._remote_request_ultimate()
	assert_eq(_client_ultimate.last_refusal, UltimateController.REFUSE_NONE, "the host-only RPC does nothing when a client runs it")

	# Charging is host-only too: a client's direct charge leaves its copy at 40.
	_client_ultimate.charge(50.0)
	assert_eq(_client_ultimate.meter, 40.0, "a client's direct charge is refused")

	# The owner presses on a full meter. The host spends it, and the client's copy
	# follows to zero.
	_host_ultimate.charge(60.0)
	await _wait_for_client_meter(100.0)
	assert_eq(_client_ultimate.meter, 100.0)
	_client_ultimate.ask_ultimate()
	for _frame: int in CONNECT_FRAMES:
		await get_tree().process_frame
		if _host_ultimate.meter == 0.0:
			break
	assert_eq(_host_ultimate.last_refusal, UltimateController.REFUSE_NONE, "the host accepts the owner's press")
	assert_signal_emit_count(Events, "ultimate_used", 1, "the host announces the ultimate once")
	await _wait_for_client_meter(0.0)
	assert_eq(_client_ultimate.meter, 0.0, "the client's copy follows the spend to zero")

	# A press from a peer that does not own the player is refused, and the meter stays.
	_host_player.peer_id = STRANGER_PEER_ID
	_host_ultimate.charge(100.0)
	_client_ultimate.ask_ultimate()
	for _frame: int in CONNECT_FRAMES:
		await get_tree().process_frame
		if _host_ultimate.last_refusal != UltimateController.REFUSE_NONE:
			break
	assert_eq(_host_ultimate.last_refusal, UltimateController.REFUSE_NOT_OWNER, "the host refuses a press from a peer that does not own the player")
	assert_eq(_host_ultimate.meter, 100.0, "a refused press keeps the meter")
	assert_signal_emit_count(Events, "ultimate_used", 1, "a refused press announces nothing")

	# A value above the cap from the host is clamped on the client's copy.
	_host_ultimate._remote_set_meter.rpc_id(_client.get_unique_id(), 150.0)
	await _wait_for_client_meter(METER_CAP)
	assert_eq(_client_ultimate.meter, METER_CAP, "the client clamps a meter value above 100")
