class_name Main
extends Node
## Entry scene: loads the World, registers it with GameState, and either
## starts networking from the launch args or shows the placeholder menu.
## Owned by foundation. Sync: none; NetworkManager owns connection state.

const WORLD_SCENE: PackedScene = preload("res://scenes/main/world.tscn")

var world: World
var options: LaunchArgs

@onready var menu: PlaceholderMenu = $UI/PlaceholderMenu


func _ready() -> void:
	world = WORLD_SCENE.instantiate() as World
	add_child(world)
	move_child(world, 0)
	GameState.world = world

	menu.solo_pressed.connect(_on_solo)
	menu.host_pressed.connect(_on_host)
	menu.join_pressed.connect(_on_join)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.host_disconnected.connect(_on_host_disconnected)

	apply_options(LaunchArgs.parse(OS.get_cmdline_user_args()))
	_start_from_options()
	if options.smoke_seconds > 0.0:
		_start_smoke(options.smoke_seconds)


## Headless smoke support: the local player walks right as soon as its node
## arrives (on a client that is after the spawner delivers it, well after
## player_joined), every player's position is logged once a second, and the
## instance quits by itself after `seconds`.
func _start_smoke(seconds: float) -> void:
	world.players.child_entered_tree.connect(_arm_autowalk_if_local)
	for child in world.players.get_children():
		_arm_autowalk_if_local(child)
	var log_timer := Timer.new()
	log_timer.wait_time = 1.0
	log_timer.autostart = true
	log_timer.timeout.connect(_log_smoke)
	add_child(log_timer)
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		print("[smoke] done, quitting")
		get_tree().quit())


func _arm_autowalk_if_local(node: Node) -> void:
	var player := node as Player
	if player != null and player.peer_id == NetworkManager.local_peer_id:
		player.debug_autowalk = Vector2(1, 0)
		print("[smoke] autowalk armed on %s" % player.name)


func _log_smoke() -> void:
	var parts: PackedStringArray = []
	for peer_id: int in NetworkManager.players:
		var p := NetworkManager.players[peer_id]
		parts.append("%s=%s" % [p.name, p.position.round()])
	print("[smoke] peer %d sees %d player(s): %s" % [NetworkManager.local_peer_id, parts.size(), " ".join(parts)])


## Records the parsed options: forced seed into GameState, menu shown only
## in MENU mode. Does not touch the network (see _start_from_options), so
## tests can drive it without opening sockets.
func apply_options(opts: LaunchArgs) -> void:
	options = opts
	for problem: String in opts.errors:
		push_warning("launch args: %s" % problem)
	GameState.forced_seed = opts.run_seed
	menu.visible = opts.mode == LaunchArgs.Mode.MENU


func _start_from_options() -> void:
	match options.mode:
		LaunchArgs.Mode.HOST:
			_on_host()
		LaunchArgs.Mode.JOIN:
			_on_join(options.join_ip)
		LaunchArgs.Mode.MENU:
			pass


func _on_solo() -> void:
	menu.hide()
	NetworkManager.start_solo()


func _on_host() -> void:
	menu.hide()
	var err := NetworkManager.host(options.port if options != null else NetworkManager.DEFAULT_PORT)
	if err != OK:
		_show_menu_with_status("Could not host: %s" % error_string(err))


func _on_join(ip: String) -> void:
	menu.hide()
	var err := NetworkManager.join(ip, options.port if options != null else NetworkManager.DEFAULT_PORT)
	if err != OK:
		_show_menu_with_status("Could not join %s: %s" % [ip, error_string(err)])


func _on_connection_failed(reason: String) -> void:
	_show_menu_with_status("Connection failed: %s" % reason)


func _on_host_disconnected() -> void:
	_show_menu_with_status("Host left the game")


func _show_menu_with_status(text: String) -> void:
	menu.set_status(text)
	menu.show()
