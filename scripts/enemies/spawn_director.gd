class_name SpawnDirector
extends RefCounted
## Fills combat rooms with enemies (SPEC-enemies-ai `SpawnDirector`, v2: waves of
## 1 to 3 per room, the next at 40 % remaining, see SpawnWaves). Owned by
## enemies-ai. Sync: host-only; enemies spawn through the EnemySpawner so every
## peer sees them, and the room counts each one so it clears when the last dies.
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
## The elite chance multiplier the Double Elites floor modifier applies.
const DOUBLE_ELITES_FACTOR: float = 2.0
## Room metadata key that holds the room's WaveState while its waves run.
const WAVE_STATE_META: StringName = &"spawn_waves"

## The enemy count one combat room fields across its waves on `floor_index`: the
## SPEC-enemies-ai budget, `Scaling.enemies_per_room(floor)` (the stats-status
## curve — its base, step and cap constants are the budget table), floored at
## `MIN_ENEMIES` so the shallowest room never fields fewer than the wave needs.
## SpawnWaves.plan cuts it into waves of 1 to 3. Pure: the floor goes in, the
## count comes out, nothing reads the tree.
static func room_budget(floor_index: int) -> int:
	return maxi(Scaling.enemies_per_room(floor_index), MIN_ENEMIES)


## Pure: which of `spawn_points` stand at least `safe_radius` px from every
## player position (SPEC-enemies-ai: "Spawn positions avoid 160 px around
## players" — a cell exactly at the radius is outside it and stays safe). The
## rule has no exception: when too few cells survive the room fields fewer —
## when none survive, an empty list — never an unsafe cell (the old
## too-small-room fallback that returned every spawn point is gone). Nothing
## reads the tree: the caller feeds the live player positions in.
static func safe_cells(spawn_points: Array[Vector2i], player_positions: Array[Vector2], \
		safe_radius: float) -> Array[Vector2i]:
	var safe: Array[Vector2i] = []
	for cell: Vector2i in spawn_points:
		var pos: Vector2 = Iso.to_screen(cell)
		var clear: bool = true
		for player_pos: Vector2 in player_positions:
			if player_pos.distance_to(pos) < safe_radius:
				clear = false
				break
		if clear:
			safe.append(cell)
	return safe


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


## Spawns the room's first wave and arms the rest (see _on_room_enemies_changed).
## Returns the enemies created. No enemy ever spawns within `SAFE_RADIUS` of a
## player: a room with fewer safe cells than the wave needs fields fewer, and one
## with no safe cell at all fields an empty wave (the old too-small-room
## fallback is gone — the spec's 160 px rule has no exception). Deterministic
## given the run seed and the room's index.
static func fill_room(room: Room) -> Array[Enemy]:
	var world: World = GameState.world
	if world == null or room.spec == null or not room.multiplayer.is_server():
		return [] as Array[Enemy]
	var floor_index: int = GameState.run.floor_index if GameState.run != null else 1
	var rng := RandomNumberGenerator.new()
	var base_seed: int = GameState.run.seed if GameState.run != null else 1
	rng.seed = FloorGenerator.layout_seed(base_seed, floor_index) + room.spec.index * SEED_MIX
	var state := WaveState.new()
	state.waves = SpawnWaves.plan(room_budget(floor_index), rng)
	state.cells = _spawn_cells(room, rng)
	state.floor_index = floor_index
	state.elites_left = ELITE_ROOM_BONUS_ELITES if room.type == FloorGenerator.RoomType.ELITE_COMBAT else 0
	state.double_elites = _has_double_elites(base_seed, floor_index)
	state.rng = rng
	room.set_meta(WAVE_STATE_META, state)
	if not room.enemies_changed.is_connected(_on_room_enemies_changed):
		room.enemies_changed.connect(_on_room_enemies_changed)
	return _spawn_next_wave(room, state)


## Releases the room's next wave when its living count has fallen to the wave
## threshold (SpawnWaves.next_wave_due). Runs on the host from Room.enemies_changed.
static func _on_room_enemies_changed(room: Room) -> void:
	if not room.has_meta(WAVE_STATE_META):
		return
	var state := room.get_meta(WAVE_STATE_META) as WaveState
	if state.waves.is_empty() or not SpawnWaves.next_wave_due(room.enemies_alive, state.spawned):
		return
	_spawn_next_wave(room, state)


## Spawns the front wave of `state` in `room` and pops it off the plan. Each slot
## rolls its elite chance (Scaling.elite_chance, doubled by Double Elites); the
## ELITE_COMBAT room's first slot is always an elite. Returns the enemies created.
static func _spawn_next_wave(room: Room, state: WaveState) -> Array[Enemy]:
	var spawned: Array[Enemy] = []
	if state.waves.is_empty():
		return spawned
	# Players move between waves, so the free cells are re-checked against where they stand now.
	state.cells = safe_cells(state.cells, _live_player_positions(), SAFE_RADIUS)
	var size: int = state.waves.pop_front()
	for index: int in size:
		if state.cells.is_empty():
			break
		var cell: Vector2i = state.cells.pop_back()
		var elite: bool = state.elites_left > 0 or state.rng.randf() < elite_chance_for(state.floor_index, state.double_elites)
		if state.elites_left > 0:
			state.elites_left -= 1
		var affix: EliteAffix.Affix = _roll_affix(state.rng) if elite else EliteAffix.Affix.NONE
		var enemy: Enemy = spawn_one(_pick_kind(state.rng, room), Iso.to_screen(cell), elite, room, affix)
		if enemy != null:
			spawned.append(enemy)
			state.spawned += 1
	return spawned


## The elite chance on `floor_index`: Scaling.elite_chance, doubled by the Double
## Elites floor modifier and capped at 1. Pure.
static func elite_chance_for(floor_index: int, double_elites: bool) -> float:
	var chance: float = Scaling.elite_chance(floor_index)
	return minf(chance * DOUBLE_ELITES_FACTOR, 1.0) if double_elites else chance


## An elite's affix, drawn from the six real affixes (never NONE) by `rng`.
static func _roll_affix(rng: RandomNumberGenerator) -> EliteAffix.Affix:
	return rng.randi_range(1, EliteAffix.Affix.size() - 1) as EliteAffix.Affix


## Whether the run's floor `floor_index` rolls the Double Elites modifier. The roll
## is the floor generator's, per run seed, so every peer agrees.
static func _has_double_elites(run_seed: int, floor_index: int) -> bool:
	var modifiers: Array[int] = FloorGenerator.roll_modifiers(run_seed, floor_index)
	return modifiers.has(FloorGenerator.FloorModifier.DOUBLE_ELITES)


## Spawns one enemy of `kind` at `pos` (carrying `affix` when it is an elite) and,
## when a room is given, registers it with that room. Host only; returns null on a
## client or when the kind has no data.
static func spawn_one(
		kind: StringName,
		pos: Vector2,
		elite: bool = false,
		room: Room = null,
		affix: EliteAffix.Affix = EliteAffix.Affix.NONE,
) -> Enemy:
	var world: World = GameState.world
	if world == null or not world.multiplayer.is_server():
		return null
	var info := EnemySpawnInfo.new(kind, pos, elite, 0, affix)
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


## The live players' positions, read off the host's NetworkManager roster.
static func _live_player_positions() -> Array[Vector2]:
	var players: Array[Vector2] = []
	for player: Player in NetworkManager.players.values():
		if is_instance_valid(player):
			players.append(player.position)
	return players


## The spawn cells of `room` that stand clear of every player, shuffled by `rng`.
static func _spawn_cells(room: Room, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var cells: Array[Vector2i] = safe_cells(room.spec.spawn_points, _live_player_positions(), SAFE_RADIUS)
	for i: int in range(cells.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Vector2i = cells[i]
		cells[i] = cells[j]
		cells[j] = swap
	return cells


## One room's wave progress, kept on the host's Room while its waves release. The
## plan (`waves`), the free cells, the elite slots left and the spawn count so far.
class WaveState:
	extends RefCounted
	var waves: Array[int] = []
	var cells: Array[Vector2i] = []
	var floor_index: int = 1
	var elites_left: int = 0
	var double_elites: bool = false
	var spawned: int = 0
	var rng: RandomNumberGenerator = null
