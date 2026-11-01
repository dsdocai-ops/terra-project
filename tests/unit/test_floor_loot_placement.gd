extends GutTest
## Chests, breakables and mining nodes are placed on generated floors (SPEC-run-economy
## "Chests, breakables, mining nodes", W4-B8). Each kind is checked on a real seeded
## floor: generate, paint, and run the COMBAT and TREASURE populators the live way.
## Owned by run-economy. Sync: host only; the furniture spawns through the room.

const WORLD_SCENE_PATH: String = "res://scenes/main/world.tscn"
const WIRING_SEED: int = 20261020
const SEEDS: Array[int] = [WIRING_SEED, 7, 4242]

var _world: World = null
var _floor: Floor = null


func before_each() -> void:
	FloorGenerator.clear_populators()
	NetworkManager.start_solo()
	_gold_gains = 0
	if not Events.currency_gained.is_connected(_count_gold):
		Events.currency_gained.connect(_count_gold)


func after_each() -> void:
	if Events.currency_gained.is_connected(_count_gold):
		Events.currency_gained.disconnect(_count_gold)
	FloorGenerator.clear_populators()
	NetworkManager.players.erase(1)
	GameState.world = null
	_world = null


## Generates `run_seed`'s floor 1, paints it into a live World, and runs the
## populators registered for COMBAT (furniture) and TREASURE (chests).
func _populated_floor(run_seed: int) -> void:
	_world = (load(WORLD_SCENE_PATH) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	GameState.world = _world
	var biome: BiomeData = BiomeData.for_index(1)
	var layout: FloorLayout = FloorGenerator.generate(run_seed, 1, biome, [] as Array[int])
	var floor_node := Floor.new()
	add_child_autofree(floor_node)
	_floor = floor_node
	floor_node.paint(layout, biome, _world)
	FloorGenerator.register_populator(FloorGenerator.RoomType.COMBAT, Callable(RoomFurniture, &"populate_combat"))
	FloorGenerator.register_populator(FloorGenerator.RoomType.TREASURE, Chest.treasure_populator())
	floor_node.populate()


func _count_kind(kind: Variant) -> int:
	var count: int = 0
	for node: Node in _all_nodes(_floor):
		if is_instance_of(node, kind):
			count += 1
	return count


func _all_nodes(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	for child: Node in root.get_children():
		found.append_array(_all_nodes(child))
	return found


func test_breakables_are_placed_on_a_generated_floor_for_every_seed() -> void:
	for run_seed: int in SEEDS:
		_populated_floor(run_seed)
		assert_gt(_count_kind(Breakable), 0, "seed %d: a combat room holds a breakable" % run_seed)
		_world = null
		FloorGenerator.clear_populators()


func test_mining_nodes_are_placed_on_a_generated_floor_for_every_seed() -> void:
	for run_seed: int in SEEDS:
		_populated_floor(run_seed)
		assert_gt(_count_kind(MiningNode), 0, "seed %d: a combat room holds an ore seam" % run_seed)
		_world = null
		FloorGenerator.clear_populators()


func test_chests_are_placed_on_a_generated_floor_for_every_seed() -> void:
	for run_seed: int in SEEDS:
		_populated_floor(run_seed)
		assert_gt(_count_kind(Chest), 0, "seed %d: the treasure room holds a chest" % run_seed)
		_world = null
		FloorGenerator.clear_populators()


# --- an enemy death on the real bus: the table is rolled by LootDrops' own listener ----

const ENEMY_SCENE: String = "res://scenes/enemies/enemy_base.tscn"
const KILL_KIND: StringName = &"hollow_miner"
var _gold_gains: int = 0


func _gold_table(amount: int) -> LootTable:
	var table := LootTable.new()
	table.entries = [{"kind": Pickup.KIND_GOLD, "weight": 1.0, "min": amount, "max": amount}]
	return table


func test_an_enemy_death_on_the_bus_pays_currency_and_spawns_its_pickups() -> void:
	# Emits `Events.enemy_killed` the way the enemy's own death path does, so the
	# LootDrops node that connected to the bus in its _ready is the one that rolls.
	_world = (load(WORLD_SCENE_PATH) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	GameState.world = _world
	var run := RunState.new(4242, 1)
	run.add_player(RunPlayerState.new(1))
	GameState.run = run
	var data: EnemyData = EnemyData.find(KILL_KIND)
	var was: LootTable = data.loot_table
	data.loot_table = _gold_table(3)
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	enemy.setup(KILL_KIND, false)
	_world.entities.add_child(enemy)
	enemy.global_position = Vector2(200.0, 200.0)
	var killer := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	add_child_autofree(killer)
	NetworkManager.players[1] = killer
	var hit := HitInfo.new()
	hit.owner_player = killer
	var pickups_before: int = _all_nodes(_world).filter(func(node: Node) -> bool: return node is Pickup).size()
	watch_signals(Events)
	Events.enemy_killed.emit(enemy, hit)
	data.loot_table = was
	assert_signal_emitted(Events, "currency_gained", "the death paid through currency_gained")
	var pickups_after: int = _all_nodes(_world).filter(func(node: Node) -> bool: return node is Pickup).size()
	assert_gt(pickups_after, pickups_before, "and the drop spawned Pickup nodes")
	GameState.run = null
	NetworkManager.players.erase(1)


func _bus_world_with_table(kind: StringName, amount: int) -> Dictionary:
	_world = (load(WORLD_SCENE_PATH) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	GameState.world = _world
	var run := RunState.new(4242, 1)
	run.add_player(RunPlayerState.new(1))
	GameState.run = run
	var data: EnemyData = EnemyData.find(kind)
	var was: LootTable = data.loot_table
	data.loot_table = _gold_table(amount)
	return {"data": data, "was": was}


func _count_gold(_player: Node, currency: StringName, _amount: int) -> void:
	if currency == &"gold":
		_gold_gains += 1


func test_an_elite_drops_its_table_once_on_elite_killed_and_not_on_enemy_killed() -> void:
	# An elite is announced on both enemy_killed and elite_killed. Its table must
	# be rolled once, on elite_killed, so the drop is not paid twice.
	var setup: Dictionary = _bus_world_with_table(KILL_KIND, 2)
	var killer := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	killer.peer_id = 1
	add_child_autofree(killer)
	NetworkManager.players[1] = killer
	var hit := HitInfo.new()
	hit.owner_player = killer
	var elite := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	elite.setup(KILL_KIND, true)
	_world.entities.add_child(elite)
	elite.global_position = Vector2(220.0, 220.0)
	var pickups_before: int = _all_nodes(_world).filter(func(node: Node) -> bool: return node is Pickup).size()
	watch_signals(Events)
	Events.enemy_killed.emit(elite, hit)
	var gold_before: int = _gold_gains
	assert_eq(_gold_gains, 0, "the elite's enemy_killed rolls no gold")
	Events.elite_killed.emit(elite, hit)
	var pickups_after: int = _all_nodes(_world).filter(func(node: Node) -> bool: return node is Pickup).size()
	assert_eq(_gold_gains - gold_before, 1, "the elite's table is rolled once, on elite_killed")
	assert_gt(pickups_after, pickups_before, "and its drop spawned a Pickup")
	# The killer is in the run, so the elite's flat echo payout reaches its total.
	var killer_slice: RunPlayerState = GameState.run.get_player(1)
	assert_between(killer_slice.echo_shards_earned, 1, 2, "the elite's 1 to 2 echo shards reach the killer's run total")
	(setup["data"] as EnemyData).loot_table = setup["was"]
	NetworkManager.players.erase(1)


func test_a_client_never_rolls_a_drop_on_the_bus() -> void:
	# The real host gate: NetworkManager.is_host, not an override.
	var setup: Dictionary = _bus_world_with_table(KILL_KIND, 2)
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	enemy.setup(KILL_KIND, false)
	_world.entities.add_child(enemy)
	var was_host: bool = NetworkManager.is_host
	NetworkManager.is_host = false
	var client_drops := LootDrops.new()
	var rolled: bool = client_drops.on_enemy_killed(enemy, HitInfo.new())
	NetworkManager.is_host = was_host
	client_drops.free()
	assert_false(rolled, "a client does not roll the table")
	assert_eq(_gold_gains, 0, "and pays nothing")
	(setup["data"] as EnemyData).loot_table = setup["was"]
