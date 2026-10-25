extends GutTest
## Act 1 progression flags and hooks (W6-B3, PLAN G7): the boss_defeated listener
## and the return-to-town beat, and the town dialogue they flip.
##
## Uses the real autoload StoryManager and Events like test_story_flags.gd does:
## emits on the live Events bus, watches for persistence through a defaults
## profile, and clears the store between tests so nothing leaks to the next file.

const FLAGS_PATH: String = "res://data/dialogue/flags.json"
const GATE: StringName = StoryManager.ACT_1_GATE
const POSSESSED: StringName = &"story.miners_possessed"
const PIT_CALLS: StringName = &"story.pit_calls"

## Every NPC and the `met` gate flag its intro entry consumes.
const NPCS: Dictionary = {
	&"hilde": &"story.met_hilde",
	&"gruff": &"story.met_gruff",
	&"moss": &"story.met_moss",
	&"pip": &"story.met_pip",
	&"sister_ash": &"story.met_sister_ash",
	&"old_tom": &"story.met_old_tom",
	&"vesper": &"story.met_vesper",
	&"rescued_miner_v1": &"story.met_rescued",
}

var _declared: Dictionary = {}
var _gate_hits: int = 0
var _pit_calls_hits: int = 0


func before_each() -> void:
	NetworkManager.start_solo()
	SaveManager.profile = PlayerProfile.defaults()
	# The autoload flattens flags.json itself at boot; validating dialogue
	# against the same set is the point (the G6 loader tests own the file's
	# exact shape).
	_declared = StoryManager._declared_flags
	_gate_hits = 0
	_pit_calls_hits = 0
	_reset_story()


func after_each() -> void:
	SaveManager.profile = null
	_reset_story()
	NetworkManager.disconnect_all()


func _reset_story() -> void:
	StoryManager._flags.clear()
	StoryManager._lore.clear()


func _watch_gate(flag: StringName) -> void:
	if flag == GATE:
		_gate_hits += 1


func _watch_pit_calls(flag: StringName) -> void:
	if flag == PIT_CALLS:
		_pit_calls_hits += 1


func _kill_the_foreman() -> void:
	Events.boss_defeated.emit(StoryManager.FOREMAN_BOSS_ID)


func _enter_town() -> void:
	StoryManager.on_town_entered()


# --- the boss_defeated listener -------------------------------------------


func test_the_foreman_killing_sets_the_act_1_gate() -> void:
	assert_eq(StoryManager.act(), 1, "a fresh profile is act 1")
	_kill_the_foreman()
	assert_true(StoryManager.has_flag(GATE))
	assert_true(StoryManager.has_flag(&"boss.foreman"), "the kill itself is recorded")
	assert_eq(StoryManager.act(), 2, "the gate flips the act to 2")


func test_the_foreman_kill_persists_to_the_profile() -> void:
	SaveManager.profile = PlayerProfile.defaults()
	_kill_the_foreman()
	assert_true(SaveManager.profile.story_flags.has(String(GATE)),
			"the act 1 gate is on the saved profile")
	assert_false(SaveManager.profile.story_flags.has("boss.foreman"),
			"the kill record is session-scoped, not saved")


func test_other_bosses_kill_nothing() -> void:
	Events.boss_defeated.emit(&"boomer_jack")
	assert_eq(StoryManager.act(), 1)
	assert_false(StoryManager.has_flag(GATE))


func test_the_foreman_kill_is_idempotent() -> void:
	StoryManager.flag_set.connect(_watch_gate)
	_kill_the_foreman()
	_kill_the_foreman()
	assert_eq(_gate_hits, 1, "a second kill is a no-op")
	assert_eq(StoryManager.act(), 2)


# --- the return-to-town beat ----------------------------------------------


func test_town_enter_before_the_gate_sets_nothing() -> void:
	_enter_town()
	assert_false(StoryManager.has_flag(POSSESSED))
	assert_false(StoryManager.has_flag(PIT_CALLS))


func test_town_enter_after_the_gate_sets_the_beat_flags() -> void:
	StoryManager.set_flag(GATE)
	SaveManager.profile = PlayerProfile.defaults()
	_enter_town()
	assert_true(StoryManager.has_flag(POSSESSED))
	assert_true(StoryManager.has_flag(PIT_CALLS))
	assert_true(SaveManager.profile.story_flags.has(String(POSSESSED)),
			"the beat flags persist with the profile")
	assert_eq(StoryManager.act(), 2, "the beat does not advance the act")


func test_town_enter_is_idempotent() -> void:
	StoryManager.set_flag(GATE)
	StoryManager.flag_set.connect(_watch_pit_calls)
	_enter_town()
	_enter_town()
	assert_eq(_pit_calls_hits, 1, "a re-loaded town cannot re-set the beat")


func test_the_town_scene_load_triggers_the_beat() -> void:
	StoryManager.set_flag(GATE)
	SaveManager.profile = PlayerProfile.defaults()
	var town: Town = (load("res://scenes/town/town.tscn") as PackedScene).instantiate() as Town
	add_child_autofree(town)
	assert_true(StoryManager.has_flag(POSSESSED),
			"town.gd announces the load; the beat fires in _ready")
	assert_true(StoryManager.has_flag(PIT_CALLS))


# --- the town dialogue the progression flips -------------------------------


func _entry_for(npc: StringName) -> DialogueData.Entry:
	var result: DialogueData.LoadResult = DialogueData.load_file(String(npc) + ".json", _declared)
	assert_not_null(result.data, "%s loads" % npc)
	assert_true(result.errors.is_empty(), "%s loads clean: %s" % [npc, result.errors])
	# null context: select_entry builds it from the defaults profile, the same
	# path start_dialogue takes for a town talk without a live selection.
	return StoryManager.select_entry(result.data, null)


func test_dialogue_stays_ambient_before_the_progression() -> void:
	StoryManager.set_flag(&"story.met_hilde")
	var entry: DialogueData.Entry = _entry_for(&"hilde")
	assert_eq(entry.id, &"intro_what",
			"after the intro, an act 1 player gets the priority-5 ambient line")
	assert_true(String(entry.id).begins_with("intro"),
			"nothing act-1 flavored plays before the Foreman falls")


func test_hilde_turns_possessed_after_the_full_progression() -> void:
	StoryManager.set_flag(&"story.met_hilde")
	_kill_the_foreman()
	assert_eq(_entry_for(&"hilde").id, &"act_1",
			"after the kill but before town: the plain act 1 reaction")
	_enter_town()
	assert_eq(_entry_for(&"hilde").id, &"act_1_possessed",
			"after the town beat: the possessed reaction wins")


func test_every_npc_reacts_with_their_act_1_lines_after_the_beat() -> void:
	_kill_the_foreman()
	_enter_town()
	for npc: StringName in NPCS.keys():
		StoryManager.set_flag(NPCS[npc])
		var entry: DialogueData.Entry = _entry_for(npc)
		assert_true(String(entry.id).begins_with("act_1"),
				"%s answers with an act 1 entry (got %s)" % [npc, entry.id])
		assert_false(String(entry.id).contains("stub"),
				"%s never falls to a stub once the beat is set" % npc)


func test_the_stub_entries_cannot_shadow_act_1_reactions() -> void:
	# Regression: the act_2_stub entries shipped at priority 20, so the moment
	# the Foreman fell (act() == 2) they outranked every act 1 reaction.
	StoryManager.set_flag(&"story.met_hilde")
	StoryManager.set_flag(GATE)
	StoryManager.set_flag(POSSESSED)
	assert_eq(_entry_for(&"hilde").id, &"act_1_possessed")
