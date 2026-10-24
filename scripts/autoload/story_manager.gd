extends Node
## Story flags, dialogue state, lore unlocks. Owned by story-dialogue (week 6
## fills it in). Week 6 addition: the flag store — `data/dialogue/flags.json`
## declares every reserved flag name grouped by namespace; `set_flag` is
## idempotent and persists when the flag is in UNLOCK_FLAGS; `act()` derives the
## current act from the act gates.
## Sync: flags are per player, set on the host for the acting player and
## merged at run end (SPEC-story-dialogue). UNLOCK_FLAGS (unlocks: characters,
## rescues, endings, secrets, act gates) persist straight to the profile the
## moment they are set; every other flag lives for the run and merges at run end
## through `PlayerProfile.merge_run_gains`.

signal flag_set(flag: StringName)
signal lore_unlocked(page_id: StringName)
signal miner_rescued(miner_id: StringName)

## Where the reserved flag names are declared. Content-as-data: the file is the
## source of truth for what may be checked in dialogue conditions; it is loaded
## in `_ready()` and never written.
const FLAG_DATA_PATH: String = "res://data/dialogue/flags.json"

## Flags that persist to the profile the moment they are set (SPEC:
## `set_flag` "idempotent, saves if flag is in UNLOCK_FLAGS"). Unlocks: the two
## act gates, Deep Mode, the four rescues, the three endings, the two secrets.
## Mirrors every `"persist": true` entry in flags.json. flags.json is the
## authoring source; this constant is what the runtime checks, and the test
## asserts the two never drift apart.
const UNLOCK_FLAGS: Array[StringName] = [
	&"story.foreman_defeated",
	&"story.miners_possessed",
	&"story.pit_calls",
	&"story.act2_started",
	&"story.vulkar_journals",
	&"story.drowned_city_found",
	&"story.pit_has_done_this_before",
	&"story.pit_feeds_on_loss",
	&"story.keeper_offer",
	&"rescue.sly_nettie",
	&"rescue.cogsworth",
	&"rescue.mortimer",
	&"rescue.elian",
	&"char.brann_unlocked",
	&"char.ivy_unlocked",
	&"char.kestrel_unlocked",
	&"ending.seal",
	&"ending.keeper",
	&"ending.true",
	&"lore.vulkar_journal_1_read",
	&"lore.vulkar_journal_2_read",
	&"lore.vulkar_journal_3_read",
	&"secret.rat_king",
	&"secret.watcher",
	&"secret.watcher_defeated",
]

## Act gates (SINKHOLE_SPEC section 11): the foreman's fall closes act 1 and
## the journals close act 2. Everything before the first gate is act 1,
## everything after the second is act 3.
const ACT_1_GATE: StringName = &"story.foreman_defeated"
const ACT_2_GATE: StringName = &"story.vulkar_journals"

var _flags: Dictionary[StringName, bool] = {}
var _lore: Dictionary[StringName, bool] = {}
## Every name declared in flags.json, flattened to full `namespace.name` keys.
var _declared_flags: Dictionary[StringName, bool] = {}


func _ready() -> void:
	_load_flag_declarations()
	_restore_persistent_flags()
	# The profile may finish loading after we do, depending on autoload order;
	# whichever way it goes, the persistent flags are restored exactly once.
	SaveManager.loaded.connect(_restore_persistent_flags)


func has_flag(flag: StringName) -> bool:
	return _flags.has(flag)


## True when `flags.json` declares the flag. Undeclared names are a content
## mistake — dialogue conditions and progression hooks should check this before
## shipping a line that can never be satisfied.
func is_declared(flag: StringName) -> bool:
	return _declared_flags.has(flag)


## True when setting the flag persists to the profile immediately rather than at
## run end. The list itself is the declaration; flags.json must also declare it.
func is_unlock_flag(flag: StringName) -> bool:
	return UNLOCK_FLAGS.has(flag)


## Idempotent; persists when the flag is in UNLOCK_FLAGS (SPEC-story-dialogue).
func set_flag(flag: StringName) -> void:
	if _flags.has(flag):
		return
	_flags[flag] = true
	_persist_unlock_flag(flag)
	flag_set.emit(flag)
	Events.story_flag_set.emit(flag)


## Writes an UNLOCK_FLAGS flag into the profile and saves. The profile may be
## absent (a run scene used standalone, or a test) — then the flag still lives
## for the session and the save is skipped, never delayed into a crash.
func _persist_unlock_flag(flag: StringName) -> void:
	if not is_unlock_flag(flag):
		return
	var profile := SaveManager.profile
	if profile == null:
		return
	if not profile.story_flags.has(String(flag)):
		profile.story_flags.append(String(flag))
	SaveManager.save()


## Brings back every flag the profile persisted — the unlock flags saved by
## `set_flag` and the run flags merged at run end by `merge_run_gains`. Only
## adds, never removes, so a merge landing later cannot un-set anything.
## `SaveManager.loaded` passes the profile; this reads it off SaveManager, so
## the argument is accepted and dropped.
func _restore_persistent_flags(_profile: PlayerProfile = null) -> void:
	var profile := SaveManager.profile
	if profile == null:
		return
	for flag_string: String in profile.story_flags:
		_flags[StringName(flag_string)] = true


func flags() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_flags.keys())
	return result


## 1 to 3, derived from the act gates: no `story.foreman_defeated` is act 1, it
## set but no `story.vulkar_journals` is act 2, both set is act 3
## (SINKHOLE_SPEC section 11).
func act() -> int:
	if not _flags.has(ACT_1_GATE):
		return 1
	if not _flags.has(ACT_2_GATE):
		return 2
	return 3


func unlock_lore(page_id: StringName) -> void:
	if _lore.has(page_id):
		return
	_lore[page_id] = true
	lore_unlocked.emit(page_id)
	Events.lore_unlocked.emit(page_id)


func lore_unlocked_count() -> int:
	return _lore.size()


## What one talker sees when a dialogue condition is judged. Town dialogue is
## per player (SPEC-story-dialogue), so the world the conditions read is the
## *local* player's: their character and class, their deepest floor, their ore,
## rescues and town levels. A caller with the player at hand (a town NPC
## reading the local SelectionState, or a run reading the live slice) fills the
## fields itself; the profile-carried half is filled by `from_profile()`.
## Sync: none (a snapshot built per conversation, read-only once built).
class EvalContext extends RefCounted:
	## The talking player's character and class ids; empty when unknown, which
	## makes `character`/`class` conditions fail — nothing matches nobody.
	var character_id: StringName = &""
	var class_id: StringName = &""
	## The player's deepest floor (the profile stat, or the caller's live value
	## during a run).
	var deepest_floor: int = 0
	## Ore id -> amount the player holds.
	var ore: Dictionary[StringName, int] = {}
	## Miner ids this player has rescued.
	var rescued_miners: Array[StringName] = []
	## Building id -> level (0 when absent — the profile's rule).
	var town_levels: Dictionary[StringName, int] = {}
	## Roll source for `random_chance`. Null means StoryManager's shared one; a
	## test (or a host wanting reproducible dialogue) seeds one and hands it in.
	var rng: RandomNumberGenerator = null


	## The context a saved profile carries: ore, rescued miners, town levels and
	## the deepest-floor stat. The identity fields stay empty — they belong to
	## the talking player, which the profile does not name; the caller (town
	## NPC, run slice) sets them from SelectionState or RunPlayerState.
	static func from_profile(profile: PlayerProfile) -> EvalContext:
		var context := EvalContext.new()
		if profile == null:
			return context
		for ore_key: String in profile.ore:
			context.ore[StringName(ore_key)] = int(profile.ore[ore_key])
		for miner: String in profile.rescued_miners:
			context.rescued_miners.append(StringName(miner))
		for building: String in profile.town:
			context.town_levels[StringName(building)] = int(profile.town[building])
		context.deepest_floor = int(profile.stats.get(PlayerProfile.STAT_DEEPEST_FLOOR, 0))
		return context


## The fallback entry's line (PLAN G3): what an NPC says when no entry's
## conditions pass.
const FALLBACK_TEXT: String = "..."

## The roll source used when the context brings none. Created once, lazily —
## `random_chance` rolls must not rebuild a generator per call.
var _condition_rng: RandomNumberGenerator = null


## The dialogue condition language (SPEC-story-dialogue): `all`, `any`, `not`
## and the ten leaf operators the loader structurally validated. An empty
## condition passes; several keys in one object are an implicit `all` (the
## loader validates each key independently, so this only tightens what it
## already allowed). An operator the loader would have rejected fails *safe* —
## warned and false — because a condition dict can also be built by hand at
## runtime, outside the loader's reach.
##
## `context` is the talker's world; null means "build it from the saved
## profile", the town-without-a-selection case. During a run, or for a
## specific player in co-op, the caller builds one and passes it.
func evaluate(condition: Dictionary, context: EvalContext = null) -> bool:
	return _evaluate(condition, _context_or_profile(context), 0)


## The highest-priority entry whose conditions pass (SPEC-story-dialogue: "the
## highest-priority entry whose conditions pass is the NPC's current
## dialogue"), or the fallback stub when none do. `entries_by_priority()`
## already orders descending with ties to file order, so the scan is a first
## match over it. Not act-filtered on purpose: an entry whose top-level
## `act_min` is above the current act fails `_evaluate` like any other
## condition, so a caller that wants the pre-filter uses
## `entries_for_act()`; one that wants live state judged (an `act_min` nested
## in `all`) gets it here.
func select_entry(dialogue: DialogueData, context: EvalContext = null) -> DialogueData.Entry:
	var talker := _context_or_profile(context)
	for entry: DialogueData.Entry in dialogue.entries_by_priority():
		if _evaluate(entry.conditions, talker, 0):
			return entry
	return fallback_entry(dialogue)


## The stub response for an NPC whose every entry failed its conditions
## (PLAN G3): a one-line entry speaking with the NPC's name and the same
## noncommittal line, built fresh each call and never added to the dialogue's
## own entries.
static func fallback_entry(dialogue: DialogueData) -> DialogueData.Entry:
	var entry := DialogueData.Entry.new()
	entry.id = &"fallback"
	entry.priority = 0
	entry.lines = [{"speaker": _speaker_from_id(dialogue.id), "text": FALLBACK_TEXT}]
	return entry


## "mayor_hilde" -> "Mayor Hilde": the fallback's speaker, humanized from the
## dialogue id. Good enough for a stub line only ever seen when content forgot
## to cover a state.
static func _speaker_from_id(dialogue_id: StringName) -> String:
	var words := PackedStringArray()
	for part: String in String(dialogue_id).split("_", false):
		words.append(part.capitalize())
	return " ".join(words) if not words.is_empty() else String(dialogue_id)


func _context_or_profile(context: EvalContext) -> EvalContext:
	if context != null:
		return context
	return EvalContext.from_profile(SaveManager.profile)


func _evaluate(condition: Variant, context: EvalContext, depth: int) -> bool:
	if condition == null:
		return true
	if not (condition is Dictionary):
		push_warning("StoryManager: condition is not an object; failing safe")
		return false
	var expr := condition as Dictionary
	if expr.is_empty():
		return true
	if depth > DialogueData.MAX_CONDITION_DEPTH:
		push_warning("StoryManager: condition nests deeper than %d; failing safe" % DialogueData.MAX_CONDITION_DEPTH)
		return false
	for op: String in expr.keys():
		if not _evaluate_op(op, expr[op], context, depth):
			return false
	return true


func _evaluate_op(op: String, value: Variant, context: EvalContext, depth: int) -> bool:
	match op:
		"all":
			if not (value is Array):
				return _warn_false(op, "an array of conditions")
			for sub: Variant in value:
				if not _evaluate(sub, context, depth + 1):
					return false
			return true
		"any":
			if not (value is Array):
				return _warn_false(op, "an array of conditions")
			if (value as Array).is_empty():
				return false
			for sub: Variant in value:
				if _evaluate(sub, context, depth + 1):
					return true
			return false
		"not":
			# The loader accepts both shapes ({"not": expr} and {"not": [expr]}),
			# so both must evaluate; an empty array is malformed and fails safe.
			if value is Array and (value as Array).size() != 1:
				return _warn_false(op, "exactly one condition")
			var sub: Variant = value[0] if value is Array else value
			return not _evaluate(sub, context, depth + 1)
		"flag":
			return _is_string(value, op) and has_flag(StringName(value as String))
		"flag_not":
			return _is_string(value, op) and not has_flag(StringName(value as String))
		"character":
			return _is_string(value, op) and context.character_id == StringName(value as String)
		"class":
			return _is_string(value, op) and context.class_id == StringName(value as String)
		"town_level":
			if not _has_string_key(value, op, "building") or not _has_int_key(value, op, "min"):
				return false
			var spec := value as Dictionary
			var level: int = context.town_levels.get(StringName(String(spec["building"])), 0)
			return level >= spec["min"] as int
		"ore_min":
			if not _has_string_key(value, op, "ore") or not _has_int_key(value, op, "min"):
				return false
			var spec := value as Dictionary
			var held: int = context.ore.get(StringName(String(spec["ore"])), 0)
			return held >= spec["min"] as int
		"deepest_floor_min":
			if not (value is int):
				return _warn_false(op, "an integer floor")
			return context.deepest_floor >= value as int
		"rescued":
			return _is_string(value, op) and context.rescued_miners.has(StringName(value as String))
		"act_min":
			if not (value is int):
				return _warn_false(op, "an integer act")
			return act() >= value as int
		"random_chance":
			if not ((value is float) or (value is int)):
				return _warn_false(op, "a number in 0..1")
			return _roll_chance(context) < float(value)
		_:
			push_warning("StoryManager: unknown condition operator \"%s\"; failing safe" % op)
			return false


## True when `value` is a non-empty string; warns and answers false otherwise,
## so a mistyped leaf never silently compares against a default.
func _is_string(value: Variant, op: String) -> bool:
	if value is String and not (value as String).is_empty():
		return true
	push_warning("StoryManager: condition \"%s\" must be a non-empty string" % op)
	return false


## True when `value` is an object holding `key` as a non-empty string; warns
## and answers false otherwise, so a half-written `{building, min}` object
## fails safe rather than reading the missing side as 0.
func _has_string_key(value: Variant, op: String, key: String) -> bool:
	if value is Dictionary:
		var held: Variant = (value as Dictionary).get(key)
		if held is String and not (held as String).is_empty():
			return true
	push_warning("StoryManager: condition \"%s\" must carry a \"%s\" string" % [op, key])
	return false


## The integer half of the same rule.
func _has_int_key(value: Variant, op: String, key: String) -> bool:
	if value is Dictionary and (value as Dictionary).get(key) is int:
		return true
	push_warning("StoryManager: condition \"%s\" must carry an integer \"%s\"" % [op, key])
	return false


func _warn_false(op: String, expected: String) -> bool:
	push_warning("StoryManager: condition \"%s\" must be %s" % [op, expected])
	return false


## One `random_chance` roll. The context's generator wins when the caller
## brought one; otherwise the autoload's shared one is built once and kept.
func _roll_chance(context: EvalContext) -> float:
	if context.rng != null:
		return context.rng.randf()
	if _condition_rng == null:
		_condition_rng = RandomNumberGenerator.new()
	return _condition_rng.randf()


## The scene start_dialogue opens (W6-B2, PLAN G5: the mock-up the flow shows).
const DIALOGUE_BOX_SCENE: String = "res://scenes/dialogue/dialogue_box.tscn"

## The loader start_dialogue reads dialogue files through. Defaults unset, which
## means `DialogueData.load_file` on `data/dialogue/<id>.json`; a test swaps it
## to feed constructed data so the wiring is provable before any Act 1 JSON
## exists (W6-B3).
var dialogue_loader: Callable = Callable()

## The local dialogue box, created on the first dialogue and kept for the
## session. One per view (SPEC: "town dialogue is per player"); this is the
## local player's.
var dialogue_box: DialogueBox = null
## The dialogue currently showing in the box; null while closed.
var current_dialogue: DialogueData = null


## Opens `dialogue_id` in the local DialogueBox (W6-B2, PLAN G5 mock-up
## wiring). Loads `data/dialogue/<id>.json`, selects the entry with the local
## player's own flag state — "town NPC dialogue is local to each player's
## view ... using the local player's flags for conditions" (SPEC) — and shows
## it. `_npc` is the anchor node; the mock-up ignores it (the box is fixed to
## the screen; the NPC-relative framing lands with the town NPCs, W6-B4 /
## PLAN G10). A missing or invalid file warns and does nothing: the data
## tests reject it long before a player ever talks.
##
## Sync: local. Flags the shown entries set go through `set_flag`, which is
## the host-authoritative store; the box itself is never replicated.
func start_dialogue(dialogue_id: StringName, _npc: Node = null) -> void:
	var result: DialogueData.LoadResult = _load_dialogue(dialogue_id)
	if result == null or result.data == null or not result.errors.is_empty():
		push_warning("StoryManager: dialogue \"%s\" did not load: %s" % [
			dialogue_id, ", ".join(result.errors) if result != null else "no loader",
		])
		return
	var context := EvalContext.from_profile(SaveManager.profile)
	var entry := select_entry(result.data, context)
	current_dialogue = result.data
	_box().show_dialogue(result.data, entry)


func _load_dialogue(dialogue_id: StringName) -> DialogueData.LoadResult:
	if dialogue_loader.is_valid():
		return dialogue_loader.call(String(dialogue_id)) as DialogueData.LoadResult
	return DialogueData.load_file(String(dialogue_id) + ".json", _declared_flags)


## The local box, created on first use under this autoload so it outlives
## scenes (a dialogue opened in town survives into nothing — town is where it
## is opened — but a test scene may come and go around it).
func _box() -> DialogueBox:
	if dialogue_box == null:
		var packed := load(DIALOGUE_BOX_SCENE) as PackedScene
		dialogue_box = packed.instantiate() as DialogueBox
		dialogue_box.name = "DialogueBox"
		add_child(dialogue_box)
		dialogue_box.choice_selected.connect(_on_dialogue_choice)
		dialogue_box.dialogue_finished.connect(_on_dialogue_finished)
	return dialogue_box


## A choice was pressed: its `set_flags` land first (the SPEC's example sets
## the flag on the choice itself), then a `goto` shows the target entry (same
## file, resolved by the loader at load time) or an `end` closes the box —
## which is what fires the entry's on_end.
func _on_dialogue_choice(_choice_index: int, choice: Dictionary) -> void:
	if current_dialogue == null or dialogue_box == null:
		return
	_apply_flag_set(choice.get("set_flags"))
	var goto: Variant = choice.get("goto")
	if goto is String and not (goto as String).is_empty():
		var next := current_dialogue.entry(StringName(goto as String))
		if next == null:
			push_warning("StoryManager: choice goto \"%s\" resolved to no entry" % goto)
			dialogue_box.close()
			return
		dialogue_box.show_dialogue(current_dialogue, next)
		return
	dialogue_box.close()


## The entry ended (advanced past its last line, or the box closed): apply its
## `on_end.set_flags` — the progression hook the SPEC's intro example shows
## (`"on_end": {"set_flags": ["story.met_hilde"]}`). Flags are idempotent, so
## the mock-up rule "on_end applies to the entry that ended the conversation"
## is safe even where a `goto` skipped an earlier entry's on_end. `on_end.give`
## is run-economy's payout path and is not wired here (mock-up scope).
func _on_dialogue_finished(entry_id: StringName) -> void:
	var entry: DialogueData.Entry = current_dialogue.entry(entry_id) \
			if current_dialogue != null else null
	current_dialogue = null
	if entry == null:
		return
	_apply_flag_set((entry.on_end as Dictionary).get("set_flags"))


## Applies an optional `set_flags` array (choices and on_end): every name goes
## through the idempotent store; a non-array is a loader rejection, not a
## runtime case, and is ignored.
func _apply_flag_set(flag_names: Variant) -> void:
	if not (flag_names is Array):
		return
	for flag_name: Variant in flag_names:
		if flag_name is String:
			set_flag(StringName(flag_name as String))


## Reads the reserved flag names out of flags.json, flattened to full
## `namespace.name` keys. A missing or unreadable file only means new names
## cannot be validated — the store itself still works — so it warns and
## continues rather than refusing to boot.
func _load_flag_declarations() -> void:
	if not FileAccess.file_exists(FLAG_DATA_PATH):
		push_warning("StoryManager: %s is missing; flag names are unvalidated" % FLAG_DATA_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(FLAG_DATA_PATH)) != OK \
			or not (json.data is Dictionary):
		push_warning("StoryManager: %s is not readable JSON; flag names are unvalidated" % FLAG_DATA_PATH)
		return
	var data: Dictionary = json.data
	var by_namespace: Variant = data.get("flags", {})
	if not (by_namespace is Dictionary):
		push_warning("StoryManager: %s has no \"flags\" table; flag names are unvalidated" % FLAG_DATA_PATH)
		return
	for namespace_key: String in (by_namespace as Dictionary).keys():
		var names: Variant = (by_namespace as Dictionary)[namespace_key]
		if not (names is Dictionary):
			continue
		for flag_name: String in (names as Dictionary).keys():
			_declared_flags[StringName(namespace_key + "." + flag_name)] = true
