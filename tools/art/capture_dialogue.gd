extends Node
## Captures the DialogueBox mock-up for design review (W6-B2, PLAN G5).
## Needs a window (not headless):
##   godot --path . --resolution 960x540 res://tools/art/capture_dialogue.tscn -- <out.png>
## Waits for the typewriter to finish and the choices to build, screenshots
## the viewport once, and quits. The sample entry is constructed data (the
## Act 1 JSON is W6-B3); the portrait is the standing placeholder asset.

var _out_path: String = "user://dialogue_box_mockup.png"
var _frames: int = 0
var _captured: bool = false
var _box: DialogueBox


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_path = args[0]
	var data := DialogueData.new()
	data.id = &"mockup_hilde"
	data.portrait = "res://assets/portraits/wren.png"
	var entry := DialogueData.Entry.new()
	entry.id = &"intro"
	entry.priority = 10
	entry.lines = [
		{"speaker": "Mayor Hilde", "text": "You're Wren's girl. The pit took him too, you know."},
	]
	entry.choices = [
		{"text": "What happened down there?", "goto": "intro_more"},
		{"text": "I'm going in.", "end": true},
	]
	data.entries = [entry]
	_box = (load("res://scenes/dialogue/dialogue_box.tscn") as PackedScene).instantiate() as DialogueBox
	add_child(_box)
	_box.show_dialogue(data, entry)


func _process(_delta: float) -> void:
	_frames += 1
	if _captured or _frames < 10:
		return
	if _box.typing() or _box._choices_box.get_child_count() == 0:
		return
	_captured = true
	_capture()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out_path)
	print("capture_dialogue: saved %s" % _out_path)
	get_tree().quit()
