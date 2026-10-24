class_name SpawnDirector
extends RefCounted
## Fills combat rooms with enemies (SPEC-enemies-ai `SpawnDirector`, v1: one
## wave per room). Owned by enemies-ai. Sync: host-only; enemies spawn through
## the EnemySpawner so every peer sees them, and the room counts each one so it
## clears when the last dies.
##
## It registers as the COMBAT and ELITE_COMBAT populator: the populator only
## arms the room (spawning waits for the first player to enter), so a floor
## does not start with every room already fighting.

const SAFE_RADIUS: float = 160.0
const MIN_ENEMIES: int = 2
## (kind, weight) for rooms whose biome lists no enemy pool.
const DEFAULT_POOL: Array[Array] = [
	[&"hollow_miner", 3],
	[&"rock_tick", 2],
	[&"lantern_wisp", 1],
]
const ELITE_ROOM_BONUS_ELITES: int = 1
const SEED_MIX: int = 7919

## Registers the combat populators with the floor generator. Safe to call more
## than once.
static func register_populators() -> void:
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, Callable(SpawnDirector, &"arm_room"))
	FloorGenerator.register_populator(FloorGenerator.RoomType.ELITE_COMBAT, Callable(SpawnDirector, &"arm_room"))


## The populator: spawns this room's enemies when it activates.
static func arm_room(room: Node) -> void:
	var typed: Room = room as Room
	if typed == null or not typed.multiplayer.is_server():
		return
	if not typed.activated.is_connected(_on_room_activated):
		typed.activated.connect(_on_room_activated)


static func _on_room_activated(room: Room) -> void:
	fill_room(room)


## Spawns the room's wave. Returns the enemies created.
static func fill_room(room: Room) -> Array[Enemy]:
	var spawned: Array[Enemy] = []
	var world: World = GameState.world
	if world == null or room.spec == null or not room.multiplayer.is_server():
		return spawned
	var floor_index: int = GameState.run.floor_index if GameState.run != null else 1
	var rng := RandomNumberGenerator.new()
	var base_seed: int = GameState.run.seed if GameState.run != null else 1
	rng.seed = FloorGenerator.layout_seed(base_seed, floor_index) + room.spec.index * SEED_MIX
	var count: int = maxi(Scaling.enemies_per_room(floor_index), MIN_ENEMIES)
	var elites_left: int = ELITE_ROOM_BONUS_ELITES if room.type == FloorGenerator.RoomType.ELITE_COMBAT else 0
	var cells: Array[Vector2i] = _spawn_cells(room, rng)
	for index: int in count:
		if cells.is_empty():
			break
		var cell: Vector2i = cells.pop_back()
		var elite: bool = elites_left > 0 or rng.randf() < Scaling.elite_chance(floor_index)
		if elites_left > 0:
			elites_left -= 1
		var enemy: Enemy = spawn_one(_pick_kind(rng, room), Iso.to_screen(cell), elite, room)
		if enemy != null:
			spawned.append(enemy)
	return spawned


## Spawns one enemy of `kind` at `pos` and, when a room is given, registers it
## with that room. Host only; returns null on a client or when the kind has no
## data.
static func spawn_one(kind: StringName, pos: Vector2, elite: bool = false, room: Room = null) -> Enemy:
	var world: World = GameState.world
	if world == null or not world.multiplayer.is_server():
		return null
	var info := EnemySpawnInfo.new(kind, pos, elite)
	var enemy: Enemy = world.enemy_spawner.spawn_enemy(info) as Enemy
	if enemy == null:
		return null
	if room != null:
		enemy.room = room
		room.track_enemy(enemy)
	Events.enemy_spawned.emit(enemy)
	return enemy


static func _pick_kind(rng: RandomNumberGenerator, room: Room) -> StringName:
	var pool: Array[Array] = DEFAULT_POOL
	var total: int = 0
	for entry: Array in pool:
		total += int(entry[1])
	var roll: int = rng.randi_range(1, total)
	for entry: Array in pool:
		roll -= int(entry[1])
		if roll <= 0:
			return StringName(entry[0])
	return StringName(pool[0][0])


## Spawn cells at least SAFE_RADIUS (px) from every player, shuffled by the
## room's rng; falls back to every cell when the room is too small to be safe.
static func _spawn_cells(room: Room, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var safe: Array[Vector2i] = []
	for cell: Vector2i in room.spec.spawn_points:
		var pos: Vector2 = Iso.to_screen(cell)
		var clear: bool = true
		for player: Player in NetworkManager.players.values():
			if is_instance_valid(player) and player.position.distance_to(pos) < SAFE_RADIUS:
				clear = false
				break
		if clear:
			safe.append(cell)
	var cells: Array[Vector2i] = safe if safe.size() >= MIN_ENEMIES else room.spec.spawn_points.duplicate()
	for i: int in range(cells.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Vector2i = cells[i]
		cells[i] = cells[j]
		cells[j] = swap
	return cells
