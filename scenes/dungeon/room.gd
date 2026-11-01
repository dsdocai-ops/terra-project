class_name Room
extends Node2D
## The live node of one generated room (SPEC-floor-generation `Room`): tracks
## which players stand inside, locks its doors on the first entry into a
## combat room, counts the enemies it spawned and clears when the last one dies.
## Owned by floor-generation. Sync: all logic is host-only; the host tells every
## peer when the doors close or open through `Floor`. The room node sits at its
## anchor (the room centre), so populators that `add_child` land on the anchor.

## A player crossed into the room (host).
signal entered(player: Player)
## A locking room was entered for the first time; wave spawners listen (host).
signal activated(room: Room)
## The last tracked enemy of a locking room died; the doors are open (host).
signal became_clear(room: Room)
## A tracked enemy died or left; `enemies_alive` is the count now. Wave spawners
## listen (host). SpawnDirector v2 (W4-A2) reads it to release the next wave.
signal enemies_changed(room: Room)

## Tiles inside the wall a player must stand to count as inside, so the door
## ring never triggers a lock.
const INSET: int = 1

var spec: RoomSpec = null
var type: int = FloorGenerator.RoomType.COMBAT
var cleared: bool = false
var triggered: bool = false
var players_inside: Array[Player] = []
## Whether this room's enemies are running and drawn (see _set_enemies_active).
var _enemies_active: bool = true
var enemies_alive: int = 0
## The owning floor; set by `Floor` before the room enters the tree.
var floor_node: Floor = null

var _tracked: Dictionary[int, bool] = {}


func setup(p_spec: RoomSpec, p_floor: Floor) -> void:
	spec = p_spec
	type = p_spec.type
	floor_node = p_floor
	name = "Room%d" % p_spec.index
	position = Iso.to_screen(p_spec.anchor)
	# A room that never locks has nothing to clear.
	cleared = not p_spec.locks()


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	_scan_players()
	if type == FloorGenerator.RoomType.EXIT:
		_check_exit()


## True when the tile is inside the room, one tile in from the wall.
func contains_cell(cell: Vector2i) -> bool:
	return spec != null and spec.rect.grow(-INSET).has_point(cell)


func _scan_players() -> void:
	var now_inside: Array[Player] = []
	for player: Player in NetworkManager.players.values():
		if not is_instance_valid(player) or player.is_downed:
			continue
		if contains_cell(Iso.to_tile(player.position)):
			now_inside.append(player)
	for player: Player in now_inside:
		if not players_inside.has(player):
			_on_player_entered(player)
	players_inside = now_inside
	_set_enemies_active(not players_inside.is_empty())


## Host. Pauses and hides this room's enemies while no player is inside it, and
## resumes them on entry (SPEC-enemies-ai: enemies outside the active room pause
## processing and are hidden). Flips only on a change. Clients are not told: the
## host's replicated positions are all a client has for an enemy.
func _set_enemies_active(active: bool) -> void:
	if active == _enemies_active:
		return
	_enemies_active = active
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or enemy.room != self:
			continue
		_apply_active(enemy, active)


## Sets one enemy's processing and drawing to match `active`.
func _apply_active(enemy: Enemy, active: bool) -> void:
	enemy.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	enemy.visible = active


func _on_player_entered(player: Player) -> void:
	entered.emit(player)
	Events.room_entered.emit(self, player)
	if triggered:
		return
	triggered = true
	if spec.locks() and not cleared:
		floor_node.set_room_locked(self, true)
		activated.emit(self)
		# A room that spawned nothing is clear straight away.
		call_deferred(&"_clear_if_empty")


## Host. Registers an enemy the room's spawner created; the room clears when
## every tracked enemy is gone.
func track_enemy(enemy: Node) -> void:
	var id: int = enemy.get_instance_id()
	if _tracked.has(id):
		return
	_tracked[id] = true
	enemies_alive += 1
	# A wave released while the room is empty (an enemy died after the last player
	# left) starts paused, so it never runs in a room nobody is in.
	if enemy is Enemy and not _enemies_active:
		_apply_active(enemy as Enemy, false)
	enemy.tree_exiting.connect(_on_enemy_gone.bind(id))
	if enemy.has_signal(&"died"):
		enemy.connect(&"died", _on_enemy_died.bind(id))


func _on_enemy_died(_hit: HitInfo, id: int) -> void:
	_on_enemy_gone(id)


func _on_enemy_gone(id: int) -> void:
	if not is_inside_tree():
		return
	if not _tracked.has(id):
		return
	_tracked.erase(id)
	enemies_alive = maxi(enemies_alive - 1, 0)
	enemies_changed.emit(self)
	_clear_if_empty()


## Host. Clears a triggered locking room once nothing is left alive.
func _clear_if_empty() -> void:
	if cleared or not triggered or enemies_alive > 0:
		return
	cleared = true
	floor_node.set_room_locked(self, false)
	became_clear.emit(self)
	Events.room_cleared.emit(self)


## Tiles from the anchor within which a player takes the stairs down.
const EXIT_RADIUS_TILES: float = 1.5


## Host. Standing on the Exit room's anchor with the exit open goes down.
func _check_exit() -> void:
	if GameState.run == null or not GameState.can_advance_floor():
		return
	for player: Player in NetworkManager.players.values():
		if not is_instance_valid(player) or player.is_downed or player.is_dead:
			continue
		var offset: Vector2i = Iso.to_tile(player.position) - spec.anchor
		if Vector2(offset).length() <= EXIT_RADIUS_TILES:
			GameState.next_floor()
			return
