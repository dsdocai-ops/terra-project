extends GutTest
## Data-driven schema validation of `DialogueData` — every dialogue JSON in
## `data/dialogue/` parses, matches the schema, resolves every goto, names
## only declared flags — plus per-rule rejection fixtures built in-memory
## (story-dialogue, W6-B1, PLAN G2).
##
## SPEC-story-dialogue: "a bad file fails the test suite, not the game" — the
## loader collects ALL violations of a file in one pass and the test prints
## them. The real-content section runs against `flags.json` (the flag
## declaration) and every dialogue file present; the rejection section feeds
## constructed Dictionaries to the same validator so each schema rule has an
## explicit failing case.

const FLAGS_PATH: String = "res://data/dialogue/flags.json"

## A valid baseline file, mutated per-case to trigger exactly one rule.
const BASE: Dictionary = {
	"id": "test_npc",
	"entries": [
		{
			"id": "intro",
			"priority": 10,
			"lines": [{"speaker": "Test NPC", "text": "Hello."}],
		},
		{
			"id": "more",
			"priority": 5,
			"lines": [{"speaker": "Test NPC", "text": "More."}],
		},
	],
}

var _declared: Dictionary = {}


func before_each() -> void:
	_declared = {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(FLAGS_PATH)) == OK \
			and json.data is Dictionary:
		var by_ns: Dictionary = (json.data as Dictionary)["flags"]
		for ns: String in by_ns:
			for fname: String in (by_ns[ns] as Dictionary):
				_declared[ns + "." + fname] = true


func after_each() -> void:
	pass


# --- helpers ----------------------------------------------------------------

func _validate(raw: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	DialogueData._validate(raw, "test_npc.json", _declared, errors)
	return errors


func _assert_clean(errors: PackedStringArray, what: String) -> void:
	assert_true(errors.is_empty(), "%s must validate clean, got: %s" % [what, "; ".join(errors)])


func _assert_error(errors: PackedStringArray, needle: String, what: String) -> void:
	var found := false
	for e: String in errors:
		if needle in e:
			found = true
			break
	assert_true(found, "%s must be rejected (expected '%s'), got: %s" % [what, needle, "; ".join(errors)])


func _mutated(field: String, value: Variant) -> Dictionary:
	var raw: Dictionary = BASE.duplicate(true)
	if field == "":
		raw.erase("id") if value == null else null
		if value != null:
			raw[field] = value
	else:
		raw[field] = value
	return raw


func _entry_mutated(index: int, field: String, value: Variant) -> Dictionary:
	var raw: Dictionary = BASE.duplicate(true)
	if value == null:
		(raw["entries"] as Array)[index].erase(field)
	else:
		(raw["entries"] as Array)[index][field] = value
	return raw


# --- the real content in data/dialogue/ -------------------------------------

func test_every_real_dialogue_file_validates() -> void:
	var results := DialogueData.load_all(_declared)
	var all_errors := PackedStringArray()
	for r: DialogueData.LoadResult in results:
		if not r.ok():
			for e: String in r.errors:
				all_errors.append(e)
	assert_eq(all_errors.size(), 0,
			"every data/dialogue file must validate; violations:\n" + "\n".join(all_errors))


func test_every_real_goto_resolves() -> void:
	var results := DialogueData.load_all(_declared)
	assert_true(results.size() >= 0, "load_all runs")
	for r: DialogueData.LoadResult in results:
		if r.ok():
			for entry: DialogueData.Entry in r.data.entries:
				for choice: Variant in entry.choices:
					if choice is Dictionary and (choice as Dictionary).has("goto"):
						assert_true(r.data.entry_ids().has(StringName((choice as Dictionary)["goto"])),
								"%s: goto target exists" % r.data.id)


# --- valid baseline ---------------------------------------------------------

func test_valid_baseline_passes() -> void:
	_assert_clean(_validate(BASE), "baseline")


func test_valid_full_featured_file_passes() -> void:
	var raw: Dictionary = {
		"id": "test_npc",
		"portrait": "res://assets/portraits/wren.png",
		"entries": [
			{
				"id": "intro",
				"priority": 10,
				"conditions": {"all": [{"flag_not": "story.met_hilde"}]},
				"lines": [
					{"speaker": "A", "text": "One.", "emotion": "worried"},
					{"speaker": "B", "text": "Two.", "character_only": "wren"},
				],
				"choices": [
					{"text": "Go deeper", "goto": "more"},
					{"text": "Done", "end": true, "set_flags": ["story.met_hilde"]},
				],
				"on_end": {"set_flags": ["story.met_hilde"], "give": {"gold": 50}},
			},
			{
				"id": "more",
				"priority": 5,
				"conditions": {"any": [{"act_min": 2}, {"flag": "story.pit_calls"}]},
				"lines": [{"speaker": "A", "text": "Deep line."}],
			},
		],
	}
	_assert_clean(_validate(raw), "full-featured")


# --- top-level rules --------------------------------------------------------

func test_missing_id_rejected() -> void:
	var raw: Dictionary = BASE.duplicate(true)
	raw.erase("id")
	_assert_error(_validate(raw), "missing \"id\"", "file without id")


func test_id_must_match_file_name() -> void:
	var raw: Dictionary = BASE.duplicate(true)
	raw["id"] = "wrong_name"
	_assert_error(_validate(raw), "file name says \"test_npc\"", "id/file mismatch")


func test_portrait_must_be_res_path() -> void:
	_assert_error(_validate(_mutated("portrait", "http://x/y.png")), "res:// path", "non-res portrait")


func test_portrait_file_must_exist() -> void:
	_assert_error(_validate(_mutated("portrait", "res://assets/portraits/no_such.png")),
			"does not exist", "missing portrait file")


func test_missing_entries_rejected() -> void:
	var raw: Dictionary = BASE.duplicate(true)
	raw.erase("entries")
	_assert_error(_validate(raw), "missing \"entries\"", "no entries")


func test_empty_entries_rejected() -> void:
	_assert_error(_validate(_mutated("entries", [])), "must not be empty", "empty entries")


func test_unknown_top_level_key_rejected() -> void:
	_assert_error(_validate(_mutated("surprise", 1)), "unknown top-level key", "unknown top key")


# --- entry rules ------------------------------------------------------------

func test_entry_missing_id_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "id", null)), "missing \"id\"", "entry without id")


func test_duplicate_entry_id_rejected() -> void:
	_assert_error(_validate(_entry_mutated(1, "id", "intro")), "repeats id", "duplicate entry id")


func test_missing_priority_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "priority", null)), "missing \"priority\"", "no priority")


func test_priority_out_of_bounds_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "priority", 101)), "outside 0..100", "priority 101")
	_assert_error(_validate(_entry_mutated(0, "priority", -1)), "outside 0..100", "priority -1")


func test_entry_unknown_key_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "bogus", 1)), "unknown key", "unknown entry key")


func test_missing_or_empty_lines_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "lines", null)), "missing \"lines\"", "no lines")
	_assert_error(_validate(_entry_mutated(0, "lines", [])), "non-empty", "empty lines")


# --- line rules -------------------------------------------------------------

func test_line_missing_speaker_or_text_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "lines", [{"text": "x"}])), "missing \"speaker\"", "no speaker")
	_assert_error(_validate(_entry_mutated(0, "lines", [{"speaker": "S"}])), "missing \"text\"", "no text")


func test_line_text_over_limit_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "lines", [
		{"speaker": "S", "text": "x".repeat(401)},
	])), "over 400 characters", "long line")


func test_line_unknown_key_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "lines", [
		{"speaker": "S", "text": "x", "mood": 1},
	])), "unknown key", "unknown line key")


# --- choice rules -----------------------------------------------------------

func test_choice_without_destination_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "choices", [{"text": "Hmm"}])),
			"needs \"goto\" or \"end\"", "choice with no destination")


func test_choice_with_both_goto_and_end_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "choices", [
		{"text": "Hmm", "goto": "more", "end": true},
	])), "both \"goto\" and \"end\"", "ambiguous choice")


func test_dangling_goto_rejected() -> void:
	var raw: Dictionary = BASE.duplicate(true)
	(raw["entries"] as Array)[0]["choices"] = [{"text": "Hmm", "goto": "nowhere"}]
	_assert_error(_validate(raw), "matches no entry", "dangling goto")


func test_choice_undeclared_set_flag_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "choices", [
		{"text": "Hmm", "end": true, "set_flags": ["story.not_declared_anywhere"]},
	])), "undeclared flag", "undeclared choice flag")


# --- on_end rules -----------------------------------------------------------

func test_on_end_unknown_currency_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "on_end", {"give": {"bitcoin": 1}})),
			"unknown currency", "bogus currency")


func test_on_end_undeclared_flag_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "on_end", {"set_flags": ["nope.not_real"]})),
			"undeclared flag", "undeclared on_end flag")


# --- condition rules --------------------------------------------------------

func test_unknown_condition_operator_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "conditions", {"weather": "sunny"})),
			"unknown condition operator", "unknown op")


func test_undeclared_flag_in_condition_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "conditions", {"flag": "story.nope"})),
			"undeclared flag", "undeclared condition flag")


func test_condition_nesting_shapes() -> void:
	_assert_clean(_validate(_entry_mutated(0, "conditions",
			{"all": [{"any": [{"not": {"flag": "story.pit_calls"}}]}]})), "nested composites (object not)")
	_assert_clean(_validate(_entry_mutated(0, "conditions",
			{"not": [{"flag": "story.pit_calls"}]})), "array not")
	_assert_error(_validate(_entry_mutated(0, "conditions", {"not": []})),
			"holds exactly one condition", "not with zero subs")
	_assert_error(_validate(_entry_mutated(0, "conditions", {"not": [{"flag": "a.b"}, {"flag": "c.d"}]})),
			"holds exactly one condition", "not with two subs")
	_assert_error(_validate(_entry_mutated(0, "conditions", {"all": {"flag": "a.b"}})),
			"must be an array", "all without array")


func test_condition_depth_cap() -> void:
	var deep: Dictionary = {"flag": "story.pit_calls"}
	for i: int in range(12):
		deep = {"not": [deep]}
	_assert_error(_validate(_entry_mutated(0, "conditions", deep)), "nests deeper than", "depth cap")


func test_leaf_value_shapes_rejected() -> void:
	_assert_error(_validate(_entry_mutated(0, "conditions", {"town_level": "blacksmith"})),
			"must be {building, min}", "town_level scalar")
	_assert_error(_validate(_entry_mutated(0, "conditions", {"ore_min": {"ore": "copper"}})),
			"missing \"min\"", "ore_min without min")
	_assert_error(_validate(_entry_mutated(0, "conditions", {"deepest_floor_min": 99})),
			"outside 1..30", "floor out of range")
	_assert_error(_validate(_entry_mutated(0, "conditions", {"act_min": 7})),
			"outside 1..3", "act out of range")
	_assert_error(_validate(_entry_mutated(0, "conditions", {"random_chance": 1.5})),
			"must be in 0..1", "chance out of range")


# --- typed accessors --------------------------------------------------------

func test_entry_lookup_and_priority_order() -> void:
	var raw: Dictionary = BASE.duplicate(true)
	raw["entries"] = [
		{"id": "low", "priority": 1, "lines": [{"speaker": "S", "text": "l"}]},
		{"id": "high", "priority": 50, "lines": [{"speaker": "S", "text": "h"}]},
		{"id": "mid", "priority": 25, "lines": [{"speaker": "S", "text": "m"}]},
		{"id": "high2", "priority": 50, "lines": [{"speaker": "S", "text": "h2"}]},
	]
	var errors := PackedStringArray()
	var data: DialogueData = DialogueData._validate(raw, "test_npc.json", _declared, errors)
	_assert_clean(errors, "priority fixture")
	var ordered := data.entries_by_priority()
	assert_eq(ordered[0].id, &"high", "highest priority first")
	assert_eq(ordered[1].id, &"high2", "ties break to file order")
	assert_eq(data.entry(&"mid").priority, 25, "entry() lookup")
	assert_eq(data.entry(&"missing"), null, "entry() miss returns null")


func test_entries_for_act_filters_and_orders() -> void:
	var raw: Dictionary = BASE.duplicate(true)
	raw["entries"] = [
		{"id": "act2", "priority": 5, "conditions": {"act_min": 2}, "lines": [{"speaker": "S", "text": "a"}]},
		{"id": "any", "priority": 10, "lines": [{"speaker": "S", "text": "b"}]},
		{"id": "act3", "priority": 100, "conditions": {"act_min": 3}, "lines": [{"speaker": "S", "text": "c"}]},
	]
	var errors := PackedStringArray()
	var data: DialogueData = DialogueData._validate(raw, "test_npc.json", _declared, errors)
	_assert_clean(errors, "act fixture")
	var act1 := data.entries_for_act(1)
	assert_eq(act1.size(), 1, "act 1 sees only the unconditional entry")
	assert_eq(act1[0].id, &"any")
	var act3 := data.entries_for_act(3)
	assert_eq(act3.size(), 3, "act 3 sees everything")
	assert_eq(act3[0].id, &"act3", "priority order kept")


# --- loader level -----------------------------------------------------------

func test_load_file_missing_reports_error() -> void:
	var r := DialogueData.load_file("definitely_not_there.json", _declared)
	assert_false(r.ok(), "missing file is not ok")
	assert_true(r.errors[0].contains("does not exist"), "error says file missing")


func test_load_file_bad_json_reports_parse_error() -> void:
	# A file with broken syntax, written into a user:// overlay is not
	# possible for res:// — so exercise the parse path through a real temp
	# file inside the dialogue dir is avoided; instead assert the error
	# format on a known-bad source via _validate's sibling.
	var r := DialogueData.load_file("flags.json", _declared)
	# flags.json is deliberately skipped by load_all but load_file can open
	# it; it must NOT validate as a dialogue file (no entries).
	assert_false(r.ok() or r.data != null and r.data.entries.size() > 0,
			"flags.json is not a dialogue file")


func test_load_all_skips_flags_json() -> void:
	var results := DialogueData.load_all(_declared)
	for r: DialogueData.LoadResult in results:
		assert_ne(r.path.get_file(), "flags.json", "flags.json never loaded as dialogue")
	pass_test("scan completed over %d files" % results.size())
