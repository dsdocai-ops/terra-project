extends GutTest
## `StoryManager.evaluate()` — the dialogue condition language, story-dialogue
## W6-B1 (PLAN G3).
##
## SPEC-story-dialogue: "`all`, `any`, `not`, `flag`, `flag_not`, `character`
## (current playable character id), `class`, `town_level {building, min}`,
## `ore_min`, `deepest_floor_min`, `rescued`, `act_min`, `random_chance`" —
## every operator has its own case here, on both its passing and failing side
## where the operator is stateful. Selection and fallback have their own
## section: "The highest-priority entry whose conditions pass is the NPC's
## current dialogue; 'talk again' shows the next passing entry or a fallback."
##
## The flags live on the real autoload, snapshotted clear in before_each; the
## world state (ore, rescues, town, deepest floor) lives in an `EvalContext`
## each case builds, so nothing here touches a profile file.

var _context: StoryManager.EvalContext
## The real declaration, flattened — selection fixtures must name real flags,
## the same way content does.
var _declared: Dictionary = {}


func before_each() -> void:
	StoryManager._flags.clear()
	StoryManager._lore.clear()
	SaveManager.profile = PlayerProfile.defaults()
	_declared = {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(
			"res://data/dialogue/flags.json")) == OK and json.data is Dictionary:
		var by_ns: Dictionary = (json.data as Dictionary)["flags"]
		for ns: String in by_ns:
			for flag_name: String in (by_ns[ns] as Dictionary):
				_declared[ns + "." + flag_name] = true
	_context = StoryManager.EvalContext.new()
	_context.character_id = &"wren"
	_context.class_id = &"warrior"
	_context.deepest_floor = 7
	_context.ore[&"copper"] = 12
	_context.rescued_miners = [&"sly_nettie"]
	_context.town_levels[&"blacksmith"] = 2
	# Seeded roll source: `random_chance` cases are deterministic, never flaky.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	_context.rng = rng


func after_each() -> void:
	SaveManager.profile = null
	StoryManager._flags.clear()
	StoryManager._lore.clear()


# --- empty and composite forms ----------------------------------------------

func test_empty_condition_passes() -> void:
	assert_true(StoryManager.evaluate({}),
			"SPEC: an entry with no conditions is always eligible")


func test_all_passes_only_when_every_sub_passes() -> void:
	StoryManager.set_flag(&"story.met_hilde")
	assert_true(StoryManager.evaluate({"all": [
		{"flag": "story.met_hilde"}, {"character": "wren"},
	]}, _context), "both true -> all true")
	assert_false(StoryManager.evaluate({"all": [
		{"flag": "story.met_hilde"}, {"character": "brann"},
	]}, _context), "one false -> all false")


func test_any_passes_when_one_sub_passes() -> void:
	StoryManager.set_flag(&"story.pit_calls")
	assert_true(StoryManager.evaluate({"any": [
		{"flag": "story.pit_calls"}, {"flag": "story.met_hilde"},
	]}, _context), "one true -> any true")
	assert_false(StoryManager.evaluate({"any": [
		{"flag": "story.met_hilde"}, {"class": "ranger"},
	]}, _context), "none true -> any false")


func test_empty_all_is_true_and_empty_any_is_false() -> void:
	# The schema doc pins the vacuous readings; evaluate() must agree or an
	# authored empty array changes meaning depending on which composite it is.
	assert_true(StoryManager.evaluate({"all": []}),
			"schema: an empty all is vacuously true")
	assert_false(StoryManager.evaluate({"any": []}),
			"schema: an empty any is vacuously false")


func test_not_negates_its_single_sub() -> void:
	StoryManager.set_flag(&"story.pit_calls")
	assert_true(StoryManager.evaluate({"not": {"flag": "story.met_hilde"}}),
			"flag unset -> not true")
	assert_false(StoryManager.evaluate({"not": {"flag": "story.pit_calls"}}),
			"flag set -> not false")


func test_not_accepts_the_array_form() -> void:
	StoryManager.set_flag(&"story.pit_calls")
	assert_true(StoryManager.evaluate({"not": [{"flag": "story.met_hilde"}]}),
			"loader accepts {not: [expr]}; evaluate must too")


func test_composites_nest() -> void:
	StoryManager.set_flag(&"story.pit_calls")
	StoryManager.set_flag(&"story.met_hilde")
	var nested: Dictionary = {"all": [
		{"any": [{"flag": "story.pit_calls"}, {"flag": "story.vulkar_journals"}]},
		{"not": {"flag_not": "story.met_hilde"}},
	]}
	assert_true(StoryManager.evaluate(nested, _context),
			"any-true AND not(not-flag) = true")


func test_multiple_keys_in_one_object_are_an_implicit_all() -> void:
	StoryManager.set_flag(&"story.pit_calls")
	assert_true(StoryManager.evaluate({"flag": "story.pit_calls", "character": "wren"}, _context),
			"both keys true -> passes")
	assert_false(StoryManager.evaluate({"flag": "story.pit_calls", "character": "brann"}, _context),
			"one key false -> fails")


# --- flag and flag_not ------------------------------------------------------

func test_flag_reads_the_flag_store() -> void:
	assert_false(StoryManager.evaluate({"flag": "story.met_hilde"}), "unset -> false")
	StoryManager.set_flag(&"story.met_hilde")
	assert_true(StoryManager.evaluate({"flag": "story.met_hilde"}), "set -> true")


func test_flag_not_is_the_negation() -> void:
	StoryManager.set_flag(&"story.vulkar_journals")
	assert_true(StoryManager.evaluate({"flag_not": "story.met_hilde"}), "unset -> true")
	assert_false(StoryManager.evaluate({"flag_not": "story.vulkar_journals"}), "set -> false")


# --- character and class ----------------------------------------------------

func test_character_matches_the_context_character() -> void:
	assert_true(StoryManager.evaluate({"character": "wren"}, _context), "wren == wren")
	assert_false(StoryManager.evaluate({"character": "brann"}, _context), "brann != wren")


func test_character_fails_for_an_unknown_talker() -> void:
	var anonymous := StoryManager.EvalContext.new()
	assert_false(StoryManager.evaluate({"character": "wren"}, anonymous),
			"an empty identity matches nobody")


func test_class_matches_the_context_class() -> void:
	assert_true(StoryManager.evaluate({"class": "warrior"}, _context), "warrior == warrior")
	assert_false(StoryManager.evaluate({"class": "ranger"}, _context), "ranger != warrior")


# --- town_level -------------------------------------------------------------

func test_town_level_passes_at_and_above_the_min() -> void:
	assert_true(StoryManager.evaluate(
			{"town_level": {"building": "blacksmith", "min": 2}}, _context),
			"level 2 >= min 2")
	assert_true(StoryManager.evaluate(
			{"town_level": {"building": "blacksmith", "min": 1}}, _context),
			"level 2 >= min 1")


func test_town_level_fails_below_the_min_and_for_unknown_buildings() -> void:
	assert_false(StoryManager.evaluate(
			{"town_level": {"building": "blacksmith", "min": 3}}, _context),
			"level 2 < min 3")
	assert_false(StoryManager.evaluate(
			{"town_level": {"building": "shrine", "min": 1}}, _context),
			"an unlisted building is level 0 (the profile's rule)")


# --- ore_min ----------------------------------------------------------------

func test_ore_min_passes_at_and_above_the_min() -> void:
	assert_true(StoryManager.evaluate({"ore_min": {"ore": "copper", "min": 12}}, _context),
			"12 >= 12")
	assert_true(StoryManager.evaluate({"ore_min": {"ore": "copper", "min": 5}}, _context),
			"12 >= 5")


func test_ore_min_fails_below_the_min_and_for_unknown_ores() -> void:
	assert_false(StoryManager.evaluate({"ore_min": {"ore": "copper", "min": 13}}, _context),
			"12 < 13")
	assert_false(StoryManager.evaluate({"ore_min": {"ore": "iron", "min": 1}}, _context),
			"an ore not held counts as 0")


# --- deepest_floor_min ------------------------------------------------------

func test_deepest_floor_min_passes_at_and_above_the_record() -> void:
	assert_true(StoryManager.evaluate({"deepest_floor_min": 7}, _context), "7 >= 7")
	assert_true(StoryManager.evaluate({"deepest_floor_min": 3}, _context), "7 >= 3")


func test_deepest_floor_min_fails_below_the_record() -> void:
	assert_false(StoryManager.evaluate({"deepest_floor_min": 8}, _context), "7 < 8")


# --- rescued ----------------------------------------------------------------

func test_rescued_matches_a_rescued_miner_id() -> void:
	assert_true(StoryManager.evaluate({"rescued": "sly_nettie"}, _context), "rescued miner")
	assert_false(StoryManager.evaluate({"rescued": "cogsworth"}, _context), "not yet rescued")


# --- act_min ----------------------------------------------------------------

func test_act_min_passes_at_and_below_the_current_act() -> void:
	StoryManager.set_flag(&"story.foreman_defeated")
	assert_true(StoryManager.evaluate({"act_min": 1}), "act 2 >= 1")
	assert_true(StoryManager.evaluate({"act_min": 2}), "act 2 >= 2")


func test_act_min_fails_above_the_current_act() -> void:
	assert_false(StoryManager.evaluate({"act_min": 3}), "act 1 < 3")
	assert_false(StoryManager.evaluate({"act_min": 2}), "act 1 < 2")


# --- random_chance ----------------------------------------------------------

func test_random_chance_1_always_and_0_never() -> void:
	assert_true(StoryManager.evaluate({"random_chance": 1.0}, _context),
			"randf() < 1.0 always holds (randf is 0..1 exclusive)")
	assert_false(StoryManager.evaluate({"random_chance": 0.0}, _context),
			"randf() < 0.0 never holds")


func test_random_chance_uses_a_seeded_context_rng_deterministically() -> void:
	# Same seed, same sequence: two contexts roll the same values in the same
	# order, so a content author can reason about a seeded run's chance lines.
	var first := StoryManager.EvalContext.new()
	var second := StoryManager.EvalContext.new()
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 42
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 42
	first.rng = rng_a
	second.rng = rng_b
	var rolls: Array[float] = []
	for i: int in 3:
		rolls.append(first.rng.randf())
	# Re-roll the second generator and replay: the sequences must match.
	rng_b.seed = 42
	for i: int in 3:
		assert_eq(second.rng.randf(), rolls[i], "roll %d matches the seeded sequence" % i)


func test_random_chance_uses_the_shared_rng_without_a_context_one() -> void:
	# Without a context rng the autoload's shared source answers; it exists
	# after the first roll and is not rebuilt per call.
	assert_true(StoryManager.evaluate({"random_chance": 1.0}),
			"a roll happened against the shared generator")
	assert_true(StoryManager._condition_rng != null, "the shared source was built once")


# --- failing safe on malformed runtime conditions ---------------------------

func test_unknown_operator_fails_safe() -> void:
	assert_false(StoryManager.evaluate({"weather": "sunny"}, _context),
			"an unknown operator is false, warned, never a crash")


func test_malformed_leaf_values_fail_safe() -> void:
	assert_false(StoryManager.evaluate({"flag": 42}, _context), "flag must be a string")
	assert_false(StoryManager.evaluate({"character": ""}, _context), "character must be non-empty")
	assert_false(StoryManager.evaluate({"town_level": "blacksmith"}, _context),
			"town_level must be an object")
	assert_false(StoryManager.evaluate({"ore_min": {"ore": "copper"}}, _context),
			"ore_min without min reads 0 and fails a 12 count")
	assert_false(StoryManager.evaluate({"deepest_floor_min": "7"}, _context),
			"deepest_floor_min must be an integer")
	assert_false(StoryManager.evaluate({"random_chance": "high"}, _context),
			"random_chance must be a number")


func test_non_object_condition_fails_safe() -> void:
	assert_false(StoryManager.evaluate({"not": []}, _context),
			"a malformed not is not a passing condition")


# --- selection: priority scan and fallback ----------------------------------

## Builds a validated DialogueData from a raw fixture. `_validate` is the same
## entry point the loader uses, so the fixtures here are checked by the schema
## too — a test fixture that stops being valid fails loudly here rather than
## testing selection against nonsense.
func _dialogue_from(raw: Dictionary, file_name: String = "test_npc.json") -> DialogueData:
	var errors := PackedStringArray()
	var data: DialogueData = DialogueData._validate(raw, file_name, _declared, errors)
	assert_true(errors.is_empty(), "selection fixture must validate: %s" % "; ".join(errors))
	return data


const TWO_ENTRY: Dictionary = {
	"id": "test_npc",
	"entries": [
		{
			"id": "high",
			"priority": 50,
			"conditions": {"flag": "story.foreman_defeated"},
			"lines": [{"speaker": "NPC", "text": "The foreman is down."}],
		},
		{
			"id": "base",
			"priority": 1,
			"lines": [{"speaker": "NPC", "text": "Hello."}],
		},
	],
}


func test_highest_priority_passing_entry_wins() -> void:
	var dialogue := _dialogue_from(TWO_ENTRY)
	assert_eq(StoryManager.select_entry(dialogue, _context).id, &"base",
			"the flag is unset: the high entry fails, the base wins")
	StoryManager.set_flag(&"story.foreman_defeated")
	assert_eq(StoryManager.select_entry(dialogue, _context).id, &"high",
			"the flag is set: the high entry wins")


func test_ties_break_to_file_order() -> void:
	var raw: Dictionary = TWO_ENTRY.duplicate(true)
	(raw["entries"] as Array)[0]["priority"] = 50
	(raw["entries"] as Array)[1]["priority"] = 50
	(raw["entries"] as Array)[0].erase("conditions")
	var dialogue := _dialogue_from(raw)
	assert_eq(StoryManager.select_entry(dialogue, _context).id, &"high",
			"equal priority: the earlier entry in file order wins")


func test_select_entry_skips_failing_higher_entries_to_find_a_lower_one() -> void:
	var raw: Dictionary = {
		"id": "test_npc",
		"entries": [
			{"id": "top", "priority": 90, "conditions": {"act_min": 3},
					"lines": [{"speaker": "NPC", "text": "top"}]},
			{"id": "mid", "priority": 60, "conditions": {"character": "brann"},
					"lines": [{"speaker": "NPC", "text": "mid"}]},
			{"id": "low", "priority": 10, "lines": [{"speaker": "NPC", "text": "low"}]},
		],
	}
	var dialogue := _dialogue_from(raw)
	assert_eq(StoryManager.select_entry(dialogue, _context).id, &"low",
			"two higher entries fail on live state; the unconditional low one answers")


func test_no_entry_passing_returns_the_fallback_stub() -> void:
	var raw: Dictionary = {
		"id": "mayor_hilde",
		"entries": [
			{"id": "gated", "priority": 10, "conditions": {"act_min": 3},
					"lines": [{"speaker": "Mayor Hilde", "text": "Late-game line."}]},
		],
	}
	var dialogue := _dialogue_from(raw, "mayor_hilde.json")
	var chosen: DialogueData.Entry = StoryManager.select_entry(dialogue, _context)
	assert_eq(chosen.id, &"fallback", "PLAN G3: a stub {id: fallback} entry")
	assert_eq(chosen.lines.size(), 1, "one stub line")
	assert_eq(chosen.lines[0]["speaker"], "Mayor Hilde", "the stub speaks with the NPC")
	assert_eq(chosen.lines[0]["text"], StoryManager.FALLBACK_TEXT)


func test_fallback_speaker_is_humanized_from_the_dialogue_id() -> void:
	# Built directly rather than through the validator: the point is the
	# speaker naming, not the schema.
	var dialogue := DialogueData.new()
	dialogue.id = &"old_tom"
	var entry := DialogueData.Entry.new()
	entry.id = &"only"
	entry.priority = 1
	entry.conditions = {"flag": "nope.not_declared"}
	entry.lines = [{"speaker": "Old Tom", "text": "hint"}]
	dialogue.entries.append(entry)
	assert_eq(StoryManager.fallback_entry(dialogue).lines[0]["speaker"], "Old Tom",
			"old_tom humanizes to Old Tom")


func test_fallback_never_enters_the_dialogues_own_entries() -> void:
	var dialogue := _dialogue_from(TWO_ENTRY)
	StoryManager.select_entry(dialogue, StoryManager.EvalContext.new())
	assert_false(dialogue.entry_ids().has(&"fallback"),
			"the stub is built per call, not appended to the data")
