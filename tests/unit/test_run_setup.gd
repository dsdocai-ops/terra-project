extends GutTest
## The pre-run flow (SPEC-town "Pre-run flow", W5-B5): per-player selections,
## validation against the profile, ready state, the start floor, and starting the
## run with one PlayerSpawnInfo per peer.

var _setup: RunSetup = null
var _profile: PlayerProfile = null
var _started: Array[int] = []


func before_each() -> void:
	NetworkManager.start_solo()
	GameState.run = null
	GameState.forced_seed = 0
	_setup = RunSetup.new()
	_profile = PlayerProfile.defaults()
	_started.clear()
	GameState.run_started.connect(_on_started)


func after_each() -> void:
	if GameState.run_started.is_connected(_on_started):
		GameState.run_started.disconnect(_on_started)
	if GameState.run != null:
		GameState.end_run(RunEndReason.Reason.ABORT)
	GameState.run = null
	GameState.forced_seed = 0
	GameState.last_run_summary = ""
	NetworkManager.disconnect_all()


func _on_started(run_seed: int) -> void:
	_started.append(run_seed)


func _selection(peer_id: int) -> SelectionState:
	return SelectionState.new(peer_id)


# --- validation ----------------------------------------------------------


func test_the_default_selection_is_valid_for_a_fresh_profile() -> void:
	assert_eq(_selection(1).refusal_for(_profile), SelectionState.REFUSAL_NONE)


func test_a_locked_character_is_refused() -> void:
	var selection: SelectionState = _selection(1)
	selection.character_id = &"vesper"
	assert_eq(selection.refusal_for(_profile), SelectionState.REFUSAL_CHARACTER_LOCKED)


func test_a_locked_class_is_refused() -> void:
	var selection: SelectionState = _selection(1)
	selection.class_id = &"rogue"
	assert_eq(selection.refusal_for(_profile), SelectionState.REFUSAL_CLASS_LOCKED)


func test_a_locked_weapon_is_refused() -> void:
	var selection: SelectionState = _selection(1)
	selection.weapon_ids = [&"pickaxe", &"greataxe"]
	assert_eq(selection.refusal_for(_profile), SelectionState.REFUSAL_WEAPON_LOCKED)


func test_pickaxe_is_always_selectable() -> void:
	for class_id: StringName in [&"warrior", &"ranger", &"mage"]:
		var selection: SelectionState = _selection(1)
		selection.class_id = class_id
		selection.weapon_ids = [&"pickaxe", &"lantern_staff"]
		assert_eq(selection.refusal_for(_profile), SelectionState.REFUSAL_NONE, String(class_id))


func test_exactly_two_distinct_weapons() -> void:
	var selection: SelectionState = _selection(1)
	selection.weapon_ids = [&"pickaxe"]
	assert_eq(selection.shape_refusal(), SelectionState.REFUSAL_WEAPON_COUNT)
	selection.weapon_ids = [&"pickaxe", &"pickaxe"]
	assert_eq(selection.shape_refusal(), SelectionState.REFUSAL_WEAPON_DUPLICATE)
	selection.weapon_ids = [&"pickaxe", &"crossbow", &"lantern_staff"]
	assert_eq(selection.shape_refusal(), SelectionState.REFUSAL_WEAPON_COUNT)


func test_submit_stores_a_copy_and_clears_ready() -> void:
	var selection: SelectionState = _selection(1)
	selection.ready = true
	assert_eq(_setup.submit(selection, _profile), RunSetup.REFUSAL_NONE)
	assert_false(_setup.selections[1].ready)
	selection.class_id = &"mage"
	assert_eq(_setup.selections[1].class_id, &"warrior", "the stored selection is a copy")


func test_an_invalid_submit_stores_nothing() -> void:
	var selection: SelectionState = _selection(1)
	selection.character_id = &"vesper"
	assert_eq(_setup.submit(selection, _profile), SelectionState.REFUSAL_CHARACTER_LOCKED)
	assert_true(_setup.selections.is_empty())


func test_a_remote_selection_without_a_profile_is_checked_for_shape() -> void:
	var selection: SelectionState = _selection(2)
	selection.weapon_ids = [&"pickaxe"]
	assert_eq(_setup.submit(selection), SelectionState.REFUSAL_WEAPON_COUNT)
	assert_eq(_setup.submit(_selection(2)), RunSetup.REFUSAL_NONE)


func test_resubmitting_unreadies_the_player() -> void:
	_setup.submit(_selection(1), _profile)
	_setup.set_ready(1, true)
	_setup.submit(_selection(1), _profile)
	assert_false(_setup.selections[1].ready)


# --- ready and start floor -------------------------------------------------


func test_ready_needs_a_selection() -> void:
	assert_eq(_setup.set_ready(1, true), RunSetup.REFUSAL_NO_SELECTION)


func test_all_ready_needs_every_peer() -> void:
	_setup.submit(_selection(1), _profile)
	_setup.submit(_selection(2))
	_setup.set_ready(1, true)
	assert_false(_setup.all_ready([1, 2]))
	_setup.set_ready(2, true)
	assert_true(_setup.all_ready([1, 2]))
	assert_false(_setup.all_ready([1, 2, 3]), "a peer with no selection blocks the start")
	assert_false(_setup.all_ready([]))


func test_the_start_floor_follows_the_map_room() -> void:
	assert_eq(_setup.set_start_floor(7, 7), RunSetup.REFUSAL_NONE)
	assert_eq(_setup.start_floor, 7)
	assert_eq(_setup.set_start_floor(12, 7), RunSetup.REFUSAL_BAD_START_FLOOR)
	assert_eq(_setup.start_floor, 7, "a refused floor changes nothing")


# --- starting --------------------------------------------------------------


func test_party_has_one_spawn_info_per_peer_in_slot_order() -> void:
	var mage: SelectionState = _selection(3)
	mage.class_id = &"mage"
	mage.weapon_ids = [&"pickaxe", &"lantern_staff"]
	_setup.submit(mage)
	_setup.submit(_selection(1), _profile)
	var party: Array[PlayerSpawnInfo] = _setup.build_party([3, 1])
	assert_eq(party.size(), 2)
	assert_eq(party[0].peer_id, 1)
	assert_eq(party[0].slot, 0)
	assert_eq(party[1].peer_id, 3)
	assert_eq(party[1].slot, 1)
	assert_eq(party[1].class_id, &"mage")
	assert_eq(party[1].weapon_ids, [&"pickaxe", &"lantern_staff"] as Array[StringName])


func test_start_refuses_until_everyone_is_ready() -> void:
	_setup.submit(_selection(1), _profile)
	assert_eq(_setup.start([1]), RunSetup.REFUSAL_NOT_READY)
	assert_null(GameState.run)


func test_start_with_no_players_is_refused() -> void:
	assert_eq(_setup.start([]), RunSetup.REFUSAL_NO_PLAYERS)


func test_start_runs_the_party_from_the_chosen_floor() -> void:
	_setup.submit(_selection(1), _profile)
	_setup.set_ready(1, true)
	_setup.set_start_floor(7, 7)
	assert_eq(_setup.start([1], 99), RunSetup.REFUSAL_NONE)
	assert_eq(_started.size(), 1)
	assert_not_null(GameState.run)
	assert_eq(GameState.run.start_floor, 7)
	assert_eq(GameState.run.get_player(1).class_id, &"warrior")
	assert_eq(GameState.run.get_player(1).weapon_ids, [&"pickaxe", &"crossbow"] as Array[StringName])


func test_a_two_player_party_starts_with_both_slices() -> void:
	_setup.submit(_selection(1), _profile)
	_setup.submit(_selection(2))
	_setup.set_ready(1, true)
	_setup.set_ready(2, true)
	assert_eq(_setup.start([1, 2], 5), RunSetup.REFUSAL_NONE)
	assert_eq(GameState.run.players.size(), 2)


func test_a_client_cannot_start_the_run() -> void:
	_setup.submit(_selection(1), _profile)
	_setup.set_ready(1, true)
	NetworkManager.is_host = false
	assert_eq(_setup.start([1]), RunSetup.REFUSAL_NOT_HOST)
	NetworkManager.is_host = true
	assert_null(GameState.run)


func test_removing_a_peer_drops_their_selection() -> void:
	_setup.submit(_selection(2))
	_setup.remove(2)
	assert_false(_setup.selections.has(2))


func test_starting_the_dive_clears_ready_for_the_next_visit() -> void:
	_setup.submit(SelectionState.new(1), _profile)
	_setup.set_ready(1, true)
	var peers: Array[int] = [1]
	assert_eq(_setup.start(peers), RunSetup.REFUSAL_NONE)
	assert_false(_setup.selections[1].ready, "the next Tavern visit starts unready")
