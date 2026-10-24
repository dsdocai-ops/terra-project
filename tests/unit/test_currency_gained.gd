extends GutTest
## G14 (raw goals G41 and G42) — the host drop path: an enemy death rolls its
## `EnemyData.loot_table`, spawns the drops through the pickup spawner and
## credits the currency the roll produced. Owned by run-economy.
##
## SPEC-run-economy, "Currencies": "Gold | enemies (by `EnemyData.loot_table`),
## chests, breakables; Miner's Luck, Gold Rush, Jackpot, Ember Heart multiply |
## shared"; "Ore | mining nodes ..., elites 1, mini-boss 3, biome boss 6, always
## the biome's ore ... | shared"; "Echo Shards | ... | per player".
## SPEC-run-economy, "Interfaces consumed": "`enemies-ai`: `elite_killed`,
## `enemy_killed` with `EnemyData.loot_table`". SPEC-run-economy, "Multiplayer
## ownership": "Run state, votes, loot rolls, currency totals ... host."
##
## `EnemyData` and the production `enemy_killed` / `elite_killed` emitters are
## Dev A's and are not in the tree, so the cases drive the spec-shaped doubles
## `tests/helpers/enemy_data_stub.gd` and `tests/helpers/loot_enemy_stub.gd` and
## fire the bus directly — **blocked on Dev A (W2-A9, W4-A4)**, recorded with
## the swap line in `HANDOFF.md`.
##
## The credit happens at the roll, not at the coin: SPEC-run-economy's "Shared
## currencies are collected by whoever touches them" describes the collection
## path, which is not wired here, so a case proves that collecting a spawned
## pickup banks nothing a second time.

const PEER_ID: int = 1
const RUN_SEED: int = 4242
## The six ore ids of SPEC-biomes' biome table, in biome order 1 to 6.
const ORE_IDS: Array[StringName] = [
	&"copper", &"iron", &"crystal", &"pearl", &"ember_ore", &"heartstone",
]
## The biome the run in these cases stands on.
const RUN_BIOME: int = 1

var _harness: EffectHarness = null
var _player: Player = null
var _run: RunState = null
var _drops: LootDrops = null
var _container: Node2D = null
var _spawner: PickupSpawner = null
var _enemy: LootEnemyStub = null
var _data: EnemyDataStub = null
var _gains: Array[Dictionary] = []


func before_each() -> void:
	NetworkManager.start_solo()
	_harness = EffectHarness.new(self)
	_harness.setup()
	_player = _harness.make_player()
	_player.peer_id = PEER_ID
	_run = RunState.new(RUN_SEED, 1)
	_run.add_player(RunPlayerState.new(PEER_ID))
	GameState.run = _run
	_gains.clear()
	Events.currency_gained.connect(_on_currency_gained)
	_container = Node2D.new()
	_container.name = &"Entities"
	add_child_autofree(_container)
	_spawner = PickupSpawner.new()
	_spawner.name = PickupSpawner.NODE_NAME
	_spawner.spawn_path = NodePath("..")
	_container.add_child(_spawner)
	_drops = LootDrops.new()
	_drops.name = &"LootDrops"
	_container.add_child(_drops)
	_data = EnemyDataStub.new()
	_enemy = LootEnemyStub.new()
	_enemy.data = _data
	add_child_autofree(_enemy)


func after_each() -> void:
	if Events.currency_gained.is_connected(_on_currency_gained):
		Events.currency_gained.disconnect(_on_currency_gained)
	GameState.run = null
	_run = null
	EffectHarness.reset_globals()


func _on_currency_gained(player: Player, currency: StringName, amount: int) -> void:
	_gains.append({"player": player, "currency": currency, "amount": amount})


## A one-entry table of a fixed amount, so a case's numbers are deterministic.
func _table(kind: StringName, amount: int, id: StringName = &"") -> LootTable:
	var table := LootTable.new()
	var entry: Dictionary = {"kind": kind, "weight": 1.0, "min": amount, "max": amount}
	if id != &"":
		entry["id"] = id
	table.entries = [entry]
	return table


## A hit whose killer is this test's player, as `hit_landed` / `enemy_killed`
## carry one (SPEC-effect-system's `enemy_killed(enemy, hit)`, with
## `hit.owner_player` "the killer, may be null (hazard)").
func _hit() -> HitInfo:
	return _hit_by(_player)


## The same payload with no killer at all: a hazard death, which
## `hit.owner_player` describes as "may be null".
func _hazard_hit() -> HitInfo:
	return _hit_by(null)


func _hit_by(killer: Player) -> HitInfo:
	var hit := HitInfo.new()
	hit.base_damage = 10.0
	hit.owner_player = killer
	return hit


func _pickups() -> Array[Pickup]:
	var found: Array[Pickup] = []
	for child: Node in _container.get_children():
		var pickup: Pickup = child as Pickup
		if pickup != null:
			found.append(pickup)
	return found


# --- the gold path ----------------------------------------------------------


func test_an_enemy_death_rolls_its_loot_table_and_pays_gold_once_per_drop() -> void:
	_data.loot_table = _table(Pickup.KIND_GOLD, 4)
	assert_true(_drops.on_enemy_killed(_enemy, _hit()), "the host pays the drop")
	assert_eq(_gains.size(), 1, "exactly one currency_gained for one drop")
	assert_eq(_gains[0]["currency"], &"gold", "under the gold currency id")
	assert_eq(_gains[0]["amount"], 4, "the amount the table rolled")
	assert_eq(_gains[0]["player"], _player, "naming the killer")
	assert_eq(_run.shared_gold, 4, "and the shared pool moved")


func test_a_table_with_three_gold_entries_announces_three_drops() -> void:
	var table := LootTable.new()
	table.entries = [
		{"kind": Pickup.KIND_GOLD, "weight": 1.0, "min": 2, "max": 2},
		{"kind": Pickup.KIND_GOLD, "weight": 1.0, "min": 3, "max": 3},
		{"kind": Pickup.KIND_GOLD, "weight": 1.0, "min": 5, "max": 5},
	]
	_data.loot_table = table
	_drops.on_enemy_killed(_enemy, _hit())
	assert_eq(_gains.size(), 3, "one announcement per drop")
	assert_eq(_run.shared_gold, 10, "and the pool is the sum of the drops")


func test_an_enemy_with_no_loot_table_drops_nothing() -> void:
	_data.loot_table = null
	assert_false(_drops.on_enemy_killed(_enemy, _hit()), "nothing to roll")
	assert_eq(_gains.size(), 0, "nothing announced")
	assert_eq(_run.shared_gold, 0, "and nothing banked")


func test_an_enemy_node_with_no_data_drops_nothing() -> void:
	var bare := LootEnemyStub.new()
	add_child_autofree(bare)
	assert_false(_drops.on_enemy_killed(bare, _hit()), "no data, no table")
	assert_eq(_gains.size(), 0, "nothing announced")


func test_a_hazard_kill_still_pays_the_shared_pool_but_names_nobody() -> void:
	_data.loot_table = _table(Pickup.KIND_GOLD, 4)
	_drops.on_enemy_killed(_enemy, _hazard_hit())
	assert_eq(_run.shared_gold, 4, "a hazard kill still drops the shared gold")
	assert_eq(_gains.size(), 0, "but there is no player to name")


# --- the shared / per-player split ------------------------------------------


func test_a_gold_drop_moves_the_shared_pool_and_a_team_mates_echo_total_not_at_all() -> void:
	_run.add_player(RunPlayerState.new(2))
	_data.loot_table = _table(Pickup.KIND_GOLD, 7)
	_drops.on_enemy_killed(_enemy, _hit())
	assert_eq(_run.shared_gold, 7, "gold is the party's")
	assert_eq(_run.get_player(PEER_ID).echo_shards_earned, 0, "and is not echo")
	assert_eq(_run.get_player(2).echo_shards_earned, 0, "nor a team-mate's echo")


func test_an_echo_drop_moves_the_killers_own_total_and_not_the_shared_pool() -> void:
	_run.add_player(RunPlayerState.new(2))
	_data.loot_table = _table(Pickup.KIND_ECHO, 3)
	_drops.on_enemy_killed(_enemy, _hit())
	assert_eq(_run.get_player(PEER_ID).echo_shards_earned, 3, "the killer's own total")
	assert_eq(_run.get_player(2).echo_shards_earned, 0, "a team-mate earns nothing")
	assert_eq(_run.shared_gold, 0, "echo never reaches the shared gold pool")
	assert_eq(_gains.size(), 1, "and is announced once")
	assert_eq(_gains[0]["currency"], EchoShards.CURRENCY_ID)


func test_an_ore_drop_credits_the_shared_ore_pool_by_the_biomes_ore() -> void:
	_data.loot_table = _table(Pickup.KIND_ORE, 2, &"copper")
	_drops.on_enemy_killed(_enemy, _hit())
	assert_eq(int(_run.shared_ore.get(&"copper", 0)), 2, "two copper in the party's pool")
	assert_eq(_run.shared_gold, 0, "and no gold")


# --- the elite path ---------------------------------------------------------


func test_an_elite_death_pays_ore_and_echo_from_the_elite_path_alone() -> void:
	_data.loot_table = _table(Pickup.KIND_GOLD, 1)
	assert_true(_drops.on_elite_killed(_enemy, _hit()), "the host pays the elite")
	assert_eq(_run.elites_killed, 1, "the run counts the elite")
	assert_eq(int(_run.shared_ore.get(OrePayout.id_for_biome(RUN_BIOME), 0)), 1, "elites pay one ore")
	assert_between(_run.get_player(PEER_ID).echo_shards_earned, 1, 2, "and 1 to 2 echo shards")
	var echo_after_elite: int = _run.get_player(PEER_ID).echo_shards_earned
	var gold_after_elite: int = _run.shared_gold
	# The game announces an elite's death on both signals (G8a decision 77), so
	# the gold path running afterwards must not pay the elite bonus twice.
	_drops.on_enemy_killed(_enemy, _hit())
	assert_eq(_run.elites_killed, 1, "the gold path counts no second elite")
	assert_eq(_run.get_player(PEER_ID).echo_shards_earned, echo_after_elite, "and pays no second echo")
	assert_eq(int(_run.shared_ore.get(OrePayout.id_for_biome(RUN_BIOME), 0)), 1, "nor a second ore")
	assert_eq(_run.shared_gold, gold_after_elite + 1, "only the table's own gold")
	assert_eq(_gains.size(), 3, "one ore, one echo, then one gold")
	assert_eq(_gains[0]["currency"], OrePayout.CURRENCY_ID, "the elite's ore first")
	assert_eq(_gains[1]["currency"], EchoShards.CURRENCY_ID, "then its echo shards")
	assert_eq(_gains[2]["currency"], &"gold", "then the table's gold")


func test_an_elite_pays_the_biomes_own_ore_on_a_deeper_floor() -> void:
	_run.floor_index = 7
	assert_eq(OrePayout.id_for_biome(_run.biome_index), &"iron", "floor 7 is biome 2")
	_drops.on_elite_killed(_enemy, _hit())
	assert_eq(int(_run.shared_ore.get(&"iron", 0)), 1, "and the elite pays iron, not copper")


func test_elite_echo_is_raised_by_echo_collector() -> void:
	_harness.attach(_harness.source(EchoShards.ECHO_COLLECTOR_ID, "Echo Collector", RelicMarkerEffect))
	_drops.on_elite_killed(_enemy, _hit())
	var paid: int = _run.get_player(PEER_ID).echo_shards_earned
	assert_between(paid, 1, 3, "the elite payout is 1 to 2 before the +50%")
	assert_true(paid >= 1, "and never zero")


# --- the physical pickups ---------------------------------------------------


func test_a_shared_drop_spawns_one_pickup_for_everyone() -> void:
	_data.loot_table = _table(Pickup.KIND_ORE, 2, &"copper")
	_drops.on_enemy_killed(_enemy, _hit())
	var pickups: Array[Pickup] = _pickups()
	assert_eq(pickups.size(), 1, "one physical drop")
	assert_eq(pickups[0].kind, Pickup.KIND_ORE)
	assert_eq(pickups[0].id, &"copper")
	assert_eq(pickups[0].amount, 2)
	assert_eq(pickups[0].visible_to_peer, Pickup.VISIBLE_TO_ALL, "a shared currency is everyone's")


func test_a_per_player_drop_spawns_a_pickup_only_its_owner_sees() -> void:
	_data.loot_table = _table(Pickup.KIND_RELIC, 1, &"ember_boots")
	_drops.on_enemy_killed(_enemy, _hit())
	var pickups: Array[Pickup] = _pickups()
	assert_eq(pickups.size(), 1, "one physical drop")
	assert_eq(pickups[0].visible_to_peer, PEER_ID, "each player sees only their own")
	assert_true(pickups[0].is_visible_to(PEER_ID), "its owner receives it")
	assert_false(pickups[0].is_visible_to(2), "a team-mate does not")
	assert_eq(_run.shared_gold, 0, "a relic drop pays no currency")


func test_a_drop_with_no_pickup_spawner_wired_still_pays_the_currency() -> void:
	_drops.spawner = null
	_data.loot_table = _table(Pickup.KIND_GOLD, 4)
	assert_true(_drops.on_enemy_killed(_enemy, _hit()), "the currency is still the host's to pay")
	assert_eq(_run.shared_gold, 4, "the pool moved")
	assert_eq(_pickups().size(), 0, "and no pickup appeared")


func test_collecting_a_spawned_pickup_banks_nothing_a_second_time() -> void:
	_data.loot_table = _table(Pickup.KIND_GOLD, 4)
	_drops.on_enemy_killed(_enemy, _hit())
	var pickup: Pickup = _pickups()[0]
	assert_true(pickup.collect(_player), "the coin is collected")
	assert_eq(_run.shared_gold, 4, "the credit happened at the roll, not at the coin")
	assert_eq(_gains.size(), 1, "one credit per drop, never two")


# --- the client gate --------------------------------------------------------


func test_a_client_never_rolls_a_loot_table() -> void:
	var client_drops := FakeClientLootDrops.new()
	client_drops.name = &"ClientLootDrops"
	_container.add_child(client_drops)
	_data.loot_table = _table(Pickup.KIND_GOLD, 4)
	assert_false(client_drops.on_enemy_killed(_enemy, _hit()), "a client's drop is refused")
	assert_eq(_run.shared_gold, 0, "nothing banked")
	assert_eq(_gains.size(), 0, "nothing announced")
	assert_eq(_pickups().size(), 0, "and nothing spawned")


func test_a_client_never_pays_an_elite() -> void:
	var client_drops := FakeClientLootDrops.new()
	_container.add_child(client_drops)
	assert_false(client_drops.on_elite_killed(_enemy, _hit()), "refused")
	assert_eq(_run.elites_killed, 0, "no count")
	assert_eq(_run.get_player(PEER_ID).echo_shards_earned, 0, "no echo")
	assert_true(_run.shared_ore.is_empty(), "no ore")


## A `LootDrops` whose host gate says no, the shape `_FakeClientEnemySpawner`
## uses for the spawners: one overridden seam, the whole host path refused.
class FakeClientLootDrops:
	extends LootDrops

	func _can_roll() -> bool:
		return false


# --- the ore data -----------------------------------------------------------


func test_the_six_ore_resources_carry_their_biome() -> void:
	var ids: Array[StringName] = OrePayout.ore_ids()
	assert_eq(ids.size(), 6, "six OreData resources under data/ore/")
	assert_eq(ids, ORE_IDS, "in the spec's biome order")
	for biome: int in range(1, 7):
		var id: StringName = OrePayout.id_for_biome(biome)
		assert_eq(id, ORE_IDS[biome - 1], "biome %d's ore" % biome)
		var ore: OreData = OrePayout.load_ore(id)
		assert_not_null(ore, "%s loads" % id)
		assert_eq(ore.biome_index, biome, "%s is biome %d's" % [id, biome])
		assert_eq(String(ore.id), String(id), "%s's id is its file name" % id)
		assert_ne(ore.display_name, "", "%s has a display name" % id)


func test_a_biome_index_outside_the_six_reads_as_no_ore() -> void:
	assert_eq(OrePayout.id_for_biome(0), &"", "below biome 1 there is no ore")
	assert_eq(OrePayout.id_for_biome(7), &"", "past biome 6 there is no ore")


func test_the_ore_payout_amounts_are_the_specs() -> void:
	assert_eq(OrePayout.amount_for(OrePayout.KIND_ELITE), 1, "elites 1")
	assert_eq(OrePayout.amount_for(OrePayout.KIND_MINI_BOSS), 3, "mini-boss 3")
	assert_eq(OrePayout.amount_for(OrePayout.KIND_BIOME_BOSS), 6, "biome boss 6")
	assert_eq(OrePayout.amount_for(&"nothing"), 0, "an unknown kill pays nothing")


func test_wrens_plus_twenty_five_percent_is_read_off_the_effect_host() -> void:
	assert_almost_eq(OrePayout.bonus_for(_player), 1.0, 0.0001, "no passive attached, no bonus")
	_harness.attach(_harness.source(OrePayout.WREN_EFFECT_ID, "Wren's Ore", RelicMarkerEffect))
	assert_almost_eq(OrePayout.bonus_for(_player), 1.25, 0.0001, "the spec's +25%")
	assert_eq(OrePayout.amount_for_kill(OrePayout.KIND_ELITE, _player), 1, "one ore rounds to one")
	assert_eq(OrePayout.amount_for_kill(OrePayout.KIND_BIOME_BOSS, _player), 8, "six becomes eight")


func test_a_mini_boss_and_a_biome_boss_pay_their_ore_into_the_shared_pool() -> void:
	OrePayout.award(_run, _player, OrePayout.KIND_MINI_BOSS)
	assert_eq(int(_run.shared_ore.get(&"copper", 0)), 3, "a mini-boss pays three")
	OrePayout.award(_run, _player, OrePayout.KIND_BIOME_BOSS)
	assert_eq(int(_run.shared_ore.get(&"copper", 0)), 9, "and a biome boss six more")
	assert_eq(_gains.size(), 2, "each payout is announced once")
	assert_eq(_gains[0]["currency"], OrePayout.CURRENCY_ID)
