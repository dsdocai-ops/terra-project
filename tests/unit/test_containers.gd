extends GutTest
## G15 (raw goals G43 and G44) — the run-economy containers: the chest and its
## `TREASURE` populator, the breakable, the mining node and the ore hooks.
## Owned by run-economy.
##
## SPEC-run-economy, "Chests, breakables, mining nodes": "`LootTable` Resource:
## weighted entries `{kind, id or rarity, weight, min, max}`. Chest rarity tiers
## common/rare/legendary; Treasure room has 2 to 3 chests; Crystal Mimic is an
## enemy disguised as a chest. Breakables (crates, barrels, bones) drop small
## gold with 30% chance. Luck stat raises rarity rolls: `rarity_roll += LUCK *
## 0.01`." SPEC-run-economy, "Currencies": "Ore | mining nodes (interactable, 3
## hits with any attack, Wren +25%) ... | shared". SPEC-relics, "Shrine flow":
## "Merchant shops and Treasure chests use the same roll helper
## `RelicRoller.roll(player, count, allow_cursed)`."
##
## Every container is an `Interactable` in SPEC-player-controller's sense — an
## area with `prompt_text`, `hold_seconds` and `interact(player)`. Only the chest
## registers a populator: SPEC-floor-generation's room-type table names
## `TREASURE` ("1 per floor, chests, dead end preferred") and names no ore or
## breakable room, so a breakable and a mining node are room *furniture* whose
## count is the room's own (`place_in(room, count)`) rather than a room type
## run-economy invents. The chest's registration is the guarded no-op pattern
## `Rope` and `Shrine` already use: **blocked on Dev A (W3-A3)**, because
## `scripts/generation/floor_generator.gd` and its populator registry are
## `floor-generation`'s and are not in the tree, so no generated floor places a
## container yet and the swap-in stays mechanical.
##
## The cases drive the real scenes, the real `LootTable` resources under
## `data/loot/` and the real `PickupSpawner`; the two in-memory fixture tables
## under `tests/helpers/` exist so a case can pin an exact amount instead of
## asserting a property of a random roll.

const PEER_ID: int = 1
const GUEST_PEER: int = 2
const RUN_SEED: int = 5150
## The floor these cases run on: biome 1, whose ore SPEC-biomes gives as copper.
const RUN_FLOOR: int = 1
## A floor in biome 2, so a case can prove the ore follows the biome.
const DEEP_FLOOR: int = 7

const CHEST_SCENE_PATH: String = "res://scenes/dungeon/interactables/chest.tscn"
const BREAKABLE_SCENE_PATH: String = "res://scenes/dungeon/interactables/breakable.tscn"
const MINING_SCENE_PATH: String = "res://scenes/dungeon/interactables/mining_node.tscn"
const CHEST_SCRIPT_PATH: String = "res://scripts/run/chest.gd"
const BREAKABLE_SCRIPT_PATH: String = "res://scripts/run/breakable.gd"
const MINING_SCRIPT_PATH: String = "res://scripts/run/mining_node.gd"
const SEAM_SCRIPT_PATH: String = "res://scripts/run/room_populator.gd"
const REGISTRY_STUB_PATH: String = "res://tests/helpers/room_registry_stub.gd"
const GOLD_FIXTURE_PATH: String = "res://tests/helpers/chest_gold_fixture.tres"
const RELIC_FIXTURE_PATH: String = "res://tests/helpers/chest_relic_fixture.tres"
## The line every blocked placement carries, so the blocker is a greppable claim
## in the code rather than a note in a doc (criterion 4).
const BLOCKER_LINE: String = "blocked on Dev A (W3-A3)"

## How many rooms the populator case populates. One draw cannot show that a
## two-to-three range is a range; the generator is seeded, so the aggregate is
## the same on every run.
const POPULATOR_ROOMS: int = 40

var _harness: EffectHarness = null
var _player: Player = null
var _run: RunState = null
var _container: Node2D = null
var _spawner: PickupSpawner = null
var _chest: Chest = null
var _breakable: Breakable = null
var _node: MiningNode = null
var _gains: Array[Dictionary] = []
var _looted: Array[Array] = []
var _rolled: Array[Array] = []
var _forwarded: Array[int] = []
var _broke: Array[Array] = []
var _mined: Array[Array] = []


func before_each() -> void:
	NetworkManager.start_solo()
	RoomRegistryStub.reset()
	_harness = EffectHarness.new(self)
	_harness.setup()
	_player = _harness.make_player()
	_player.peer_id = PEER_ID
	_run = RunState.new(RUN_SEED, RUN_FLOOR)
	_run.add_player(RunPlayerState.new(PEER_ID))
	GameState.run = _run
	_gains.clear()
	_looted.clear()
	_rolled.clear()
	_forwarded.clear()
	_broke.clear()
	_mined.clear()
	Events.currency_gained.connect(_on_currency_gained)
	_container = Node2D.new()
	_container.name = &"Entities"
	add_child_autofree(_container)
	_spawner = PickupSpawner.new()
	_spawner.name = PickupSpawner.NODE_NAME
	_spawner.spawn_path = NodePath("..")
	_container.add_child(_spawner)
	_chest = _make_chest()
	_breakable = _make_breakable()
	_node = _make_mining_node()


func after_each() -> void:
	if Events.currency_gained.is_connected(_on_currency_gained):
		Events.currency_gained.disconnect(_on_currency_gained)
	GameState.run = null
	_run = null
	RoomRegistryStub.reset()
	EffectHarness.reset_globals()
	NetworkManager.disconnect_all()


func _on_currency_gained(player: Player, currency: StringName, amount: int) -> void:
	_gains.append({"player": player, "currency": currency, "amount": amount})


func _on_looted(peer_id: int, drops: Array[Dictionary]) -> void:
	_looted.append([peer_id, drops])


func _on_relics_rolled(peer_id: int, ids: Array[StringName]) -> void:
	_rolled.append([peer_id, ids])


func _on_forwarded(peer_id: int) -> void:
	_forwarded.append(peer_id)


func _on_broke(peer_id: int, gold: int) -> void:
	_broke.append([peer_id, gold])


func _on_mined(peer_id: int, ore_id: StringName, amount: int) -> void:
	_mined.append([peer_id, ore_id, amount])


# --- the three containers, from their scenes -------------------------------


## The `spawner` is handed in before the node enters the tree, so a container
## never has to reach for a world a unit case does not build.
func _make_chest() -> Chest:
	var packed: PackedScene = load(CHEST_SCENE_PATH) as PackedScene
	assert_not_null(packed, "%s loads" % CHEST_SCENE_PATH)
	if packed == null:
		return null
	var chest: Chest = packed.instantiate() as Chest
	chest.spawner = _spawner
	chest.looted.connect(_on_looted)
	chest.relics_rolled.connect(_on_relics_rolled)
	chest.interaction_forwarded.connect(_on_forwarded)
	add_child_autofree(chest)
	return chest


func _make_breakable() -> Breakable:
	var packed: PackedScene = load(BREAKABLE_SCENE_PATH) as PackedScene
	assert_not_null(packed, "%s loads" % BREAKABLE_SCENE_PATH)
	if packed == null:
		return null
	var breakable: Breakable = packed.instantiate() as Breakable
	breakable.spawner = _spawner
	breakable.broke.connect(_on_broke)
	breakable.interaction_forwarded.connect(_on_forwarded)
	add_child_autofree(breakable)
	return breakable


func _make_mining_node() -> MiningNode:
	var packed: PackedScene = load(MINING_SCENE_PATH) as PackedScene
	assert_not_null(packed, "%s loads" % MINING_SCENE_PATH)
	if packed == null:
		return null
	var node: MiningNode = packed.instantiate() as MiningNode
	node.spawner = _spawner
	node.mined.connect(_on_mined)
	node.interaction_forwarded.connect(_on_forwarded)
	add_child_autofree(node)
	return node


func _pickups() -> Array[Pickup]:
	var found: Array[Pickup] = []
	for child: Node in _container.get_children():
		var pickup: Pickup = child as Pickup
		if pickup != null:
			found.append(pickup)
	return found


## A fresh room for a placement case: a bare `Node2D`, because SPEC-floor-
## generation's `Room` is Dev A's and a container only needs `add_child`.
func _room() -> Node2D:
	var room := Node2D.new()
	add_child_autofree(room)
	return room


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _has_property(node: Object, property_name: String) -> bool:
	for entry: Dictionary in node.get_property_list():
		if String(entry.get("name", "")) == property_name:
			return true
	return false


## A bare `Player` for the peer id a container reads off its interactor. The
## real player scene is the harness's; a container only needs `peer_id`, the way
## `Rope`'s cases use one.
func _bare_player(peer_id: int) -> Player:
	var player: Player = Player.new()
	player.peer_id = peer_id
	autofree(player)
	return player


## Holds every relic in `data/relics/` at its own `max_stacks`, so a roll finds
## nothing left to offer.
func _hold_every_relic() -> void:
	var slice: RunPlayerState = _run.get_player(PEER_ID)
	for data: RelicData in RelicRoller.load_pool():
		for copy: int in range(maxi(data.max_stacks, 1)):
			slice.relics.append(data.id)


## Three hits at one damage each, which is what empties a node.
func _mine_out() -> void:
	for hit_index: int in range(MiningNode.HITS_REQUIRED):
		_node.apply_hit(1, _player)


# =============================================================================
# The three scenes and the Interactable contract (criterion 1)
# =============================================================================


func test_the_three_container_scenes_live_where_spec_project_puts_interactables() -> void:
	for path: String in [CHEST_SCENE_PATH, BREAKABLE_SCENE_PATH, MINING_SCENE_PATH]:
		assert_true(FileAccess.file_exists(path), "%s exists (SPEC-project: scenes/dungeon/interactables/)" % path)
	for path: String in [CHEST_SCRIPT_PATH, BREAKABLE_SCRIPT_PATH, MINING_SCRIPT_PATH, SEAM_SCRIPT_PATH]:
		assert_true(FileAccess.file_exists(path), "%s exists" % path)


func test_each_container_scene_instantiates_with_the_interactable_prompt() -> void:
	for pair: Array in [
		[_chest, Chest.INTERACTABLE_LAYER, "chest"],
		[_breakable, Breakable.INTERACTABLE_LAYER, "breakable"],
		[_node, MiningNode.INTERACTABLE_LAYER, "mining node"],
	]:
		var container: Area2D = pair[0] as Area2D
		assert_not_null(container, "the %s scene's root is its container class" % pair[2])
		if container == null:
			continue
		assert_true(String(container.get("prompt_text")).length() > 0, "the %s offers an interact prompt" % pair[2])
		assert_eq(float(container.get("hold_seconds")), 0.0, "the %s is a press, not a hold" % pair[2])
		assert_eq(container.collision_layer, int(pair[1]), "the %s sits on the interactable physics layer" % pair[2])
		assert_eq(container.get_child_count(), 2, "the %s carries an interact shape and placeholder art" % pair[2])


func test_each_container_satisfies_the_interactable_contract_the_player_scans_for() -> void:
	var stub: InteractableStub = InteractableStub.new()
	add_child_autofree(stub)
	for container: Node in [_chest, _breakable, _node]:
		assert_true(container.has_method("interact"), "the player's scan duck-types on interact()")
		for property_name: String in ["prompt_text", "hold_seconds"]:
			assert_true(_has_property(container, property_name), "the container exposes %s like Interactable does" % property_name)
			assert_true(_has_property(stub, property_name), "the stub exposes %s" % property_name)
		container.call("interact", _bare_player(PEER_ID))
	assert_eq(stub.interactions, 0, "the stub is only the shape being compared")


func test_each_container_states_its_sync_contract_and_its_dev_a_blocker() -> void:
	for path: String in [CHEST_SCRIPT_PATH, BREAKABLE_SCRIPT_PATH, MINING_SCRIPT_PATH, SEAM_SCRIPT_PATH]:
		var source: String = _read(path)
		assert_true(source.contains("Sync:"), "%s states who owns it and how it syncs" % path)
		assert_true(source.contains(BLOCKER_LINE), "%s carries the greppable placement blocker" % path)


# =============================================================================
# The chest (criterion 2)
# =============================================================================


func test_a_chest_table_is_selected_by_its_tier() -> void:
	var paths: Array[String] = []
	for tier: int in LootTable.CHEST_TIERS:
		assert_true(LootTable.is_chest_tier(tier), "%d is one of the spec's three chest tiers" % tier)
		var path: String = Chest.table_path_for_tier(tier)
		assert_true(path.begins_with("res://data/loot/"), "%s lives under data/loot/ (SPEC-run-economy, Data model)" % path)
		assert_true(FileAccess.file_exists(path), "%s exists" % path)
		var table: LootTable = Chest.table_for_tier(tier)
		assert_not_null(table, "%s loads as a LootTable" % path)
		if table != null:
			assert_true(table.entries.size() > 0, "%s has entries to roll" % path)
		paths.append(path)
	assert_eq(paths.size(), 3, "one table per tier")
	assert_eq(_unique(paths).size(), 3, "and three different tables, so the tier changes what drops")


func test_an_unknown_tier_reads_as_the_common_chest() -> void:
	assert_eq(Chest.table_path_for_tier(99), Chest.table_path_for_tier(LootTable.CHEST_TIER_COMMON),
		"a chest always has something to open")


func _unique(values: Array[String]) -> Array[String]:
	var seen: Array[String] = []
	for value: String in values:
		if not seen.has(value):
			seen.append(value)
	return seen


func test_the_chest_tiers_are_the_games_own_rarity_weights() -> void:
	assert_eq(Chest.tier_from_roll(0.0), LootTable.CHEST_TIER_COMMON, "the bottom of the roll is common")
	assert_eq(Chest.tier_from_roll(0.999), LootTable.CHEST_TIER_LEGENDARY, "the top of the roll is legendary")
	assert_eq(Chest.tier_from_rarity(RelicData.Rarity.COMMON), LootTable.CHEST_TIER_COMMON, "a common roll is a common chest")
	assert_eq(Chest.tier_from_rarity(RelicData.Rarity.RARE), LootTable.CHEST_TIER_RARE, "a rare roll a rare chest")
	assert_eq(Chest.tier_from_rarity(RelicData.Rarity.EPIC), LootTable.CHEST_TIER_LEGENDARY,
		"and an epic roll, which no chest drawer holds, is promoted to the tier above it")
	assert_eq(Chest.tier_from_rarity(RelicData.Rarity.LEGENDARY), LootTable.CHEST_TIER_LEGENDARY, "a legendary roll too")
	assert_eq(Chest.tier_from_rarity(RelicData.Rarity.CURSED), LootTable.CHEST_TIER_LEGENDARY,
		"and a cursed roll, which a chest never makes, tops out rather than reading off the end")
	var total: int = 0
	for tier: int in LootTable.CHEST_TIERS:
		total += Chest.tier_weight(tier)
	assert_eq(total, 100, "the three tier weights are the game's four rarity weights, and they add up")
	assert_eq(Chest.tier_weight(LootTable.CHEST_TIER_LEGENDARY),
		RelicData.roll_weight(RelicData.Rarity.EPIC) + RelicData.roll_weight(RelicData.Rarity.LEGENDARY),
		"with the promoted epic weight landing there and nowhere else")
	assert_eq(Chest.tier_weight(LootTable.CHEST_TIER_COMMON), RelicData.roll_weight(RelicData.Rarity.COMMON),
		"and a tier's weight is its own rarity's plus any rarity promoted into it")


func test_the_chest_luck_sentence_shifts_its_tier() -> void:
	assert_eq(Chest.tier_from_roll(0.59, 0.0), LootTable.CHEST_TIER_COMMON, "0.59 is below the 0.60 common/rare line")
	assert_eq(Chest.tier_from_roll(0.59, 10.0), LootTable.CHEST_TIER_RARE,
		"SPEC-run-economy: 'rarity_roll += LUCK * 0.01' — 10 Luck buys 0.10 of roll")


func test_the_chests_relic_draw_is_the_shared_relic_roller() -> void:
	assert_eq(Chest.RELIC_COUNT, 1, "a chest normally drops one relic (design doc: Trickster 'chests can drop double')")
	assert_false(Chest.ALLOW_CURSED, "cursed relics have exactly one source, the CURSED_ALTAR (SPEC-relics)")
	for tier: int in LootTable.CHEST_TIERS:
		assert_eq(Chest.relic_count(tier), Chest.RELIC_COUNT, "every tier draws the same count")
		assert_eq(Chest.allows_cursed(tier), Chest.ALLOW_CURSED, "and none of them rolls cursed")
	assert_eq(Chest.relic_pool().size(), RelicRoller.load_pool().size(),
		"the stock is the roller's own pool, not a second copy of the content folder")


func test_a_chest_rolls_its_table_and_credits_the_gold_when_opened() -> void:
	_chest.table_path = GOLD_FIXTURE_PATH
	var drops: Array[Dictionary] = _chest.loot(_player)
	assert_false(drops.is_empty(), "the chest rolled its table")
	assert_eq(_run.shared_gold, 7, "the single-entry fixture pays its fixed amount")
	assert_eq(_gains.size(), 1, "announced exactly once")
	assert_eq(_gains[0]["currency"], &"gold")
	assert_eq(_gains[0]["amount"], 7)
	assert_eq(_gains[0]["player"], _player, "naming the opener")
	assert_eq(_looted.size(), 1, "the chest reports the loot it handed out")
	assert_eq(_looted[0][0], PEER_ID, "to the peer that opened it")


func test_a_chest_spawns_a_physical_pickup_for_its_drop() -> void:
	_chest.table_path = GOLD_FIXTURE_PATH
	_chest.loot(_player)
	var pickups: Array[Pickup] = _pickups()
	assert_eq(pickups.size(), 1, "one physical drop")
	assert_eq(pickups[0].kind, Pickup.KIND_GOLD)
	assert_eq(pickups[0].amount, 7, "carrying what was already credited")
	assert_eq(pickups[0].visible_to_peer, Pickup.VISIBLE_TO_ALL, "a shared currency is everyone's")


func test_a_chest_relic_entry_spawns_a_per_player_pickup() -> void:
	_chest.table_path = RELIC_FIXTURE_PATH
	_chest.loot(_player)
	var pickups: Array[Pickup] = _pickups()
	assert_eq(pickups.size(), 1, "one physical drop")
	assert_eq(pickups[0].kind, Pickup.KIND_RELIC)
	assert_eq(pickups[0].id, &"ember_boots", "the id the entry names")
	assert_true(pickups[0].is_visible_to(PEER_ID), "the opener receives it")
	assert_false(pickups[0].is_visible_to(GUEST_PEER), "a team-mate does not (SPEC-run-economy: per-player drops)")
	assert_eq(_run.shared_gold, 0, "a relic pickup pays no currency")


func test_a_chest_offers_relic_ids_from_the_content_folder() -> void:
	_chest.table_path = GOLD_FIXTURE_PATH
	_chest.loot(_player)
	assert_eq(_rolled.size(), 1, "the chest announced its relic draw")
	assert_eq(_rolled[0][0], PEER_ID, "to the opener")
	var known: Array[StringName] = []
	for data: RelicData in RelicRoller.load_pool():
		known.append(data.id)
	var offered: Array[StringName] = _rolled[0][1] as Array[StringName]
	assert_eq(offered.size(), Chest.RELIC_COUNT, "one relic")
	for id: StringName in offered:
		assert_true(known.has(id), "%s is a relic that exists" % id)


func test_a_chest_with_nothing_left_to_offer_offers_no_relic() -> void:
	_hold_every_relic()
	_chest.table_path = GOLD_FIXTURE_PATH
	_chest.loot(_player)
	assert_eq(_rolled.size(), 0, "the roller's max-stacks filter is the chest's filter too")
	assert_eq(_pickups().size(), 1, "the gold still drops")


func test_a_chest_opens_once() -> void:
	_chest.table_path = GOLD_FIXTURE_PATH
	_chest.loot(_player)
	var again: Array[Dictionary] = _chest.loot(_player)
	assert_true(again.is_empty(), "the second open yields nothing")
	assert_eq(_run.shared_gold, 7, "and pays no second time")
	assert_eq(_gains.size(), 1, "one credit per chest")
	assert_eq(_pickups().size(), 1, "and one drop")
	assert_true(_chest.is_open(), "the chest records that it was opened")


func test_a_chest_opens_its_own_tiers_table_when_no_table_is_named() -> void:
	_chest.interact(_bare_player(PEER_ID))
	assert_true(_chest.is_open(), "the host's interact is the open")
	assert_eq(Chest.table_path_for_tier(_chest.tier()), _chest.table_path,
		"and the table it rolled is the one its tier names")
	assert_true(LootTable.is_chest_tier(_chest.tier()), "%d is a chest tier" % _chest.tier())


func test_a_client_never_opens_a_chest() -> void:
	NetworkManager.is_host = false
	_chest.table_path = GOLD_FIXTURE_PATH
	assert_true(_chest.loot(_player).is_empty(), "a client rolls nothing (SPEC-run-economy, Multiplayer ownership)")
	assert_eq(_run.shared_gold, 0, "nothing is credited")
	assert_eq(_pickups().size(), 0, "and nothing spawns")


func test_a_client_interaction_is_forwarded_and_opens_nothing() -> void:
	NetworkManager.is_host = false
	_chest.interact(_bare_player(GUEST_PEER))
	assert_eq(_forwarded, [GUEST_PEER] as Array[int], "the client hands its open to the request path")
	assert_false(_chest.is_open(), "and opens nothing locally")
	assert_eq(_gains.size(), 0, "nothing is credited")


func test_a_chest_with_no_live_run_pays_nothing() -> void:
	GameState.run = null
	_chest.table_path = GOLD_FIXTURE_PATH
	assert_true(_chest.loot(_player).is_empty(), "there is nowhere to put the gold")
	assert_false(_chest.is_open(), "and the chest stays shut rather than being spent")
	assert_eq(_pickups().size(), 0, "nothing spawns")


# =============================================================================
# The breakable (criterion 2)
# =============================================================================


func test_the_breakable_chance_is_the_specs_thirty_percent() -> void:
	assert_almost_eq(Breakable.GOLD_DROP_CHANCE, 0.30, 0.0001, "SPEC-run-economy: 'drop small gold with 30% chance'")
	assert_almost_eq(Breakable.default_gold_chance(), Breakable.GOLD_DROP_CHANCE, 0.0001,
		"and data/loot/breakable.tres carries the same number, so the two cannot drift")
	assert_almost_eq(_breakable.gold_chance, Breakable.GOLD_DROP_CHANCE, 0.0001, "a fresh breakable starts at the spec's chance")


func test_the_breakable_gold_range_is_small() -> void:
	var range: Vector2i = Breakable.gold_range()
	assert_eq(range, Vector2i(Breakable.SMALL_GOLD_MIN, Breakable.SMALL_GOLD_MAX),
		"data/loot/breakable.tres carries the same range as the constants")
	assert_between(range.x, 1, 3, "SPEC-run-economy: 'small gold' — one to three, not a chest")
	assert_between(range.y, 1, 3, "at both ends of the range")


func test_a_breakable_drops_small_gold_when_the_chance_passes() -> void:
	_breakable.gold_chance = 1.0
	var paid: int = _breakable.break_it(_player)
	assert_between(paid, Breakable.SMALL_GOLD_MIN, Breakable.SMALL_GOLD_MAX, "the drop is inside the table's range")
	assert_eq(_run.shared_gold, paid, "and the shared pool moved by it")
	assert_eq(_gains.size(), 1, "announced once")
	assert_eq(_gains[0]["currency"], &"gold")
	assert_eq(_gains[0]["amount"], paid)
	assert_eq(_broke.size(), 1, "the break is reported with its yield")
	assert_eq(_broke[0][0], PEER_ID)
	assert_eq(_broke[0][1], paid)
	assert_eq(_pickups().size(), 1, "and one coin hits the floor")


func test_a_breakable_drops_nothing_when_the_chance_fails() -> void:
	_breakable.gold_chance = 0.0
	var paid: int = _breakable.break_it(_player)
	assert_eq(paid, 0, "the 70% of the roll that drops nothing")
	assert_eq(_run.shared_gold, 0, "nothing is credited")
	assert_eq(_gains.size(), 0, "and nothing is announced")
	assert_eq(_pickups().size(), 0, "and nothing spawns")
	assert_true(_breakable.is_broken(), "a breakable still breaks")


func test_a_breakable_breaks_once() -> void:
	_breakable.gold_chance = 1.0
	_breakable.break_it(_player)
	assert_eq(_breakable.break_it(_player), 0, "the second hit finds nothing left to break")
	assert_eq(_broke.size(), 1, "so the break is reported once")
	assert_eq(_gains.size(), 1, "and pays no second time")


func test_a_breakable_is_broken_by_any_single_hit() -> void:
	assert_eq(Breakable.HITS_REQUIRED, 1, "a crate, a barrel or a pile of bones is one hit, not a mining node")
	_breakable.gold_chance = 0.0
	assert_true(_breakable.apply_hit(_player), "the hit lands")
	assert_true(_breakable.is_broken())
	assert_false(_breakable.apply_hit(_player), "and a later hit finds nothing to break")


func test_a_client_never_breaks_a_breakable() -> void:
	NetworkManager.is_host = false
	_breakable.gold_chance = 1.0
	assert_false(_breakable.apply_hit(_player), "only the host breaks anything")
	assert_false(_breakable.is_broken(), "and nothing is broken locally")
	assert_eq(_run.shared_gold, 0, "and nothing is paid")
	_breakable.interact(_bare_player(GUEST_PEER))
	assert_eq(_forwarded, [GUEST_PEER] as Array[int], "the client's hit is forwarded instead")


# =============================================================================
# The mining node and the ore hooks (criterion 2)
# =============================================================================


func test_a_mining_node_takes_three_hits_with_any_attack() -> void:
	assert_eq(MiningNode.HITS_REQUIRED, 3, "SPEC-run-economy: '3 hits with any attack'")
	assert_true(_node.apply_hit(1), "the first hit lands")
	assert_eq(_node.hits_taken, 1, "and is counted")
	assert_true(_node.apply_hit(50), "the damage does not matter")
	assert_true(_node.apply_hit(999), "nor does a huge one: the count is what empties it")
	assert_eq(_node.hits_taken, 3)
	assert_true(_node.is_depleted(), "the third hit empties it")
	assert_eq(_node.hits_left(), 0)
	assert_false(_node.apply_hit(1), "and a fourth hit finds nothing")


func test_the_interact_path_is_one_hit() -> void:
	_node.interact(_bare_player(PEER_ID))
	assert_eq(_node.hits_taken, 1, "the prompt and an attack are the same count")


func test_a_mining_node_yields_the_biomes_ore() -> void:
	var ore_id: StringName = OrePayout.id_for_biome(_run.biome_index)
	assert_eq(ore_id, &"copper", "floor 1 is biome 1 (SPEC-biomes)")
	assert_eq(_node.ore_id(), ore_id, "the node reads the ore off the live run's biome")
	_mine_out()
	assert_eq(int(_run.shared_ore.get(ore_id, 0)), MiningNode.MINE_YIELD, "the node's own yield of that ore")
	assert_eq(_gains.size(), 1, "announced once")
	assert_eq(_gains[0]["currency"], OrePayout.CURRENCY_ID)
	assert_eq(_gains[0]["amount"], MiningNode.MINE_YIELD)
	assert_eq(_mined.size(), 1, "and reported with its id")
	assert_eq(_mined[0][0], PEER_ID)
	assert_eq(_mined[0][1], ore_id)
	assert_eq(_mined[0][2], MiningNode.MINE_YIELD)


func test_a_mining_node_on_a_deeper_floor_yields_that_biomes_ore() -> void:
	_run.floor_index = DEEP_FLOOR
	assert_eq(OrePayout.id_for_biome(_run.biome_index), &"iron", "floor 7 is biome 2")
	_mine_out()
	assert_eq(int(_run.shared_ore.get(&"iron", 0)), MiningNode.MINE_YIELD, "iron, not copper")
	assert_eq(int(_run.shared_ore.get(&"copper", 0)), 0, "and nothing of the first biome's")


func test_a_mining_node_with_no_live_run_pays_nothing_and_is_not_spent() -> void:
	GameState.run = null
	_mine_out()
	assert_eq(_gains.size(), 0, "no run, no payout")
	assert_eq(_mined.size(), 0, "and no seam is reported as mined")
	assert_false(_node.is_depleted(), "the seam is not spent for nothing, the way a chest with no run stays shut")
	assert_eq(_node.hits_left(), MiningNode.HITS_REQUIRED, "and the hits went uncounted rather than paid for with the seam")


func test_a_mining_node_pays_the_party_and_spawns_the_ore_it_paid() -> void:
	_mine_out()
	var pickups: Array[Pickup] = _pickups()
	assert_eq(pickups.size(), 1, "one physical ore chunk")
	assert_eq(pickups[0].kind, Pickup.KIND_ORE)
	assert_eq(pickups[0].id, &"copper")
	assert_eq(pickups[0].amount, MiningNode.MINE_YIELD, "carrying what was already credited")
	assert_eq(pickups[0].visible_to_peer, Pickup.VISIBLE_TO_ALL, "ore is the party's (SPEC-run-economy, Currencies)")


func test_wrens_passive_raises_the_mined_ore_by_a_quarter() -> void:
	_harness.attach(_harness.source(OrePayout.WREN_EFFECT_ID, "Wren's Ore", RelicMarkerEffect))
	_mine_out()
	assert_eq(int(_run.shared_ore.get(&"copper", 0)), 4, "three ore through Wren's +25% rounds to four")
	assert_eq(_mined[0][2], 4, "and the pickup carries the raised amount")


func test_the_mined_row_is_the_nodes_own_and_pays_the_same_with_no_earner() -> void:
	assert_eq(OrePayout.amount_for(OrePayout.KIND_MINED), MiningNode.MINE_YIELD,
		"SPEC's kill sentence names 'elites 1, mini-boss 3, biome boss 6'; the node's row is its own")
	assert_eq(OrePayout.amount_for_kill(OrePayout.KIND_MINED, null), MiningNode.MINE_YIELD,
		"and with no earner attached it pays the bare yield")
	assert_ne(OrePayout.KIND_MINED, OrePayout.KIND_ELITE, "a mined node is not a kill")
	assert_eq(OrePayout.amount_for(OrePayout.KIND_ELITE), 1, "and the spec's three kill rows are untouched")
	assert_eq(OrePayout.amount_for(OrePayout.KIND_BIOME_BOSS), 6, "including the boss's six")


func test_a_client_never_mines() -> void:
	NetworkManager.is_host = false
	assert_false(_node.apply_hit(1), "only the host mines")
	assert_eq(_node.hits_taken, 0, "the hit is not even counted")
	_node.interact(_bare_player(GUEST_PEER))
	assert_eq(_forwarded, [GUEST_PEER] as Array[int], "the client's hit is forwarded instead")


# =============================================================================
# The TREASURE populator, its placement and the guarded registration
# (criteria 3 and 4)
# =============================================================================


func test_the_treasure_populator_spawns_two_or_three_chests() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = RUN_SEED
	var found: Dictionary[int, int] = {}
	for room_index: int in range(POPULATOR_ROOMS):
		var size: int = Chest.populate_room(_room(), rng).size()
		found[size] = int(found.get(size, 0)) + 1
	for size: int in found.keys():
		assert_between(size, Chest.MIN_CHESTS, Chest.MAX_CHESTS, "SPEC-run-economy: 'Treasure room has 2 to 3 chests'")
	assert_true(found.has(Chest.MIN_CHESTS), "the bottom of the range is reachable")
	assert_true(found.has(Chest.MAX_CHESTS), "and so is the top, so two-to-three is a range and not a constant")


func test_the_treasure_populator_adds_chests_to_the_room_and_nothing_else() -> void:
	var room: Node2D = _room()
	var spawned: Array[Chest] = Chest.populate_room(room)
	assert_between(spawned.size(), Chest.MIN_CHESTS, Chest.MAX_CHESTS, "two or three chests")
	assert_eq(room.get_child_count(), spawned.size(), "and they are the only children it added")
	for child: Node in room.get_children():
		assert_not_null(child as Chest, "every child the populator adds is a Chest")
	for chest: Chest in spawned:
		assert_eq(chest.position, Vector2.ZERO, "a chest sits at the room origin until the anchor lands")


func test_a_placed_chest_is_ready_to_open() -> void:
	var room: Node2D = _room()
	var spawned: Array[Chest] = Chest.populate_room(room)
	assert_true(spawned.size() > 0, "the room got chests")
	if spawned.is_empty():
		return
	var chest: Chest = spawned[0]
	assert_false(chest.is_open(), "a fresh chest is closed")
	chest.table_path = GOLD_FIXTURE_PATH
	assert_false(chest.loot(_player).is_empty(), "and it opens and pays")


func test_a_breakable_and_a_mining_node_are_placed_by_count_not_by_room_type() -> void:
	var room: Node2D = _room()
	var crates: Array[Breakable] = Breakable.place_in(room, 3)
	var nodes: Array[MiningNode] = MiningNode.place_in(room, 2)
	assert_eq(crates.size(), 3, "the caller names how many crates the room holds")
	assert_eq(nodes.size(), 2, "and how many ore veins")
	assert_eq(room.get_child_count(), 5, "and they are the only children added")
	for crate: Breakable in crates:
		assert_not_null(crate, "the placement adds Breakables")
	for node: MiningNode in nodes:
		assert_not_null(node, "the placement adds MiningNodes")


func test_placement_refuses_a_missing_room_and_runs_on_the_host_only() -> void:
	assert_eq(Chest.populate_room(null).size(), 0, "a null room is refused rather than crashing")
	assert_eq(Breakable.place_in(null, 1).size(), 0)
	assert_eq(MiningNode.place_in(null, 1).size(), 0)
	var room: Node2D = _room()
	NetworkManager.is_host = false
	assert_eq(Chest.populate_room(room).size(), 0, "a client places no containers")
	assert_eq(Breakable.place_in(room, 1).size(), 0)
	assert_eq(MiningNode.place_in(room, 1).size(), 0)
	assert_eq(room.get_child_count(), 0, "and adds nothing at all")


# --- the guarded registration ------------------------------------------------


func test_the_treasure_populator_callable_targets_the_treasure_room() -> void:
	assert_eq(Chest.treasure_populator().get_method(), &"_populate_treasure_room", "the TREASURE populator body")
	assert_true(Chest.treasure_populator().is_valid(), "and is a Callable whether or not the registry exists")
	assert_eq(Chest.ROOM_TYPE, &"TREASURE", "SPEC-floor-generation: 'TREASURE | 1 per floor, chests'")


func test_the_registration_is_a_guarded_no_op_while_dev_as_generator_is_absent() -> void:
	var registry_exists: bool = ResourceLoader.exists(RoomPopulator.GENERATOR_SCRIPT_PATH)
	assert_eq(Chest.register_populator(), registry_exists,
		"the registration succeeds exactly when Dev A's floor_generator.gd exists")
	assert_eq(Chest.blocker_warnings(), 0 if registry_exists else 1,
		"the blocked path notes its blocker once per process, not once per call")
	if registry_exists:
		return
	assert_eq(Chest.register_populator(), false, "a second call is the same no-op")
	assert_eq(Chest.blocker_warnings(), 1, "with no second warning, because a floor change must not reprint it")
	assert_eq(RoomRegistryStub.registered.size(), 0, "and nothing reached a registry")


func test_the_generator_path_is_the_one_the_floor_sync_seam_already_guards() -> void:
	assert_eq(RoomPopulator.GENERATOR_SCRIPT_PATH, FloorGeneratorSeam.GENERATOR_SCRIPT_PATH,
		"run-economy's populator guard and networking's floor seam name the same file, so one landing swaps both")
	assert_eq(RoomPopulator.GENERATOR_SCRIPT_PATH, "res://scripts/generation/floor_generator.gd",
		"and it is where SPEC-project puts floor-generation's generator")


func test_the_registration_resolves_the_treasure_room_type_off_the_generator_script() -> void:
	var stub: Script = load(REGISTRY_STUB_PATH) as Script
	assert_not_null(stub, "%s loads" % REGISTRY_STUB_PATH)
	if stub == null:
		return
	var room_types: Dictionary = stub.get_script_constant_map().get(&"RoomType", {})
	assert_true(room_types.has("TREASURE"), "the registry double declares TREASURE")
	assert_true(room_types.has("ROPE"), "and the rope's type beside it")
	assert_eq(RoomPopulator.room_type_value(stub, Chest.ROOM_TYPE), room_types.get("TREASURE", null),
		"the chest resolves RoomType.TREASURE off whatever script the path points at")
	assert_ne(RoomPopulator.room_type_value(stub, Chest.ROOM_TYPE), room_types.get("ROPE", null),
		"and never the rope's type")
	assert_eq(Chest.room_type_value(stub), RoomPopulator.room_type_value(stub, Chest.ROOM_TYPE),
		"the chest's own read is the shared seam helper's")
	assert_null(Chest.room_type_value(Shrine), "a script with no RoomType enumeration resolves nothing")
	assert_null(RoomPopulator.room_type_value(null, Chest.ROOM_TYPE), "and neither does no script at all")


func test_a_container_with_no_pickup_spawner_still_pays_the_currency() -> void:
	_chest.spawner = null
	_breakable.spawner = null
	_node.spawner = null
	_mine_out()
	_breakable.gold_chance = 1.0
	_breakable.break_it(_player)
	_chest.table_path = GOLD_FIXTURE_PATH
	_chest.loot(_player)
	assert_eq(_pickups().size(), 0, "there is nowhere to put a coin")
	assert_eq(int(_run.shared_ore.get(&"copper", 0)), MiningNode.MINE_YIELD, "but the ore pool still moved")
	assert_eq(_run.shared_gold, 7 + _broke[0][1], "and so did the gold: the currency is the host's to give")


func test_the_host_body_of_each_container_is_readable_on_its_own() -> void:
	assert_true(_chest.has_method("loot"), "the chest's open is a call a case can drive")
	assert_true(_breakable.has_method("break_it"), "the breakable's break is too")
	assert_true(_breakable.has_method("apply_hit"), "and combat reaches it through apply_hit")
	assert_true(_node.has_method("apply_hit"), "a mining node the same way")
	assert_true(_node.has_method("ore_id"), "and the node exposes the ore it will yield")
	assert_eq(_node.hits_left(), MiningNode.HITS_REQUIRED, "a fresh node has its full count left")
	assert_false(_breakable.is_broken(), "and a fresh breakable is whole")
	assert_false(_chest.is_open(), "and a fresh chest is shut")
