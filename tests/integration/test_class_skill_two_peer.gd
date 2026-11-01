extends GutTest
## Integration: a class skill request over a real ENet pair (SPEC-classes-characters
## "ClassController"; W5-G9b). Both peers run in this process, each on its own
## SceneMultiplayer subtree joined by a socket, as in test_ultimate_two_peer.gd. The
## client's request reaches the host by RPC; the host refuses a request from a sender
## who does not own the player, and runs the skill once for the owner. The skill is
## a fixture (FixtureClassSkill). One pair serves every case, because a second pair
## built after the first one's teardown logs a synchronizer root_path error. Owned by
## classes-characters.

const PORT: int = 7818
const HOST_ROOT: String = "HostSide"
const CLIENT_ROOT: String = "ClientSide"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const PLAYER_NAME: String = "Fixture"
const CONNECT_FRAMES: int = 300
const STRANGER_PEER_ID: int = 999
const CLASS_ID: StringName = &"fixture_warrior"
const SKILL_COOLDOWN: float = 6.0

var _server: ENetMultiplayerPeer
var _client: ENetMultiplayerPeer
var _host_root: Node
var _client_root: Node
var _host_controller: ClassController
var _client_controller: ClassController
var _host_player: Player
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


## One peer's subtree: a real player.tscn with its ClassController, under its own
## SceneMultiplayer.
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
	var classes := player.get_node("ClassController") as ClassController
	classes.set_physics_process(false)
	if root_name == HOST_ROOT:
		_host_player = player
		_host_controller = classes
	else:
		_client_controller = classes
	return root


func _skill_scene() -> PackedScene:
	var packed := PackedScene.new()
	var skill := FixtureClassSkill.new()
	skill.cooldown_seconds = SKILL_COOLDOWN
	packed.pack(skill)
	skill.free()
	return packed


## The fixture class the host sets. The client never sets a class: its copy only
## sends the request.
func _class_data() -> ClassData:
	var data := ClassData.new()
	data.id = CLASS_ID
	data.class_skill = _skill_scene()
	return data


func _host_skill() -> FixtureClassSkill:
	return _host_controller.skill as FixtureClassSkill


## Waits until the host's controller reports `reason` as its last refusal, or the
## frame budget runs out.
func _wait_for_refusal(reason: StringName) -> void:
	for _frame: int in CONNECT_FRAMES:
		await get_tree().process_frame
		if _host_controller.last_refusal == reason:
			return


## Waits until the host's skill has performed `count` times, or the frame budget runs out.
func _wait_for_performs(count: int) -> void:
	for _frame: int in CONNECT_FRAMES:
		await get_tree().process_frame
		if _host_skill().performs >= count:
			return


## All cases share one connected pair, in this order: a stranger's request is refused
## by the host, then the owner's request runs the skill once on the host and emits
## class_skill_used once on the host.
func test_a_client_request_reaches_the_host_and_only_the_owner_is_served() -> void:
	assert_true(await _connect_pair(), "the client connects to the host in this process")
	_host_controller.set_class(_class_data())
	_host_player.peer_id = _client.get_unique_id()
	watch_signals(Events)

	# The client reports connected before the host has registered the join. A request
	# sent in that gap has no peer to go to, so wait until the host's side lists it.
	for _frame: int in CONNECT_FRAMES:
		await get_tree().process_frame
		if _host_player.multiplayer.get_peers().has(_client.get_unique_id()):
			break

	# A request from a peer that does not own the player is refused, and nothing runs.
	_host_player.peer_id = STRANGER_PEER_ID
	_client_controller.ask_class_skill()
	await _wait_for_refusal(ClassController.REFUSE_NOT_OWNER)
	assert_eq(_host_controller.last_refusal, ClassController.REFUSE_NOT_OWNER,
		"the host refuses a request from a sender who does not own the player")
	assert_eq(_host_skill().performs, 0, "a refused request performs nothing on the host")
	assert_signal_not_emitted(Events, "class_skill_used")

	# The owner's request reaches the host by RPC, and the host runs the skill once.
	_host_player.peer_id = _client.get_unique_id()
	_client_controller.ask_class_skill()
	await _wait_for_performs(1)
	assert_eq(_host_skill().performs, 1, "the owner's request runs the skill once on the host")
	assert_signal_emit_count(Events, "class_skill_used", 1, "the host announces the use once")
	assert_eq(_host_skill().cooldown_left(), SKILL_COOLDOWN, "the host starts the cooldown")
