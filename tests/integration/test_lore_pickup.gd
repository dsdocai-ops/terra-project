extends GutTest
## The lore loop end to end, story-dialogue W6-B2 (PLAN G4 sub-task 5): the
## placement hook fills a `LORE` room from the run's biome, the walk-over reads
## the page, and both the session store and the saved profile carry it.
##
## PLAN G4: "generate a floor, spawn a lore page, pick it up, verify flag is set
## and save includes it." Dev A's `FloorGenerator` has not landed (W3-A3), so the
## floor these cases stand on is a `Node2D` room and a live `RunState` — the same
## stand-in the chest's placement cases use — with the populator called through
## the same guarded seam a real floor will call. The pages are the fixture set
## under `tests/fixtures/lore/`, read through the real loader and pinned as the
## catalog, because `data/lore/` stays empty until W6-B3 authors it.
##
## Signal cases record through named methods; a page's connections die with it.

const PAGE_SCENE_PATH: String = "res://scenes/dungeon/interactables/lore_page.tscn"
const FIXTURE_DIR: String = "res://tests/fixtures/lore"

const PEER_ID: int = 1
const RUN_SEED: int = 5150
## The floor these cases run on: biome 2, whose pages the fixtures carry.
const RUN_FLOOR: int = 6

const ALPHA_ID: StringName = &"lore.test_alpha"
const BETA_ID: StringName = &"lore.test_beta"
const GAMMA_ID: StringName = &"lore.test_gamma"

var _player: Player = null
var _unlocked: Array[StringName] = []


func before_each() -> void:
	NetworkManager.start_solo()
	StoryManager._lore.clear()
	LorePage.reset_catalog()
	LorePage.set_catalog_override(LorePage.catalog_at(FIXTURE_DIR))
	SaveManager.profile = PlayerProfile.defaults()
	GameState.run = RunState.new(RUN_SEED, RUN_FLOOR)
	_player = Player.new()
	_player.peer_id = PEER_ID
	_unlocked.clear()
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


# --- the named signal recorder ----------------------------------------------


func _on_lore_unlocked(page_id: StringName) -> void:
	_unlocked.append(page_id)


func _room() -> Node2D:
	var room := Node2D.new()
	add_child_autofree(room)
	return room


func test_a_lore_room_spawns_the_biomes_lowest_unread_page_and_a_walk_over_reads_it() -> void:
	var room := _room()
	var spawned := LorePage.populate_room(room)
	assert_eq(spawned.size(), 1, "the placement hook fills the LORE room from the run's biome")
	var page: LorePage = spawned[0]
	assert_eq(page.page_id, ALPHA_ID, "the lowest-order unread page")
	page._on_body_entered(_player)
	assert_eq(StoryManager.lore_unlocked_count(), 1, "the flag is set in StoryManager.unlock_lore")
	assert_eq(_unlocked, [ALPHA_ID] as Array[StringName], "announced through lore_unlocked")
	assert_true(page.is_collected(), "the page is spent")
	assert_true(page.is_queued_for_deletion(), "and freed")


func test_the_pickup_is_saved_into_the_profile() -> void:
	var room := _room()
	var spawned := LorePage.populate_room(room)
	var page: LorePage = spawned[0]
	page._on_body_entered(_player)
	assert_true(SaveManager.profile.lore_unlocked.has(String(ALPHA_ID)),
		"the save's profile carries the page id")
	assert_eq(SaveManager.profile.lore_unlocked.count(String(ALPHA_ID)), 1, "recorded once")


func test_the_next_lore_room_steps_to_the_next_page_and_then_stops() -> void:
	var first := LorePage.populate_room(_room())
	(first[0] as LorePage)._on_body_entered(_player)
	var second := LorePage.populate_room(_room())
	assert_eq(second.size(), 1, "a read page makes room for the next order")
	assert_eq((second[0] as LorePage).page_id, BETA_ID, "the second-lowest unread page")
	(second[0] as LorePage)._on_body_entered(_player)
	var third := LorePage.populate_room(_room())
	assert_eq(third.size(), 0, "both biome-2 pages read, the room stays empty")
	assert_eq(_unlocked, [ALPHA_ID, BETA_ID] as Array[StringName], "two pages, two unlocks")
	assert_eq(SaveManager.profile.lore_unlocked.size(), 2, "and the profile holds both")


func test_a_lore_room_in_another_biome_reads_that_biomes_own_page() -> void:
	GameState.run = RunState.new(RUN_SEED, 11)
	var spawned := LorePage.populate_room(_room())
	assert_eq(spawned.size(), 1, "floor 11 is biome 3")
	assert_eq((spawned[0] as LorePage).page_id, GAMMA_ID, "and biome 3's own page is the one")
