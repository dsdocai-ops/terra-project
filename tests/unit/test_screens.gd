extends GutTest
## The week 5 screens (SPEC-ui-hud, W5-B6): the row models, the death and
## inventory screens, the pause list, the town menus and run banking. The models
## are pure, so most cases assert on rows; the screens are driven through their
## own choose paths, the way a click would.

const HUD_SCENE := "res://scenes/ui/hud.tscn"
const TOWN_SCENE := "res://scenes/town/town.tscn"

var _returns: int = 0
var _town: Town = null


func before_each() -> void:
	NetworkManager.start_solo()
	GameState.run = null
	_returns = 0


func after_each() -> void:
	if GameState.run != null:
		GameState.end_run(RunEndReason.Reason.ABORT)
	GameState.run = null
	GameState.last_run_summary = ""
	NetworkManager.disconnect_all()


func _on_return() -> void:
	_returns += 1


func _result(reason: RunEndReason.Reason = RunEndReason.Reason.DEFEAT) -> RunResult:
	var run: RunState = RunState.new(77, 1)
	var slice: RunPlayerState = RunPlayerState.new(1, &"wren", &"ranger")
	slice.relics = [&"a", &"b"]
	slice.echo_shards_earned = 9
	slice.class_xp_earned = 120
	run.add_player(slice)
	run.shared_gold = 200
	run.shared_ore = {&"copper": 6}
	run.floors_cleared = 4
	var result: RunResult = RunResult.new(reason, run.seed, run.floors_cleared)
	RunEconomyRules.settle(result, run)
	return result


func _cells(section: ScreenPanel.Section, row: int) -> PackedStringArray:
	return section.rows[row]


# --- pause --------------------------------------------------------------------


func test_pause_in_the_menu_has_resume_settings_codex() -> void:
	assert_eq(ScreenModels.pause_items(false, false, false), ["Resume", "Settings", "Codex"] as Array[String])


func test_pause_in_a_co_op_run_adds_quit_to_town_and_leave_co_op() -> void:
	var items: Array[String] = ScreenModels.pause_items(true, true, false)
	assert_eq(items, ["Resume", "Settings", "Codex", "Quit to Town", "Leave Co-op"] as Array[String])


func test_quit_to_town_asks_to_be_pressed_again() -> void:
	var items: Array[String] = ScreenModels.pause_items(true, false, true)
	assert_true(items[3].begins_with("Press again"))
	assert_eq(ScreenModels.pause_action(items, 3), &"quit_to_town")


func test_pause_actions_map_by_label() -> void:
	var items: Array[String] = ScreenModels.pause_items(true, true, false)
	assert_eq(ScreenModels.pause_action(items, 0), &"resume")
	assert_eq(ScreenModels.pause_action(items, 4), &"leave_coop")
	assert_eq(ScreenModels.pause_action(items, 9), &"")


# --- death screen rows --------------------------------------------------------


func test_death_title_follows_the_reason() -> void:
	assert_eq(ScreenModels.death_title(RunEndReason.Reason.DEFEAT), "YOU FELL")
	assert_eq(ScreenModels.death_title(RunEndReason.Reason.EXTRACT), "YOU CLIMBED OUT")
	assert_eq(ScreenModels.death_title(RunEndReason.Reason.VICTORY), "THE PIT IS QUIET")
	assert_eq(ScreenModels.death_title(RunEndReason.Reason.ABORT), "YOU LEFT THE PIT")


func test_death_table_shows_kept_and_lost_from_the_result() -> void:
	var sections: Array[ScreenPanel.Section] = ScreenModels.death_sections(_result(), 1)
	var table: ScreenPanel.Section = sections[0]
	assert_eq(_cells(table, 1), PackedStringArray(["Gold", "50", "150"]), "25% of 200 kept")
	assert_eq(_cells(table, 2), PackedStringArray(["Ore", "0", "6"]))
	assert_eq(_cells(table, 3), PackedStringArray(["Relics", "0", "2"]))
	assert_eq(_cells(table, 4), PackedStringArray(["Echo Shards", "9", "-"]))
	assert_eq(_cells(table, 5), PackedStringArray(["Class XP", "120", "-"]))


func test_an_extract_keeps_everything_on_the_screen() -> void:
	var table: ScreenPanel.Section = ScreenModels.death_sections(_result(RunEndReason.Reason.EXTRACT), 1)[0]
	assert_eq(_cells(table, 1), PackedStringArray(["Gold", "200", "0"]))
	assert_eq(_cells(table, 2), PackedStringArray(["Ore", "6", "0"]))


func test_the_dive_section_carries_floors_and_seed() -> void:
	var dive: ScreenPanel.Section = ScreenModels.death_sections(_result(), 1)[1]
	assert_eq(_cells(dive, 0), PackedStringArray(["Floors cleared", "4"]))
	assert_eq(_cells(dive, 1), PackedStringArray(["Seed", "77"]))


func test_an_unknown_peer_still_gets_a_table_of_zeros() -> void:
	var table: ScreenPanel.Section = ScreenModels.death_sections(_result(), 42)[0]
	assert_eq(_cells(table, 1), PackedStringArray(["Gold", "0", "0"]))


func test_the_death_screen_shows_and_returns_to_town() -> void:
	var screen: DeathScreen = DeathScreen.new()
	add_child_autofree(screen)
	screen.return_requested.connect(_on_return)
	assert_false(screen.visible)
	screen.show_result(_result(), 1)
	assert_true(screen.visible)
	assert_eq(screen.panel.title, "YOU FELL")
	assert_eq(screen.panel.buttons, ["Return to Town"] as Array[String])
	screen.panel.chosen.emit(0)
	assert_false(screen.visible)
	assert_eq(_returns, 1)


# --- inventory --------------------------------------------------------------------


func test_relics_group_into_stacks_in_pickup_order() -> void:
	var stacks: Array[Array] = ScreenModels.relic_stacks([&"b", &"a", &"b"])
	assert_eq(stacks.size(), 2)
	assert_eq(stacks[0], [&"b", 2])
	assert_eq(stacks[1], [&"a", 1])


func test_inventory_lists_all_eleven_stats_even_without_a_stat_block() -> void:
	var sections: Array[ScreenPanel.Section] = ScreenModels.inventory_sections(RunPlayerState.new(1), null, {})
	var stats: ScreenPanel.Section = sections[1]
	assert_eq(stats.rows.size(), 11)
	assert_eq(_cells(stats, 0)[1], "-")


func test_inventory_formats_stat_values() -> void:
	assert_eq(ScreenModels.format_stat(120.0), "120")
	assert_eq(ScreenModels.format_stat(0.08), "0.08")
	var values: Dictionary[int, float] = {0: 120.0, 10: 2.0}
	var stats: ScreenPanel.Section = ScreenModels.inventory_sections(RunPlayerState.new(1), null, values)[1]
	assert_eq(_cells(stats, 0), PackedStringArray(["Max HP", "120"]))
	assert_eq(_cells(stats, 10), PackedStringArray(["Luck", "2"]))


func test_inventory_shows_the_loadout() -> void:
	var run: RunState = RunState.new(1, 7)
	var slice: RunPlayerState = RunPlayerState.new(1, &"wren", &"mage")
	slice.add_weapon(&"pickaxe", [&"fast", &"sharp"])
	slice.add_weapon(&"lantern_staff")
	run.add_player(slice)
	var loadout: ScreenPanel.Section = ScreenModels.inventory_sections(slice, run, {})[2]
	assert_eq(_cells(loadout, 0), PackedStringArray(["Class", "Mage"]))
	assert_eq(_cells(loadout, 1), PackedStringArray(["Pickaxe", "+2 mutations"]))
	assert_eq(_cells(loadout, 2), PackedStringArray(["Lantern Staff", ""]))
	assert_eq(_cells(loadout, 5)[1], "7 / 30")


func test_the_inventory_screen_toggles() -> void:
	var screen: InventoryScreen = InventoryScreen.new()
	add_child_autofree(screen)
	screen.toggle(1)
	assert_true(screen.visible)
	screen.toggle(1)
	assert_false(screen.visible)


func test_the_hud_opens_the_death_screen_when_the_run_ends() -> void:
	var hud: Hud = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	GameState.start_run(5, 1, [PlayerSpawnInfo.new(1)])
	GameState.end_run(RunEndReason.Reason.DEFEAT)
	assert_true(hud.death_screen.visible)
	assert_false(hud.pause_layer.visible)


func test_the_hud_builds_inventory_and_death_screens_hidden() -> void:
	var hud: Hud = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	assert_false(hud.inventory_screen.visible)
	assert_false(hud.death_screen.visible)


func test_quit_to_town_needs_two_presses_then_ends_the_run() -> void:
	var hud: Hud = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	GameState.start_run(5, 1, [PlayerSpawnInfo.new(1), PlayerSpawnInfo.new(2)])
	hud.set_paused_view(true)
	var at: int = hud.pause_items.find("Quit to Town")
	assert_gt(at, -1)
	hud._on_pause_chosen(at)
	assert_not_null(GameState.run, "the first press only asks")
	hud._on_pause_chosen(at)
	assert_null(GameState.run, "the second press counts as a death")


# --- the rope vote prompt -----------------------------------------------------------


func test_the_vote_prompt_waits_for_the_living_not_just_the_voters() -> void:
	var hud: Hud = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	hud._on_rope_vote_updated({2: true})
	assert_true(hud.rope_vote_prompt.visible)
	assert_eq(hud.rope_vote_prompt.agreed, 1)
	hud._on_rope_vote_updated({})
	assert_false(hud.rope_vote_prompt.visible, "a cancel closes it")


# --- town menus ---------------------------------------------------------------------


func _make_town(profile: PlayerProfile) -> Town:
	var town: Town = (load(TOWN_SCENE) as PackedScene).instantiate() as Town
	add_child_autofree(town)
	town.load_profile(profile)
	return town


func test_the_blacksmith_menu_lists_stock_by_price() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.town["blacksmith"] = 1
	profile.gold_banked = 160
	var ids: Array[StringName] = []
	var section: ScreenPanel.Section = ScreenModels.blacksmith_sections(profile, ids)[0]
	assert_eq(section.heading, "Gold 160")
	assert_eq(ids.size(), Blacksmith.stock().size())
	assert_eq(int(Blacksmith.PRICES[ids[0]]), 150, "cheapest first")
	assert_eq(_cells(section, ids.find(&"greataxe"))[1], "250 - too dear")
	assert_eq(_cells(section, ids.find(&"shortbow"))[1], "150")


func test_buying_a_weapon_through_the_menu_spends_gold() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.town["blacksmith"] = 1
	profile.gold_banked = 400
	_town = _make_town(profile)
	_town.menus.open_blacksmith()
	assert_true(_town.menus.is_open())
	var index: int = _town.menus._weapon_ids.find(&"sledgehammer")
	_town.menus.panel.chosen.emit(index)
	assert_eq(profile.gold_banked, 250)
	assert_true(profile.weapons_unlocked.has("sledgehammer"))
	assert_eq(_town.menus.panel.subtitle, "Bought Sledgehammer")


func test_a_poor_blacksmith_visit_says_so() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.town["blacksmith"] = 1
	_town = _make_town(profile)
	_town.menus.open_blacksmith()
	_town.menus.panel.chosen.emit(0)
	assert_eq(_town.menus.panel.subtitle, "Not enough gold")


func test_the_build_prompt_shows_cost_and_shortfall() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.ore["copper"] = 4
	var section: ScreenPanel.Section = ScreenModels.build_sections(profile, &"alchemist")[0]
	assert_eq(_cells(section, 2), PackedStringArray(["Cost", "10 Copper"]))
	assert_eq(_cells(section, 3), PackedStringArray(["You have", "4"]))
	assert_eq(_cells(section, 4)[0], "Needs 6 more")


func test_touching_an_unbuilt_building_asks_before_it_spends() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.ore["copper"] = 10
	_town = _make_town(profile)
	_town.building(&"blacksmith").interact(_bare_player(1))
	assert_eq(_town.menus.screen, TownMenus.Screen.BUILD)
	assert_eq(profile.ore_count(&"copper"), 10, "nothing is spent by touching")
	_town.menus.panel.chosen.emit(0)
	assert_eq(profile.building_level(&"blacksmith"), 1)
	assert_false(_town.menus.is_open())


func test_cancelling_the_build_prompt_spends_nothing() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.ore["copper"] = 10
	_town = _make_town(profile)
	_town.building(&"blacksmith").interact(_bare_player(1))
	_town.menus.panel.chosen.emit(1)
	assert_eq(profile.building_level(&"blacksmith"), 0)
	assert_false(_town.menus.is_open())


func test_the_tavern_opens_the_setup_screen_with_a_default_selection() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.town["tavern"] = 1
	_town = _make_town(profile)
	_town.building(&"tavern").interact(_bare_player(1))
	assert_eq(_town.menus.screen, TownMenus.Screen.SETUP)
	assert_true(_town.run_setup.selections.has(1))
	assert_true(_town.menus.panel.buttons.has("Ready"))
	assert_true(_town.menus.panel.buttons.has("Start dive"), "the solo host can start")


func test_setup_cycles_class_weapons_and_floor() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.town["tavern"] = 1
	profile.map_room_deepest_rope = 7
	_town = _make_town(profile)
	_town.menus.open_setup()
	var items: Array[String] = _town.menus.panel.buttons
	_town.menus.panel.chosen.emit(items.find("Class: Warrior"))
	assert_ne(_town.run_setup.selections[1].class_id, &"warrior")
	_town.menus.panel.chosen.emit(_town.menus.panel.buttons.find("Weapon 2: Crossbow"))
	assert_eq(_town.run_setup.selections[1].weapon_ids[1], &"lantern_staff")
	_town.menus.panel.chosen.emit(_town.menus.panel.buttons.find("Start floor: 1"))
	assert_eq(_town.run_setup.start_floor, 2)


func test_ready_then_start_dive_begins_the_run() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.town["tavern"] = 1
	_town = _make_town(profile)
	_town.menus.open_setup()
	_town.menus.panel.chosen.emit(_town.menus.panel.buttons.find("Ready"))
	assert_true(_town.run_setup.selections[1].ready)
	_town.menus.panel.chosen.emit(_town.menus.panel.buttons.find("Start dive"))
	assert_not_null(GameState.run, "the dive started")
	assert_false(_town.menus.is_open())


func test_start_dive_before_ready_is_refused_with_a_message() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	_town = _make_town(profile)
	_town.menus.open_setup()
	_town.menus.panel.chosen.emit(_town.menus.panel.buttons.find("Start dive"))
	assert_null(GameState.run)
	assert_eq(_town.menus.panel.subtitle, "Everyone has to be ready")


func test_changing_a_choice_unreadies_the_player() -> void:
	_town = _make_town(PlayerProfile.defaults())
	_town.menus.open_setup()
	_town.menus.panel.chosen.emit(_town.menus.panel.buttons.find("Ready"))
	_town.menus.panel.chosen.emit(_town.menus.panel.buttons.find("Class: Warrior"))
	assert_false(_town.run_setup.selections[1].ready)


func test_the_setup_party_rows_show_ready_state() -> void:
	var setup: RunSetup = RunSetup.new()
	setup.submit(SelectionState.new(1))
	setup.set_ready(1, true)
	var party: ScreenPanel.Section = ScreenModels.setup_sections(setup, 1, [1, 2] as Array[int])[1]
	assert_eq(_cells(party, 0), PackedStringArray(["Player 1", "ready"]))
	assert_eq(_cells(party, 1), PackedStringArray(["Player 2", "waiting"]))


func test_pretty_ids() -> void:
	assert_eq(ScreenModels.pretty(&"lantern_staff"), "Lantern Staff")
	assert_eq(ScreenModels.pretty(&"ember_ore"), "Ember Ore")


func _bare_player(peer_id: int) -> Player:
	var player: Player = Player.new()
	player.peer_id = peer_id
	autofree(player)
	return player


# --- banking ---------------------------------------------------------------------------


func test_gains_are_the_kept_row_in_merge_shape() -> void:
	var gains: Dictionary = RunEconomyRules.gains_for(_result(RunEndReason.Reason.EXTRACT), 1)
	assert_eq(gains["gold_banked"], 200)
	assert_eq(gains["ore"], {"copper": 6})
	assert_eq(gains["echo_shards"], 9)
	assert_eq(gains["class_id"], "ranger")
	assert_eq(gains["class_xp"], 120)


func test_banking_a_death_adds_only_what_was_kept() -> void:
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.merge_run_gains(RunEconomyRules.gains_for(_result(), 1))
	assert_eq(profile.gold_banked, 50)
	assert_eq(profile.ore_count(&"copper"), 0)
	assert_eq(profile.echo_shards, 9)
	assert_eq(profile.classes["ranger"]["xp"], 120)


func test_gains_for_an_unknown_peer_are_empty() -> void:
	var gains: Dictionary = RunEconomyRules.gains_for(_result(), 99)
	assert_eq(gains["gold_banked"], 0)
	assert_eq(gains["class_id"], "")
