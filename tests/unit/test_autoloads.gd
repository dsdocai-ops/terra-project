extends GutTest
## Tests that the seven autoloads exist in spec order and expose the public
## API shapes their module specs name, so consumers compile against the real
## names from week 1. Owned by foundation.

const ORDER: Array[String] = ["Events", "TimeManager", "GameState", "SaveManager", "StoryManager", "AudioManager", "NetworkManager"]

## Methods from each spec's "Interfaces provided" block.
const METHODS: Dictionary[String, Array] = {
	"TimeManager": ["scale_for", "set_group", "slow_enemies", "stop_enemies", "clear_source", "set_entity_scale", "hit_stop", "timer", "register_rewindable", "unregister_rewindable", "rewind"],
	"GameState": ["start_run", "next_floor", "request_extract_vote", "end_run"],
	"SaveManager": ["save", "load", "reset_profile", "export_debug"],
	"StoryManager": ["has_flag", "set_flag", "flags", "act", "unlock_lore", "lore_unlocked_count", "evaluate", "start_dialogue"],
	"AudioManager": ["play_music", "play_sfx", "set_bus_volume", "stop_music"],
	"NetworkManager": ["host", "join", "start_solo", "disconnect_all", "get_player", "player_count", "enemy_hp_multiplier", "request_debug"],
}

## Signals from each spec.
const SIGNALS: Dictionary[String, Array] = {
	"TimeManager": ["enemy_time_changed"],
	"GameState": ["run_started", "floor_changed", "run_ended"],
	"SaveManager": ["saved", "loaded"],
	"StoryManager": ["flag_set", "lore_unlocked", "miner_rescued"],
	"NetworkManager": ["player_joined", "player_left", "connection_failed", "host_disconnected"],
}

## The Events bus signal set from SPEC-effect-system.
const EVENTS_SIGNALS: Array[String] = [
	"hit_landed", "crit_landed", "player_damaged", "player_healed", "heavy_attack_released", "weapon_swapped", "projectile_fired",
	"player_dodged", "player_downed", "player_revived", "player_died",
	"enemy_spawned", "enemy_killed", "elite_killed", "boss_defeated",
	"status_applied", "combo_triggered",
	"ability_cast", "ultimate_used", "class_skill_used",
	"room_entered", "room_cleared", "floor_entered", "floor_cleared", "run_started", "run_ended", "rope_vote_updated",
	"currency_gained", "pickup_collected", "relic_picked", "relic_removed", "synergy_activated", "mutation_applied", "ascension_chosen",
	"story_flag_set", "lore_unlocked", "miner_rescued",
]


func _autoload(name: String) -> Node:
	return get_tree().root.get_node_or_null(name)


func test_all_seven_autoloads_exist_in_spec_order() -> void:
	var found: Array[String] = []
	for child in get_tree().root.get_children():
		if ORDER.has(child.name):
			found.append(child.name)
	assert_eq(found, ORDER, "autoloads present and in order")


func test_each_autoload_exposes_its_spec_methods() -> void:
	for name: String in METHODS:
		var node := _autoload(name)
		assert_not_null(node, name)
		if node == null:
			continue
		for method: String in METHODS[name]:
			assert_true(node.has_method(method), "%s.%s" % [name, method])


func test_each_autoload_exposes_its_spec_signals() -> void:
	for name: String in SIGNALS:
		var node := _autoload(name)
		assert_not_null(node, name)
		if node == null:
			continue
		for sig: String in SIGNALS[name]:
			assert_true(node.has_signal(sig), "%s.%s" % [name, sig])


func test_events_bus_has_every_spec_signal_and_no_logic() -> void:
	var events := _autoload("Events")
	assert_not_null(events)
	if events == null:
		return
	for sig: String in EVENTS_SIGNALS:
		assert_true(events.has_signal(sig), sig)
	# Signals only: no public methods beyond Node's.
	for method: Dictionary in events.get_script().get_script_method_list():
		assert_true(String(method["name"]).begins_with("_"), "Events has no public methods, found %s" % method["name"])


func test_network_manager_constants_and_solo_default() -> void:
	var net := _autoload("NetworkManager")
	assert_eq(net.get("DEFAULT_PORT"), 7777)
	assert_eq(net.get("MAX_PLAYERS"), 4)
	assert_eq(net.get("ENEMY_HP_PER_EXTRA_PLAYER"), 0.5)


func test_save_manager_constants() -> void:
	var save := _autoload("SaveManager")
	assert_eq(save.get("SAVE_VERSION"), 1)
	assert_eq(save.get("PATH"), "user://save.json")


func test_content_data_base_class_round_trips() -> void:
	var data := ContentData.new()
	data.id = &"ember_boots"
	data.display_name = "Ember Boots"
	data.tags = [&"fire", &"dodge"]
	var path := "user://_test_content_data.tres"
	assert_eq(ResourceSaver.save(data, path), OK)
	var loaded := load(path) as ContentData
	assert_not_null(loaded)
	assert_eq(loaded.id, &"ember_boots")
	assert_eq(loaded.display_name, "Ember Boots")
	assert_eq(loaded.tags, [&"fire", &"dodge"] as Array[StringName])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
