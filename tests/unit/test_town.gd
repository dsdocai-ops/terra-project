extends GutTest
## Town v1 (SPEC-town, W5-B4): the building data, buying a level, the Blacksmith's
## weapons, and the town scene with its 11 buildings and the pit edge.

const ELEVEN: Array[StringName] = [
	&"blacksmith", &"alchemist", &"map_room", &"shrine_of_echoes", &"tavern", &"relic_vault",
	&"rune_library", &"training_grounds", &"rescue_camp", &"bounty_board", &"wardrobe",
]
const FUNCTIONAL: Array[StringName] = [&"blacksmith", &"shrine_of_echoes", &"tavern"]

var _saves: int = 0
var _town: Town = null
var _build_prompts: Array[StringName] = []
var _setup_requests: Array[int] = []
var _shrine_visits: Array[int] = []
var _smith_visits: Array[int] = []


func before_each() -> void:
	NetworkManager.start_solo()
	_saves = 0
	_build_prompts.clear()
	_setup_requests.clear()
	_shrine_visits.clear()
	_smith_visits.clear()


func after_each() -> void:
	NetworkManager.disconnect_all()


func _count_save() -> void:
	_saves += 1


func _profile_with_ore(ore_id: String, amount: int) -> PlayerProfile:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.ore[ore_id] = amount
	return profile


func _make_town(profile: PlayerProfile) -> Town:
	var town: Town = (load("res://scenes/town/town.tscn") as PackedScene).instantiate() as Town
	add_child_autofree(town)
	town.load_profile(profile)
	return town


# --- data ----------------------------------------------------------------


func test_there_are_eleven_buildings_with_three_levels_each() -> void:
	assert_eq(BuildingPurchase.building_ids().size(), 11)
	for id: StringName in ELEVEN:
		var data: BuildingData = BuildingPurchase.data_for(id)
		assert_not_null(data, "%s loads" % id)
		assert_eq(data.id, id)
		assert_eq(data.levels.size(), 3, "%s has three levels" % id)
		for level: BuildingLevel in data.levels:
			assert_not_null(OrePayout.load_ore(level.ore_id), "%s costs a real ore" % id)
			assert_gt(level.ore_amount, 0)
			assert_false(level.description.is_empty())


func test_exactly_three_buildings_work_in_week_five() -> void:
	for id: StringName in ELEVEN:
		assert_eq(BuildingPurchase.data_for(id).functional_in_v1, FUNCTIONAL.has(id), String(id))


# --- buying ---------------------------------------------------------------


func test_buying_spends_the_ore_and_raises_the_level() -> void:
	var profile: PlayerProfile = _profile_with_ore("copper", 15)
	var reason: StringName = BuildingPurchase.purchase(profile, &"blacksmith", _count_save)
	assert_eq(reason, BuildingPurchase.REFUSAL_NONE)
	assert_eq(profile.building_level(&"blacksmith"), 1)
	assert_eq(profile.ore_count(&"copper"), 5)
	assert_eq(_saves, 1, "a sale saves once")


func test_not_enough_ore_refuses_and_changes_nothing() -> void:
	var profile: PlayerProfile = _profile_with_ore("copper", 9)
	assert_eq(BuildingPurchase.purchase(profile, &"blacksmith", _count_save), BuildingPurchase.REFUSAL_NOT_ENOUGH_ORE)
	assert_eq(profile.building_level(&"blacksmith"), 0)
	assert_eq(profile.ore_count(&"copper"), 9)
	assert_eq(_saves, 0)


func test_each_level_costs_the_next_ore_in_the_table() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.ore = {"copper": 10, "iron": 25, "crystal": 50}
	for expected_level: int in [1, 2, 3]:
		assert_eq(BuildingPurchase.purchase(profile, &"blacksmith", _count_save), BuildingPurchase.REFUSAL_NONE)
		assert_eq(profile.building_level(&"blacksmith"), expected_level)
	assert_eq(profile.ore_count(&"crystal"), 0)


func test_the_level_cap_is_three() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.town["blacksmith"] = 3
	assert_eq(BuildingPurchase.purchase(profile, &"blacksmith", _count_save), BuildingPurchase.REFUSAL_MAX_LEVEL)


func test_an_unknown_building_is_refused() -> void:
	assert_eq(BuildingPurchase.purchase(PlayerProfile.defaults(), &"moat", _count_save), BuildingPurchase.REFUSAL_NO_BUILDING)


# --- the blacksmith -----------------------------------------------------------


func test_the_blacksmith_sells_nothing_until_built() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.gold_banked = 1000
	assert_eq(Blacksmith.buy_weapon(profile, &"greataxe", _count_save), Blacksmith.REFUSAL_NOT_BUILT)


func test_buying_a_weapon_spends_banked_gold_and_unlocks_it() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.town["blacksmith"] = 1
	profile.gold_banked = 300
	assert_eq(Blacksmith.buy_weapon(profile, &"greataxe", _count_save), Blacksmith.REFUSAL_NONE)
	assert_eq(profile.gold_banked, 50)
	assert_true(profile.weapons_unlocked.has("greataxe"))
	assert_eq(_saves, 1)


func test_weapon_purchase_refusals() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.town["blacksmith"] = 1
	profile.gold_banked = 100
	assert_eq(Blacksmith.buy_weapon(profile, &"greataxe", _count_save), Blacksmith.REFUSAL_POOR)
	assert_eq(Blacksmith.buy_weapon(profile, &"pickaxe", _count_save), Blacksmith.REFUSAL_NOT_FOR_SALE)
	assert_eq(Blacksmith.buy_weapon(profile, &"leviathans_tooth", _count_save), Blacksmith.REFUSAL_NOT_FOR_SALE)
	profile.weapons_unlocked.append("sledgehammer")
	assert_eq(Blacksmith.buy_weapon(profile, &"sledgehammer", _count_save), Blacksmith.REFUSAL_OWNED)
	assert_eq(profile.gold_banked, 100)
	assert_eq(_saves, 0)


func test_class_granted_and_starting_weapons_are_never_for_sale() -> void:
	for id: StringName in [&"twin_daggers", &"hand_cannon", &"grave_scythe", &"longsword", &"crossbow", &"lantern_staff"]:
		assert_false(Blacksmith.stock().has(id), String(id))


# --- the scene ------------------------------------------------------------------


func test_the_town_scene_has_eleven_buildings_at_level_zero() -> void:
	_town = _make_town(PlayerProfile.defaults())
	assert_eq(_town.buildings().size(), 11)
	for candidate: Building in _town.buildings():
		assert_eq(candidate.level, 0, "%s is a sign" % candidate.building_id)


func test_a_saved_profile_shows_its_levels() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.town["tavern"] = 2
	_town = _make_town(profile)
	assert_eq(_town.building(&"tavern").level, 2)
	assert_eq(_town.building(&"blacksmith").level, 0)


func test_the_pit_edge_starts_at_stage_zero_and_shrinks() -> void:
	_town = _make_town(PlayerProfile.defaults())
	assert_eq(_town.pit_stage, 0)
	var big: int = _town.pit_cell_count()
	assert_gt(big, 0)
	_town.set_pit_stage(3)
	assert_lt(_town.pit_cell_count(), big)
	_town.set_pit_stage(99)
	assert_eq(_town.pit_stage, 3, "clamped to the last stage")


func test_the_ground_is_painted() -> void:
	_town = _make_town(PlayerProfile.defaults())
	assert_gt(_town.floor_layer.get_used_cells().size(), 100)


func test_touching_an_unbuilt_building_builds_it_when_affordable() -> void:
	var profile: PlayerProfile = _profile_with_ore("copper", 10)
	_town = _make_town(profile)
	var shop: Building = _town.building(&"blacksmith")
	assert_eq(_town.buy(&"blacksmith"), BuildingPurchase.REFUSAL_NONE)
	assert_eq(shop.level, 1, "the sign updates")
	assert_eq(profile.building_level(&"blacksmith"), 1)


func test_a_refused_build_leaves_the_sign() -> void:
	_town = _make_town(PlayerProfile.defaults())
	assert_eq(_town.buy(&"blacksmith"), BuildingPurchase.REFUSAL_NOT_ENOUGH_ORE)
	assert_eq(_town.building(&"blacksmith").level, 0)


func test_the_tavern_dive_asks_for_the_run_setup() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.town["tavern"] = 1
	_town = _make_town(profile)
	_town.run_setup_requested.connect(_on_setup_requested)
	_town.building(&"tavern").interact(_bare_player(1))
	assert_eq(_setup_requests, [1] as Array[int])


func test_the_shrine_and_blacksmith_announce_themselves() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.town["shrine_of_echoes"] = 1
	profile.town["blacksmith"] = 1
	_town = _make_town(profile)
	_town.shrine_entered.connect(_on_shrine)
	_town.blacksmith_opened.connect(_on_smith)
	_town.building(&"shrine_of_echoes").interact(_bare_player(1))
	_town.building(&"blacksmith").interact(_bare_player(1))
	assert_eq(_shrine_visits, [1] as Array[int])
	assert_eq(_smith_visits, [1] as Array[int])


func test_a_non_functional_building_does_nothing_when_built() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.town["wardrobe"] = 1
	_town = _make_town(profile)
	_town.run_setup_requested.connect(_on_setup_requested)
	_town.shrine_entered.connect(_on_shrine)
	_town.building(&"wardrobe").interact(_bare_player(1))
	assert_true(_setup_requests.is_empty() and _shrine_visits.is_empty())


func test_a_client_cannot_buy() -> void:
	_town = _make_town(_profile_with_ore("copper", 10))
	NetworkManager.is_host = false
	assert_eq(_town.buy(&"blacksmith"), &"not_host")
	NetworkManager.is_host = true
	assert_eq(_town.profile.building_level(&"blacksmith"), 0)


func _bare_player(peer_id: int) -> Player:
	var player: Player = Player.new()
	player.peer_id = peer_id
	autofree(player)
	return player


func _on_setup_requested(peer_id: int) -> void:
	_setup_requests.append(peer_id)


func _on_shrine(peer_id: int) -> void:
	_shrine_visits.append(peer_id)


func _on_smith(peer_id: int) -> void:
	_smith_visits.append(peer_id)
