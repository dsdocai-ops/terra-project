class_name DebugConsole
extends CanvasLayer
## Debug console: a backtick-toggled LineEdit + scrollback under a CanvasLayer,
## a command registry (register()), and the run loop. Commands execute on the
## host; a client's console sends the line to the host through
## NetworkManager.request_debug and shows its own echo (the host's console
## prints the result). The core command set is installed by DebugCommands;
## other modules register their own commands here. Owned by debug-tools
## (W2-B4).
## Sync: host-authoritative. Commands run only where multiplayer.is_server();
## a client's console routes the line to the host via the request_debug RPC,
## matching SPEC-networking's request_* convention. The god and FPS overlay
## toggles are per-peer local debug state, not gameplay state.

const TOGGLE_ACTION := &"debug_console"
const MAX_HISTORY_LINES := 200

## name -> CommandEntry.
var _commands: Dictionary[StringName, CommandEntry] = {}
var _history: Array[String] = []
var _god_peers: Dictionary[int, bool] = {}
var _fps_overlay: bool = false
## The object that owns the core command handlers. Held here so the bound
## callables never dangle (a locally-created RefCounted would be freed once
## nothing referenced it).
var commands: DebugCommands

var _input: LineEdit
var _scrollback: RichTextLabel
var _fps_label: Label


func _ready() -> void:
	layer = 100
	# Keep the console usable even while gameplay nodes are paused or frozen
	# by a time effect (the engine's global time scale is never used).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	commands = DebugCommands.new()
	commands.console = self
	commands.register_all()
	NetworkManager.debug_command_requested.connect(_on_debug_command_requested)
	hide()


func _process(_delta: float) -> void:
	# Polling keeps the toggle working while the LineEdit has focus (the key
	# would otherwise be consumed as text before it reaches unhandled input).
	if Input.is_action_just_pressed(TOGGLE_ACTION):
		_toggle()
	if _fps_overlay and _fps_label != null:
		_fps_label.text = "fps %d" % Engine.get_frames_per_second()


## Registers a command. `callable` receives (args: PackedStringArray,
## issuing_peer_id: int) and returns the result text.
func register(name: StringName, callable: Callable, help: String) -> void:
	_commands[StringName(name)] = CommandEntry.new(StringName(name), callable, help)


func has_command(name: StringName) -> bool:
	return _commands.has(StringName(name))


## The CommandEntry for a command name, or null when unregistered.
func entry(name: StringName) -> CommandEntry:
	var key := StringName(name)
	if not _commands.has(key):
		return null
	return _commands[key]


## Every registered command in registration order.
func list_commands() -> Array[CommandEntry]:
	var result: Array[CommandEntry] = []
	for entry: CommandEntry in _commands.values():
		result.append(entry)
	return result


## Runs a console line as the host would and returns the result text. Blank
## lines return "". `issuing_peer_id` is who asked, used by targeting commands
## (spawn at the player, give/gold/heal on the player).
func run(line: String, issuing_peer_id: int) -> String:
	var tokens := DebugParser.tokenize(line)
	if tokens.is_empty():
		return ""
	var name := StringName(tokens[0])
	var args := tokens.slice(1)
	var command := entry(name)
	if command == null:
		return "unknown command: %s (type 'help' for a list)" % name
	return String(command.callable.call(args, issuing_peer_id))


## The fps command's toggle. Returns the new state for feedback.
func toggle_fps() -> bool:
	_fps_overlay = not _fps_overlay
	if _fps_label != null:
		_fps_label.visible = _fps_overlay
	return _fps_overlay


func is_fps_overlay() -> bool:
	return _fps_overlay


## Toggles god mode for one peer. God mode is debug-local state until
## combat-core's Health lands and consumes it.
func toggle_god(peer_id: int) -> void:
	_god_peers[peer_id] = not _god_peers.get(peer_id, false)


func is_god(peer_id: int) -> bool:
	return _god_peers.get(peer_id, false)


func _toggle() -> void:
	if visible:
		hide()
		_input.release_focus()
	else:
		show()
		_input.clear()
		_input.grab_focus()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.offset_left = 8.0
	margin.offset_top = 8.0
	add_child(margin)

	var panel := PanelContainer.new()
	margin.add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)

	_scrollback = RichTextLabel.new()
	_scrollback.custom_minimum_size = Vector2(560, 220)
	_scrollback.scroll_following = true
	_scrollback.bbcode_enabled = false
	box.add_child(_scrollback)

	_input = LineEdit.new()
	_input.placeholder_text = "debug (backtick toggles)"
	_input.text_submitted.connect(_submit_command)
	box.add_child(_input)

	_fps_label = Label.new()
	_fps_label.visible = false
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_fps_label)


## LineEdit submit: run locally as the host, or send the line to the host when
## this peer is a client so commands always execute where gameplay runs.
func _submit_command(text: String) -> void:
	_input.clear()
	if text.strip_edges().is_empty():
		return
	if NetworkManager.is_host:
		_execute(text, NetworkManager.local_peer_id)
		return
	if not NetworkManager.is_active:
		_print_line("not connected; command dropped: %s" % text)
		return
	NetworkManager.rpc_id(NetworkManager.HOST_PEER_ID, "request_debug", text, NetworkManager.local_peer_id)
	_print_line("sent to host: %s" % text)


## Host side of a request_debug from any peer: execute the line for that peer.
func _on_debug_command_requested(line: String, peer_id: int) -> void:
	_execute(line, peer_id)


func _execute(line: String, peer_id: int) -> void:
	var result := run(line, peer_id)
	_print_line("> %s" % line)
	if not result.is_empty():
		_print_line(result)
	print("[console] %s (peer %d) -> %s" % [line, peer_id, result])


func _print_line(text: String) -> void:
	_history.append(text)
	if _history.size() > MAX_HISTORY_LINES:
		_history.pop_front()
	_scrollback.text = "\n".join(_history)


## One registered command: name, the handler callable, and help text.
class CommandEntry:
	extends RefCounted

	var name: StringName
	var callable: Callable
	var help: String

	func _init(p_name: StringName, p_callable: Callable, p_help: String) -> void:
		name = p_name
		callable = p_callable
		help = p_help
