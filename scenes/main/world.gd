class_name World
extends Node2D
## The Y-sorted gameplay root: tile layers, entity containers, camera, FX.
## Owned by foundation. Sync: loaded identically on every peer; nothing here
## holds game state. Players, enemies, pickups spawn under the containers
## through networking's MultiplayerSpawners.
##
## Other modules reach these nodes through GameState.world, never by path.
##
## Ownership: the scene is foundation (both lanes). The Camera child runs
## player-controller's GameCamera script, and networking adds the spawners
## under Players and Entities; those are PRs into this scene with the other
## lane's review (SPEC-project, Ask first).

## Paints a square test floor on ready so week 1 has somewhere to walk.
## floor-generation turns this off when it starts painting real floors.
@export var debug_test_floor: bool = true
@export var debug_test_floor_size: int = 20

@onready var floor_layer: TileMapLayer = $Floor
@onready var walls_layer: TileMapLayer = $Walls
@onready var entities: Node2D = $Entities
@onready var enemy_spawner: EnemySpawner = $Entities/EnemySpawner
@onready var projectile_spawner: ProjectileSpawner = $Entities/ProjectileSpawner
## run-economy's drop path (W4-B8): the host's loot rolls land here.
@onready var pickup_spawner: PickupSpawner = $Entities/PickupSpawner
@onready var loot_drops: LootDrops = $Entities/LootDrops
@onready var players: Node2D = $Players
@onready var player_spawner: PlayerSpawner = $PlayerSpawner
@onready var camera: GameCamera = $Camera
@onready var fx: Node2D = $FX

## combat-core's per-peer hit feedback (see _build_combat_feedback).
var combat_feedback: CombatFeedback = null


func _ready() -> void:
	if debug_test_floor:
		paint_test_floor(debug_test_floor_size)
	NetworkManager.floor_layout_ready.connect(_on_floor_layout_ready)
	NetworkManager.player_joined.connect(_on_player_joined)
	_build_combat_feedback()
	var prompt := InteractPrompt.new()
	prompt.name = "InteractPrompt"
	add_child(prompt)
	var existing: FloorLayout = NetworkManager.last_floor_layout as FloorLayout
	if existing != null:
		build_floor(existing)


## Hit feedback (numbers, flash, shake, sparks) is one local node per peer. It is
## made here, not in world.tscn, so the shared scene stays untouched; the fixed
## name keeps its RPC path identical on every peer.
func _build_combat_feedback() -> void:
	combat_feedback = CombatFeedback.new()
	combat_feedback.name = "CombatFeedback"
	add_child(combat_feedback)
	combat_feedback.setup(fx, camera)


## Clears both layers, paints a `size` x `size` floor from (0, 0) and a one
## tile wall ring around it.
func paint_test_floor(size: int) -> void:
	floor_layer.clear()
	walls_layer.clear()
	for x in size:
		for y in size:
			floor_layer.set_cell(Vector2i(x, y), Tiles.SOURCE, Tiles.FLOOR)
	for i in range(-1, size + 1):
		walls_layer.set_cell(Vector2i(i, -1), Tiles.SOURCE, Tiles.WALL)
		walls_layer.set_cell(Vector2i(i, size), Tiles.SOURCE, Tiles.WALL)
	for i in size:
		walls_layer.set_cell(Vector2i(-1, i), Tiles.SOURCE, Tiles.WALL)
		walls_layer.set_cell(Vector2i(size, i), Tiles.SOURCE, Tiles.WALL)


## True when the cell has a floor tile flagged walkable and no wall on top.
func is_walkable(tile: Vector2i) -> bool:
	if walls_layer.get_cell_source_id(tile) != -1:
		return false
	var data := floor_layer.get_cell_tile_data(tile)
	return data != null and bool(data.get_custom_data(Tiles.WALKABLE))


# --- generated floors (floor-generation) ---------------------------------------

## Players spawn on a ring this far (px) around the Start room anchor.
const START_RING_RADIUS: float = 40.0

## The live floor, created with the first generated layout.
var floor_node: Floor = null
## Peers whose player has not spawned yet when a floor was built.
var _pending_teleports: Array[int] = []


func _on_floor_layout_ready(layout: RefCounted) -> void:
	var typed: FloorLayout = layout as FloorLayout
	if typed != null:
		build_floor(typed)


## Paints `layout`, rebuilds rooms and doors, and on the host clears the last
## floor's entities, runs the populators and moves every player to Start.
func build_floor(layout: FloorLayout) -> void:
	debug_test_floor = false
	if floor_node == null:
		floor_node = Floor.new()
		floor_node.name = "FloorRoot"
		add_child(floor_node)
	if multiplayer.is_server():
		_clear_floor_entities()
	floor_node.paint(layout, BiomeData.for_index(layout.biome_id), self)
	if multiplayer.is_server():
		floor_node.populate()
		for peer_id: int in NetworkManager.players:
			teleport_to_start(peer_id)


## Host. Frees enemies, pickups and interactables of the previous floor; the
## spawners and drop logic stay.
func _clear_floor_entities() -> void:
	for child: Node in entities.get_children():
		if child is MultiplayerSpawner or child == loot_drops:
			continue
		child.queue_free()


## Host. Puts a peer's player on the Start room's ring slot, or queues it until
## the player node exists.
func teleport_to_start(peer_id: int) -> void:
	var player: Player = NetworkManager.players.get(peer_id)
	if player == null or floor_node == null:
		if not _pending_teleports.has(peer_id):
			_pending_teleports.append(peer_id)
		return
	var index: int = maxi(player.slot, 0)
	var angle: float = TAU * float(index) / float(NetworkManager.MAX_PLAYERS)
	var offset: Vector2 = Vector2(START_RING_RADIUS, 0.0).rotated(angle)
	var target: Vector2 = floor_node.start_position() + Vector2(offset.x, offset.y * 0.5)
	player.position = target
	player.synced_position = target


func _on_player_joined(peer_id: int) -> void:
	if multiplayer.is_server() and floor_node != null:
		_pending_teleports.append(peer_id)


func _physics_process(_delta: float) -> void:
	if _pending_teleports.is_empty() or not multiplayer.is_server():
		return
	var still_waiting: Array[int] = []
	for peer_id: int in _pending_teleports:
		if NetworkManager.players.has(peer_id):
			teleport_to_start(peer_id)
		else:
			still_waiting.append(peer_id)
	_pending_teleports = still_waiting
