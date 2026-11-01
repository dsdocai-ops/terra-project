extends GutTest
## Integration: a host's FriendlyUnit positions reach the client's copies over a
## real ENet pair (SPEC-abilities "Shadow Clones", W5-G4b, decision D-G4-1). The
## host casts Shadow Clones, walks its player away, and the host's clones follow.
## Within one second the client's copies sit within SYNC_TOLERANCE of the host's
## clones. One pair per test file (see test_ability_two_peer.gd, W5-G2b). Owned by
## abilities.

const PORT: int = 7814
const HOST_ROOT: String = "HostSide"
const CLIENT_ROOT: String = "ClientSide"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const SHADOW_CLONES: String = "res://data/abilities/shadow_clones.tres"
const PLAYER_NAME: String = "Fixture"
const CONNECT_FRAMES: int = 300
const SYNC_WINDOW_MSEC: int = 1000
const SYNC_TOLERANCE: float = 8.0
const WALK_TO: Vector2 = Vector2(120.0, 0.0)
const MIN_MOVE: float = 20.0

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
## SceneMultiplayer. The player's processing is off, so only the clones move.
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


## The host walks away and the clones follow on the host. The client's copies must
## end up within SYNC_TOLERANCE of the host's clones inside SYNC_WINDOW_MSEC, and
## both sides must have moved, so the match is not two units that never moved.
func test_the_client_copies_of_the_clones_follow_the_host_units_within_a_second() -> void:
	assert_true(await _connect_pair(), "the client connects to the host in this process")
	var host_player := _host_controller.get_parent() as Player
	host_player.peer_id = _client.get_unique_id()
	# The client reaches CONNECTED before the host has processed the peer, so the
	# host's broadcast would find no peers. Wait until the host lists the client.
	for _frame: int in CONNECT_FRAMES:
		if _host_controller.multiplayer.get_peers().size() > 0:
			break
		await get_tree().process_frame
	_host_controller.assign(0, load(SHADOW_CLONES) as AbilityData)
	assert_true(_host_controller.request_cast(0, Vector2(64.0, 0.0)), "the host casts Shadow Clones")
	var host_cast := _host_controller.last_cast as ShadowClonesCast
	assert_not_null(host_cast, "the host spawns the clone cast")

	var client_cast: ShadowClonesCast = null
	for _frame: int in CONNECT_FRAMES:
		await get_tree().process_frame
		client_cast = _client_controller.last_cast as ShadowClonesCast
		if client_cast != null and client_cast.units.size() == ShadowClonesCast.CLONE_COUNT:
			break
	assert_not_null(client_cast, "the client shows the clone cast the host broadcast")
	if host_cast == null or client_cast == null:
		return

	var host_start: Array[Vector2] = _unit_positions(host_cast)
	var client_start: Array[Vector2] = _unit_positions(client_cast)
	host_player.global_position = WALK_TO
	# Sampling starts once the host's clones have moved, so the first frames are not
	# a match from the spawn point. settled_frame is the first sampled frame from
	# which every later frame has every copy within SYNC_TOLERANCE.
	var frames: int = 0
	var walk_frame: int = -1
	var settled_frame: int = -1
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < SYNC_WINDOW_MSEC:
		await get_tree().process_frame
		frames += 1
		if walk_frame < 0 and _any_moved_past(host_cast, host_start):
			walk_frame = frames
		if walk_frame < 0:
			continue
		if _worst_gap(host_cast, client_cast) < SYNC_TOLERANCE:
			if settled_frame < 0:
				settled_frame = frames
		else:
			settled_frame = -1
	print("[sync] walk seen at frame %d of %d; every copy within %s px from frame %d on" % [walk_frame, frames, SYNC_TOLERANCE, settled_frame])
	assert_gt(walk_frame, 0, "the host's clones move while the player walks")
	assert_gt(settled_frame, 0, "the copies are within %s px of the host's clones from some frame on" % SYNC_TOLERANCE)

	var host_now: Array[Vector2] = _unit_positions(host_cast)
	var client_now: Array[Vector2] = _unit_positions(client_cast)
	assert_eq(host_now.size(), ShadowClonesCast.CLONE_COUNT, "the host still has its three clones")
	assert_eq(client_now.size(), ShadowClonesCast.CLONE_COUNT, "the client still has its three copies")
	for index: int in mini(host_now.size(), client_now.size()):
		assert_gt(host_start[index].distance_to(host_now[index]), MIN_MOVE, "host clone %d moved toward the walk" % index)
		assert_gt(client_start[index].distance_to(client_now[index]), MIN_MOVE, "client copy %d moved with the host's clone" % index)
		assert_lt(client_now[index].distance_to(host_now[index]), SYNC_TOLERANCE, "client copy %d is within %s px of the host's clone" % [index, SYNC_TOLERANCE])


## Global positions of a cast's units, in unit order.
func _unit_positions(cast: ShadowClonesCast) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for unit: FriendlyUnit in cast.units:
		positions.append(unit.global_position)
	return positions


## True once any of the cast's units is more than MIN_MOVE from where it started.
func _any_moved_past(cast: ShadowClonesCast, starts: Array[Vector2]) -> bool:
	var now: Array[Vector2] = _unit_positions(cast)
	for index: int in mini(now.size(), starts.size()):
		if now[index].distance_to(starts[index]) > MIN_MOVE:
			return true
	return false


## The largest distance between a host clone and its client copy, over every
## clone, right now. INF when the two sides do not have the same unit count.
func _worst_gap(host_cast: ShadowClonesCast, client_cast: ShadowClonesCast) -> float:
	var host_now: Array[Vector2] = _unit_positions(host_cast)
	var client_now: Array[Vector2] = _unit_positions(client_cast)
	if host_now.size() != client_now.size():
		return INF
	var worst: float = 0.0
	for index: int in host_now.size():
		worst = maxf(worst, client_now[index].distance_to(host_now[index]))
	return worst
