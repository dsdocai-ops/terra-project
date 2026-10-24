extends GutTest
## The DialogueBox mock-up and its StoryManager wiring — story-dialogue
## W6-B2 (PLAN G5).
##
## SPEC-story-dialogue, "Dialogue UI": "portrait left, name, typewriter text
## (skippable), choices list ... Pauses the local player's input, not the
## game (co-op)." The box cases cover the mock-up's four behaviors — show,
## typewriter, choices, close — plus the input swallow; the StoryManager
## cases prove the flow (priority selection, goto, end, on_end flags) through
## a swapped loader, so no Act 1 JSON needs to exist yet (W6-B3 content).
##
## The typewriter is driven by `advance_time(delta)` directly: the mock-up's
## reveal is delta-based (never `Engine.time_scale`), and tests that waited
## real frames would be flaky for no reason. The flags live on the real
## autoload, snapshotted clear around each case, as test_story_conditions
## does; the swapped loader is un-swapped in after_each so later suites load
## real files.

const BOX_SCENE := "res://scenes/dialogue/dialogue_box.tscn"
const PORTRAIT_PATH := "res://assets/portraits/wren.png"

var _box: DialogueBox


func before_each() -> void:
	_box = (load(BOX_SCENE) as PackedScene).instantiate() as DialogueBox
	add_child_autofree(_box)
	StoryManager._flags.clear()
	StoryManager._lore.clear()
	SaveManager.profile = PlayerProfile.defaults()


func after_each() -> void:
	StoryManager.dialogue_loader = Callable()
	if StoryManager.dialogue_box != null and StoryManager.dialogue_box.visible:
		StoryManager.dialogue_box.close()
	SaveManager.profile = null
	StoryManager._flags.clear()
	StoryManager._lore.clear()


# --- box fixtures ------------------------------------------------------------


func _line(speaker: String, text: String) -> Dictionary:
	return {"speaker": speaker, "text": text}


func _entry_with(
	entry_id: StringName,
	lines: Array,
	choices: Array = [],
	conditions: Dictionary = {},
	priority: int = 10,
) -> DialogueData.Entry:
	var entry := DialogueData.Entry.new()
	entry.id = entry_id
	entry.priority = priority
	entry.conditions = conditions
	entry.lines = lines
	entry.choices = choices
	return entry


func _dialogue_with(portrait: String, entries: Array[DialogueData.Entry]) -> DialogueData:
	var data := DialogueData.new()
	data.id = &"test_npc"
	data.portrait = portrait
	data.entries = entries
	return data


func _show(box: DialogueBox, data: DialogueData, entry: DialogueData.Entry) -> void:
	box.show_dialogue(data, entry)


# --- show --------------------------------------------------------------------


func test_show_populates_portrait_name_and_first_line() -> void:
	var data := _dialogue_with(PORTRAIT_PATH, [
		_entry_with(&"intro", [_line("Wren", "The pit took him.")]),
	])
	_show(_box, data, data.entries[0])
	assert_true(_box.is_open(), "the box is open while an entry shows")
	assert_eq(_box._name_plate.text, "Wren", "the first line's speaker names the plate")
	assert_not_null(_box._portrait.texture, "the declared portrait loaded")
	assert_eq(_box._text_label.text, "The pit took him.", "the line's text is set")
	assert_eq(_box._text_label.visible_characters, 0, "the typewriter starts empty")


func test_show_without_portrait_hides_the_frame() -> void:
	var data := _dialogue_with("", [
		_entry_with(&"intro", [_line("Old Tom", "The well's been whispering.")]),
	])
	_show(_box, data, data.entries[0])
	assert_null(_box._portrait.texture)
	assert_false(_box._portrait.visible, "no declared portrait, no empty frame")


# --- typewriter --------------------------------------------------------------


func test_typewriter_reveals_at_the_spec_rate() -> void:
	var data := _dialogue_with("", [_entry_with(&"intro", [_line("Gruff", "0123456789")])])
	_show(_box, data, data.entries[0])
	assert_true(_box.typing(), "a fresh line types")
	_box.advance_time(0.05)
	assert_eq(_box._text_label.visible_characters, 1, "one character per 0.05 s")
	_box.advance_time(0.10)
	assert_eq(_box._text_label.visible_characters, 3, "the rate accumulates")
	_box.advance_time(1.0)
	assert_false(_box.typing(), "a fully revealed line stops typing")
	assert_eq(_box._text_label.visible_characters, 10, "every character revealed")


func test_advance_skips_typing_then_shows_the_next_line() -> void:
	var data := _dialogue_with("", [_entry_with(&"intro", [
		_line("Hilde", "You're Wren's girl."),
		_line("Wren", "Tell me about the pit."),
	])])
	_show(_box, data, data.entries[0])
	_box.advance_time(0.01)
	_box.advance()
	assert_false(_box.typing(), "advance skips the typing")
	assert_eq(_box._text_label.visible_characters, _box._text_label.text.length())
	_box.advance()
	assert_eq(_box._name_plate.text, "Wren", "the next line's speaker names the plate")
	assert_eq(_box._text_label.text, "Tell me about the pit.")
	assert_eq(_box._text_label.visible_characters, 0, "the next line types from empty")
	assert_true(_box.typing())


# --- choices -----------------------------------------------------------------


func test_choices_build_after_the_last_line_and_emit_their_index() -> void:
	var choices := [
		{"text": "What happened down there?", "goto": "intro_more"},
		{"text": "I'm going in.", "end": true},
	]
	var data := _dialogue_with("", [
		_entry_with(&"intro", [_line("Hilde", "You're Wren's girl.")], choices),
	])
	_show(_box, data, data.entries[0])
	watch_signals(_box)
	_box.advance()  # skip the typing
	var buttons: Array[Node] = _box._choices_box.get_children()
	assert_eq(buttons.size(), 2, "one button per choice, after the line finishes")
	assert_eq((buttons[0] as Button).text, "What happened down there?")
	assert_eq((buttons[1] as Button).text, "I'm going in.")
	(buttons[1] as Button).pressed.emit()
	assert_signal_emitted(_box, "choice_selected")
	assert_signal_emitted_with_parameters(_box, "choice_selected",
			[1, choices[1]], 0)
	assert_true(_box.is_open(), "the box waits for the caller after a choice")
	await wait_process_frames(1)  # let the pressed button's queue_free land


func test_choices_do_not_build_while_the_text_types() -> void:
	var data := _dialogue_with("", [
		_entry_with(&"intro", [_line("Hilde", "A long line indeed.")],
				[{"text": "Bye", "end": true}]),
	])
	_show(_box, data, data.entries[0])
	assert_eq(_box._choices_box.get_child_count(), 0, "buttons wait for the reveal")


# --- finishing and closing ---------------------------------------------------


func test_an_entry_without_choices_finishes_and_closes() -> void:
	var data := _dialogue_with("", [
		_entry_with(&"intro", [_line("Moss", "The forest gives; the pit takes.")]),
	])
	_show(_box, data, data.entries[0])
	watch_signals(_box)
	_box.advance()  # reveal
	_box.advance()  # past the last line
	assert_false(_box.is_open(), "the conversation ended")
	assert_signal_emitted_with_parameters(_box, "dialogue_finished", [&"intro"], 0)


func test_the_finished_signal_fires_once_whichever_way_the_entry_ends() -> void:
	var data := _dialogue_with("", [
		_entry_with(&"intro", [_line("Moss", "Careful down there.")]),
	])
	_show(_box, data, data.entries[0])
	watch_signals(_box)
	_box.advance()
	_box.advance()
	assert_signal_emit_count(_box, "dialogue_finished", 1)
	_box.close()
	assert_signal_emit_count(_box, "dialogue_finished", 1, "close after a natural finish is inert")
	_show(_box, data, data.entries[0])
	_box.close()
	assert_signal_emit_count(_box, "dialogue_finished", 2, "a new entry can finish again")


func test_close_stops_consuming_input() -> void:
	var data := _dialogue_with("", [_entry_with(&"intro", [_line("Pip", "Deeper, then?")])])
	_show(_box, data, data.entries[0])
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	assert_true(_box.handles_input(accept), "an open box owns the advance press")
	_box.close()
	assert_false(_box.handles_input(accept), "a closed box leaves input to the world")


func test_cancel_closes_the_open_box() -> void:
	var data := _dialogue_with("", [_entry_with(&"intro", [_line("Pip", "Maps soon.")])])
	_show(_box, data, data.entries[0])
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	assert_true(_box.handles_input(cancel), "an open box owns the cancel press")
	assert_false(_box.is_open(), "cancel closed it")


# --- StoryManager wiring -------------------------------------------------------


var _loaded_id: String = ""
var _test_dialogue: DialogueData = null


func _fake_loader(dialogue_id: String) -> DialogueData.LoadResult:
	_loaded_id = dialogue_id
	var result := DialogueData.LoadResult.new()
	result.path = "test://%s.json" % dialogue_id
	result.data = _test_dialogue
	return result


func _install_loader(dialogue: DialogueData) -> void:
	_test_dialogue = dialogue
	StoryManager.dialogue_loader = _fake_loader


func test_start_dialogue_shows_the_entry_whose_conditions_pass() -> void:
	_install_loader(_dialogue_with("", [
		_entry_with(&"act_line", [_line("Hilde", "The foreman is gone.")],
				[], {"flag": "story.g5_top"}, 10),
		_entry_with(&"base", [_line("Hilde", "Good luck down there.")], [], {}, 0),
	]))
	StoryManager.start_dialogue(&"test_npc")
	assert_eq(_loaded_id, "test_npc", "the loader read the requested dialogue id")
	assert_not_null(StoryManager.dialogue_box, "the box was created for the session")
	assert_true(StoryManager.dialogue_box.is_open())
	assert_eq(StoryManager.current_dialogue, _test_dialogue)
	# The top entry needs story.g5_top, unset — the base entry shows.
	assert_eq(StoryManager.dialogue_box._text_label.text, "Good luck down there.")
	StoryManager.set_flag(&"story.g5_top")
	StoryManager.start_dialogue(&"test_npc")
	assert_eq(StoryManager.dialogue_box._text_label.text, "The foreman is gone.",
			"with the flag set, the higher-priority entry shows")


func test_start_dialogue_with_unknown_id_warns_and_stays_closed() -> void:
	# No loader swapped: the real file load of a missing id fails cleanly.
	StoryManager.start_dialogue(&"nobody_at_all")
	assert_false(StoryManager.dialogue_box.is_open(),
			"a failed load opens nothing")


func test_end_choice_sets_its_flags_and_closes_with_on_end() -> void:
	_install_loader(_dialogue_with("", [
		_entry_with(&"intro", [_line("Hilde", "You're Wren's girl.")], [
			{"text": "I'm going in.", "end": true,
					"set_flags": ["story.g5_choice"]},
		]),
		_entry_with(&"on_end", [_line("Hilde", "Go, then.")], [], {}, 0),
	]))
	# The shown entry carries the on_end that applies when it ends.
	var data: DialogueData = _test_dialogue
	data.entries[0].on_end = {"set_flags": ["story.g5_intro"]}
	StoryManager.start_dialogue(&"test_npc")
	StoryManager.dialogue_box.advance()  # skip typing; buttons build
	(StoryManager.dialogue_box._choices_box.get_child(0) as Button).pressed.emit()
	assert_false(StoryManager.dialogue_box.is_open(), "the end choice closed the box")
	assert_true(StoryManager.has_flag(&"story.g5_choice"), "the choice's set_flags landed")
	assert_true(StoryManager.has_flag(&"story.g5_intro"),
			"the entry's on_end set_flags landed with the finish")
	await wait_process_frames(1)  # let the pressed button's queue_free land


func test_goto_choice_shows_the_target_entry() -> void:
	_install_loader(_dialogue_with("", [
		_entry_with(&"intro", [_line("Hilde", "You're Wren's girl.")], [
			{"text": "What happened down there?", "goto": "intro_more"},
		]),
		_entry_with(&"intro_more", [_line("Hilde", "The pit opened.")], [], {}, 5),
	]))
	StoryManager.start_dialogue(&"test_npc")
	var box: DialogueBox = StoryManager.dialogue_box
	box.advance()
	(box._choices_box.get_child(0) as Button).pressed.emit()
	assert_true(box.is_open())
	assert_eq(box._text_label.text, "The pit opened.", "the goto target entry shows")
	assert_eq(box._name_plate.text, "Hilde")
	await wait_process_frames(1)  # let the pressed button's queue_free land
