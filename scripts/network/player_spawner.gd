class_name PlayerSpawner
extends MultiplayerSpawner
## Spawns one Player per peer under World/Players. Owned by networking.
## Sync: the host (authority 1) calls spawn_player(); MultiplayerSpawner
## replays the custom spawn function on every peer, including late joiners,
## and despawns when the host frees the node. Each spawned player's root and
## StateSync stay host-owned; only its InputSync belongs to the owning peer
## and is visible to the host alone.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
## Center of the week 1 test floor; players spawn on a ring around it.
const SPAWN_CENTER_TILE := Vector2i(10, 10)
const SPAWN_RING_RADIUS := 48.0


func _ready() -> void:
	spawn_function = _spawn_from_data
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)


## Where a peer appears when nothing else decides: spread around the floor
## center so players never overlap.
static func default_spawn_position(peer_id: int) -> Vector2:
	var index := maxi(peer_id - 1, 0)
	var angle := TAU * float(index) / float(NetworkManager.MAX_PLAYERS)
	var offset := Vector2(SPAWN_RING_RADIUS, 0).rotated(angle)
	return Iso.to_screen(SPAWN_CENTER_TILE) + Vector2(offset.x, offset.y * 0.5)


## Host only. Lowest co-op slot no spawned player holds, so a peer that
## leaves frees its color for the next one to join.
func free_slot() -> int:
	var taken: Dictionary[int, bool] = {}
	for player: Player in NetworkManager.players.values():
		if is_instance_valid(player):
			taken[player.slot] = true
	for candidate in NetworkManager.MAX_PLAYERS:
		if not taken.has(candidate):
			return candidate
	return 0


## Host only. Replaces any existing player for the same peer.
func spawn_player(info: PlayerSpawnInfo) -> Player:
	if not multiplayer.is_server():
		push_error("PlayerSpawner.spawn_player called on a client")
		return null
	despawn_player(info.peer_id)
	var node := spawn(info.to_dict())
	return node as Player


## Host only. Frees the peer's player; peers despawn it automatically.
func despawn_player(peer_id: int) -> void:
	var existing: Player = NetworkManager.players.get(peer_id)
	if existing == null:
		return
	NetworkManager.players.erase(peer_id)
	var parent := existing.get_parent()
	if parent != null:
		parent.remove_child(existing)
	existing.queue_free()


## Runs on every peer with the host's PlayerSpawnInfo dictionary.
func _spawn_from_data(data: Variant) -> Node:
	var info := PlayerSpawnInfo.from_dict(data as Dictionary)
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = "Player%d" % info.peer_id
	player.peer_id = info.peer_id
	player.slot = info.slot
	player.position = info.spawn_position
	player.synced_position = info.spawn_position
	# SPEC-stats-status, "Status effects", last line: "Players can receive BURN,
	# CHILL, TOXIN, BLEED from enemies and hazards, never MARK/UNRAVEL/FREEZE."
	# StatusEffects reads that off this group (W4-B4, G20) rather than off a
	# script class, so the tag is applied here, by the module that composes a
	# player, and the player scene stays the other lane's.
	player.add_to_group(StatusEffects.PLAYER_TAG)
	# Input is the owning peer's; it is sent to the host only.
	var input_sync := player.get_node("InputSync") as MultiplayerSynchronizer
	input_sync.set_multiplayer_authority(info.peer_id)
	input_sync.public_visibility = false
	input_sync.set_visibility_for(NetworkManager.HOST_PEER_ID, true)
	NetworkManager.players[info.peer_id] = player
	player.tree_exited.connect(_on_player_exited.bind(info.peer_id, player))
	print("[spawn] %s spawned at %s (local peer %d)" % [player.name, player.position, multiplayer.get_unique_id()])
	return player


func _on_player_exited(peer_id: int, player: Player) -> void:
	if NetworkManager.players.get(peer_id) == player:
		NetworkManager.players.erase(peer_id)


func _on_player_joined(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if GameState.world != get_parent():
		return
	spawn_player(PlayerSpawnInfo.new(peer_id, PlayerSpawnInfo.DEFAULT_CHARACTER, PlayerSpawnInfo.DEFAULT_CLASS, [], default_spawn_position(peer_id), free_slot()))


func _on_player_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	despawn_player(peer_id)
