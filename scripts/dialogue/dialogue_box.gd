class_name DialogueBox
extends CanvasLayer
## The dialogue box: portrait, name plate, typewriter text, choices. Owned by
## story-dialogue (W6-B2, PLAN G5).
##
## MOCK-UP — awaiting design review. The week 6 mockup is documented in
## specs/SPEC-story-dialogue.md ("DialogueBox mock-up") and is ready for Dev A
## feedback: the layout is the SPEC's (portrait left, name above the text,
## skippable typewriter, choices list) and the visuals are placeholders from
## `UiPalette` (parchment panel, bronze border). The W6-B6 theme art
## (portrait frame, name plate, choice buttons, PLAN G13) replaces the
## StyleBoxes without touching this script's behavior.
##
## SPEC-story-dialogue, "Dialogue UI": "portrait left, name, typewriter text
## (skippable), choices list, controller-friendly later. Pauses the local
## player's input, not the game (co-op). In co-op, town dialogue is per
## player ... pit dialogue (rescue, lore) shows to all with the triggering
## player choosing."
##
## Three sentences, three parts. The **box is local**: one instance per view,
## drawn on a CanvasLayer above the world, and it never touches
## `get_tree().paused` — pausing the tree would freeze every other player, so
## the input pause is the swallow below instead. The **swallow** is
## `handles_input()`: while the box is open it consumes the advance, interact
## and cancel presses so they cannot leak to the world behind it, which is
## the local input pause the SPEC asks for; the polled-movement half (the
## player reads `Input.get_vector` every physics tick) lands with the town
## interact wiring (W6-B4, PLAN G10), which is also what places the box
## relative to the NPC. The **conversation flow is not the box's**: the box
## shows one entry at a time and reports back, while `StoryManager`
## (the caller) resolves choices — a `goto` shows the next entry through
## `show_dialogue()`, an `end` choice closes the box — and applies the
## entry's `on_end.set_flags` when the box finishes (mock-up simplification:
## per-entry `on_end` on a `goto` hop applies only to the final entry; flags
## are idempotent so the double-set of the SPEC's example is harmless).
##
## Sync: none (pure presentation). One box per local view; in co-op every
## player opens their own from their own NPC talk, reading their own flags
## through `StoryManager.select_entry()` at the caller.

## A line's character appears every CHAR_SECONDS (PLAN G5 sub-task 3: 0.05 s).
## Reads off `TimeManager`-safe `_process` delta — never `Engine.time_scale`.
const CHAR_SECONDS: float = 0.05

signal choice_selected(choice_index: int, choice: Dictionary)
signal dialogue_finished(entry_id: StringName)

## The peer whose view this box is. Per-player in town (SPEC-story-dialogue):
## the caller stamps it when opening; the box only displays it.
var local_peer: int = 1

var _dialogue: DialogueData = null
var _entry: DialogueData.Entry = null
var _line_index: int = 0
var _typing: bool = false
var _elapsed: float = 0.0
var _finished: bool = false

@onready var _portrait: TextureRect = $Root/Box/Margin/Column/Header/Portrait
@onready var _name_plate: Label = $Root/Box/Margin/Column/Header/NamePlate
@onready var _text_label: Label = $Root/Box/Margin/Column/Text
@onready var _choices_box: VBoxContainer = $Root/Box/Margin/Column/Choices
@onready var _dim: ColorRect = $Root/Dim


func _ready() -> void:
	# Hidden until a dialogue opens; visible=false on the CanvasLayer covers
	# the whole layer, so no per-child state to reset.
	visible = false
	_dim.gui_input.connect(_on_dim_input)


func _process(delta: float) -> void:
	advance_time(delta)


## The typewriter tick. Public because tests drive it directly (one call per
## simulated frame) instead of waiting real frames — a 0.05 s/char reveal
## never depends on wall-clock in a test.
func advance_time(delta: float) -> void:
	if not _typing:
		return
	_elapsed += delta
	var total: int = _text_label.text.length()
	var target: int = mini(total, int(_elapsed / CHAR_SECONDS))
	if target > _text_label.visible_characters:
		_text_label.visible_characters = target
	if _text_label.visible_characters >= total:
		_finish_line()


## Shows `entry` of `dialogue`: portrait from the file, the first line's
## speaker on the name plate, the first line typing. The caller (StoryManager)
## owns what comes next; the box only reports.
func show_dialogue(dialogue: DialogueData, entry: DialogueData.Entry) -> void:
	_dialogue = dialogue
	_entry = entry
	_line_index = 0
	_finished = false
	_clear_choices()
	visible = true
	_load_portrait(dialogue.portrait)
	_show_line(0)


## The advance press: skip the typing, step to the next line, or finish the
## entry. With choices on screen it does nothing — the buttons own the exit.
func advance() -> void:
	if not is_open():
		return
	if _typing:
		_reveal_all()
		return
	if _line_index + 1 < _entry.lines.size():
		_show_line(_line_index + 1)
		return
	if not _entry.choices.is_empty():
		return
	_finish_entry()


## Closes the box from the outside (an `end` choice, `ui_cancel`). The
## finished signal fires once per shown entry, whichever way it ends.
func close() -> void:
	if not visible:
		return
	_finish_entry()


func is_open() -> bool:
	return visible and _entry != null and not _finished


func typing() -> bool:
	return _typing


## True when this press belongs to the open dialogue: advance/skip
## (`ui_accept` or the player's `interact`), or close (`ui_cancel`). While
## open these events are consumed — `_unhandled_input` marks them handled —
## so the local player's presses cannot reach the world behind the box. That
## is the input pause the SPEC asks for; the tree itself is never paused,
## because in co-op the pause would be everyone's.
func handles_input(event: InputEvent) -> bool:
	if not is_open():
		return false
	if event.is_action_pressed(&"ui_cancel"):
		close()
		return true
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact"):
		advance()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if handles_input(event):
		get_viewport().set_input_as_handled()


func _show_line(index: int) -> void:
	_line_index = index
	var line: Dictionary = _entry.lines[index]
	_name_plate.text = String(line.get("speaker", ""))
	_text_label.text = String(line.get("text", ""))
	_text_label.visible_characters = 0
	_elapsed = 0.0
	_typing = true


func _reveal_all() -> void:
	_text_label.visible_characters = _text_label.text.length()
	_typing = false
	_maybe_build_choices()


func _finish_line() -> void:
	_text_label.visible_characters = _text_label.text.length()
	_typing = false
	_maybe_build_choices()


## The choices wait for the last line to finish typing (skip counts), so the
## buttons never appear over text still revealing.
func _maybe_build_choices() -> void:
	if _entry == null or _entry.choices.is_empty():
		return
	if _line_index + 1 < _entry.lines.size() or _choices_box.get_child_count() > 0:
		return
	for i: int in _entry.choices.size():
		var choice: Dictionary = _entry.choices[i]
		var button := Button.new()
		button.text = String(choice.get("text", ""))
		button.pressed.connect(_on_choice_pressed.bind(i))
		_choices_box.add_child(button)


func _on_choice_pressed(choice_index: int) -> void:
	if not is_open() or choice_index >= _entry.choices.size():
		return
	choice_selected.emit(choice_index, _entry.choices[choice_index])


## Ends the shown entry: report up and hide. `dialogue_finished` carries the
## entry id; the caller resolves its `on_end`. Fires once — `close()` after a
## natural finish sees `_finished` and the hidden layer.
func _finish_entry() -> void:
	if _finished:
		return
	_finished = true
	var entry_id: StringName = _entry.id
	visible = false
	_entry = null
	_dialogue = null
	_clear_choices()
	dialogue_finished.emit(entry_id)


func _load_portrait(path: String) -> void:
	if path.is_empty():
		# No portrait declared: the name plate spans the header instead of
		# showing an empty frame (the placeholder look the mock-up reviews).
		_portrait.texture = null
		_portrait.visible = false
		return
	_portrait.texture = load(path) as Texture2D
	_portrait.visible = true


## Removes the choice buttons at once (remove + queue_free, not free: a
## choice press lands inside the button's own signal chain, and the next
## entry must see an empty box immediately).
func _clear_choices() -> void:
	for child: Node in _choices_box.get_children():
		_choices_box.remove_child(child)
		child.queue_free()


func _on_dim_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		advance()
