class_name Main
extends Node
## Entry scene: loads the World, registers it with GameState, and either
## starts networking from the launch args or shows the placeholder menu.
## Owned by foundation. Sync: none; NetworkManager owns connection state.

const WORLD_SCENE: PackedScene = preload("res://scenes/main/world.tscn")
## How often the floor-sync smoke driver looks for the client before starting
## the run, and how long it waits for one before starting it alone.
const SMOKE_FLOOR_POLL_SECONDS: float = 0.25
const SMOKE_FLOOR_CLIENT_WAIT_SECONDS: float = 5.0

var world: World
var options: LaunchArgs

## Smoke step 3 (SPEC-networking two-instance step 3): the client asks the
## host to spawn a stub enemy and then kill it over request_debug; the host
## resolves one hit so HP drops on both screens; enemy_killed fires exactly
## once. Markers are grepped by tools/smoke_two.sh. Host and client run the
## same poll timer; NetworkManager.is_host picks the role.
var _smoke3_poll: Timer
var _smoke3_spawn_requested: bool = false
var _smoke3_kill_requested: bool = false
var _smoke3_hit_applied: bool = false
var _smoke3_hit_refusal_logged: bool = false
var _smoke3_death_logged: bool = false
var _smoke3_kill_logged: bool = false
var _smoke3_kill_emissions: int = 0
var _smoke3_logged_hp_host: int = -1
var _smoke3_logged_hp_client: int = -1
## Full-HP ticks seen before resolving the partial hit: gives StateSync a
## beat to deliver the spawn (hp=10) to the client before the drop.
var _smoke3_full_hp_ticks: int = 0

## Floor-sync smoke (SPEC-networking "Seed sync", W3-B3a). The host starts a run
## once a client has joined, which broadcasts floor_ready for floor 1; both
## peers then log the seed, floor, biome and the layout_hash they generated
## locally from it under [floor] markers, and smoke_two.sh compares the two
## hashes. Driven by --smoke-floor.
var _smoke_floor_poll: Timer
var _smoke_floor_started: bool = false
var _smoke_floor_waited: float = 0.0

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
	_maybe_add_debug_console()
	_maybe_add_hud()
	# Module startup registration (SPEC-floor-generation: each owning module
	# registers its room populators at startup). Guarded in each module itself:
	# a no-op that records its blocker once until the registry exists.
	Rope.register_populator()
	Shrine.register_populator()
	_start_from_options()
	if options.smoke_seconds > 0.0:
		_start_smoke(options.smoke_seconds)
	elif options.smoke3_seconds > 0.0:
		_start_smoke3(options.smoke3_seconds)
	elif options.smoke_floor_seconds > 0.0:
		_start_smoke_floor(options.smoke_floor_seconds)


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


## Smoke step 3 driver. The client asks the host (through request_debug) to
## spawn a stub enemy ("spawn grub 1"), the host resolves one partial hit so
## HP drops 10 -> 7 on both screens via StateSync, and the client then asks
## the host to kill it — enemy_killed must fire exactly once. Every marker is
## [smoke3] and grepped by smoke_two.sh. Host resolves hits; clients only
## request (they refuse to resolve — the W2-B3 host-only rule).
func _start_smoke3(seconds: float) -> void:
	Events.enemy_killed.connect(_on_smoke3_enemy_killed)
	_smoke3_poll = Timer.new()
	_smoke3_poll.wait_time = 0.25
	_smoke3_poll.autostart = true
	_smoke3_poll.timeout.connect(_on_smoke3_poll)
	add_child(_smoke3_poll)
	print("[smoke3] armed on peer %d (%s)" % [NetworkManager.local_peer_id, "host" if NetworkManager.is_host else "client"])
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		print("[smoke3] done, quitting")
		get_tree().quit())


func _on_smoke3_enemy_killed(_enemy: Node, _hit: RefCounted) -> void:
	_smoke3_kill_emissions += 1


func _on_smoke3_poll() -> void:
	if NetworkManager.is_host:
		_smoke3_host_tick()
	else:
		_smoke3_client_tick()


## The first entity child that takes hits (has apply_hit) — the placeholder
## enemy, once spawned. Spawners don't count because they lack apply_hit.
func _smoke3_find_enemy() -> Node:
	for child: Node in world.entities.get_children():
		if child.has_method("apply_hit"):
			return child
	return null


## Host: once the enemy is spawned with full HP and the client has joined,
## wait a beat so the client observes the full-HP spawn, then resolve one hit
## of 3 (HP 10 -> 7, replicated to everyone). When the client's kill lands,
## log how many times enemy_killed fired — it must be exactly 1.
func _smoke3_host_tick() -> void:
	var enemy := _smoke3_find_enemy()
	if enemy == null:
		return
	var hp: int = int(enemy.get("current_hp"))
	if hp != _smoke3_logged_hp_host:
		_smoke3_logged_hp_host = hp
		print("[smoke3] host sees %s hp=%d" % [enemy.name, hp])
	if not _smoke3_hit_applied and hp >= 10 and NetworkManager.player_count() >= 2:
		_smoke3_full_hp_ticks += 1
		if _smoke3_full_hp_ticks >= 4:
			var resolved: bool = bool(enemy.apply_hit(3))
			_smoke3_hit_applied = true
			print("[smoke3] host resolved hit on %s hp 10 -> 7 (resolved=%s)" % [enemy.name, resolved])
			_smoke3_logged_hp_host = int(enemy.get("current_hp"))
			print("[smoke3] host sees %s hp=%d" % [enemy.name, _smoke3_logged_hp_host])
	if hp == 0 and not _smoke3_kill_logged:
		_smoke3_kill_logged = true
		print("[smoke3] enemy_killed emitted %d time(s)" % _smoke3_kill_emissions)


## Client: ask the host to spawn the stub enemy, watch the replicated HP drop
## (StateSync brings the host's 10 -> 7 over the wire), then ask the host to
## kill it. The kill gate (hp < 10) guarantees the drop was seen before the
## kill, proving HP drops on both screens.
func _smoke3_client_tick() -> void:
	if not NetworkManager.is_active:
		return
	if not _smoke3_spawn_requested:
		_smoke3_spawn_requested = true
		NetworkManager.rpc_id(NetworkManager.HOST_PEER_ID, "request_debug", "spawn grub 1", NetworkManager.local_peer_id)
		print("[smoke3] client requested spawn grub 1")
	var enemy := _smoke3_find_enemy()
	if enemy == null:
		return
	var hp: int = int(enemy.get("current_hp"))
	if hp != _smoke3_logged_hp_client:
		_smoke3_logged_hp_client = hp
		print("[smoke3] client sees %s hp=%d" % [enemy.name, hp])
	if not _smoke3_kill_requested and hp < 10:
		_smoke3_kill_requested = true
		NetworkManager.rpc_id(NetworkManager.HOST_PEER_ID, "request_debug", "kill", NetworkManager.local_peer_id)
		print("[smoke3] client requested kill")
	if hp == 0 and not _smoke3_death_logged:
		_smoke3_death_logged = true
		print("[smoke3] client sees %s hp=0 (dead)" % enemy.name)


## Floor-sync smoke driver (W3-B3a). The host waits for a client to join, then
## starts a run: GameState's run_started makes NetworkManager broadcast
## floor_ready for floor 1, and both peers generate that floor locally from the
## seed. Both print the [floor] line NetworkManager writes on receipt, so
## smoke_two.sh can compare the two layout hashes for one --seed. The client
## only waits; the host's broadcast is what tells it which floor to build.
func _start_smoke_floor(seconds: float) -> void:
	_smoke_floor_poll = Timer.new()
	_smoke_floor_poll.wait_time = SMOKE_FLOOR_POLL_SECONDS
	_smoke_floor_poll.autostart = true
	_smoke_floor_poll.timeout.connect(_on_smoke_floor_poll)
	add_child(_smoke_floor_poll)
	print("[smoke-floor] armed on peer %d (%s)" % [NetworkManager.local_peer_id, "host" if NetworkManager.is_host else "client"])
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		print("[smoke-floor] done, quitting")
		get_tree().quit())


## Host: start the run once the client is here (or after the wait, so a
## single-instance launch still exercises the path). Client: nothing to drive —
## it logs the floor the host names. Both quit on the timer above.
func _on_smoke_floor_poll() -> void:
	if not NetworkManager.is_host or _smoke_floor_started:
		return
	_smoke_floor_waited += SMOKE_FLOOR_POLL_SECONDS
	if NetworkManager.player_count() < 2 and _smoke_floor_waited < SMOKE_FLOOR_CLIENT_WAIT_SECONDS:
		return
	_smoke_floor_started = true
	var party: Array = []
	for peer_id: int in NetworkManager.peer_ids:
		party.append(PlayerSpawnInfo.new(peer_id))
	GameState.start_run(0, 1, party)
	print("[smoke-floor] host started the run with %d player(s)" % party.size())


## Records the parsed options: forced seed into GameState, menu shown only
## in MENU mode. Does not touch the network (see _start_from_options), so
## tests can drive it without opening sockets.
func apply_options(opts: LaunchArgs) -> void:
	options = opts
	for problem: String in opts.errors:
		push_warning("launch args: %s" % problem)
	GameState.forced_seed = opts.run_seed
	menu.visible = opts.mode == LaunchArgs.Mode.MENU


## Adds the debug console (SPEC-debug-tools) in debug builds or when launched
## with --debug-tools. Loaded lazily (never preloaded) so a release export
## that filters scripts/debug/ out of the pack never references it.
func _maybe_add_debug_console() -> void:
	if options == null or not (OS.is_debug_build() or options.debug_tools):
		return
	var script_path := "res://scripts/debug/debug_console.gd"
	if not ResourceLoader.exists(script_path):
		return
	var console: CanvasLayer = (load(script_path) as GDScript).new()
	console.name = "DebugConsole"
	add_child(console)


## Adds the HUD CanvasLayer over the world (SPEC-ui-hud). Loaded lazily so
## the main scene never references ui-hud until it exists.
func _maybe_add_hud() -> void:
	if not ResourceLoader.exists("res://scenes/ui/hud.tscn"):
		return
	var hud_scene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud: CanvasLayer = hud_scene.instantiate() as CanvasLayer
	hud.name = "HUD"
	add_child(hud)


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
