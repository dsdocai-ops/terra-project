class_name Main
extends Node
## Entry scene: loads the World, registers it with GameState, and either
## starts networking from the launch args or shows the placeholder menu.
## Owned by foundation. Sync: none; NetworkManager owns connection state.

const WORLD_SCENE: PackedScene = preload("res://scenes/main/world.tscn")
const VOID_COLOR: Color = Color(0.085, 0.095, 0.115, 1.0)
## How often the floor-sync smoke driver looks for the client before starting
## the run, and how long it waits for one before starting it alone.
const SMOKE_FLOOR_POLL_SECONDS: float = 0.25
const SMOKE_FLOOR_CLIENT_WAIT_SECONDS: float = 5.0
## The time-stop smoke: the command the client sends, and how often it checks
## whether it has a connected host with the other player in the run.
const SMOKE_TIME_COMMAND: String = "timestop 2"
## The per-entity stop the client asks for after the global one (W4-B9 follow-up).
const SMOKE_ENTITY_TIME_COMMAND: String = "entitystop 2"
const SMOKE_TIME_POLL_SECONDS: float = 0.25
## The ability smoke (W5-G2b): the content it casts, how often it polls, and the
## poll ticks (counted once two players exist) at which the client sends its NaN
## aim and then its finite cast request.
const SMOKE_ABILITY_PATH: String = "res://data/abilities/meteor_call.tres"
const SMOKE_ABILITY_POLL_SECONDS: float = 0.25
const SMOKE_ABILITY_NAN_TICK: int = 2
const SMOKE_ABILITY_CAST_TICK: int = 6
## The Shadow Clones smoke (W5-G4): the client casts slot 1 at this tick, and both
## screens must show three clones.
const SMOKE_CLONES_PATH: String = "res://data/abilities/shadow_clones.tres"
const SMOKE_CLONES_CAST_TICK: int = 10
const SMOKE_CLONES_COUNT: int = 3
## The ultimate smoke (W5-G6): the host charges the client's meter to full at the
## charge tick, the client reads it on its copy, and the client's press at the press
## tick reaches the host. No ultimate is assigned yet (Cave-In is W5-G7), so the host
## refuses the press; that refusal is the only ultimate path this smoke proves.
const SMOKE_ULTIMATE_CHARGE_TICK: int = 12
const SMOKE_ULTIMATE_PRESS_TICK: int = 13

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
var _smoke3_host_heavy_ticks: int = -1
var _smoke3_crack_forwarded: bool = false
var _smoke3_crack_received: bool = false
## Full-HP ticks seen before resolving the partial hit: gives StateSync a
## beat to deliver the spawn (hp=10) to the client before the drop.
var _smoke3_full_hp_ticks: int = 0

## Time-stop smoke (W4-B9), run inside the steps 1+2 pair. The client is the using
## player: it asks the host for `timestop` over request_debug. Both peers log when
## the enemy time stop starts and ends, with the host player's x, so smoke_two.sh
## can check that the non-using player kept moving through the stop on both screens.
## The stop reaches the client only through the host's reliable time_effect_applied RPC.
var _smoke_time_poll: Timer
var _smoke_time_requested: bool = false
var _smoke_time_stopped: bool = false
var _smoke_time_resumed: bool = false
## Entity time-stop smoke (W4-B9 follow-up): both peers poll the client's player
## TimeManager scale. The stop reaches the client only through the host's reliable
## entity_time_applied RPC, so the client's own TimeManager state is what is logged.
var _smoke_entity_timer: Timer
var _smoke_entity_stopped: bool = false
var _smoke_entity_resumed: bool = false

## Ability smoke (W5-G2b), run inside the steps 1+2 pair. Once two players exist,
## each peer gives every player Meteor Call in slot Q. The client sends a NaN aim,
## which the host must refuse over the RPC, then a finite aim, which the host must
## cast once. smoke_two.sh greps the markers the host and client log.
var _smoke_ability_poll: Timer
var _smoke_ability_ticks: int = 0
var _smoke_ability_assigned: bool = false
var _smoke_ability_refusal_logged: bool = false
var _smoke_ability_copy_logged: bool = false
var _smoke_ultimate_charged: bool = false
var _smoke_ultimate_copy_logged: bool = false
var _smoke_ultimate_pressed: bool = false
var _smoke_ultimate_refusal_logged: bool = false
var _smoke_ability_emissions: int = 0
var _smoke_clones_host_logged: bool = false
var _smoke_clones_copy_logged: bool = false

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

## Hollowmere, while the party is between runs; null during a dive.
var town: Town = null

const TOWN_SCENE: String = "res://scenes/town/town.tscn"
## Where the party stands in town, below the pit.
const TOWN_SPAWN: Vector2 = Vector2(0.0, 230.0)

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
	GameState.run_started.connect(_leave_town)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.host_disconnected.connect(_on_host_disconnected)

	apply_options(LaunchArgs.parse(OS.get_cmdline_user_args()))
	_maybe_add_debug_console()
	_maybe_add_hud()
	register_populators()
	_start_from_options()
	if options.smoke_seconds > 0.0:
		_start_smoke(options.smoke_seconds)
	elif options.smoke3_seconds > 0.0:
		_start_smoke3(options.smoke3_seconds)
	elif options.smoke_floor_seconds > 0.0:
		_start_smoke_floor(options.smoke_floor_seconds)


## Module startup registration (SPEC-floor-generation: each owning module
## registers its room populators at startup). Guarded in each module itself:
## a no-op that records its blocker once until the registry exists. A method of
## its own so a test can run the live registration without the whole `_ready`.
func register_populators() -> void:
	Rope.register_populator()
	SpawnDirector.register_populators()
	Shrine.register_populator()
	Chest.register_populator()
	RoomFurniture.register_populator()
	Shopkeeper.register_populator()
	LorePage.register_populator()


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
	TimeManager.enemy_time_changed.connect(_on_smoke_time_scale)
	_smoke_entity_timer = Timer.new()
	_smoke_entity_timer.wait_time = SMOKE_TIME_POLL_SECONDS
	_smoke_entity_timer.autostart = true
	_smoke_entity_timer.timeout.connect(_on_smoke_entity_poll)
	add_child(_smoke_entity_timer)
	_start_smoke_ability()
	if not NetworkManager.is_host:
		_smoke_time_poll = Timer.new()
		_smoke_time_poll.wait_time = SMOKE_TIME_POLL_SECONDS
		_smoke_time_poll.autostart = true
		_smoke_time_poll.timeout.connect(_on_smoke_time_poll)
		add_child(_smoke_time_poll)
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		print("[smoke] done, quitting")
		get_tree().quit())


func _arm_autowalk_if_local(node: Node) -> void:
	var player := node as Player
	if player != null and player.peer_id == NetworkManager.local_peer_id:
		player.debug_autowalk = Vector2(1, 0)
		print("[smoke] autowalk armed on %s" % player.name)


## Client (the using player): once connected and the host player is in the run,
## ask the host for a timestop over request_debug, exactly once.
func _on_smoke_time_poll() -> void:
	if _smoke_time_requested:
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if not NetworkManager.is_active or peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if NetworkManager.player_count() < 2:
		return
	_smoke_time_requested = true
	NetworkManager.rpc_id(NetworkManager.HOST_PEER_ID, "request_debug", SMOKE_TIME_COMMAND, NetworkManager.local_peer_id)
	print("[smoke-time] client requested %s" % SMOKE_TIME_COMMAND)
	NetworkManager.rpc_id(NetworkManager.HOST_PEER_ID, "request_debug", SMOKE_ENTITY_TIME_COMMAND, NetworkManager.local_peer_id)
	print("[smoke-time] client requested %s" % SMOKE_ENTITY_TIME_COMMAND)


## Both peers: TimeManager's enemy scale changed. Below 1.0 is the stop starting
## (the host's own call locally, the client through the reliable RPC); back at 1.0
## is it expiring. The host player's x at each edge shows whether it kept moving.
func _on_smoke_time_scale(scale: float) -> void:
	var who := "host" if NetworkManager.is_host else "client"
	if scale < 1.0 and not _smoke_time_stopped:
		_smoke_time_stopped = true
		print("[smoke-time] %s sees the enemy time stop (scale %.2f) with Player1 x=%.1f" % [who, scale, _smoke_time_host_x()])
	elif scale >= 1.0 and _smoke_time_stopped and not _smoke_time_resumed:
		_smoke_time_resumed = true
		print("[smoke-time] %s sees the enemy time resume with Player1 x=%.1f" % [who, _smoke_time_host_x()])


## The host player's x as this peer currently sees it (replicated on the client).
func _smoke_time_host_x() -> float:
	var host_player: Player = NetworkManager.players.get(NetworkManager.HOST_PEER_ID) as Player
	return host_player.position.x if host_player != null else NAN


## Both peers: the client's player as this peer sees it, polled. Below 1.0 is the
## per-entity stop reaching this screen (the host's own call locally, the client
## through the reliable entity_time_applied RPC); back at 1.0 is it expiring.
func _on_smoke_entity_poll() -> void:
	var client_player: Player = null
	for peer_id: int in NetworkManager.players:
		if peer_id != NetworkManager.HOST_PEER_ID:
			client_player = NetworkManager.players[peer_id] as Player
	if client_player == null:
		return
	var scale := TimeManager.scale_for(client_player)
	var who := "host" if NetworkManager.is_host else "client"
	if scale < 1.0 and not _smoke_entity_stopped:
		_smoke_entity_stopped = true
		print("[smoke-time] %s sees the entity time stop on %s (scale %.2f)" % [who, client_player.name, scale])
	elif scale >= 1.0 and _smoke_entity_stopped and not _smoke_entity_resumed:
		_smoke_entity_resumed = true
		print("[smoke-time] %s sees the entity time resume on %s" % [who, client_player.name])


func _start_smoke_ability() -> void:
	Events.ability_cast.connect(_on_smoke_ability_cast)
	_smoke_ability_poll = Timer.new()
	_smoke_ability_poll.wait_time = SMOKE_ABILITY_POLL_SECONDS
	_smoke_ability_poll.autostart = true
	_smoke_ability_poll.timeout.connect(_on_smoke_ability_poll)
	add_child(_smoke_ability_poll)


## Both peers: once two players exist, give each one Meteor Call (the host needs
## it on every player, since a client's request lands on the host's copy of that
## player's controller), then run the client's requests on the poll ticks.
func _on_smoke_ability_poll() -> void:
	if NetworkManager.player_count() < 2:
		return
	if not _smoke_ability_assigned:
		_smoke_ability_assigned = true
		var meteor := load(SMOKE_ABILITY_PATH) as AbilityData
		var clones := load(SMOKE_CLONES_PATH) as AbilityData
		for peer_id: int in NetworkManager.players:
			var player := NetworkManager.players[peer_id] as Player
			(player.get_node("AbilityController") as AbilityController).assign(0, meteor)
			(player.get_node("AbilityController") as AbilityController).assign(1, clones)
	_smoke_ability_ticks += 1
	if NetworkManager.is_host:
		_smoke_ability_host_tick()
		_smoke_ultimate_host_tick()
	else:
		_smoke_ability_client_tick()
		_smoke_ultimate_client_tick()


## Host: logs the first refusal of a non-finite aim by a client's controller.
func _smoke_ability_host_tick() -> void:
	if _smoke_ability_refusal_logged:
		return
	for peer_id: int in NetworkManager.players:
		if peer_id == NetworkManager.HOST_PEER_ID:
			continue
		var player := NetworkManager.players[peer_id] as Player
		var ability := player.get_node("AbilityController") as AbilityController
		if ability.last_refusal == AbilityController.REFUSE_NOT_FINITE:
			_smoke_ability_refusal_logged = true
			print("[smoke-ability] host refused the non-finite aim from %s (%s)" % [player.name, ability.last_refusal])


## Client: sends the NaN aim, then the finite cast, and logs the visual copy the
## host sends back on its own player's controller.
func _smoke_ability_client_tick() -> void:
	var me := NetworkManager.players.get(NetworkManager.local_peer_id) as Player
	if me == null:
		return
	var ability := me.get_node("AbilityController") as AbilityController
	if _smoke_ability_ticks == SMOKE_ABILITY_NAN_TICK:
		ability.ask_cast(0, Vector2(NAN, 0.0))
		print("[smoke-ability] client asked for a cast with a NaN aim")
	elif _smoke_ability_ticks == SMOKE_ABILITY_CAST_TICK:
		ability.ask_cast(0, me.global_position + Vector2(96, 0))
		print("[smoke-ability] client asked the host to cast Meteor Call")
	elif _smoke_ability_ticks == SMOKE_CLONES_CAST_TICK:
		ability.ask_cast(1, me.global_position + Vector2(64, 0))
		print("[smoke-clones] client asked the host to cast Shadow Clones")
	if not _smoke_clones_copy_logged and ability.last_cast is ShadowClonesCast and (ability.last_cast as ShadowClonesCast).units.size() == SMOKE_CLONES_COUNT:
		_smoke_clones_copy_logged = true
		print("[smoke-clones] client sees %d clones on %s" % [SMOKE_CLONES_COUNT, me.name])
	if not _smoke_ability_copy_logged and is_instance_valid(ability.last_cast):
		_smoke_ability_copy_logged = true
		print("[smoke-ability] client sees the cast on %s (host RPC)" % me.name)


## Host: charges each client's meter to full once at the charge tick, then logs the
## refusal of the client's press once. The meter the client reads is this copy's
## value, sent over UltimateController's RPC.
func _smoke_ultimate_host_tick() -> void:
	for peer_id: int in NetworkManager.players:
		if peer_id == NetworkManager.HOST_PEER_ID:
			continue
		var player := NetworkManager.players[peer_id] as Player
		var ultimate := player.get_node("UltimateController") as UltimateController
		if _smoke_ability_ticks == SMOKE_ULTIMATE_CHARGE_TICK and not _smoke_ultimate_charged:
			_smoke_ultimate_charged = true
			ultimate.charge(UltimateController.METER_MAX)
			print("[smoke-ultimate] host charged the meter of %s to %.0f" % [player.name, ultimate.meter])
		if not _smoke_ultimate_refusal_logged and ultimate.last_refusal == UltimateController.REFUSE_NO_ULTIMATE:
			_smoke_ultimate_refusal_logged = true
			print("[smoke-ultimate] host refused the ultimate press from %s (%s) with meter %.0f" % [player.name, ultimate.last_refusal, ultimate.meter])


## Client: presses the ultimate at the press tick, and logs its meter once the host's
## value reaches this copy.
func _smoke_ultimate_client_tick() -> void:
	var me := NetworkManager.players.get(NetworkManager.local_peer_id) as Player
	if me == null:
		return
	var ultimate := me.get_node("UltimateController") as UltimateController
	if _smoke_ability_ticks == SMOKE_ULTIMATE_PRESS_TICK and not _smoke_ultimate_pressed:
		_smoke_ultimate_pressed = true
		ultimate.ask_ultimate()
		print("[smoke-ultimate] client pressed the ultimate on %s" % me.name)
	if not _smoke_ultimate_copy_logged and ultimate.meter >= UltimateController.METER_MAX:
		_smoke_ultimate_copy_logged = true
		print("[smoke-ultimate] client sees ultimate meter %.0f on %s (host RPC)" % [ultimate.meter, me.name])


## Both peers connect, but only the host emits a cast, so only the host logs one.
## Logged with its emission count and the node the cast spawned under.
func _on_smoke_ability_cast(player: Player, ability: Resource, rank: int) -> void:
	if not NetworkManager.is_host:
		return
	var data := ability as AbilityData
	if data != null and data.id == &"shadow_clones":
		_log_smoke_clones(player)
		return
	_smoke_ability_emissions += 1
	var cast := (player.get_node("AbilityController") as AbilityController).last_cast
	var parent_name: String = str(cast.get_parent().name) if is_instance_valid(cast) else "none"
	print("[smoke-ability] host emitted ability_cast #%d for %s (rank %d) under %s" % [_smoke_ability_emissions, player.name, rank, parent_name])


## Host: logs the clones one Shadow Clones cast spawned, once. Clones are counted
## apart from Meteor Call, so the "#2" check on Meteor Call still means a second
## Meteor cast.
func _log_smoke_clones(player: Player) -> void:
	if _smoke_clones_host_logged:
		return
	var cast := (player.get_node("AbilityController") as AbilityController).last_cast as ShadowClonesCast
	if cast == null:
		return
	_smoke_clones_host_logged = true
	print("[smoke-clones] host spawned %d clones for %s" % [cast.units.size(), player.name])


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
	# The kill's gold drop is a pickup on the spawner. MultiplayerSpawner.spawned fires
	# only on the receiving peers, so this logs the client's replicated copy; the host
	# counts its own drops at the kill instead (see _smoke3_host_tick).
	var pickup_spawner := world.entities.get_node_or_null(String(PickupSpawner.NODE_NAME)) as PickupSpawner
	if pickup_spawner != null:
		pickup_spawner.spawned.connect(_on_smoke3_pickup_spawned)
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
		# Then the host swings its own heavy: its ground crack is a swing the
		# client did not run, so the client only sees it over the crack RPC.
		if NetworkManager.is_host and _smoke3_host_heavy_ticks < 0:
			_smoke3_host_heavy_ticks = 0


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


## Host: the same press-and-release the client drove, on its own player. The
## pickaxe heavy's ground crack is a swing the client did not run, so the
## client only sees it over `_remote_ground_crack` — the smoke's crack proof.
func _smoke3_drive_host_heavy() -> void:
	var me: Player = NetworkManager.players.get(NetworkManager.local_peer_id) as Player
	if me == null:
		return
	var controller: AttackController = me.get_node("AttackController") as AttackController
	if _smoke3_host_heavy_ticks == 0:
		controller.send(AttackController.Kind.HEAVY_PRESS, 0.0)
		print("[smoke3] host pressed heavy")
	elif _smoke3_host_heavy_ticks == 4:
		controller.send(AttackController.Kind.HEAVY, 0.9, false)
		print("[smoke3] host released heavy")
	_smoke3_host_heavy_ticks += 1


## The crack counter on a peer's WeaponController: forwarded on the host,
## received over the RPC on the client. 0 while the player is not here yet.
func _smoke3_crack_count(peer_id: int, forwarded: bool) -> int:
	var player: Player = NetworkManager.players.get(peer_id) as Player
	if player == null:
		return 0
	var weapons: WeaponController = player.get_node("WeaponController") as WeaponController
	if weapons == null:
		return 0
	return weapons.cracks_forwarded if forwarded else weapons.remote_cracks_received


## The rule for the smoke's client skill press, as a pure function so the GUT
## suite can test each term: the step-3 driver is armed, this peer is a client, the
## session is live, the host's perfect-dodge window is open on this player, the
## attack may start on this frame, and the press has not been sent yet.
static func smoke3_skill_press_due(armed: bool, is_host_peer: bool, active: bool, window_open: bool, legal: bool, already_pressed: bool) -> bool:
	return armed and not is_host_peer and active and window_open and legal and not already_pressed


## Client: once the host's perfect-dodge window reaches this player (the host RPC),
## press heavy inside it. That fires the weapon skill on both sides. The press
## waits for a frame the attack may start: a press during the heavy's recovery is
## buffered for 0.2 s and can miss the window (the W5-G5b flake), so this runs
## every frame from _process, not on the 0.25 s poll.
func _smoke3_drive_skill() -> void:
	var me: Player = NetworkManager.players.get(NetworkManager.local_peer_id) as Player
	if me == null:
		return
	var controller: AttackController = me.get_node("AttackController") as AttackController
	if not smoke3_skill_press_due(_smoke3_poll != null, NetworkManager.is_host, NetworkManager.is_active,
			me.is_perfect_dodge_window(), controller.can_start_attack(), _smoke3_window_seen):
		return
	_smoke3_window_seen = true
	print("[smoke3] client sees the perfect-dodge window (host RPC)")
	controller.send(AttackController.Kind.HEAVY_PRESS, 0.0)
	print("[smoke3] client pressed heavy inside the window")


func _on_smoke3_enemy_killed(_enemy: Node, _hit: RefCounted) -> void:
	_smoke3_kill_emissions += 1


func _on_smoke3_pickup_spawned(_pickup: Node) -> void:
	print("[smoke3] client received a pickup spawn on peer %d" % NetworkManager.local_peer_id)


## Host: the drops still on the floor after the kill. Pickups spawn under the same
## Entities node as the enemy, so this is the host's own copy of the drop.
func _smoke3_pickup_count() -> int:
	var count: int = 0
	for child: Node in world.entities.get_children():
		if child is Pickup:
			count += 1
	return count


## Host: the kill's gold drop needs a run to pay into, and the smoke has none. This
## sets `GameState.run` directly rather than through `start_run`, because
## `start_run` broadcasts floor_ready and would regenerate the floor under the
## step-3 enemy.
func _smoke3_start_loot_run() -> void:
	var run := RunState.new(1, 1)
	for peer_id: int in NetworkManager.peer_ids:
		run.add_player(RunPlayerState.new(peer_id))
	GameState.run = run


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
	if GameState.run == null:
		_smoke3_start_loot_run()
	if _smoke3_host_heavy_ticks >= 0 and _smoke3_host_heavy_ticks <= 4:
		_smoke3_drive_host_heavy()
	if not _smoke3_crack_forwarded and _smoke3_crack_count(NetworkManager.local_peer_id, true) > 0:
		_smoke3_crack_forwarded = true
		print("[smoke3] host forwarded the ground crack to the client")
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
		print("[smoke3] host sees %d pickup(s) after the kill" % _smoke3_pickup_count())


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
	if not _smoke3_crack_received and _smoke3_crack_count(NetworkManager.HOST_PEER_ID, false) > 0:
		_smoke3_crack_received = true
		print("[smoke3] client received the ground crack over the host RPC")
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


## Banks what this machine kept (SPEC-run-economy "Banking") and saves, then walks
## back into Hollowmere. The Tavern's Dive starts the next run.
func _on_return_to_town() -> void:
	bank_last_run()
	if NetworkManager.is_host:
		_enter_town()


## Host and solo. Clears the pit floor, stands everyone up in town and shows the
## town scene. The run is already over (or aborted) by the time this runs.
func _enter_town() -> void:
	if town != null:
		return
	world.clear_floor()
	NetworkManager.last_floor_layout = null
	town = (load(TOWN_SCENE) as PackedScene).instantiate() as Town
	town.name = "Town"
	add_child(town)
	move_child(town, 1)
	# The world's co-op camera follows the players; the town's own would fight it.
	var town_camera: Node = town.get_node_or_null("Camera")
	if town_camera != null:
		town_camera.queue_free()
	for player: Player in NetworkManager.players.values():
		player.reset_for_run()
		var spot: Vector2 = TOWN_SPAWN + Vector2(float(maxi(player.slot, 0)) * 48.0, 0.0)
		player.position = spot
		player.synced_position = spot
	print("[run] back in Hollowmere")


## A run started (the Tavern's Dive, or a straight dive): the town steps aside.
func _leave_town(_run_seed: int = 0) -> void:
	if town == null:
		return
	town.queue_free()
	town = null


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
	# The smoke's client skill press runs per frame (see _smoke3_drive_skill).
	_smoke3_drive_skill()
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
