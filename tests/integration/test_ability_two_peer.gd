extends GutTest
## Integration: a client's cast request crosses a real ENet pair (SPEC-abilities
## "AbilityController", W5-G2b). Both peers run in this one process: each one's
## SceneMultiplayer is set on its own subtree, so the client's ask_cast and the
## host's _remote_request_cast are separate controllers joined by a socket. The
## host's player carries the client's peer id, so the sender check passes as it
## does in a live session. Owned by abilities.

const PORT: int = 7813
const HOST_ROOT: String = "HostSide"
const CLIENT_ROOT: String = "ClientSide"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const PLAYER_NAME: String = "Fixture"
const CONNECT_FRAMES: int = 300

var _server: ENetMultiplayerPeer
var _client: ENetMultiplayerPeer
var _host_root: Node
var _client_root: Node
var _host_controller: AbilityController
var _client_controller: AbilityController
var _default_api: MultiplayerAPI


func before_each() -> void:
	_default_api = get_multiplayer()


## The sides are freed while their own SceneMultiplayer is still set, so the
## synchronizers unhook from the API they registered with. Then the default API
## goes back on each root.
func after_each() -> void:
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


## One peer's subtree: a real player.tscn with its AbilityController, under its own
## SceneMultiplayer. Processing is off on the player, so no frame moves its
## cooldowns or synchronizers between the test's awaits.
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
	var controller := player.get_node("AbilityController") as AbilityController
	controller.set_physics_process(false)
	if root_name == HOST_ROOT:
		_host_controller = controller
	else:
		_client_controller = controller
	return root


## One connected pair runs both requests in order. A second pair built after the
## first one's teardown logs a synchronizer root_path error, so the cases share it.
func test_a_client_request_crosses_the_wire_and_the_host_refuses_a_nan_aim_then_casts_once() -> void:
	assert_true(await _connect_pair(), "the client connects to the host in this process")
	var host_player := _host_controller.get_parent() as Player
	host_player.peer_id = _client.get_unique_id()
	_host_controller.assign(0, FixtureAbility.make())
	watch_signals(Events)

	_client_controller.ask_cast(0, Vector2(NAN, 0.0))
	for _frame: int in CONNECT_FRAMES:
		await get_tree().process_frame
		if _host_controller.last_refusal != AbilityController.REFUSE_NONE:
			break
	assert_eq(_host_controller.last_refusal, &"not_finite", "the host refuses the NaN aim it received")
	assert_null(_host_controller.last_cast, "the refused aim spawns no cast")
	assert_signal_not_emitted(Events, "ability_cast", "the refused aim announces no cast")

	_client_controller.ask_cast(0, Vector2(64, 0))
	for _frame: int in CONNECT_FRAMES:
		await get_tree().process_frame
		if _host_controller.last_cast != null:
			break
	assert_eq(_host_controller.last_refusal, AbilityController.REFUSE_NONE, "the host accepts the finite aim")
	assert_not_null(_host_controller.last_cast, "the host spawns the cast the client asked for")
	assert_signal_emit_count(Events, "ability_cast", 1, "the host announces the cast once")
