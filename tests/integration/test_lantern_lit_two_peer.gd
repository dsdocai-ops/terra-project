extends GutTest
## Integration: the Lantern Staff's `lit` flag reaches the client's copy of an enemy
## over a real ENet pair (SPEC-weapons Magic row, W5-G8d). The host's charged beam
## lights the enemy inside its cone, and the client's copy reads `lit == true` within
## SYNC_WINDOW_MSEC. Once the light runs out on the host, the copy reads `false` within
## the same window. The flag rides the enemy's StateSync (enemy_base.tscn, on change).
## One pair per test file (see test_ability_two_peer.gd, W5-G2b). Owned by weapons.

const PORT: int = 7817
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const ENEMY_SCENE: String = "res://scenes/enemies/enemy_base.tscn"
const STAFF_NODE_SCENE: String = "res://scenes/player/weapons/lantern_staff.tscn"
const HOST_ROOT: String = "HostSide"
const CLIENT_ROOT: String = "ClientSide"
const PLAYER_NAME: String = "Fixture"
const ENEMY_NAME: String = "Grub"
const CONNECT_FRAMES: int = 300
const SYNC_WINDOW_MSEC: int = 1000
## Ahead of the staff on its aim (RIGHT), inside the zero-charge cone.
const INSIDE: Vector2 = Vector2(80.0, 0.0)

var _server: ENetMultiplayerPeer
var _client: ENetMultiplayerPeer
var _host_root: Node
var _client_root: Node
var _host_enemy: Enemy
var _client_enemy: Enemy
var _staff: LanternStaffAttack
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


## One peer's subtree under its own SceneMultiplayer, with a player and one enemy named
## the same on both sides so the StateSync paths match. The staff exists on the host
## only, since only the host lights enemies. Processing is off on every node the test
## does not drive by hand.
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
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	enemy.name = ENEMY_NAME
	enemy.position = INSIDE
	enemy.set_physics_process(false)
	root.add_child(enemy)
	if root_name == HOST_ROOT:
		_host_enemy = enemy
		_staff = (load(STAFF_NODE_SCENE) as PackedScene).instantiate() as LanternStaffAttack
		_staff.player = player
		_staff.weapons = player.get_node("WeaponController") as WeaponController
		_staff.aim_dir = Vector2.RIGHT
		root.add_child(_staff)
		_staff.set_physics_process(false)
	else:
		_client_enemy = enemy
		# Both peers share one SceneTree in this process, and the staff lights every node
		# in the enemies group. A production client never runs the staff, so the copy is
		# taken out of the group. Otherwise the host's beam would light it locally and the
		# test could not tell a local write from the replicated one.
		enemy.remove_from_group(Enemy.GROUP)
	return root


## The host lights the enemy with a full heavy beam. The client's copy reads lit within
## the sync window, and it reads false again within the window after the light runs out.
func test_the_client_copy_reads_lit_while_the_beam_holds_and_clears_after() -> void:
	assert_true(await _connect_pair(), "the client connects to the host in this process")
	# The client reaches CONNECTED before the host has processed the peer, so the host's
	# sync would find no peers. Wait until the host lists the client.
	for _frame: int in CONNECT_FRAMES:
		if _host_root.multiplayer.get_peers().size() > 0:
			break
		await get_tree().process_frame
	_staff.heavy(1.0)
	assert_true(_host_enemy.lit, "the host lights its enemy in the cone")
	assert_true(await _wait_for_flag(_client_enemy, true), "the client's copy reads lit == true within %d ms" % SYNC_WINDOW_MSEC)

	_staff._physics_process(LanternStaffAttack.LIT_SECONDS + 0.1)
	assert_false(_host_enemy.lit, "the host's light runs out after LIT_SECONDS")
	assert_true(await _wait_for_flag(_client_enemy, false), "the client's copy reads lit == false within %d ms" % SYNC_WINDOW_MSEC)


## Polls the client's copy until `lit` equals `wanted` or the window closes. True on a match.
func _wait_for_flag(enemy: Enemy, wanted: bool) -> bool:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < SYNC_WINDOW_MSEC:
		if enemy.lit == wanted:
			return true
		await get_tree().process_frame
	return enemy.lit == wanted
