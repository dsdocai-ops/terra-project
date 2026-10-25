class_name Main
extends Node
## Entry scene: loads the World, registers it with GameState, and either
## starts networking from the launch args or shows the placeholder menu.
## Owned by foundation. Sync: none; NetworkManager owns connection state.

const WORLD_SCENE: PackedScene = preload("res://scenes/main/world.tscn")
const VOID_COLOR: Color = Color(0.055, 0.043, 0.035, 1.0)
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
var _smoke3_stagger_logged: bool = false
var _smoke3_heavy_ticks: int = -1
var _smoke3_charge_seen: bool = false
var _smoke3_feedback_repeats: int = 0
var _smoke3_window_pending: bool = false
var _smoke3_window_sent: bool = false
var _smoke3_window_seen: bool = false
var _smoke3_skill_seen: bool = false
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
var _last_result: RunResult = null
## The co-op lobby screen and the LAN announcer a hosting session runs.
var lobby: LobbyMenu = null
var _announcer: LobbyDiscovery = null
var _last_join: Dictionary = {}
## The in-game HUD; hidden whenever a menu is up or no session is running.
var _hud: CanvasLayer = null

@onready var menu: PlaceholderMenu = $UI/PlaceholderMenu


func _ready() -> void:
	# Dark cave void around the floor instead of the engine's default grey.
	RenderingServer.set_default_clear_color(VOID_COLOR)
	world = WORLD_SCENE.instantiate() as World
	add_child(world)
	move_child(world, 0)
	GameState.world = world

	menu.solo_pressed.connect(_on_solo)
	menu.coop_pressed.connect(_open_lobby)
	lobby = LobbyMenu.new()
	lobby.name = "LobbyMenu"
	$UI.add_child(lobby)
	lobby.host_requested.connect(_on_lobby_host)
	lobby.join_requested.connect(_on_lobby_join)
	lobby.back_pressed.connect(_on_lobby_back)
	NetworkManager.join_refused.connect(_on_join_refused)
	multiplayer.connected_to_server.connect(lobby.close)
	menu.settings_pressed.connect(_on_menu_stub.bind("Settings arrive in a later update"))
	menu.codex_pressed.connect(_on_menu_stub.bind("The Codex fills as you play"))
	menu.quit_pressed.connect(_on_quit)
	GameState.run_ended.connect(_on_run_ended)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.host_disconnected.connect(_on_host_disconnected)

	apply_options(LaunchArgs.parse(OS.get_cmdline_user_args()))
	_maybe_add_debug_console()
	_maybe_add_hud()
	# Module startup registration (SPEC-floor-generation: each owning module
	# registers its room populators at startup). Guarded in each module itself:
	# a no-op that records its blocker once until the registry exists.
	Rope.register_populator()
	SpawnDirector.register_populators()
	Shrine.register_populator()
	Chest.register_populator()
	RoomFurniture.register_populator()
	Shopkeeper.register_populator()
	LorePage.register_populator()
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
	world.combat_feedback.feedback_played.connect(_on_smoke3_feedback_played)
	world.combat_feedback.dodge_ping_played.connect(_on_smoke3_dodge_ping)
	Events.heavy_attack_released.connect(_on_smoke3_heavy_released)
	_smoke3_poll = Timer.new()
	_smoke3_poll.wait_time = 0.25
	_smoke3_poll.autostart = true
	_smoke3_poll.timeout.connect(_on_smoke3_poll)
	add_child(_smoke3_poll)
	print("[smoke3] armed on peer %d (%s)" % [NetworkManager.local_peer_id, "host" if NetworkManager.is_host else "client"])
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		print("[smoke3] done, quitting")
		get_tree().quit())


## Both peers log each feedback packet they play, so the smoke can prove the host's
## unreliable CombatFeedback RPC reached the client.
func _on_smoke3_feedback_played(payload: Dictionary) -> void:
	print("[smoke3] feedback played on peer %d dmg=%d" % [NetworkManager.local_peer_id, int(payload.get("final_damage", 0))])


## The host logs the heavy a client released, with the charge it validated.
func _on_smoke3_heavy_released(player: Player, charge: float) -> void:
	print("[smoke3] heavy_attack_released from peer %d charge=%.2f" % [player.peer_id, charge])
	if player.peer_id != NetworkManager.local_peer_id:
		_smoke3_window_pending = true


func _on_smoke3_dodge_ping(player: Player) -> void:
	print("[smoke3] dodge ping played on peer %d over Player%d" % [NetworkManager.local_peer_id, player.peer_id])


## Client: after the kill request, press and hold the heavy button through
## AttackController (the same messages the real input sends), then release it a
## second later with a charge. The host must see the player charging (the press
## RPC) and then the release (the release RPC with the charge).
func _smoke3_drive_heavy() -> void:
	var me: Player = NetworkManager.players.get(NetworkManager.local_peer_id) as Player
	if me == null:
		return
	var controller: AttackController = me.get_node("AttackController") as AttackController
	if _smoke3_heavy_ticks == 0:
		controller.send(AttackController.Kind.HEAVY_PRESS, 0.0)
		print("[smoke3] client pressed heavy")
	elif _smoke3_heavy_ticks == 4:
		controller.send(AttackController.Kind.HEAVY, 0.9, false)
		print("[smoke3] client released heavy")
	_smoke3_heavy_ticks += 1


## Client: once the host's perfect-dodge window reaches this player (the host RPC),
## press heavy inside it. That fires the weapon skill on both sides.
func _smoke3_drive_skill() -> void:
	var me: Player = NetworkManager.players.get(NetworkManager.local_peer_id) as Player
	if me == null or _smoke3_window_seen or not me.is_perfect_dodge_window():
		return
	_smoke3_window_seen = true
	print("[smoke3] client sees the perfect-dodge window (host RPC)")
	var controller: AttackController = me.get_node("AttackController") as AttackController
	controller.send(AttackController.Kind.HEAVY_PRESS, 0.0)
	print("[smoke3] client pressed heavy inside the window")


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
	if _smoke3_window_pending and not _smoke3_window_sent:
		# Stand-in for a dodged hit: the same call Player makes when the hurtbox
		# reports a blocked hit (opens the host's window, freezes and pings the
		# dodger, tells the owning client).
		for peer_id: int in NetworkManager.players:
			var target: Player = NetworkManager.players[peer_id] as Player
			if peer_id != NetworkManager.local_peer_id and target != null:
				_smoke3_window_sent = true
				target._on_dodge_blocked(HitInfo.new())
				print("[smoke3] host opened a perfect-dodge window for Player%d" % peer_id)
	if _smoke3_window_sent and not _smoke3_skill_seen:
		for peer_id: int in NetworkManager.players:
			var other_player: Player = NetworkManager.players[peer_id] as Player
			if peer_id == NetworkManager.local_peer_id or other_player == null:
				continue
			var weapons: WeaponController = other_player.get_node("WeaponController") as WeaponController
			if weapons.skill_cooldown_left() > 0.0:
				_smoke3_skill_seen = true
				print("[smoke3] host sees the client fire the weapon skill")
	if not _smoke3_charge_seen:
		for peer_id: int in NetworkManager.players:
			var other: Player = NetworkManager.players[peer_id] as Player
			if peer_id != NetworkManager.local_peer_id and other != null and other.state_machine.current_name() == &"HeavyCharge":
				_smoke3_charge_seen = true
				print("[smoke3] host sees the client player charging a heavy")
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
			# The same landed hit goes through CombatFeedback: hit-stop on the host, then
			# the unreliable RPC to every peer. apply_hit above bypasses Hurtbox, so no
			# hit_landed fires for it; this stands in for that event.
			var landed := HitInfo.new()
			landed.target = enemy
			landed.final_damage = 77
			landed.staggered = true
			world.combat_feedback._on_hit_landed(landed)
			enemy.call("enter_stagger", landed)
			print("[smoke3] host sent feedback for %s" % enemy.name)
	# The feedback RPC is unreliable by design, so the smoke sends it on two more
	# ticks: one packet arriving is the proof, and a single drop is not a failure.
	if _smoke3_hit_applied and _smoke3_feedback_repeats < 2:
		_smoke3_feedback_repeats += 1
		var again := HitInfo.new()
		again.target = enemy
		again.final_damage = 77
		world.combat_feedback._on_hit_landed(again)
	if hp == 0 and not _smoke3_kill_logged:
		_smoke3_kill_logged = true
		print("[smoke3] enemy_killed emitted %d time(s)" % _smoke3_kill_emissions)


## Client: ask the host to spawn the stub enemy, watch the replicated HP drop
## (StateSync brings the host's 10 -> 7 over the wire), then ask the host to
## kill it. The kill gate (hp < 10) guarantees the drop was seen before the
## kill, proving HP drops on both screens.
func _smoke3_client_tick() -> void:
	# Wait for the handshake to finish: an RPC sent while the peer is still
	# connecting is refused, which used to lose the whole step-3 run when the
	# client started slowly.
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if not NetworkManager.is_active or peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if _smoke3_heavy_ticks >= 0 and _smoke3_heavy_ticks <= 4:
		_smoke3_drive_heavy()
	_smoke3_drive_skill()
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
		_smoke3_heavy_ticks = 0
	if bool(enemy.get("staggered")) and not _smoke3_stagger_logged:
		_smoke3_stagger_logged = true
		print("[smoke3] client sees %s staggered (StateSync)" % enemy.name)
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
	_hud = hud
	hud.connect(&"return_to_town_requested", _on_return_to_town)
	hud.connect(&"leave_coop_requested", _on_leave_coop)


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
	_begin_dive()


func _on_host() -> void:
	menu.hide()
	var port: int = options.port if options != null else NetworkManager.DEFAULT_PORT
	var host_name: String = options.server_name if options != null and not options.server_name.is_empty() else "Sinkhole host"
	var password: String = options.password if options != null else ""
	var err := NetworkManager.host(port, host_name, password)
	if err != OK:
		_show_menu_with_status("Could not host: %s" % error_string(err))
	else:
		_start_announcing(host_name, not password.is_empty(), port)
		_begin_dive()


## Host and solo: starts a run straight into floor 1 (the town flow replaces this
## once the walkable town spawns players). Skipped when a run already exists.
func _begin_dive() -> void:
	if GameState.run != null or not NetworkManager.is_host:
		return
	if options != null and (options.smoke_seconds > 0.0 or options.smoke3_seconds > 0.0 or options.smoke_floor_seconds > 0.0):
		return
	var party: Array = []
	for peer_id: int in NetworkManager.peer_ids:
		party.append(PlayerSpawnInfo.new(peer_id))
	GameState.start_run(0, 1, party)


func _on_join(ip: String) -> void:
	menu.hide()
	var err := NetworkManager.join(ip, options.port if options != null else NetworkManager.DEFAULT_PORT, options.password if options != null else "")
	if err != OK:
		_show_menu_with_status("Could not join %s: %s" % [ip, error_string(err)])


func _on_connection_failed(reason: String) -> void:
	if lobby != null and lobby.visible:
		lobby.show_error("Connection failed: %s" % reason)
		return
	_show_menu_with_status("Connection failed: %s" % reason)


func _on_host_disconnected() -> void:
	_stop_announcing()
	GameState.abandon_run()
	_show_menu_with_status("Host left the game")


func _show_menu_with_status(text: String) -> void:
	menu.set_status(text)
	menu.show()


## Settings (week 12) and Codex (week 10) are not built yet; the menu says so.
func _on_menu_stub(text: String) -> void:
	menu.set_status(text)


func _on_quit() -> void:
	get_tree().quit()


## Banks this machine's kept row the moment the run ends, so quitting, leaving
## co-op or closing the game from the death screen cannot lose it.
func _on_run_ended(result: RefCounted) -> void:
	_last_result = result as RunResult
	bank_last_run()


## Banks what this machine kept (SPEC-run-economy "Banking") and saves, then goes
## back to town. blocked on Dev A (W5-A1): the walkable town needs the Player to
## spawn there, so until it does this stops after banking.
func _on_return_to_town() -> void:
	bank_last_run()
	print("[run] back in Hollowmere (the walkable town is not wired yet, so a new dive starts)")
	if NetworkManager.is_host:
		for player: Player in NetworkManager.players.values():
			player.reset_for_run()
		_begin_dive()


## Merges the local player's kept row into their profile and saves. Idempotent:
## a run banks once.
func bank_last_run() -> bool:
	if _last_result == null or SaveManager.profile == null:
		return false
	var gains: Dictionary = RunEconomyRules.gains_for(_last_result, NetworkManager.local_peer_id)
	SaveManager.profile.merge_run_gains(gains)
	SaveManager.save()
	_last_result = null
	return true


func _on_leave_coop() -> void:
	_stop_announcing()
	NetworkManager.disconnect_all()
	GameState.abandon_run()
	_show_menu_with_status("You left the co-op session")


# --- co-op lobby ----------------------------------------------------------------


## Menu Co-op: the lobby handles both hosting and joining.
func _open_lobby(address: Variant = "") -> void:
	menu.hide()
	lobby.open(str(address) if address is String else "")


func _on_lobby_host(server_name: String, password: String) -> void:
	if NetworkManager.is_active:
		return
	var port: int = options.port if options != null else NetworkManager.DEFAULT_PORT
	var err: Error = NetworkManager.host(port, server_name, password)
	if err != OK:
		lobby.show_error("Could not host: %s" % error_string(err))
		return
	lobby.close()
	_start_announcing(server_name, not password.is_empty(), port)
	_begin_dive()


func _on_lobby_join(address: String, port: int, password: String) -> void:
	if NetworkManager.is_active:
		return
	_last_join = {"address": address, "port": port, "had_password": not password.is_empty()}
	var err: Error = NetworkManager.join(address, port, password)
	if err != OK:
		lobby.show_error("Could not join %s: %s" % [address, error_string(err)])
		return
	lobby.show_error("Joining %s…" % address)


## A server turned the player away: ask for the password again.
func _on_join_refused(_reason: StringName) -> void:
	if _last_join.is_empty():
		return
	var message: String = "Wrong password. Try again." if bool(_last_join["had_password"]) else "That server needs a password."
	lobby.show()
	lobby.ask_password(String(_last_join["address"]), int(_last_join["port"]), message)


func _start_announcing(server_name: String, locked: bool, port: int) -> void:
	_stop_announcing()
	_announcer = LobbyDiscovery.new()
	_announcer.name = "LobbyAnnouncer"
	add_child(_announcer)
	_announcer.start_announcing(server_name, locked, port)


func _stop_announcing() -> void:
	if _announcer != null:
		_announcer.stop()
		_announcer.queue_free()
		_announcer = null


## The HUD belongs to the game: it shows only in a live session, never over the
## main menu or the co-op lobby.
func _process(_delta: float) -> void:
	if _hud == null:
		return
	var menus_up: bool = (menu != null and menu.visible) or (lobby != null and lobby.visible)
	_hud.visible = NetworkManager.is_active and not menus_up


## Back from the lobby cancels a join that is still connecting, then shows the
## main menu again.
func _on_lobby_back() -> void:
	if NetworkManager.is_active:
		NetworkManager.disconnect_all()
	menu.show()
