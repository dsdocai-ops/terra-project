class_name FloorGenerator
extends RefCounted
## Deterministic seeded floor generation (SPEC-floor-generation, W3-A1/A3).
## Owned by floor-generation (Dev A lane). Sync: none; every peer calls
## `generate()` on the host's seed and the `layout_hash` assertion compares.
##
## All randomness comes from one RandomNumberGenerator seeded with
## `layout_seed(run_seed, floor_index)`: no global rolls, no unseeded shuffles.
## Populators run on the host after the live `Floor` paints.

enum RoomType {
	START, EXIT, COMBAT, ELITE_COMBAT, TREASURE, SHRINE, RUNE, ANVIL, SHOP,
	CURSED_ALTAR, CHALLENGE, LORE, REST, SECRET, ROPE, MINI_BOSS, BOSS,
}

enum FloorModifier { DARKNESS, DOUBLE_ELITES, FAST_ENEMIES, LOW_GRAVITY, GOLD_RUSH, EXPLOSIVE_ENEMIES }

## Room types whose doors lock on enter and open when the room is clear.
const LOCKING_TYPES: Array[int] = [RoomType.COMBAT, RoomType.ELITE_COMBAT, RoomType.MINI_BOSS, RoomType.BOSS]

const GRID: int = 96
const MIN_ROOMS: int = 8
const MAX_ROOMS: int = 14
const ROOM_GAP: int = 2
const EDGE_MARGIN: int = 3
const CORRIDOR_HALF: int = 1
const MAX_FLOOR_ATTEMPTS: int = 20
const PLACEMENT_TRIES: int = 500
const MIN_COMBAT_ROOMS: int = 2
const SPAWN_MARGIN: int = 2
const SPAWN_STEP: int = 2
const RUNE_CHANCE: float = 0.35
const MAX_MODIFIERS: int = 2
const MODIFIER_CHANCE_PER_FLOOR: float = 0.02
const SEED_MIX: int = 2654435761
const FLOOR_STRIDE: int = 40503
const HASH_MIX: int = 1000003

## RoomType (int) -> Array[Callable]; each is `func(room: Room) -> void`.
static var _populators: Dictionary = {}


## Registers a populator for a room type. The generator's caller runs them
## through `run_populators` after painting. Idempotent per (type, callable).
static func register_populator(type: int, populator: Callable) -> void:
	var list: Array = _populators.get(type, [])
	if not list.has(populator):
		list.append(populator)
	_populators[type] = list


static func populator_count(type: int) -> int:
	var list: Array = _populators.get(type, [])
	return list.size()


## Drops every registration (tests).
static func clear_populators() -> void:
	_populators.clear()


## Calls every populator registered for the room's type. Host only.
static func run_populators(room: Node) -> void:
	var type: int = int(room.get(&"type"))
	var list: Array = _populators.get(type, [])
	for populator: Callable in list:
		if populator.is_valid():
			populator.call(room)


## The one seed a floor's randomness comes from: hash(run_seed, floor_index).
static func layout_seed(run_seed: int, floor_index: int) -> int:
	return absi(run_seed * SEED_MIX + floor_index * FLOOR_STRIDE) + 1


## Up to two modifiers, deeper floors likelier. Deterministic per floor.
static func roll_modifiers(run_seed: int, floor_index: int) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed(run_seed, floor_index) + HASH_MIX
	var chance: float = clampf(MODIFIER_CHANCE_PER_FLOOR * float(floor_index), 0.0, 0.6)
	var rolled: Array[int] = []
	var kinds: int = FloorModifier.size()
	for _slot: int in MAX_MODIFIERS:
		var roll: float = rng.randf()
		var kind: int = rng.randi_range(0, kinds - 1)
		if roll < chance and not rolled.has(kind):
			rolled.append(kind)
	return rolled


## The floor for (seed, floor, biome, modifiers). `biome` is a BiomeData; any
## other resource is replaced by biome 1's defaults.
static func generate(run_seed: int, floor_index: int, biome: Resource, modifiers: Array[int]) -> FloorLayout:
	var biome_data: BiomeData = biome as BiomeData
	if biome_data == null:
		biome_data = BiomeData.for_index(1)
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed(run_seed, floor_index)
	var rects: Array[Rect2i] = []
	for attempt: int in MAX_FLOOR_ATTEMPTS:
		rects = _place_rooms(rng, biome_data, attempt)
		if rects.size() >= MIN_ROOMS:
			break
	if rects.size() < MIN_ROOMS:
		rects = _fallback_rooms()
	var edges: Array[Vector2i] = _connect(rng, rects)
	var adjacency: Array[PackedInt32Array] = _adjacency(rects.size(), edges)
	var types: Array[int] = _assign_types(rng, adjacency, floor_index, biome_data)
	var corridor_cells: Array[Vector2i] = _carve_corridors(rects, edges)
	return assemble(run_seed, floor_index, biome_data.biome_index, modifiers, rects, types, corridor_cells, edges)


## Builds the full layout (walkable set, doors, spawn points, hash) from the
## primitives. The wire format rebuilds through this too.
static func assemble(run_seed: int, floor_index: int, biome_id: int, modifiers: Array[int], rects: Array[Rect2i], types: Array[int], corridor_cells: Array[Vector2i], edges: Array[Vector2i]) -> FloorLayout:
	var layout := FloorLayout.new()
	layout.seed = run_seed
	layout.floor_index = floor_index
	layout.biome_id = biome_id
	layout.modifiers.assign(modifiers)
	layout.corridors = corridor_cells
	layout.edges = edges
	var adjacency: Array[PackedInt32Array] = _adjacency(rects.size(), edges)
	for cell: Vector2i in corridor_cells:
		layout.walkable[cell] = true
	for index: int in rects.size():
		var room := RoomSpec.new()
		room.index = index
		room.rect = rects[index]
		room.type = types[index] if index < types.size() else RoomType.COMBAT
		room.neighbors = adjacency[index]
		room.anchor = room.center()
		layout.rooms.append(room)
		for x: int in range(room.rect.position.x, room.rect.end.x):
			for y: int in range(room.rect.position.y, room.rect.end.y):
				layout.walkable[Vector2i(x, y)] = true
	for room: RoomSpec in layout.rooms:
		room.door_cells = _door_cells(room, layout)
		room.spawn_points = _spawn_points(room)
		if room.type == RoomType.START:
			layout.start_room = room
		elif room.type == RoomType.EXIT:
			layout.exit_room = room
	layout.required_rooms = _required_rooms(layout, adjacency)
	layout.layout_hash = _hash_layout(layout)
	return layout


# --- placement ----------------------------------------------------------------


static func _place_rooms(rng: RandomNumberGenerator, biome: BiomeData, attempt: int) -> Array[Rect2i]:
	var target: int = rng.randi_range(MIN_ROOMS, MAX_ROOMS)
	# Later attempts shrink the largest allowed room so a crowded roll still fits.
	var shrink: int = attempt / 4
	var max_w: int = maxi(biome.room_size_max.x - shrink * 2, biome.room_size_min.x)
	var max_h: int = maxi(biome.room_size_max.y - shrink * 2, biome.room_size_min.y)
	var rects: Array[Rect2i] = []
	var tries: int = 0
	while rects.size() < target and tries < PLACEMENT_TRIES:
		tries += 1
		var size := Vector2i(rng.randi_range(biome.room_size_min.x, max_w), rng.randi_range(biome.room_size_min.y, max_h))
		var pos := Vector2i(
			rng.randi_range(EDGE_MARGIN, GRID - size.x - EDGE_MARGIN),
			rng.randi_range(EDGE_MARGIN, GRID - size.y - EDGE_MARGIN))
		var candidate := Rect2i(pos, size)
		var clear: bool = true
		for other: Rect2i in rects:
			if candidate.grow(ROOM_GAP).intersects(other):
				clear = false
				break
		if clear:
			rects.append(candidate)
	return rects


## A fixed 3x3 grid of the smallest rooms: the guaranteed-valid last resort.
static func _fallback_rooms() -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for row: int in 3:
		for col: int in 3:
			rects.append(Rect2i(8 + col * 28, 8 + row * 28, 9, 7))
	return rects


# --- graph --------------------------------------------------------------------


static func _center_of(rect: Rect2i) -> Vector2i:
	return rect.position + rect.size / 2


static func _dist2(a: Rect2i, b: Rect2i) -> int:
	var delta: Vector2i = _center_of(a) - _center_of(b)
	return delta.x * delta.x + delta.y * delta.y


## MST on room centres, then 1..3 extra loops between near non-neighbours.
static func _connect(rng: RandomNumberGenerator, rects: Array[Rect2i]) -> Array[Vector2i]:
	var count: int = rects.size()
	var in_tree: Array[bool] = []
	in_tree.resize(count)
	in_tree.fill(false)
	in_tree[0] = true
	var edges: Array[Vector2i] = []
	for _step: int in count - 1:
		var best: int = -1
		var best_pair := Vector2i(-1, -1)
		for a: int in count:
			if not in_tree[a]:
				continue
			for b: int in count:
				if in_tree[b]:
					continue
				var d: int = _dist2(rects[a], rects[b])
				if best < 0 or d < best:
					best = d
					best_pair = Vector2i(a, b)
		in_tree[best_pair.y] = true
		edges.append(Vector2i(mini(best_pair.x, best_pair.y), maxi(best_pair.x, best_pair.y)))
	var candidates: Array[Vector2i] = []
	for a: int in count:
		for b: int in range(a + 1, count):
			if not edges.has(Vector2i(a, b)):
				candidates.append(Vector2i(a, b))
	candidates.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		var dp: int = _dist2(rects[p.x], rects[p.y])
		var dq: int = _dist2(rects[q.x], rects[q.y])
		if dp != dq:
			return dp < dq
		if p.x != q.x:
			return p.x < q.x
		return p.y < q.y)
	var pool: Array[Vector2i] = candidates.slice(0, mini(8, candidates.size()))
	var loops: int = mini(rng.randi_range(1, 3), pool.size())
	for _loop: int in loops:
		var pick: int = rng.randi_range(0, pool.size() - 1)
		edges.append(pool[pick])
		pool.remove_at(pick)
	return edges


static func _adjacency(count: int, edges: Array[Vector2i]) -> Array[PackedInt32Array]:
	var adjacency: Array[PackedInt32Array] = []
	for _index: int in count:
		adjacency.append(PackedInt32Array())
	for edge: Vector2i in edges:
		if edge.x < count and edge.y < count:
			adjacency[edge.x].append(edge.y)
			adjacency[edge.y].append(edge.x)
	return adjacency


## Hop distance from `origin` to every room (-1 when unreachable).
static func _bfs(adjacency: Array[PackedInt32Array], origin: int) -> Array[int]:
	var dist: Array[int] = []
	dist.resize(adjacency.size())
	dist.fill(-1)
	dist[origin] = 0
	var queue: Array[int] = [origin]
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for next: int in adjacency[current]:
			if dist[next] < 0:
				dist[next] = dist[current] + 1
				queue.append(next)
	return dist


static func _farthest(dist: Array[int]) -> int:
	var best: int = 0
	for index: int in dist.size():
		if dist[index] > dist[best]:
			best = index
	return best


# --- room types ---------------------------------------------------------------


static func _assign_types(rng: RandomNumberGenerator, adjacency: Array[PackedInt32Array], floor_index: int, biome: BiomeData) -> Array[int]:
	var count: int = adjacency.size()
	var types: Array[int] = []
	types.resize(count)
	types.fill(RoomType.COMBAT)
	var start: int = _farthest(_bfs(adjacency, 0))
	var exit_room: int = _farthest(_bfs(adjacency, start))
	types[start] = RoomType.START
	types[exit_room] = RoomType.EXIT
	var in_biome: int = BiomeData.floor_in_biome(floor_index)
	# Priority order: when the floor has more specials than rooms, the tail drops.
	var wanted: Array[int] = []
	if in_biome == 2:
		wanted.append(RoomType.ROPE)
	if in_biome == biome.lore_floor:
		wanted.append(RoomType.LORE)
	wanted.append(RoomType.TREASURE)
	wanted.append(RoomType.SHRINE)
	if floor_index >= 3:
		wanted.append(RoomType.ELITE_COMBAT)
	if floor_index >= 11:
		wanted.append(RoomType.ELITE_COMBAT)
	if in_biome >= 2 and in_biome <= 4:
		wanted.append(RoomType.SHOP)
	if in_biome >= 3 and in_biome <= 4:
		wanted.append(RoomType.REST)
	if floor_index % 2 == 0 or floor_index % 5 == 4:
		wanted.append(RoomType.ANVIL)
	# The roll is always consumed so a missed chance cannot shift later draws.
	if rng.randf() < RUNE_CHANCE:
		wanted.append(RoomType.RUNE)
	var pool: Array[int] = []
	for index: int in count:
		if index != start and index != exit_room:
			pool.append(index)
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = pool[i]
		pool[i] = pool[j]
		pool[j] = swap
	var budget: int = maxi(pool.size() - MIN_COMBAT_ROOMS, 0)
	for type: int in wanted:
		if budget <= 0 or pool.is_empty():
			break
		var chosen: int = 0
		if type == RoomType.TREASURE:
			# A dead end suits a treasure room; the shuffle breaks ties.
			for slot: int in pool.size():
				if adjacency[pool[slot]].size() < adjacency[pool[chosen]].size():
					chosen = slot
		types[pool[chosen]] = type
		pool.remove_at(chosen)
		budget -= 1
	return types


# --- carving ------------------------------------------------------------------


## L-shaped corridors, three tiles wide, between every edge's room centres.
static func _carve_corridors(rects: Array[Rect2i], edges: Array[Vector2i]) -> Array[Vector2i]:
	var cells: Dictionary[Vector2i, bool] = {}
	for edge: Vector2i in edges:
		var from: Vector2i = _center_of(rects[edge.x])
		var to: Vector2i = _center_of(rects[edge.y])
		var step_x: int = 1 if to.x >= from.x else -1
		var x: int = from.x
		while true:
			_carve_column(cells, Vector2i(x, from.y), true)
			if x == to.x:
				break
			x += step_x
		var step_y: int = 1 if to.y >= from.y else -1
		var y: int = from.y
		while true:
			_carve_column(cells, Vector2i(to.x, y), false)
			if y == to.y:
				break
			y += step_y
	var ordered: Array[Vector2i] = []
	for y: int in GRID:
		for x: int in GRID:
			if cells.has(Vector2i(x, y)):
				ordered.append(Vector2i(x, y))
	return ordered


## Marks the 3-wide slice of a corridor centred on `centre`.
static func _carve_column(cells: Dictionary[Vector2i, bool], centre: Vector2i, horizontal: bool) -> void:
	for offset: int in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
		var cell: Vector2i = centre + (Vector2i(0, offset) if horizontal else Vector2i(offset, 0))
		if cell.x >= 1 and cell.y >= 1 and cell.x < GRID - 1 and cell.y < GRID - 1:
			cells[cell] = true


## Walkable cells touching the room from outside: where its doors stand.
static func _door_cells(room: RoomSpec, layout: FloorLayout) -> Array[Vector2i]:
	var doors: Array[Vector2i] = []
	if not room.locks():
		return doors
	var rect: Rect2i = room.rect
	for x: int in range(rect.position.x, rect.end.x):
		for y: int in [rect.position.y - 1, rect.end.y]:
			if layout.is_walkable(Vector2i(x, y)):
				doors.append(Vector2i(x, y))
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in [rect.position.x - 1, rect.end.x]:
			if layout.is_walkable(Vector2i(x, y)):
				doors.append(Vector2i(x, y))
	return doors


static func _spawn_points(room: RoomSpec) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var rect: Rect2i = room.rect
	for x: int in range(rect.position.x + SPAWN_MARGIN, rect.end.x - SPAWN_MARGIN, SPAWN_STEP):
		for y: int in range(rect.position.y + SPAWN_MARGIN, rect.end.y - SPAWN_MARGIN, SPAWN_STEP):
			points.append(Vector2i(x, y))
	return points


## Locking rooms on the shortest Start to Exit path, ends excluded.
static func _required_rooms(layout: FloorLayout, adjacency: Array[PackedInt32Array]) -> int:
	if layout.start_room == null or layout.exit_room == null:
		return 0
	var parent: Array[int] = []
	parent.resize(layout.rooms.size())
	parent.fill(-2)
	parent[layout.start_room.index] = -1
	var queue: Array[int] = [layout.start_room.index]
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for next: int in adjacency[current]:
			if parent[next] == -2:
				parent[next] = current
				queue.append(next)
	var required: int = 0
	var node: int = parent[layout.exit_room.index]
	while node >= 0 and node != layout.start_room.index:
		if layout.rooms[node].locks():
			required += 1
		node = parent[node]
	return required


static func _hash_layout(layout: FloorLayout) -> int:
	var acc: int = layout.floor_index * FLOOR_STRIDE + layout.biome_id
	for room: RoomSpec in layout.rooms:
		acc = acc * 31 + room.rect.position.x * 37 + room.rect.position.y * 41
		acc = acc * 31 + room.rect.size.x * 43 + room.rect.size.y * 47 + room.type * 53
		acc %= HASH_MIX * HASH_MIX
	for cell: Vector2i in layout.corridors:
		acc = (acc * 31 + cell.x * 59 + cell.y * 61) % (HASH_MIX * HASH_MIX)
	for modifier: int in layout.modifiers:
		acc = (acc * 43 + modifier) % (HASH_MIX * HASH_MIX)
	return absi(acc)
