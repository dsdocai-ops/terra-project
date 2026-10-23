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


## Dialogue condition language. TODO(story-dialogue): all operators.
func evaluate(_condition: Dictionary) -> bool:
	return true


func start_dialogue(_dialogue_id: StringName, _npc: Node = null) -> void:
	pass


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
