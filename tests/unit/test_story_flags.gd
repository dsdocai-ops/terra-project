extends GutTest
## `StoryManager`'s flag store — namespaces, persistence, and act gates,
## story-dialogue, W6-B1 (PLAN G1).
##
## SPEC-story-dialogue: "func set_flag(flag: StringName) -> void            #
## idempotent, saves if flag is in UNLOCK_FLAGS" — so unlock flags must reach
## `PlayerProfile.story_flags` (the field week 5 already serializes) the moment
## they are set, while every other flag stays run-local and merges at run end
## through `merge_run_gains`. "func act() -> int                    # 1 to 3,
## derived from story flags" — SINKHOLE_SPEC section 11: the foreman closes
## act 1, Vulkar's journals close act 2. And `data/dialogue/flags.json` is the
## declaration: every reserved name, grouped by namespace, with `"persist": true`
## marking exactly the UNLOCK_FLAGS members.
##
## The autoload is the real thing; before_each snapshots and clears it so each
## case starts with an empty store. Cases that need a profile build one with
## `PlayerProfile.defaults()` and hand it straight to `SaveManager`, never
## touching the real files under `user://` — `save()` with a defaults profile
## writes only when something is dirty, and nothing here dirties settings.

const FLAGS_PATH: String = "res://data/dialogue/flags.json"

const NAMESPACE_KEYS: Array[String] = [
	"story", "rescue", "char", "ending", "lore", "town", "secret", "boss",
]


func before_each() -> void:
	StoryManager._flags.clear()
	StoryManager._lore.clear()


func after_each() -> void:
	SaveManager.profile = null
	StoryManager._flags.clear()
	StoryManager._lore.clear()


## Builds a defaults profile and installs it. `set_flag`'s persistence hook
## touches only the in-memory profile, so no real file under `user://` is read
## or written by any case here.
func _install_profile() -> void:
	SaveManager.profile = PlayerProfile.defaults()


# --- flags.json is the declaration -----------------------------------------

func test_flags_json_declares_every_namespace_and_twenty_plus_flags() -> void:
	assert_file_exists(FLAGS_PATH)
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(FLAGS_PATH)), OK,
			"SPEC: flags.json must parse as JSON")
	var data: Dictionary = json.data
	assert_has(data, "flags", "SPEC: the declaration lives under a `flags` table")
	var by_namespace: Dictionary = data["flags"]
	for namespace_key: String in NAMESPACE_KEYS:
		assert_has(by_namespace, namespace_key, "SPEC: namespace `%s` declared" % namespace_key)
	var total := 0
	for names: Variant in by_namespace.values():
		total += (names as Dictionary).size()
	assert_gte(total, 20, "SPEC: all reserved flag names declared")


func test_every_flag_entry_is_a_documented_dictionary() -> void:
	var by_namespace := _flags_by_namespace()
	for namespace_key: String in by_namespace:
		for flag_name: String in (by_namespace[namespace_key] as Dictionary):
			var entry: Variant = (by_namespace[namespace_key] as Dictionary)[flag_name]
			assert_true(entry is Dictionary, "%s.%s documents itself" % [namespace_key, flag_name])
			assert_true((entry as Dictionary).has("persist"),
					"%s.%s says whether it persists" % [namespace_key, flag_name])
			assert_true(String((entry as Dictionary).get("note", "")).length() > 0,
					"%s.%s carries a note" % [namespace_key, flag_name])


func test_every_unlock_flag_is_declared_in_flags_json() -> void:
	var by_namespace := _flags_by_namespace()
	for flag: StringName in StoryManager.UNLOCK_FLAGS:
		var parts := String(flag).split(".", false)
		assert_eq(parts.size(), 2, "flags must be namespaced: %s" % flag)
		assert_has(by_namespace, parts[0], "namespace of %s declared" % flag)
		assert_has(by_namespace[parts[0]], parts[1], "flag %s declared" % flag)


func test_persist_markers_match_unlock_flags_exactly() -> void:
	var by_namespace := _flags_by_namespace()
	var declared_unlocks: Array[StringName] = []
	for namespace_key: String in by_namespace:
		for flag_name: String in (by_namespace[namespace_key] as Dictionary):
			var entry: Dictionary = (by_namespace[namespace_key] as Dictionary)[flag_name]
			if entry.get("persist", false):
				declared_unlocks.append(StringName(namespace_key + "." + flag_name))
	assert_eq(declared_unlocks, StoryManager.UNLOCK_FLAGS,
			"flags.json `persist: true` entries and UNLOCK_FLAGS are the same list")


func test_the_loader_flattens_every_declared_name() -> void:
	var by_namespace := _flags_by_namespace()
	for namespace_key: String in by_namespace:
		for flag_name: String in (by_namespace[namespace_key] as Dictionary):
			var full := StringName(namespace_key + "." + flag_name)
			assert_true(StoryManager.is_declared(full), "flattened name %s is declared" % full)
	assert_false(StoryManager.is_declared(&"story.not_a_real_flag"),
			"an undeclared name is not declared")


func _flags_by_namespace() -> Dictionary:
	var json := JSON.new()
	json.parse(FileAccess.get_file_as_string(FLAGS_PATH))
	return (json.data as Dictionary)["flags"] as Dictionary


# --- set_flag: idempotent, signals, persists only unlock flags --------------

func test_set_flag_is_idempotent_and_emits_once() -> void:
	var counter := FlagSetCounter.new()
	counter.target = &"story.met_hilde"
	StoryManager.flag_set.connect(counter._on_flag_set)
	add_child_autofree(counter)

	StoryManager.set_flag(&"story.met_hilde")
	StoryManager.set_flag(&"story.met_hilde")
	StoryManager.set_flag(&"story.met_hilde")

	assert_eq(StoryManager.flags(), [StringName(&"story.met_hilde")],
			"the flag appears exactly once")
	assert_eq(counter.hits, 1, "flag_set fired once for three sets")
	assert_true(StoryManager.has_flag(&"story.met_hilde"))


func test_set_flag_persists_unlock_flags_to_the_profile() -> void:
	_install_profile()
	StoryManager.set_flag(&"story.foreman_defeated")
	assert_true(SaveManager.profile.story_flags.has("story.foreman_defeated"),
			"SPEC: the unlock flag reaches PlayerProfile.story_flags immediately")


func test_set_flag_does_not_persist_run_local_flags() -> void:
	_install_profile()
	StoryManager.set_flag(&"story.met_hilde")
	assert_false(SaveManager.profile.story_flags.has("story.met_hilde"),
			"a run-local flag stays out of the profile until run end")


func test_persistent_flags_come_back_from_the_profile() -> void:
	_install_profile()
	SaveManager.profile.story_flags = [
		"story.foreman_defeated", "rescue.sly_nettie", "ending.seal",
	]
	StoryManager._restore_persistent_flags()
	assert_true(StoryManager.has_flag(&"story.foreman_defeated"))
	assert_true(StoryManager.has_flag(&"rescue.sly_nettie"))
	assert_true(StoryManager.has_flag(&"ending.seal"))
	assert_false(StoryManager.has_flag(&"story.met_hilde"),
			"run-local flags are not restored")


func test_set_flag_without_a_profile_still_works() -> void:
	SaveManager.profile = null
	StoryManager.set_flag(&"rescue.cogsworth")
	assert_true(StoryManager.has_flag(&"rescue.cogsworth"),
			"the flag still lives for the session when no profile exists")


# --- act(): 1 to 3, derived from the act gates ------------------------------

func test_act_is_1_before_the_foreman_gate() -> void:
	StoryManager.set_flag(&"story.met_hilde")
	assert_eq(StoryManager.act(), 1, "SINKHOLE_SPEC 11: no foreman, act 1")


func test_act_is_2_after_the_foreman_before_the_journals() -> void:
	StoryManager.set_flag(&"story.foreman_defeated")
	assert_eq(StoryManager.act(), 2, "SINKHOLE_SPEC 11: foreman down, journals missing")


func test_act_is_3_after_both_gates() -> void:
	StoryManager.set_flag(&"story.foreman_defeated")
	StoryManager.set_flag(&"story.vulkar_journals")
	assert_eq(StoryManager.act(), 3, "SINKHOLE_SPEC 11: both gates down, act 3")


func test_act_gates_come_back_from_a_restored_profile() -> void:
	_install_profile()
	SaveManager.profile.story_flags = ["story.foreman_defeated"]
	StoryManager._restore_persistent_flags()
	assert_eq(StoryManager.act(), 2, "the act follows restored flags too")


# --- lore stays its own counter ---------------------------------------------

func test_unlock_lore_is_idempotent_and_counts_pages() -> void:
	StoryManager.unlock_lore(&"vulkar_journal_1_read")
	StoryManager.unlock_lore(&"vulkar_journal_1_read")
	StoryManager.unlock_lore(&"vulkar_journal_2_read")
	assert_eq(StoryManager.lore_unlocked_count(), 2, "duplicate pages count once")


## A tiny helper node with a named method callback — GUT never fires lambdas,
## so signal connections in tests go through methods on a real Node.
class FlagSetCounter:
	extends Node

	var target: StringName = &""
	var hits: int = 0

	func _on_flag_set(flag: StringName) -> void:
		if flag == target:
			hits += 1
