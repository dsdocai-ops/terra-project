extends GutTest
## `RelicData` and the rules every `data/relics/*.tres` must satisfy — relics,
## W4-B5 (PLAN G3 / raw G27).
##
## SPEC-relics "Testing" makes this file the project's rule-enforcement
## mechanism rather than a description of one: every `.tres` under
## `data/relics/` is walked and checked for the id matching its file name, a
## non-empty `display_name` and `description`, a `rarity` and a `kind` from the
## class's own enums, 1 to 2 tags from the `Tags` vocabulary, `max_stacks >= 1`
## and an `effect_script` that extends `Effect`. The folder holds no relic until
## the first content batch lands, so **every rule is also demonstrated on a
## fixture this test writes itself** (the `test_data_loads.gd` pattern): a green
## scan of an empty folder proves nothing on its own, and a rule whose failing
## path has never been observed is an assumption.
##
## The two id/weight tables the later relic goals read are pinned against the
## documents they come from — the 20 Week 4 ids against design doc 9.1 nos. 1 to
## 20 and the Shrine rarity weights against SPEC-relics — so neither can drift
## away from its source without this file failing.
##
## The file also carries **the harness-completeness gate** (PLAN G8b, raw goal
## G35's gate half): the folder must hold exactly the twenty ids and every one of
## them must have a case of its own in `tests/integration/test_relic_triggers.gd`,
## so the week's "20 relics" count cannot survive a deleted `.tres` or a deleted
## case. Both halves fail on their own, and the goal's evidence demonstrates each
## by removing one file and renaming one case.
##
## Owned by relics. Sync: none (data).
##

const RELIC_DIR: String = "res://data/relics"
## SPEC-relics "Testing" names this file the other half of the pair: one case per
## relic. The completeness gate reads it rather than restating its contents.
const HARNESS_PATH: String = "res://tests/integration/test_relic_triggers.gd"
const SPEC_RELICS_PATH: String = "res://specs/SPEC-relics.md"
const DESIGN_DOC_PATH: String = "res://SINKHOLE_SPEC.md"
const EFFECT_SCRIPT_PATH: String = "res://scripts/effects/effect.gd"
const SAMPLE_EFFECT_PATH: String = "res://tests/helpers/harness_sample_effect.gd"
const CONTENT_DATA_PATH: String = "res://scripts/data/content_data.gd"
## The design doc's passive-relic group heading that opens its numbered list.
const DESIGN_DOC_HEADING: String = "### 9.1 Passive relics (70 listed)"
## Fixtures are written here and removed in `after_each()`; never in `data/`.
const FIXTURE_DIR: String = "user://_relic_fixtures"
const WEEK_4_COUNT: int = 20
## How many relic `.tres` files `data/relics/` must hold, read off the table G3
## pinned against design doc 9.1 rather than kept as a second copy of the number
## (PLAN G8b raises G7's decision-75 floor of 16 to the batch's own size, so a
## missing file and a stray file now fail the same check). It is spelled as the
## scan case's own expression and not as a `const`: GDScript refuses a method
## call in a constant expression, which this goal measured rather than assumed —
## `Parse Error: Assigned value for constant "WEEK_4_LANDED_MIN" isn't a
## constant expression` (`.goals/evidence/g8b/…-test-relic-data-first.log`).

var _fixture_paths: Array[String] = []


func after_each() -> void:
	for path: String in _fixture_paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_fixture_paths.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_DIR))


# --- helpers ---------------------------------------------------------------

func _read_lines(path: String) -> PackedStringArray:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "could not open %s" % path)
	if file == null:
		return PackedStringArray()
	var text := file.get_as_text()
	file.close()
	return text.split("\n")


## Every `.tres` under `dir_path`, recursively, as full `res://`-style paths.
func _collect_tres(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	assert_not_null(dir, "open %s" % dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(_collect_tres(full))
		elif entry.ends_with(".tres"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


## True when `script` is `Effect` itself or inherits from it, by walking the
## base-script chain rather than instantiating anything.
func _extends_effect(script: GDScript) -> bool:
	if script == null:
		return false
	var effect_script := load(EFFECT_SCRIPT_PATH) as GDScript
	var current: GDScript = script
	while current != null:
		if current == effect_script:
			return true
		current = current.get_base_script() as GDScript
	return false


## A conforming relic. Every broken fixture below starts from this and changes
## exactly one field, so each rule's case fails for its own reason.
func _valid_relic(relic_id: String) -> RelicData:
	var data := RelicData.new()
	data.id = StringName(relic_id)
	data.display_name = "Fixture Relic"
	data.description = "Takes {value} less damage while the fixture is held."
	data.rarity = RelicData.Rarity.RARE
	data.kind = RelicData.Kind.PASSIVE
	data.tags = [Tags.FIRE, Tags.DODGE] as Array[StringName]
	data.max_stacks = 1
	data.weight = 1.0
	data.effect_script = load(SAMPLE_EFFECT_PATH) as GDScript
	return data


## Every rule a relic must satisfy, as a list of problem strings in the order
## the spec's "Testing" line lists them. Pure: both the folder scan and the
## fixture cases call this same function, so a rule cannot be enforced in one
## place and described in another.
func _problems_for(data: RelicData, expected_id: String) -> Array[String]:
	var problems: Array[String] = []
	if data == null:
		problems.append("does not load as a RelicData")
		return problems
	if String(data.id) != expected_id:
		problems.append("id `%s` does not match the file name `%s`" % [data.id, expected_id])
	if String(data.display_name).strip_edges() == "":
		problems.append("display_name is empty")
	if String(data.description).strip_edges() == "":
		problems.append("description is empty")
	if not RelicData.Rarity.values().has(data.rarity):
		problems.append("rarity %d is not one of RelicData.Rarity" % data.rarity)
	if not RelicData.Kind.values().has(data.kind):
		problems.append("kind %d is not one of RelicData.Kind" % data.kind)
	if data.tags.is_empty() or data.tags.size() > 2:
		problems.append("tags holds %d entries, the spec allows 1 to 2" % data.tags.size())
	for tag: StringName in data.tags:
		if not Tags.is_valid(tag):
			problems.append("tag `%s` is not in the Tags vocabulary" % tag)
	if data.max_stacks < 1:
		problems.append("max_stacks is %d, at least 1 is required" % data.max_stacks)
	if not _extends_effect(data.effect_script):
		problems.append("effect_script does not extend Effect")
	return problems


## Saves `data` into the fixture folder and remembers it for cleanup.
func _write_fixture(data: RelicData, file_name: String) -> String:
	var dir := DirAccess.open(FIXTURE_DIR)
	if dir == null:
		assert_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_DIR)), OK, "fixture dir")
	var path := FIXTURE_DIR.path_join(file_name)
	assert_eq(ResourceSaver.save(data, path), OK, "save %s" % path)
	_fixture_paths.append(path)
	return path


## "Rune of Ricochet" -> `rune_of_ricochet`: the id rule the design doc's names
## imply (SPEC-project: "Content ids are the snake_case file name").
func _id_from_display_name(display_name: String) -> String:
	return display_name.strip_edges().to_lower().replace("'", "").replace(" ", "_")


## The harness file's test cases as `case name -> case body`. A case runs from
## its own `func test_...` line to the next `func`, so "this case covers that
## relic" is read off the case rather than off the file — a batch case that
## mentions an id in passing cannot stand in for the relic's own case.
func _harness_cases(path: String) -> Dictionary:
	var cases: Dictionary = {}
	var case_name: String = ""
	var case_body: String = ""
	for raw: String in _read_lines(path):
		var line: String = raw
		if line.begins_with("func "):
			if case_name != "":
				cases[case_name] = case_body
				case_name = ""
				case_body = ""
			if line.begins_with("func test_"):
				case_name = line.substr("func ".length()).split("(")[0].strip_edges()
				case_body = line
			continue
		if case_name != "":
			case_body += "\n" + line
	if case_name != "":
		cases[case_name] = case_body
	return cases


## True when a harness case's name is the relic's own: `test_<id>` or
## `test_<id>_...`. The trailing separator keeps `test_bloodthirsty` from
## counting as `bloodthirst`.
func _is_named_for(case_name: String, relic_id: StringName) -> bool:
	var exact: String = "test_%s" % relic_id
	return case_name == exact or case_name.begins_with(exact + "_")


# --- the folder scan -------------------------------------------------------

func test_the_relic_folder_exists_and_the_scan_reports_what_it_holds() -> void:
	var dir := DirAccess.open(RELIC_DIR)
	assert_not_null(dir, "%s exists, so an empty result means an empty folder" % RELIC_DIR)
	var paths: Array[String] = _collect_tres(RELIC_DIR)
	for path: String in paths:
		assert_true(path.ends_with(".tres"), "%s is a relic resource" % path)
	# The floor and the ceiling are now the same number — the batch's own size —
	# so a relic whose file goes missing and a stray file that is not a Week-4
	# relic are both caught here, and the gate case below names the id.
	assert_between(paths.size(), RelicData.WEEK_4_IDS.size(), RelicData.WEEK_4_IDS.size(),
		"the folder holds every Week 4 relic, and only those")
	pass_test("%d relic .tres files in %s" % [paths.size(), RELIC_DIR])


func test_every_relic_file_satisfies_the_data_rules() -> void:
	var paths: Array[String] = _collect_tres(RELIC_DIR)
	for path: String in paths:
		var data := load(path) as RelicData
		assert_not_null(data, "%s loads as a RelicData" % path)
		var file_name: String = path.get_file().get_basename()
		assert_eq(_problems_for(data, file_name), [] as Array[String], "%s satisfies every relic rule" % path)
	pass_test("%d relics checked against the data rules" % paths.size())


# --- the harness-completeness gate ------------------------------------------
#
# SPEC-relics "Testing" makes this file and the harness a pair: `data/relics/`
# holds the content and `test_relic_triggers.gd` holds "one case per relic".
# Neither half is evidence alone — twenty `.tres` with no case prove nothing
# runs, and twenty cases with a file missing prove nothing shipped — so the two
# cases below walk both. Each fails on its own: the first names the missing id,
# the second names the unharnessed one, and G8b's evidence shows both by
# removing one `.tres` and renaming one case (PLAN G8b, raw goal G35's gate half).

func test_the_folder_holds_exactly_the_twenty_week_4_relics_by_id() -> void:
	var found: Array[String] = []
	for path: String in _collect_tres(RELIC_DIR):
		var file_name: String = path.get_file().get_basename()
		var data := load(path) as RelicData
		assert_not_null(data, "%s loads as a RelicData" % path)
		if data == null:
			continue
		assert_eq(String(data.id), file_name, "%s's id is its file name" % file_name)
		assert_eq(_problems_for(data, file_name), [] as Array[String],
			"%s satisfies every relic rule the spec's Testing line lists" % file_name)
		found.append(file_name)

	var expected: Array[String] = []
	for relic_id: StringName in RelicData.WEEK_4_IDS:
		expected.append(String(relic_id))
	found.sort()
	expected.sort()
	assert_eq(found.size(), WEEK_4_COUNT, "the folder holds the batch's twenty, not one fewer")
	# Sorted whole-list equality rather than a count, and then the two halves of
	# that list spelled out separately, so the failure names the id that went
	# missing and the id that does not belong instead of reporting a shift. This
	# is what makes it a gate rather than a tally.
	assert_eq(found, expected,
		"data/relics/ holds design doc 9.1's nos. 1 to 20 by id, nothing missing and nothing extra")
	var missing: Array[String] = []
	for relic_id: String in expected:
		if not found.has(relic_id):
			missing.append(relic_id)
	var extra: Array[String] = []
	for relic_id: String in found:
		if not expected.has(relic_id):
			extra.append(relic_id)
	assert_eq(missing, [] as Array[String], "every design doc 9.1 id has a .tres under data/relics/")
	assert_eq(extra, [] as Array[String], "no file under data/relics/ falls outside design doc 9.1's twenty")


func test_every_week_4_relic_has_its_own_case_in_the_harness() -> void:
	assert_true(FileAccess.file_exists(HARNESS_PATH), "%s exists" % HARNESS_PATH)
	var cases: Dictionary = _harness_cases(HARNESS_PATH)
	assert_gt(cases.size(), WEEK_4_COUNT, "%s parses into its cases" % HARNESS_PATH.get_file())

	for relic_id: StringName in RelicData.WEEK_4_IDS:
		var covered: String = ""
		var named: int = 0
		for case_name: String in cases:
			if not _is_named_for(case_name, relic_id):
				continue
			named += 1
			# The case names its relic's own id — which is how it loads
			# `data/relics/<id>.tres` — so a case named for a relic but about
			# something else does not count as that relic's coverage.
			if String(cases[case_name]).contains("\"%s\"" % relic_id):
				covered = case_name
				break
		assert_true(named > 0, "%s has a case of its own in %s (none of the %d cases is named `test_%s…`)" % [
			relic_id, HARNESS_PATH.get_file(), cases.size(), relic_id])
		assert_ne(covered, "", "%s's own case in %s names it (a case that is not about its relic is not coverage)" % [
			relic_id, HARNESS_PATH.get_file()])


func test_the_gate_credits_only_a_case_that_is_the_relics_own() -> void:
	# The gate is only as good as what it counts as "a case for this relic", so
	# the rules it leans on are pinned rather than trusted — the same shape as
	# `test_the_effect_rule_reads_the_scripts_inheritance_chain`.
	assert_true(_is_named_for("test_ember_boots_leaves_a_fire_trail_on_a_dodge", &"ember_boots"),
		"a case named for the relic counts")
	assert_true(_is_named_for("test_ember_boots", &"ember_boots"),
		"a case named exactly for the relic counts")
	assert_false(_is_named_for("test_ember_bootstraps", &"ember_boots"),
		"a longer name is not the relic's name")
	assert_false(_is_named_for("test_the_six_fire_for_their_own_players_dodge", &"ember_boots"),
		"a batch case is not the relic's own case")

	var cases: Dictionary = _harness_cases(HARNESS_PATH)
	# A case that names a relic without being *about* it: the scene test loads
	# Ember Boots' own `.tres` to check where its FX comes from, and is nobody's
	# coverage — which is exactly why coverage is read inside the case and not
	# across the file (a file-wide search would call this case Ember Boots' and
	# let the relic's own case be deleted unnoticed).
	var mentioning_case: String = "test_the_spawning_relics_take_their_scene_from_the_relics_own_vfx_id"
	assert_true(cases.has(mentioning_case), "%s parses out of the harness file" % mentioning_case)
	if not cases.has(mentioning_case):
		return
	assert_true(String(cases[mentioning_case]).contains("\"ember_boots\""),
		"that case does name a relic in passing")
	assert_false(_is_named_for(mentioning_case, &"ember_boots"),
		"and the gate still refuses it as the relic's own case")


# --- the rules, demonstrated on fixtures this test writes itself ------------

func test_the_walker_and_the_rules_accept_a_written_fixture_folder() -> void:
	_write_fixture(_valid_relic("fixture_one"), "fixture_one.tres")
	_write_fixture(_valid_relic("fixture_two"), "fixture_two.tres")
	var paths: Array[String] = _collect_tres(FIXTURE_DIR)
	assert_eq(paths.size(), 2, "the walker finds both written fixtures")
	for path: String in paths:
		var data := load(path) as RelicData
		assert_not_null(data, "%s loads back as a RelicData" % path)
		assert_eq(_problems_for(data, path.get_file().get_basename()), [] as Array[String], "%s satisfies the rules" % path)


func test_a_relic_round_trips_through_the_tres_file_it_is_written_to() -> void:
	var written := _valid_relic("round_trip")
	written.rarity = RelicData.Rarity.LEGENDARY
	written.kind = RelicData.Kind.ACTIVE
	written.max_stacks = 3
	written.weight = 0.5
	written.active_cooldown = 12.0
	written.active_charges = 3
	var path := _write_fixture(written, "round_trip.tres")

	var loaded := load(path) as RelicData
	assert_not_null(loaded, "the written relic loads back")
	assert_eq(String(loaded.id), "round_trip")
	assert_eq(loaded.rarity, RelicData.Rarity.LEGENDARY, "the rarity enum survives the file")
	assert_eq(loaded.kind, RelicData.Kind.ACTIVE, "the kind enum survives the file")
	assert_eq(loaded.tags, [Tags.FIRE, Tags.DODGE] as Array[StringName])
	assert_eq(loaded.max_stacks, 3)
	assert_eq(loaded.weight, 0.5)
	assert_eq(loaded.active_cooldown, 12.0)
	assert_eq(loaded.active_charges, 3)
	assert_eq(String(loaded.description), String(written.description))


func test_each_rule_rejects_its_own_violation_and_only_that_one() -> void:
	# Positive control first: the conforming fixture is accepted, so a red case
	# below is the rule firing and not the fixture being broken to begin with.
	var good := _valid_relic("fixture")
	assert_eq(_problems_for(good, "fixture"), [] as Array[String], "the base fixture conforms")

	var cases: Array[Dictionary] = []

	var renamed := _valid_relic("fixture")
	renamed.id = &"not_the_file_name"
	cases.append({"data": renamed, "file": "fixture", "expect": "does not match the file name"})

	var unnamed := _valid_relic("fixture")
	unnamed.display_name = "  "
	cases.append({"data": unnamed, "file": "fixture", "expect": "display_name is empty"})

	var undescribed := _valid_relic("fixture")
	undescribed.description = ""
	cases.append({"data": undescribed, "file": "fixture", "expect": "description is empty"})

	var bad_rarity := _valid_relic("fixture")
	bad_rarity.rarity = 99
	cases.append({"data": bad_rarity, "file": "fixture", "expect": "not one of RelicData.Rarity"})

	var bad_kind := _valid_relic("fixture")
	bad_kind.kind = 99
	cases.append({"data": bad_kind, "file": "fixture", "expect": "not one of RelicData.Kind"})

	var untagged := _valid_relic("fixture")
	untagged.tags = [] as Array[StringName]
	cases.append({"data": untagged, "file": "fixture", "expect": "tags holds 0 entries"})

	var over_tagged := _valid_relic("fixture")
	over_tagged.tags = [Tags.FIRE, Tags.DODGE, Tags.CRIT] as Array[StringName]
	cases.append({"data": over_tagged, "file": "fixture", "expect": "tags holds 3 entries"})

	var invented_tag := _valid_relic("fixture")
	invented_tag.tags = [&"sparkly"] as Array[StringName]
	cases.append({"data": invented_tag, "file": "fixture", "expect": "is not in the Tags vocabulary"})

	var unstackable := _valid_relic("fixture")
	unstackable.max_stacks = 0
	cases.append({"data": unstackable, "file": "fixture", "expect": "at least 1 is required"})

	var scriptless := _valid_relic("fixture")
	scriptless.effect_script = null
	cases.append({"data": scriptless, "file": "fixture", "expect": "does not extend Effect"})

	var wrong_script := _valid_relic("fixture")
	wrong_script.effect_script = load(CONTENT_DATA_PATH) as GDScript
	cases.append({"data": wrong_script, "file": "fixture", "expect": "does not extend Effect"})

	for case: Dictionary in cases:
		var problems: Array[String] = _problems_for(case["data"] as RelicData, String(case["file"]))
		assert_eq(problems.size(), 1, "exactly one rule fires for `%s`, got %s" % [case["expect"], str(problems)])
		if problems.size() == 1:
			assert_string_contains(problems[0], String(case["expect"]), "the rule names its violation")


func test_the_effect_rule_reads_the_scripts_inheritance_chain() -> void:
	assert_true(_extends_effect(load(EFFECT_SCRIPT_PATH) as GDScript), "Effect itself is an Effect")
	assert_true(_extends_effect(load(SAMPLE_EFFECT_PATH) as GDScript), "a subclass of Effect is an Effect")
	assert_false(_extends_effect(load(CONTENT_DATA_PATH) as GDScript), "ContentData is not an Effect")
	assert_false(_extends_effect(null), "no script at all is not an Effect")


# --- the two tables later relic goals read ---------------------------------

func test_rarity_and_kind_are_the_specs_own_enums_in_the_specs_own_order() -> void:
	# The enum's order is the serialised value of every `.tres` on disk, so a
	# reordering would silently re-map all 88 relics' rarity and kind.
	assert_eq(RelicData.Rarity.keys(), ["COMMON", "RARE", "EPIC", "LEGENDARY", "CURSED"] as Array[String])
	assert_eq(RelicData.Rarity.values(), [0, 1, 2, 3, 4] as Array[int])
	assert_eq(RelicData.Kind.keys(), ["PASSIVE", "ACTIVE", "CURSED"] as Array[String])
	assert_eq(RelicData.Kind.values(), [0, 1, 2] as Array[int])


func test_the_shrine_rarity_weights_are_the_specs_own_numbers() -> void:
	var re := RegEx.new()
	re.compile("Shrine rolls: common (\\d+), rare (\\d+), epic (\\d+), legendary (\\d+)")
	var text: String = "\n".join(_read_lines(SPEC_RELICS_PATH))
	var m: RegExMatch = re.search(text)
	assert_not_null(m, "SPEC-relics states the Shrine rarity weights")
	if m == null:
		return
	assert_eq(RelicData.RARITY_WEIGHT_COMMON, int(m.get_string(1)), "common weight comes from the spec")
	assert_eq(RelicData.RARITY_WEIGHT_RARE, int(m.get_string(2)), "rare weight comes from the spec")
	assert_eq(RelicData.RARITY_WEIGHT_EPIC, int(m.get_string(3)), "epic weight comes from the spec")
	assert_eq(RelicData.RARITY_WEIGHT_LEGENDARY, int(m.get_string(4)), "legendary weight comes from the spec")
	assert_eq(RelicData.roll_weight(RelicData.Rarity.COMMON), 60)
	assert_eq(RelicData.roll_weight(RelicData.Rarity.RARE), 28)
	assert_eq(RelicData.roll_weight(RelicData.Rarity.EPIC), 10)
	assert_eq(RelicData.roll_weight(RelicData.Rarity.LEGENDARY), 2)
	assert_eq(RelicData.roll_weight(RelicData.Rarity.CURSED), 0, "cursed never rolls at a Shrine")


func test_the_week_4_id_list_is_the_design_docs_first_twenty_relics() -> void:
	var re := RegEx.new()
	re.compile("^(\\d+)\\. \\*\\*(.+?):\\*\\* .+")
	var numbered: Dictionary = {}
	var in_section: bool = false
	for raw: String in _read_lines(DESIGN_DOC_PATH):
		var line: String = raw.strip_edges()
		if line.begins_with("### "):
			in_section = line == DESIGN_DOC_HEADING
			continue
		if not in_section:
			continue
		var m: RegExMatch = re.search(line)
		if m == null:
			continue
		var number: int = int(m.get_string(1))
		if number >= 1 and number <= WEEK_4_COUNT:
			numbered[number] = _id_from_display_name(m.get_string(2))
	assert_eq(numbered.size(), WEEK_4_COUNT, "design doc 9.1 numbers 1 to 20 parse out of the document")

	var expected: Array[StringName] = []
	for number: int in range(1, WEEK_4_COUNT + 1):
		expected.append(StringName(String(numbered.get(number, ""))))
	assert_eq(RelicData.WEEK_4_IDS, expected, "the Week 4 id list is design doc 9.1 nos. 1 to 20, in order")

	var shape := RegEx.new()
	shape.compile("^[a-z][a-z0-9_]*$")
	assert_eq(RelicData.WEEK_4_IDS.size(), WEEK_4_COUNT)
	for relic_id: StringName in RelicData.WEEK_4_IDS:
		assert_not_null(shape.search(String(relic_id)), "`%s` is a snake_case id" % relic_id)


func test_relic_defaults_match_the_spec_block() -> void:
	var data := RelicData.new()
	assert_eq(data.rarity, RelicData.Rarity.COMMON)
	assert_eq(data.kind, RelicData.Kind.PASSIVE)
	assert_eq(String(data.description), "")
	assert_eq(data.max_stacks, 1, "the spec defaults max_stacks to 1")
	assert_eq(data.weight, 1.0, "the spec defaults weight to 1.0")
	assert_eq(data.active_cooldown, 0.0, "actives only")
	assert_eq(data.active_charges, 0, "actives only")
	# Inherited from ContentData, not re-declared here (which would shadow the
	# base's export and break every saved `.tres` of the parent type).
	assert_eq(String(data.id), "")
	assert_eq(String(data.display_name), "")
	assert_eq(data.tags, [] as Array[StringName])
	assert_null(data.effect_script)
	assert_null(data.icon)
