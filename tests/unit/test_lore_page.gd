extends GutTest
## The `LorePage` pickup and its `LORE` room populator, story-dialogue W6-B2
## (PLAN G4).
##
## SPEC-story-dialogue: "40+ pages across biomes (at least 6 per biome plus
## Vulkar's journals). `LORE` room populator spawns a `LorePage` pickup for the
## lowest-order unread page of that biome." PLAN G4: "On `body_entered(player)`,
## call `StoryManager.unlock_lore(page_id)` and queue_free", and the placement
## hook registers under `RoomType.LORE` "with biome context".
##
## The cases drive the real scene and the real `StoryManager` store; the lore
## content itself lives under `tests/fixtures/lore/` because `data/lore/` stays
## empty until W6-B3 authors it — the populator must be finished and tested
## before the first real page exists, so content landing is data, not code.
##
## Signal cases record through named methods (`StoryManager.lore_unlocked` is an
## autoload, so its connection is made in `before_each` and dropped in
## `after_each`; a page's own connections die with the page).
##
## blocked on Dev A (W3-A3): the registration cases accept either verdict of the
## guarded no-op, exactly as the chest's and shrine's registration cases do.

const PAGE_SCENE_PATH: String = "res://scenes/dungeon/interactables/lore_page.tscn"
const SEAM_SCRIPT_PATH: String = "res://scripts/run/room_populator.gd"
const REGISTRY_STUB_PATH: String = "res://tests/helpers/story_registry_stub.gd"
const FIXTURE_DIR: String = "res://tests/fixtures/lore"
const DUP_DIR: String = "res://tests/fixtures/lore_dup"

const PEER_ID: int = 1
const RUN_SEED: int = 5150
## The floor these cases run on: biome 2, whose pages the fixtures carry.
const RUN_FLOOR: int = 6

const ALPHA_ID: StringName = &"lore.test_alpha"
const BETA_ID: StringName = &"lore.test_beta"
const GAMMA_ID: StringName = &"lore.test_gamma"

var _player: Player = null
var _picked: Array[Dictionary] = []
var _unlocked: Array[StringName] = []
var _forwarded: Array[Dictionary] = []


func before_each() -> void:
	NetworkManager.start_solo()
	StoryManager._lore.clear()
	LorePage.reset_catalog()
	StoryRegistryStub.reset()
	SaveManager.profile = null
	GameState.run = null
	_player = Player.new()
	_player.peer_id = PEER_ID
	_picked.clear()
	_unlocked.clear()
	_forwarded.clear()
	StoryManager.lore_unlocked.connect(_on_lore_unlocked)


func after_each() -> void:
	StoryManager.lore_unlocked.disconnect(_on_lore_unlocked)
	LorePage.reset_catalog()
	StoryManager._lore.clear()
	SaveManager.profile = null
	GameState.run = null
	if _player != null:
		_player.free()
	_player = null


# --- the named signal recorders ---------------------------------------------


func _on_picked_up(peer_id: int, page_id: StringName) -> void:
	_picked.append({"peer_id": peer_id, "page_id": page_id})


func _on_lore_unlocked(page_id: StringName) -> void:
	_unlocked.append(page_id)


func _on_pickup_forwarded(peer_id: int, page_id: StringName) -> void:
	_forwarded.append({"peer_id": peer_id, "page_id": page_id})


## One valid page dict, shaped exactly as `_page_at` normalizes one.
func _page(id: String, biome: int, order: int) -> Dictionary:
	return {
		"id": StringName(id),
		"title": "Test %s" % id,
		"body": "A test page for %s." % id,
		"biome": biome,
		"act": 1,
		"order": order,
	}


## A fresh page out of the real scene, named `page_id`, in the tree.
func _page_node(page_id: StringName) -> LorePage:
	var page: LorePage = add_child_autofree((load(PAGE_SCENE_PATH) as PackedScene).instantiate())
	page.page_id = page_id
	return page


func _room() -> Node2D:
	var room := Node2D.new()
	add_child_autofree(room)
	return room


# --- the pickup is a real scene ----------------------------------------------


func test_the_scene_is_an_area_on_the_interactable_layer_with_the_prop_sprite() -> void:
	assert_file_exists(PAGE_SCENE_PATH)
	var packed: PackedScene = load(PAGE_SCENE_PATH) as PackedScene
	assert_not_null(packed, "%s loads" % PAGE_SCENE_PATH)
	if packed == null:
		return
	var page: LorePage = packed.instantiate() as LorePage
	autofree(page)
	assert_not_null(page, "the scene's root is a LorePage")
	if page == null:
		return
	assert_eq(page.collision_layer, LorePage.INTERACTABLE_LAYER,
		"the page sits on physics layer 6, the interactable layer")
	var sprite: Sprite2D = page.get_node_or_null("Body") as Sprite2D
	assert_not_null(sprite, "the page carries its static sprite")
	if sprite != null:
		assert_not_null(sprite.texture, "and the sprite holds the generated prop art")
	var shape: CollisionShape2D = page.get_node_or_null("PickupShape") as CollisionShape2D
	assert_not_null(shape, "the page carries its pickup collision")


func test_ready_wires_the_walk_over_trigger() -> void:
	var page: LorePage = add_child_autofree((load(PAGE_SCENE_PATH) as PackedScene).instantiate())
	assert_true(page.body_entered.is_connected(Callable(page, &"_on_body_entered")),
		"the walk-over trigger is connected once the page is in the tree")


# --- the walk-over ----------------------------------------------------------


func test_a_walk_over_unlocks_the_page_and_frees_it() -> void:
	var page := _page_node(ALPHA_ID)
	page.picked_up.connect(_on_picked_up)
	page._on_body_entered(_player)
	assert_eq(StoryManager.lore_unlocked_count(), 1, "the page is read in StoryManager")
	assert_eq(_unlocked, [ALPHA_ID] as Array[StringName], "through the lore_unlocked signal")
	assert_eq(_picked.size(), 1, "and the pickup is announced")
	assert_eq(_picked[0]["page_id"], ALPHA_ID, "naming the page")
	assert_eq(_picked[0]["peer_id"], PEER_ID, "and the reading peer")
	assert_true(page.is_collected(), "host state: the page is spent")
	assert_true(page.is_queued_for_deletion(), "and freed the way PLAN G4 asks")


func test_a_second_walk_over_cannot_read_one_page_twice() -> void:
	var page := _page_node(ALPHA_ID)
	page._on_body_entered(_player)
	var count := StoryManager.lore_unlocked_count()
	page._on_body_entered(_player)
	assert_eq(StoryManager.lore_unlocked_count(), count, "the unlock is idempotent")
	assert_eq(_unlocked.size(), 1, "and the signal fired once")


func test_a_page_the_populator_never_named_is_refused() -> void:
	var page := _page_node(&"")
	page._on_body_entered(_player)
	assert_eq(StoryManager.lore_unlocked_count(), 0, "no name, no unlock")
	assert_false(page.is_collected(), "and the page is not spent")
	assert_false(page.is_queued_for_deletion(), "nor freed")


func test_a_body_that_is_not_a_player_is_ignored() -> void:
	var page := _page_node(ALPHA_ID)
	var stranger := StaticBody2D.new()
	add_child_autofree(stranger)
	page._on_body_entered(stranger)
	assert_eq(StoryManager.lore_unlocked_count(), 0, "only a player reads a page")
	assert_false(page.is_collected(), "and the page stays")


func test_a_client_forwards_the_walk_over_instead_of_unlocking() -> void:
	var page := _page_node(ALPHA_ID)
	page.pickup_forwarded.connect(_on_pickup_forwarded)
	NetworkManager.is_host = false
	page._on_body_entered(_player)
	assert_eq(_forwarded.size(), 1, "the walk-over travels up the request path")
	assert_eq(_forwarded[0]["page_id"], ALPHA_ID, "naming the page")
	assert_eq(_forwarded[0]["peer_id"], PEER_ID, "and the peer whose body reached it")
	assert_eq(StoryManager.lore_unlocked_count(), 0, "a client unlocks nothing locally")
	assert_false(page.is_collected(), "and frees nothing")


func test_the_peer_behind_a_body_is_the_players_or_the_local_one() -> void:
	var page: LorePage = autofree((load(PAGE_SCENE_PATH) as PackedScene).instantiate())
	assert_eq(page.peer_id_of(_player), PEER_ID, "the player's own peer")
	assert_eq(page.peer_id_of(null), NetworkManager.local_peer_id, "the local peer when unnamed")


func test_a_page_read_without_a_profile_still_counts_for_the_session() -> void:
	SaveManager.profile = null
	var page := _page_node(ALPHA_ID)
	page._on_body_entered(_player)
	assert_eq(StoryManager.lore_unlocked_count(), 1, "the session still records the read")


func test_a_page_read_with_a_profile_is_recorded_there_once() -> void:
	SaveManager.profile = PlayerProfile.defaults()
	var page := _page_node(ALPHA_ID)
	page._on_body_entered(_player)
	assert_true(SaveManager.profile.lore_unlocked.has(String(ALPHA_ID)),
		"the profile carries the page id")
	var second := _page_node(ALPHA_ID)
	second._on_body_entered(_player)
	assert_eq(SaveManager.profile.lore_unlocked.count(String(ALPHA_ID)), 1,
		"and a second read appends nothing")


# --- the LORE populator and its registration seam ----------------------------


func test_the_lore_populator_callable_targets_the_lore_room() -> void:
	assert_eq(LorePage.lore_populator().get_method(), &"_populate_lore_room", "the LORE populator body")
	assert_true(LorePage.lore_populator().is_valid(), "and is a Callable whether or not the registry exists")
	assert_eq(LorePage.ROOM_TYPE, &"LORE",
		"SPEC-floor-generation: 'LORE | 1 per biome at a fixed floor from BiomeData.lore_floor'")


func test_the_registration_is_a_guarded_no_op_while_dev_as_generator_is_absent() -> void:
	var registry_exists: bool = ResourceLoader.exists(RoomPopulator.GENERATOR_SCRIPT_PATH)
	assert_eq(LorePage.register_populator(), registry_exists,
		"the registration succeeds exactly when Dev A's floor_generator.gd exists")
	assert_eq(LorePage.blocker_warnings(), 0 if registry_exists else 1,
		"the blocked path notes its blocker once per process, not once per call")
	if registry_exists:
		return
	assert_eq(LorePage.register_populator(), false, "a second call is the same no-op")
	assert_eq(LorePage.blocker_warnings(), 1, "with no second warning, because a floor change must not reprint it")
	assert_eq(StoryRegistryStub.registered.size(), 0, "and nothing reached a registry")


func test_the_generator_path_is_the_one_the_floor_sync_seam_already_guards() -> void:
	assert_eq(RoomPopulator.GENERATOR_SCRIPT_PATH, FloorGeneratorSeam.GENERATOR_SCRIPT_PATH,
		"story-dialogue's populator guard and networking's floor seam name the same file, so one landing swaps both")
	assert_eq(RoomPopulator.GENERATOR_SCRIPT_PATH, "res://scripts/generation/floor_generator.gd",
		"and it is where SPEC-project puts floor-generation's generator")


func test_the_registration_resolves_the_lore_room_type_off_the_generator_script() -> void:
	var stub: Script = load(REGISTRY_STUB_PATH) as Script
	assert_not_null(stub, "%s loads" % REGISTRY_STUB_PATH)
	if stub == null:
		return
	var room_types: Dictionary = stub.get_script_constant_map().get(&"RoomType", {})
	assert_true(room_types.has("LORE"), "the registry double declares LORE")
	assert_eq(RoomPopulator.room_type_value(stub, LorePage.ROOM_TYPE), room_types.get("LORE", null),
		"the page resolves RoomType.LORE off whatever script the path points at")
	assert_eq(LorePage.room_type_value(stub), RoomPopulator.room_type_value(stub, LorePage.ROOM_TYPE),
		"the page's own read is the shared seam helper's")
	assert_null(LorePage.room_type_value(Chest), "a script with no RoomType enumeration resolves nothing")
	assert_null(RoomPopulator.room_type_value(null, LorePage.ROOM_TYPE), "and neither does no script at all")


# --- the catalog -------------------------------------------------------------


func test_the_fixture_catalog_loads_sorted_and_skips_everything_invalid() -> void:
	var pages := LorePage.catalog_at(FIXTURE_DIR)
	assert_eq(pages.size(), 3, "the three valid fixture pages load")
	assert_eq(pages[0]["id"], ALPHA_ID, "the lowest order sorts first")
	assert_eq(pages[2]["id"], BETA_ID, "the highest order sorts last")
	for page: Dictionary in pages:
		assert_has(page, "title", "%s carries its title" % page["id"])
		assert_has(page, "body", "and its body")
	for bad: String in [
		"bad_missing_id.json", "bad_missing_title.json", "bad_missing_body.json",
		"bad_biome_string.json", "bad_biome_range.json", "bad_act_range.json",
		"bad_negative_order.json", "bad_not_object.json", "bad_broken_json.json",
	]:
		assert_eq(LorePage._page_at(FIXTURE_DIR.path_join(bad)), {}, "%s is refused" % bad)


func test_a_duplicated_biome_order_costs_one_page_its_place() -> void:
	var pages := LorePage.catalog_at(DUP_DIR)
	assert_eq(pages.size(), 1, "two pages cannot share one biome and order")


func test_the_real_lore_folder_is_empty_until_w6_b3_authors_it() -> void:
	assert_eq(LorePage.catalog().size(), 0, "no real pages yet, so the catalog is empty")


# --- selection ---------------------------------------------------------------


func test_the_lowest_order_unread_page_wins_its_biome() -> void:
	LorePage.set_catalog_override([
		_page("lore.test_beta", 2, 2), _page("lore.test_alpha", 2, 1), _page("lore.test_gamma", 3, 1),
	])
	assert_eq(LorePage._next_page_for_biome(2)["id"], ALPHA_ID,
		"the lowest order in the biome, whatever the file order")
	assert_eq(LorePage._next_page_for_biome(3)["id"], GAMMA_ID, "each biome reads its own pages")
	assert_eq(LorePage._next_page_for_biome(5), {}, "a biome with no pages offers none")


func test_a_read_page_steps_the_selection_to_the_next_order() -> void:
	LorePage.set_catalog_override([
		_page("lore.test_alpha", 2, 1), _page("lore.test_beta", 2, 2),
	])
	SaveManager.profile = PlayerProfile.defaults()
	assert_eq(LorePage._next_page_for_biome(2)["id"], ALPHA_ID, "the unread lowest order first")
	SaveManager.profile.lore_unlocked.append(String(ALPHA_ID))
	assert_eq(LorePage._next_page_for_biome(2)["id"], BETA_ID, "then the next order once alpha is read")
	SaveManager.profile.lore_unlocked.append(String(BETA_ID))
	assert_eq(LorePage._next_page_for_biome(2), {}, "and nothing once every page is read")


# --- placement ---------------------------------------------------------------


func test_placement_refuses_a_missing_room_and_runs_on_the_host_only() -> void:
	assert_eq(LorePage.populate_room(null).size(), 0, "a null room is refused rather than crashing")
	var room: Node2D = _room()
	LorePage.set_catalog_override([_page("lore.test_alpha", 2, 1)])
	NetworkManager.is_host = false
	assert_eq(LorePage.populate_room(room).size(), 0, "a client places no pages")
	assert_eq(room.get_child_count(), 0, "and adds nothing at all")


func test_a_room_is_filled_from_the_live_run_biome() -> void:
	GameState.run = RunState.new(RUN_SEED, RUN_FLOOR)
	var room: Node2D = _room()
	LorePage.set_catalog_override([
		_page("lore.test_alpha", 2, 1), _page("lore.test_beta", 2, 2), _page("lore.test_gamma", 3, 1),
	])
	var spawned := LorePage.populate_room(room)
	assert_eq(spawned.size(), 1, "SPEC-floor-generation: a LORE room 'holds one unread page'")
	assert_eq(spawned[0].page_id, ALPHA_ID, "the lowest-order unread page of the run's biome")
	assert_eq(spawned[0].biome, 2, "carrying the biome context the hook was called with")
	assert_eq(room.get_child_count(), 1, "and the page is the room's only child")


func test_a_named_biome_overrides_the_run() -> void:
	GameState.run = RunState.new(RUN_SEED, RUN_FLOOR)
	var room: Node2D = _room()
	LorePage.set_catalog_override([_page("lore.test_gamma", 3, 1)])
	var spawned := LorePage.populate_room(room, 3)
	assert_eq(spawned.size(), 1, "the caller's biome context wins")
	assert_eq(spawned[0].page_id, GAMMA_ID, "and the page follows it")


func test_a_room_with_no_live_run_or_a_foreign_biome_stays_empty() -> void:
	var room: Node2D = _room()
	LorePage.set_catalog_override([_page("lore.test_alpha", 2, 1)])
	assert_eq(LorePage.populate_room(room).size(), 0, "no run, no biome to read a page for")
	GameState.run = RunState.new(RUN_SEED, RUN_FLOOR)
	assert_eq(LorePage.populate_room(room).size(), 1, "the run's biome has a page, so it lands")
	LorePage.set_catalog_override([_page("lore.test_gamma", 3, 1)])
	assert_eq(LorePage.populate_room(room).size(), 0, "and a page for another biome is not it")
	assert_eq(room.get_child_count(), 1, "only the run's page ever landed")
