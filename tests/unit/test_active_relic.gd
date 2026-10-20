extends GutTest
## Tests for the active-relic slot controller: slot 1 on the `relic_active_1`
## input action, the per-slot charges and cooldown, the room refill, and
## `request_activate_relic(slot)` with its host apply path (SPEC-relics "Active
## relics", "Multiplayer ownership"; SPEC-networking "RPC conventions";
## SPEC-foundation's Input Map table; W4-B7, PLAN G11 / raw goals G36 + G37).
## Owned by relics.
##
## The rules this file pins down, in the spec's own order:
##  * **the binding is the Input Map's** — `relic_active_1` (C) for slot 1 and
##    `relic_active_2` (B) for slot 2, taken out of the Input Map at run time and
##    matched back through `InputMap.event_is_action`, never a keycode written
##    into the controller;
##  * **charges**: an active with `active_charges = 3` spends exactly one per
##    activation, and an activation with nothing left to spend is refused;
##  * **the cooldown** is the relic's own `active_cooldown`, and
##    `cooldown_fraction(slot)` runs 1.0 (just used) to 0.0 (ready again);
##  * **charges refill per room where the relic says so** — the relic's effect
##    states it, the controller asks, and a relic that does not say it keeps its
##    spent charges across a room change;
##  * **host-authoritative**: a client's `request_activate_relic(slot)` is
##    validated by the host (the peer holds an active in that slot, has a charge,
##    is not on cooldown) and applied there; a client's own local call is refused
##    and applies nothing;
##  * **time comes from `TimeManager`**: a stop on the enemies does not stall the
##    cooldown, and the player's own entity-scale does.
##
## The RPC declarations are `NetworkManager`'s — the crate the request travels on
## (`request_activate_relic` is `any_peer` / `call_remote` / `reliable` and reads
## `get_remote_sender_id()`; the `relic_activated` broadcast is `authority` /
## `call_local` / `reliable`) — and the test reads those attributes off the
## script rather than trusting the comment.
##
## after_each clears the run, the injected pool, the two `TimeManager` sources
## and the session, so no autoload state leaks into the next file (LESSONS).

const HOST_PEER: int = 1
const GUEST_PEER: int = 2
const FORCED_SEED: int = 4242

## The fixture id. Ids are the snake_case file name in `data/relics/`; this one
## is built in memory by `_make_active()` because the actives themselves are a
## week-8 batch (W4-B7's own note) and `data/relics/` holds exactly the 20
## week-4 relics, which `test_relic_data.gd` pins.
const ACTIVE_ID: StringName = &"test_bomb_bag"
const PASSIVE_ID: StringName = &"test_passive_relic"

const ACTIVE_SCRIPT: String = "res://tests/helpers/active_relic_stub.gd"
const CONTROLLER_PATH: String = "res://scripts/relics/active_relic_controller.gd"

## The two numbers the fixture states, so an assertion reads as a delta from
## what the relic says rather than from a literal repeated in the case.
const CHARGES: int = 3
const COOLDOWN: float = 2.0

## Unique `TimeManager` sources, cleared in `after_each`: the global stack is
## autoload state shared by the whole GUT run.
const TIME_SOURCE_STOP: StringName = &"test-active-stop"
const TIME_SOURCE_ENTITY: StringName = &"test-active-entity"

var _harness: EffectHarness = null
var _player: Player = null
var _stub: ActiveRelicStub = null
var _controller: ActiveRelicController = null
var _active: RelicData = null
## Every controller `_guest_with_the_active()` built, so each is disconnected in
## `after_each` and the host's announcement of a remote use is observable.
var _guests: Array[ActiveRelicController] = []
## Every slot the client-side wire half was asked for.
var _requests: Array[int] = []
## Every activation the controller announced, as {slot, id}.
var _announced: Array[Dictionary] = []
## Every activation broadcast that landed on the wire half, as
## {peer_id, slot, id}.
var _received: Array[Dictionary] = []


func before_each() -> void:
	TimeManager.clear_source(TIME_SOURCE_STOP)
	TimeManager.clear_source(TIME_SOURCE_ENTITY)
	GameState.run = null
	GameState.forced_seed = 0
	NetworkManager.players.clear()
	NetworkManager.start_solo()
	_harness = EffectHarness.new(self)
	_harness.setup()
	_active = _make_active()
	_start_run([HOST_PEER, GUEST_PEER])
	_player = _make_holder(HOST_PEER)
	_slice(HOST_PEER).relics.append(ACTIVE_ID)
	_stub = _harness.attach(_active, 1, _player) as ActiveRelicStub
	_controller = ActiveRelicController.for_player(_player)
	_controller.pool = [_active]
	_requests.clear()
	_announced.clear()
	_received.clear()
	_guests.clear()
	NetworkManager.relic_activate_requested.connect(_on_requested)
	_controller.slot_activated.connect(_on_slot_activated)


func after_each() -> void:
	if NetworkManager.relic_activate_requested.is_connected(_on_requested):
		NetworkManager.relic_activate_requested.disconnect(_on_requested)
	if _controller != null and is_instance_valid(_controller) \
			and _controller.slot_activated.is_connected(_on_slot_activated):
		_controller.slot_activated.disconnect(_on_slot_activated)
	for guest: ActiveRelicController in _guests:
		if guest != null and is_instance_valid(guest) \
				and guest.slot_activated.is_connected(_on_slot_activated):
			guest.slot_activated.disconnect(_on_slot_activated)
	_guests.clear()
	TimeManager.clear_source(TIME_SOURCE_STOP)
	TimeManager.clear_source(TIME_SOURCE_ENTITY)
	NetworkManager.players.clear()
	GameState.run = null
	GameState.forced_seed = 0
	EffectHarness.reset_globals()
	_player = null
	_stub = null
	_controller = null
	_harness = null


func _on_requested(slot: int) -> void:
	_requests.append(slot)


func _on_slot_activated(slot: int, id: StringName) -> void:
	_announced.append({"slot": slot, "id": id})


## Named, not a lambda: a lambda connected to a signal never fires under the GUT
## runner (LESSONS).
func _on_activated_received(peer_id: int, slot: int, id: StringName) -> void:
	_received.append({"peer_id": peer_id, "slot": slot, "id": id})


# --- fixtures --------------------------------------------------------------


## The fixture active relic: `Kind.ACTIVE`, three charges, a two-second cooldown
## and the stub effect script, built in memory so no week-8 `.tres` is invented.
func _make_active() -> RelicData:
	var made := RelicData.new()
	made.id = ACTIVE_ID
	made.display_name = "Test Bomb Bag"
	made.kind = RelicData.Kind.ACTIVE
	made.active_charges = CHARGES
	made.active_cooldown = COOLDOWN
	made.effect_script = load(ACTIVE_SCRIPT) as GDScript
	return made


## A player for `peer_id`, registered the way `PlayerSpawner` registers one, so
## the host's `apply_activate_request` can resolve a remote sender to its player.
func _make_holder(peer_id: int) -> Player:
	var made: Player = _harness.make_player()
	made.peer_id = peer_id
	NetworkManager.players[peer_id] = made
	return made


## A second player holding the same active relic, with its own controller — the
## remote client's half of the request path. Its `slot_activated` is listened to
## as well as the host's, because the host applies a remote use through **that
## peer's** controller, so the announcement it makes is that controller's.
func _guest_with_the_active() -> ActiveRelicController:
	var guest: Player = _make_holder(GUEST_PEER)
	_slice(GUEST_PEER).relics.append(ACTIVE_ID)
	_harness.attach(_active, 1, guest)
	var made: ActiveRelicController = ActiveRelicController.for_player(guest)
	made.pool = [_active]
	made.slot_activated.connect(_on_slot_activated)
	_guests.append(made)
	return made


func _party(peer_ids: Array[int]) -> Array[PlayerSpawnInfo]:
	var party: Array[PlayerSpawnInfo] = []
	for peer_id: int in peer_ids:
		party.append(PlayerSpawnInfo.new(peer_id))
	return party


func _start_run(peer_ids: Array[int]) -> void:
	GameState.forced_seed = FORCED_SEED
	GameState.start_run(0, 2, _party(peer_ids))
	assert_not_null(GameState.run, "the run is live")


func _slice(peer_id: int) -> RunPlayerState:
	return GameState.run.get_player(peer_id) if GameState.run != null else null


func _become_client() -> void:
	NetworkManager.is_host = false


## The event the Input Map holds for `action`, pressed. Read out of the map (not
## a keycode written here), so a case proves the controller resolved a real
## binding rather than a literal.
func _pressed_event_for(action: StringName) -> InputEvent:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key: InputEventKey = (event as InputEventKey).duplicate() as InputEventKey
			key.pressed = true
			key.physical_keycode = (event as InputEventKey).physical_keycode
			key.keycode = (event as InputEventKey).keycode
			return key
	return null


func _rpc_config(method: StringName) -> Dictionary:
	var script: Script = NetworkManager.get_script()
	if script == null or not script.has_method(&"get_rpc_config"):
		return {}
	var config: Variant = script.call(&"get_rpc_config")
	if not config is Dictionary:
		return {}
	var entry: Variant = (config as Dictionary).get(method, {})
	return entry if entry is Dictionary else {}


func _argument_names(method: StringName) -> Array[String]:
	var names: Array[String] = []
	var script: Script = NetworkManager.get_script()
	if script == null:
		return names
	for entry: Dictionary in script.get_script_method_list():
		if str(entry.get("name", "")) != String(method):
			continue
		for arg: Variant in entry.get("args", []):
			names.append(str((arg as Dictionary).get("name", "")))
		break
	return names


# --- the Input Map binding (SPEC-foundation's action table) ----------------


func test_slot_one_is_bound_to_the_input_maps_relic_active_1_action() -> void:
	var action: StringName = ActiveRelicController.action_for(ActiveRelicController.SLOT_1)
	assert_eq(action, &"relic_active_1", "slot 1 is the C slot SPEC-relics names")
	assert_true(InputMap.has_action(action), "%s is in the Input Map" % action)
	assert_false(InputMap.action_get_events(action).is_empty(),
		"%s is bound to at least one event" % action)
	assert_eq(ActiveRelicController.action_for(ActiveRelicController.SLOT_2), &"relic_active_2",
		"slot 2 is the B slot")
	assert_true(InputMap.has_action(&"relic_active_2"), "and it is bound too")


func test_a_press_of_the_input_maps_binding_resolves_to_its_slot() -> void:
	var one: InputEvent = _pressed_event_for(&"relic_active_1")
	var two: InputEvent = _pressed_event_for(&"relic_active_2")
	assert_not_null(one, "the Input Map binds a key to relic_active_1")
	assert_not_null(two, "the Input Map binds a key to relic_active_2")
	if one == null or two == null:
		return
	assert_eq(_controller.slot_of(one), ActiveRelicController.SLOT_1,
		"the event read out of the Input Map resolves to slot 1")
	assert_eq(_controller.slot_of(two), ActiveRelicController.SLOT_2,
		"the second binding resolves to slot 2")


func test_an_unbound_press_resolves_to_no_slot() -> void:
	var stranger := InputEventKey.new()
	stranger.physical_keycode = KEY_Z
	stranger.pressed = true
	assert_eq(_controller.slot_of(stranger), ActiveRelicController.NO_SLOT,
		"an event in no relic binding aims at no slot")
	assert_false(_controller.handle_input_event(stranger), "and nothing activates")


func test_a_press_activates_its_slot_and_a_release_or_echo_does_not() -> void:
	var press: InputEvent = _pressed_event_for(&"relic_active_1")
	assert_not_null(press, "the Input Map binds a key to relic_active_1")
	if press == null:
		return
	assert_true(_controller.handle_input_event(press), "the press activates slot 1")
	assert_eq(_stub.activations, 1, "the relic's own activate() ran once")
	var release: InputEventKey = (press as InputEventKey).duplicate() as InputEventKey
	release.pressed = false
	assert_false(_controller.handle_input_event(release), "a release activates nothing")
	var echo: InputEventKey = (press as InputEventKey).duplicate() as InputEventKey
	echo.echo = true
	assert_false(_controller.handle_input_event(echo), "an echo is not a second press")
	assert_eq(_stub.activations, 1, "neither the release nor the echo reached the relic")


# --- the slot's relic ------------------------------------------------------


func test_slot_one_holds_the_first_active_the_peer_holds() -> void:
	var slice: RunPlayerState = _slice(HOST_PEER)
	slice.relics.insert(0, PASSIVE_ID)
	var slot_one: RelicData = _controller.slot_data(ActiveRelicController.SLOT_1)
	assert_not_null(slot_one, "slot 1 resolves")
	if slot_one != null:
		assert_eq(slot_one.id, ACTIVE_ID, "a passive relic is not an active and is skipped")
	assert_null(_controller.slot_data(ActiveRelicController.SLOT_2),
		"one active held means slot 2 is empty")


func test_a_slot_with_no_active_relic_is_refused() -> void:
	assert_false(_controller.activate(ActiveRelicController.SLOT_2), "there is no second active")
	assert_eq(ActiveRelicController.last_refusal, ActiveRelicController.REFUSAL_NO_ACTIVE)
	assert_false(_controller.activate(99), "a slot outside the pair is not a slot")
	assert_eq(ActiveRelicController.last_refusal, ActiveRelicController.REFUSAL_BAD_SLOT)
	assert_eq(_stub.activations, 0, "nothing reached the relic")


func test_a_held_active_with_no_attached_effect_is_refused() -> void:
	var host: EffectHost = _player.get_node_or_null(NodePath(EffectHost.NODE_NAME)) as EffectHost
	assert_true(host.remove(_active), "the effect is detached, the relic still held")
	assert_false(_controller.activate(ActiveRelicController.SLOT_1))
	assert_eq(ActiveRelicController.last_refusal, ActiveRelicController.REFUSAL_NOT_ATTACHED,
		"the relic must be live, not only held (blocked on Dev A W2-A1 for the scene wiring)")
	assert_eq(_stub.activations, 0, "a detached effect is never asked to activate")


# --- charges ---------------------------------------------------------------


func test_an_active_with_three_charges_spends_one_per_activation() -> void:
	assert_eq(_controller.max_charges(ActiveRelicController.SLOT_1), CHARGES,
		"the pool is the relic's own active_charges")
	assert_eq(_controller.charges(ActiveRelicController.SLOT_1), CHARGES, "it starts full")
	var spent: int = 0
	for use: int in range(CHARGES):
		assert_true(_controller.activate(ActiveRelicController.SLOT_1),
			"use %d of %d applies" % [use + 1, CHARGES])
		spent += 1
		assert_eq(_controller.charges(ActiveRelicController.SLOT_1), CHARGES - spent,
			"one charge per activation")
		_controller.advance(COOLDOWN)
	assert_eq(_stub.activations, CHARGES, "the relic fired once per charge")
	assert_eq(_controller.charges(ActiveRelicController.SLOT_1), 0, "all three spent")


func test_a_charge_less_activation_is_refused() -> void:
	for use: int in range(CHARGES):
		assert_true(_controller.activate(ActiveRelicController.SLOT_1))
		_controller.advance(COOLDOWN)
	assert_false(_controller.activate(ActiveRelicController.SLOT_1),
		"with no charge left the activation is refused")
	assert_eq(ActiveRelicController.last_refusal, ActiveRelicController.REFUSAL_NO_CHARGES)
	assert_eq(_stub.activations, CHARGES, "the exhausted relic was not asked again")
	assert_eq(_announced.size(), CHARGES, "and nothing was announced for it")


# --- the cooldown ----------------------------------------------------------


func test_the_cooldown_is_the_relics_active_cooldown_and_the_fraction_runs_one_to_zero() -> void:
	assert_true(_controller.activate(ActiveRelicController.SLOT_1))
	assert_true(_controller.is_ready(ActiveRelicController.SLOT_1) == false,
		"the slot is on cooldown the moment it is used")
	assert_almost_eq(_controller.cooldown_fraction(ActiveRelicController.SLOT_1), 1.0, 0.0001,
		"the fraction starts at 1: the whole cooldown is left")
	assert_false(_controller.activate(ActiveRelicController.SLOT_1),
		"a second use inside the cooldown is refused")
	assert_eq(ActiveRelicController.last_refusal, ActiveRelicController.REFUSAL_ON_COOLDOWN)
	_controller.advance(COOLDOWN * 0.5)
	assert_almost_eq(_controller.cooldown_fraction(ActiveRelicController.SLOT_1), 0.5, 0.0001,
		"half the cooldown is two quarters of it")
	_controller.advance(COOLDOWN * 0.5)
	assert_almost_eq(_controller.cooldown_fraction(ActiveRelicController.SLOT_1), 0.0, 0.0001,
		"and it reaches 0 when the relic's own cooldown has passed")
	assert_true(_controller.is_ready(ActiveRelicController.SLOT_1), "the slot is usable again")
	assert_true(_controller.activate(ActiveRelicController.SLOT_1), "and the next use applies")


func test_the_node_ticks_its_own_cooldown_each_physics_frame() -> void:
	assert_true(_controller.activate(ActiveRelicController.SLOT_1))
	assert_almost_eq(_controller.cooldown_fraction(ActiveRelicController.SLOT_1), 1.0, 0.0001)
	await wait_physics_frames(3)
	assert_lt(_controller.cooldown_fraction(ActiveRelicController.SLOT_1), 1.0,
		"the cooldown runs without anyone calling advance()")


func test_a_relic_that_refuses_to_fire_spends_nothing() -> void:
	_stub.applies = false
	assert_false(_controller.activate(ActiveRelicController.SLOT_1),
		"the relic said no, so the activation did not apply")
	assert_eq(ActiveRelicController.last_refusal, ActiveRelicController.REFUSAL_EFFECT_REFUSED)
	assert_eq(_controller.charges(ActiveRelicController.SLOT_1), CHARGES, "no charge was spent")
	assert_almost_eq(_controller.cooldown_fraction(ActiveRelicController.SLOT_1), 0.0, 0.0001,
		"and no cooldown was started")
	assert_true(_announced.is_empty(), "nothing was announced")


# --- the room refill -------------------------------------------------------


func test_charges_refill_per_room_where_the_relic_says_so() -> void:
	_stub.refill_on_room = true
	assert_true(_controller.activate(ActiveRelicController.SLOT_1))
	assert_eq(_controller.charges(ActiveRelicController.SLOT_1), CHARGES - 1, "one spent")
	_enter_room_for(_player)
	assert_eq(_controller.charges(ActiveRelicController.SLOT_1), CHARGES,
		"the relic states its charges refill, so the room refills them")


func test_a_relic_that_does_not_say_so_keeps_its_spent_charges() -> void:
	assert_false(_stub.refill_on_room, "the fixture does not state a refill")
	assert_true(_controller.activate(ActiveRelicController.SLOT_1))
	_enter_room_for(_player)
	assert_eq(_controller.charges(ActiveRelicController.SLOT_1), CHARGES - 1,
		"the room is not a free reload for every active")


func test_another_players_room_does_not_refill_this_slot() -> void:
	_stub.refill_on_room = true
	assert_true(_controller.activate(ActiveRelicController.SLOT_1))
	var other: Node2D = _harness.make_player()
	_enter_room_for(other)
	assert_eq(_controller.charges(ActiveRelicController.SLOT_1), CHARGES - 1,
		"a room entered by somebody else is not this player's room")


func _enter_room_for(who: Player) -> void:
	var room := Node2D.new()
	add_child_autofree(room)
	Events.room_entered.emit(room, who)


# --- the host's request path (SPEC-relics "Multiplayer ownership") ---------


func test_a_client_never_applies_its_own_activation() -> void:
	_become_client()
	assert_false(_controller.activate(ActiveRelicController.SLOT_1),
		"only the host applies an activation")
	assert_eq(ActiveRelicController.last_refusal, ActiveRelicController.REFUSAL_NOT_HOST)
	assert_eq(_stub.activations, 0, "the client asked its own relic nothing")
	assert_eq(_controller.charges(ActiveRelicController.SLOT_1), CHARGES, "and spent nothing")


func test_a_clients_press_asks_the_host_and_applies_nothing() -> void:
	_become_client()
	assert_false(_controller.request_activation(ActiveRelicController.SLOT_1),
		"a session with no remote host sends nothing")
	assert_eq(_requests, [ActiveRelicController.SLOT_1] as Array[int],
		"the request was put on the wire half")
	assert_eq(_stub.activations, 0, "and the client applied no activation of its own")


func test_the_hosts_own_press_applies_directly() -> void:
	assert_true(NetworkManager.is_host, "the test session hosts")
	assert_true(_controller.request_activation(ActiveRelicController.SLOT_1),
		"solo and a hosting peer are the same code path")
	assert_eq(_stub.activations, 1, "the host's own use reached the relic")


func test_the_host_validates_and_applies_a_remote_clients_request() -> void:
	_guest_with_the_active()
	assert_true(ActiveRelicController.apply_activate_request(GUEST_PEER, ActiveRelicController.SLOT_1),
		"the host applies a valid request")
	assert_eq(_announced.size(), 1, "and announces it once")
	if not _announced.is_empty():
		assert_eq(int(_announced[0]["slot"]), ActiveRelicController.SLOT_1)
		assert_eq(_announced[0]["id"], ACTIVE_ID, "the announcement names the relic")


func test_the_host_refuses_a_request_it_cannot_honour() -> void:
	_guest_with_the_active()
	assert_false(ActiveRelicController.apply_activate_request(0, ActiveRelicController.SLOT_1),
		"a direct local call reports sender 0 and is not a client's request")
	assert_eq(ActiveRelicController.last_refusal, ActiveRelicController.REFUSAL_NOT_A_REQUEST)
	assert_false(ActiveRelicController.apply_activate_request(99, ActiveRelicController.SLOT_1),
		"a peer this machine has no player for cannot activate anything")
	assert_eq(ActiveRelicController.last_refusal, ActiveRelicController.REFUSAL_NO_PLAYER)
	var guest: ActiveRelicController = ActiveRelicController.for_player(NetworkManager.get_player(GUEST_PEER))
	_slice(GUEST_PEER).relics.clear()
	assert_false(ActiveRelicController.apply_activate_request(GUEST_PEER, ActiveRelicController.SLOT_1),
		"the peer holds no active in that slot")
	assert_eq(ActiveRelicController.last_refusal, ActiveRelicController.REFUSAL_NO_ACTIVE,
		"the host validated the requester's own slot state")
	assert_eq(guest.charges(ActiveRelicController.SLOT_1), 0, "and the refusals spent nothing")


func test_a_client_cannot_apply_another_peers_request() -> void:
	_become_client()
	assert_false(ActiveRelicController.apply_activate_request(GUEST_PEER, ActiveRelicController.SLOT_1))
	assert_eq(ActiveRelicController.last_refusal, ActiveRelicController.REFUSAL_NOT_HOST)


# --- the wire (SPEC-networking "RPC conventions") --------------------------


func test_request_activate_relic_is_a_client_to_host_request() -> void:
	var config: Dictionary = _rpc_config(&"request_activate_relic")
	assert_false(config.is_empty(), "request_activate_relic is declared with @rpc")
	assert_eq(config.get("rpc_mode"), MultiplayerAPI.RPC_MODE_ANY_PEER,
		"a client asks the host; the host did not originate the call")
	assert_eq(config.get("call_local"), false, "the caller does not run the host's half")
	assert_eq(config.get("transfer_mode"), MultiplayerPeer.TRANSFER_MODE_RELIABLE,
		"an activation is never dropped")
	assert_eq(_argument_names(&"request_activate_relic"), ["slot"] as Array[String],
		"the request carries a slot only, never an id or a value the host would trust")


func test_the_broadcast_is_host_to_everyone_and_runs_locally() -> void:
	var config: Dictionary = _rpc_config(&"relic_activated")
	assert_false(config.is_empty(), "relic_activated is declared with @rpc")
	assert_eq(config.get("rpc_mode"), MultiplayerAPI.RPC_MODE_AUTHORITY,
		"only the host announces an activation")
	assert_eq(config.get("call_local"), true, "the host's own screen sees it too")
	assert_eq(config.get("transfer_mode"), MultiplayerPeer.TRANSFER_MODE_RELIABLE,
		"an activation announcement is never dropped")
	assert_true(NetworkManager.has_method(&"send_activate_request"), "the client-side sender")
	assert_true(NetworkManager.has_method(&"route_relic_activated"), "the host-side router")
	assert_true(NetworkManager.has_method(&"apply_relic_activation"), "the receiving half")


func test_the_receiving_half_puts_the_activation_on_the_ui_signal() -> void:
	_received.clear()
	NetworkManager.relic_activated_received.connect(_on_activated_received)
	assert_true(NetworkManager.apply_relic_activation(GUEST_PEER, ActiveRelicController.SLOT_1, ACTIVE_ID),
		"a peer applies the host's activation broadcast")
	if NetworkManager.relic_activated_received.is_connected(_on_activated_received):
		NetworkManager.relic_activated_received.disconnect(_on_activated_received)
	assert_eq(_received.size(), 1, "the broadcast reaches the presentation layer once")
	if not _received.is_empty():
		assert_eq(int(_received[0]["peer_id"]), GUEST_PEER)
		assert_eq(int(_received[0]["slot"]), ActiveRelicController.SLOT_1)
		assert_eq(_received[0]["id"], ACTIVE_ID)


func test_the_controller_lives_in_the_relics_module() -> void:
	assert_true(FileAccess.file_exists(CONTROLLER_PATH), "%s exists" % CONTROLLER_PATH)
	var source: String = FileAccess.get_file_as_string(CONTROLLER_PATH)
	assert_true(source.contains("Sync:"), "every stateful script states who owns it and how it syncs")
	assert_true(source.contains("request_activate_relic"),
		"the controller names the request it is the host half of")


# --- time (SPEC-relics "Active relics"; SPEC-time-manager) -----------------


func test_an_enemy_time_stop_does_not_stall_the_cooldown() -> void:
	assert_true(_controller.activate(ActiveRelicController.SLOT_1))
	TimeManager.stop_enemies(10.0, TIME_SOURCE_STOP)
	assert_eq(TimeManager.scale_for(_player), 1.0, "a player ignores the global enemy stack")
	assert_almost_eq(_controller.time_scale(), 1.0, 0.0001,
		"the controller's clock is the player's, not the enemies'")
	_controller.advance(COOLDOWN * 0.5)
	assert_almost_eq(_controller.cooldown_fraction(ActiveRelicController.SLOT_1), 0.5, 0.0001,
		"a stopped enemy world does not freeze a player's relic")


func test_a_frozen_player_stalls_the_cooldown() -> void:
	assert_true(_controller.activate(ActiveRelicController.SLOT_1))
	TimeManager.set_entity_scale(_player, 0.0, 10.0, TIME_SOURCE_ENTITY)
	assert_almost_eq(_controller.time_scale(), 0.0, 0.0001,
		"the controller reads the player's own TimeManager scale")
	_controller.advance(COOLDOWN)
	assert_almost_eq(_controller.cooldown_fraction(ActiveRelicController.SLOT_1), 1.0, 0.0001,
		"time that did not pass for the player did not pass for its cooldown")
	TimeManager.clear_source(TIME_SOURCE_ENTITY)
	_controller.advance(COOLDOWN)
	assert_almost_eq(_controller.cooldown_fraction(ActiveRelicController.SLOT_1), 0.0, 0.0001,
		"and it runs again once the player is unfrozen")
