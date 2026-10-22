extends GutTest
## Tests for the revive contract: `request_revive` and the host revive rule
## (SPEC-player-controller "Downed and revive", SPEC-networking "Requests from
## client to host", SPEC-run-economy's death and extraction rules). Owned by
## networking (PR into player.gd, Dev A reviews).
##
## The rule this file pins down:
##  * `request_revive` is the client -> host half, declared
##    `@rpc("any_peer", "call_remote", "reliable")` and validating
##    `multiplayer.get_remote_sender_id()`, so a client cannot revive anybody by
##    calling it itself -- SPEC-run-economy's ruling that a client never revives
##    on its own authority;
##  * the host refuses a revive of a peer that is not downed, of a peer that is
##    already dead for this floor, of a caller with no player of its own, of a
##    caller reviving itself, and of a caller standing further than
##    REVIVE_RANGE from the teammate;
##  * a valid request applies exactly one revive: the target stands, its run
##    slice's downed flag clears so `RunPlayerState.is_standing()` is true again,
##    the target's own `revived(by)` fires once, and `Events.player_revived`
##    fires once.
##
## The player nodes here are the real scene, added to the tree, because the
## revive range reads their positions; the extra peers are registered with
## NetworkManager the way PlayerSpawner does once a spawn has completed.
##
## after_each ends any live run and drops the session before the asserts are
## torn down, so no autoload state leaks into the next file (LESSONS: autoload
## state bleeds across GUT files).

## The peer ids a single-process test uses for the three roles. The real ids
## arrive over ENet; 1 is always the host (NetworkManager.HOST_PEER_ID).
const HOST_PEER: int = 1
const CLIENT_PEER: int = 2
const THIRD_PEER: int = 3
const FORCED_SEED: int = 4242

const PLAYER_SCENE := "res://scenes/player/player.tscn"

## peer_id -> the real player node registered for it this test.
var _players: Dictionary[int, Player] = {}
var _scene: PackedScene


func before_each() -> void:
	_scene = load(PLAYER_SCENE) as PackedScene
	_players.clear()
	GameState.run = null
	GameState.forced_seed = 0
	GameState.last_run_summary = ""
	GameState.last_advance_refusal = GameState.ADVANCE_REFUSAL_NONE
	NetworkManager.last_revive_refusal = NetworkManager.REVIVE_REFUSAL_NONE


func after_each() -> void:
	# A live run holds the Events subscriptions open; ending it is also what a
	# real quit does, so cleanup uses the public path rather than poking at the
	# private handlers.
	if GameState.run != null and NetworkManager.is_host:
		GameState.end_run(RunEndReason.Reason.ABORT)
	GameState.run = null
	GameState.forced_seed = 0
	GameState.last_run_summary = ""
	GameState.last_advance_refusal = GameState.ADVANCE_REFUSAL_NONE
	NetworkManager.disconnect_all()
	NetworkManager.last_revive_refusal = NetworkManager.REVIVE_REFUSAL_NONE


# --- the revive numbers -----------------------------------------------------

func test_the_revive_numbers_are_the_specs() -> void:
	# SPEC-player-controller "Downed and revive": hold interact within 48 px for
	# 3 s to revive to 40% HP.
	assert_eq(NetworkManager.REVIVE_RANGE, 48.0, "teammates revive within 48 px")
	assert_eq(NetworkManager.REVIVE_SECONDS, 3.0, "the hold takes 3 s")
	assert_eq(NetworkManager.REVIVE_HP_FRACTION, 0.4, "and the revived player comes back at 40% HP")


func test_revive_seconds_scale_with_the_revivers_speed_multiplier() -> void:
	# SPEC-player-controller: "Revive speed multipliers come from StatBlock via a
	# revive_speed_mult stat-like field (Field Medic, Sanctuary)". A larger
	# multiplier means a shorter hold.
	var holder := _join(CLIENT_PEER)
	assert_eq(NetworkManager.revive_seconds_for(holder), NetworkManager.REVIVE_SECONDS, "no modifier: the base 3 s")
	holder.revive_speed_mult = 2.0
	assert_eq(NetworkManager.revive_seconds_for(holder), 1.5, "Field Medic twice as fast is half the hold")
	assert_eq(NetworkManager.revive_seconds_for(null), NetworkManager.REVIVE_SECONDS, "no reviver: the base hold")


func test_a_nonsense_speed_multiplier_cannot_make_the_hold_infinite() -> void:
	# A zero or negative multiplier would divide the hold to infinity or past it.
	var holder := _join(CLIENT_PEER)
	holder.revive_speed_mult = 0.0
	var floored: float = NetworkManager.revive_seconds_for(holder)
	assert_true(is_finite(floored), "the hold stays a real number")
	assert_eq(floored, NetworkManager.REVIVE_SECONDS / NetworkManager.REVIVE_SPEED_MULT_MIN)
	holder.revive_speed_mult = -1.0
	assert_eq(NetworkManager.revive_seconds_for(holder), floored, "a negative multiplier behaves like the floor")


func test_the_revived_player_comes_back_at_forty_percent_hp() -> void:
	assert_eq(NetworkManager.revive_hp_for(100), 40, "100 max HP revives at 40")
	assert_eq(NetworkManager.revive_hp_for(250), 100, "250 max HP revives at 100")
	assert_eq(NetworkManager.revive_hp_for(7), 3, "7 max HP revives at 3, rounded to a whole HP")
	assert_eq(NetworkManager.revive_hp_for(1), 1, "a revive never comes back at 0 HP")
	assert_eq(NetworkManager.revive_hp_for(0), 1, "and never at a negative HP")


# --- the RPC contract -------------------------------------------------------

func test_request_revive_is_a_client_to_host_request() -> void:
	var config: Dictionary = _rpc_config(&"request_revive")
	assert_false(config.is_empty(), "request_revive is declared with @rpc")
	assert_eq(config.get("rpc_mode"), MultiplayerAPI.RPC_MODE_ANY_PEER,
		"a client asks the host; the host did not originate the call")
	assert_eq(config.get("call_local"), false, "the caller does not run the host's half")
	assert_eq(config.get("transfer_mode"), MultiplayerPeer.TRANSFER_MODE_RELIABLE, "a revive is never dropped")
	assert_eq(_argument_names(&"request_revive"), ["target_peer_id"] as Array[String],
		"the request carries an id, never a position or a value the host would trust (SPEC-networking)")


func test_the_spec_interface_exists_on_both_halves() -> void:
	# SPEC-player-controller declares `func request_revive(target: Player)` as the
	# client's entry point; this module owns the transport it forwards to.
	assert_true(NetworkManager.has_method(&"request_revive"), "the RPC exists")
	assert_true(NetworkManager.has_method(&"send_revive_request"), "and the client-side sender")
	assert_true(NetworkManager.has_method(&"can_apply_revive_request"), "and the host's seam")
	var player: Player = _join(HOST_PEER)
	assert_true(player.has_method(&"request_revive"), "the player's own entry point exists")


func test_a_local_call_is_not_a_clients_request() -> void:
	# The body validates `multiplayer.get_remote_sender_id()` first: a direct
	# local call reports sender 0 everywhere, so a peer cannot revive by calling
	# the request on itself instead of sending it to the host.
	_host()
	var target: Player = _join(CLIENT_PEER)
	target.is_downed = true
	watch_signals(Events)
	NetworkManager.request_revive(CLIENT_PEER)
	assert_true(target.is_downed, "an unvalidated local call revives nobody")
	assert_signal_not_emitted(Events, "player_revived")
	assert_eq(NetworkManager.last_revive_refusal, NetworkManager.REVIVE_REFUSAL_NOT_A_REQUEST,
		"sender 0 is not a client's request")
	assert_push_warning("revive refused")


# --- the host's refusals ----------------------------------------------------

func test_the_host_refuses_a_revive_asked_of_a_client() -> void:
	_become_client()
	var target: Player = _join(THIRD_PEER)
	target.is_downed = true
	assert_eq(NetworkManager.revive_refusal_reason(CLIENT_PEER, target), NetworkManager.REVIVE_REFUSAL_NOT_HOST)
	assert_false(NetworkManager.can_apply_revive_request(CLIENT_PEER, target))
	var accepted: bool = NetworkManager.apply_revive_request(CLIENT_PEER, target)
	assert_false(accepted, "only the host applies a revive")
	assert_true(target.is_downed, "the downed flag is untouched on a client")


func test_the_host_refuses_a_revive_of_a_peer_that_is_not_downed() -> void:
	_host()
	var target: Player = _join(CLIENT_PEER)
	assert_false(target.is_downed, "the teammate is standing")
	assert_eq(NetworkManager.revive_refusal_reason(HOST_PEER, target), NetworkManager.REVIVE_REFUSAL_TARGET_NOT_DOWNED)
	assert_false(NetworkManager.apply_revive_request(HOST_PEER, target))


func test_the_host_refuses_a_revive_of_a_peer_that_is_dead_this_floor() -> void:
	# SPEC-player-controller: bleed-out timeout is "Dead for the rest of the
	# floor"; reviving at the next floor start is week 5.
	_host()
	var victim: Player = _join(THIRD_PEER)
	_start_run([HOST_PEER, CLIENT_PEER, THIRD_PEER])
	Events.player_downed.emit(victim)
	Events.player_died.emit(victim)
	assert_true(_slice(THIRD_PEER).is_dead, "the run slice knows the teammate died")
	victim.is_downed = true
	assert_eq(NetworkManager.revive_refusal_reason(CLIENT_PEER, victim), NetworkManager.REVIVE_REFUSAL_TARGET_DEAD)
	assert_false(NetworkManager.apply_revive_request(CLIENT_PEER, victim))
	assert_true(victim.is_downed, "a dead teammate stays down for the rest of the floor")


func test_the_host_refuses_a_reviver_with_no_player_of_its_own() -> void:
	_host()
	var target: Player = _join(CLIENT_PEER)
	target.is_downed = true
	assert_false(NetworkManager.players.has(THIRD_PEER), "peer 3 has no player on this peer")
	assert_eq(NetworkManager.revive_refusal_reason(THIRD_PEER, target), NetworkManager.REVIVE_REFUSAL_NO_REVIVER)
	assert_false(NetworkManager.apply_revive_request(THIRD_PEER, target))
	assert_true(target.is_downed, "a caller nobody can place revives nobody")


func test_the_host_refuses_a_revive_of_an_unknown_peer() -> void:
	_host()
	assert_eq(NetworkManager.revive_refusal_reason(CLIENT_PEER, null), NetworkManager.REVIVE_REFUSAL_NO_TARGET)
	assert_false(NetworkManager.apply_revive_request(CLIENT_PEER, null))


func test_the_host_refuses_a_player_reviving_itself() -> void:
	# SPEC-player-controller: "Teammates hold interact", and the self-revive
	# paths (Second Wind, Undying, Phoenix) intercept at Health.about_to_die
	# before the down, so they are not a revive request.
	_host()
	var alone: Player = _join(CLIENT_PEER)
	alone.is_downed = true
	assert_eq(NetworkManager.revive_refusal_reason(CLIENT_PEER, alone), NetworkManager.REVIVE_REFUSAL_SELF)
	assert_false(NetworkManager.apply_revive_request(CLIENT_PEER, alone))
	assert_true(alone.is_downed)


func test_the_reviver_must_stand_within_revive_range() -> void:
	_host()
	var holder: Player = _join(CLIENT_PEER)
	var target: Player = _join(THIRD_PEER)
	target.is_downed = true
	target.position = Vector2.ZERO

	holder.position = Vector2(NetworkManager.REVIVE_RANGE + 1.0, 0.0)
	assert_eq(NetworkManager.revive_distance(holder, target), NetworkManager.REVIVE_RANGE + 1.0)
	assert_eq(NetworkManager.revive_refusal_reason(CLIENT_PEER, target), NetworkManager.REVIVE_REFUSAL_OUT_OF_RANGE)
	assert_false(NetworkManager.apply_revive_request(CLIENT_PEER, target), "a teammate across the room cannot revive")
	assert_true(target.is_downed)

	holder.position = Vector2(NetworkManager.REVIVE_RANGE, 0.0)
	assert_eq(NetworkManager.revive_refusal_reason(CLIENT_PEER, target), NetworkManager.REVIVE_REFUSAL_NONE,
		"exactly at the range is inside it")
	assert_true(NetworkManager.apply_revive_request(CLIENT_PEER, target), "and the revive applies")


# --- a valid request --------------------------------------------------------

func test_a_valid_request_stands_the_teammate_up() -> void:
	_host()
	var holder: Player = _join(CLIENT_PEER)
	var target: Player = _join(THIRD_PEER)
	target.is_downed = true
	assert_false(target.simulates, "a downed player runs no states")
	assert_true(NetworkManager.can_apply_revive_request(CLIENT_PEER, target))
	assert_true(NetworkManager.apply_revive_request(CLIENT_PEER, target), "the host applied the revive")
	assert_false(target.is_downed, "the teammate is standing")
	assert_true(target.simulates, "and simulates its own states again")
	assert_eq(NetworkManager.last_revive_refusal, NetworkManager.REVIVE_REFUSAL_NONE)
	assert_true(holder.position.distance_to(target.position) <= NetworkManager.REVIVE_RANGE, "the holder was in range")


func test_a_valid_request_emits_the_bus_event_exactly_once() -> void:
	_host()
	var holder: Player = _join(CLIENT_PEER)
	var target: Player = _join(THIRD_PEER)
	target.is_downed = true
	watch_signals(Events)
	NetworkManager.apply_revive_request(CLIENT_PEER, target)
	# GUT reads a fourth argument as an emission index, not as a label, so this
	# assertion takes no trailing message.
	assert_signal_emitted_with_parameters(Events, "player_revived", [target, holder])
	assert_signal_emit_count(Events, "player_revived", 1, "one revive, one bus event")


func test_the_revived_player_gets_its_own_revived_signal_naming_who_did_it() -> void:
	# SPEC-player-controller declares `signal revived(by: Player)`. W3-B4a left it
	# to the revive path to emit, because only a revive knows who did it.
	_host()
	var holder: Player = _join(CLIENT_PEER)
	var target: Player = _join(THIRD_PEER)
	target.is_downed = true
	watch_signals(target)
	NetworkManager.apply_revive_request(CLIENT_PEER, target)
	assert_signal_emitted_with_parameters(target, "revived", [holder])
	assert_signal_emit_count(target, "revived", 1)


func test_a_repeated_request_revives_nothing_a_second_time() -> void:
	_host()
	var target: Player = _join(THIRD_PEER)
	_join(CLIENT_PEER)
	target.is_downed = true
	watch_signals(Events)
	assert_true(NetworkManager.apply_revive_request(CLIENT_PEER, target))
	assert_false(NetworkManager.apply_revive_request(CLIENT_PEER, target), "the teammate is already standing")
	assert_eq(NetworkManager.last_revive_refusal, NetworkManager.REVIVE_REFUSAL_TARGET_NOT_DOWNED)
	assert_signal_emit_count(Events, "player_revived", 1, "one down is worth one revive")


func test_a_client_cannot_revive_on_its_own_authority() -> void:
	# SPEC-run-economy: the host decides. A client's call must change nothing
	# locally, whichever of the two entry points it uses.
	_become_client()
	var holder: Player = _join(CLIENT_PEER)
	var target: Player = _join(THIRD_PEER)
	target.is_downed = true
	watch_signals(Events)
	watch_signals(target)
	player_request_revive(holder, target)
	NetworkManager.request_revive(THIRD_PEER)
	assert_true(target.is_downed, "the client's copy stays downed")
	assert_signal_not_emitted(Events, "player_revived")
	assert_signal_not_emitted(target, "revived")


func test_the_client_half_reports_when_there_is_no_host_to_ask() -> void:
	# Solo, a hosting peer, and a single-process test all have no remote host, so
	# the request is recorded and reported rather than sent into nowhere.
	_become_client()
	watch_signals(NetworkManager)
	assert_false(NetworkManager.send_revive_request(THIRD_PEER), "nothing was sent")
	assert_signal_emitted_with_parameters(NetworkManager, "revive_requested", [THIRD_PEER])
	assert_push_warning("no remote host")


# --- the run slice ----------------------------------------------------------

func test_the_run_slice_leaves_the_downed_state_and_stands_again() -> void:
	# The criterion the week-3 checkpoint is written against: the revived slice
	# leaves the downed state and is_standing() is true again.
	_host()
	var victim: Player = _join(THIRD_PEER)
	_join(CLIENT_PEER)
	_start_run([HOST_PEER, CLIENT_PEER, THIRD_PEER])
	Events.player_downed.emit(victim)
	assert_true(_slice(THIRD_PEER).is_downed, "the down reached the run slice")
	assert_false(_slice(THIRD_PEER).is_standing())
	victim.is_downed = true
	assert_true(NetworkManager.apply_revive_request(CLIENT_PEER, victim), "the host applied the revive")
	assert_false(_slice(THIRD_PEER).is_downed, "the slice left the downed state")
	assert_true(_slice(THIRD_PEER).is_standing(), "and the player is standing again")


func test_a_revive_does_not_resurrect_a_dead_slice() -> void:
	_host()
	var victim: Player = _join(THIRD_PEER)
	_start_run([HOST_PEER, CLIENT_PEER, THIRD_PEER])
	Events.player_downed.emit(victim)
	Events.player_died.emit(victim)
	NetworkManager.apply_revive_request(CLIENT_PEER, victim)
	assert_true(_slice(THIRD_PEER).is_dead, "a dead player is dead for the rest of the floor")
	assert_false(_slice(THIRD_PEER).is_standing())


func test_one_revive_ends_the_defeat_press_when_another_player_stands() -> void:
	# The revive is what makes the all-downed rule survivable: two players go
	# down in turn, the second is revived, and the run is still live.
	_host()
	_join(HOST_PEER)
	var first: Player = _join(CLIENT_PEER)
	var second: Player = _join(THIRD_PEER)
	_start_run([HOST_PEER, CLIENT_PEER, THIRD_PEER])
	Events.player_downed.emit(first)
	assert_true(GameState.run != null, "one player down is not the end of the run")
	Events.player_downed.emit(second)
	assert_true(GameState.run != null, "and neither is two, while the host still stands")
	second.is_downed = true
	assert_true(NetworkManager.apply_revive_request(HOST_PEER, second))
	assert_false(_slice(THIRD_PEER).is_downed)
	assert_true(GameState.run != null, "the run is still live after the revive")


func test_a_run_that_is_over_does_not_record_a_revive() -> void:
	# An ended run stops listening, so a late revive cannot move a cleared run.
	_host()
	var victim: Player = _join(THIRD_PEER)
	_join(CLIENT_PEER)
	_start_run([HOST_PEER, CLIENT_PEER, THIRD_PEER])
	Events.player_downed.emit(victim)
	GameState.end_run(RunEndReason.Reason.ABORT)
	victim.is_downed = true
	assert_true(NetworkManager.apply_revive_request(CLIENT_PEER, victim), "the revive still applies to the player")
	assert_true(GameState.run == null, "but there is no run left to record it in")


# --- helpers ----------------------------------------------------------------

## Starts the host session every host-rule test runs in. A solo session is a
## host with one peer, the same code path co-op uses.
func _host() -> void:
	NetworkManager.start_solo()
	assert_true(NetworkManager.is_host, "test session is a host")


## Puts NetworkManager in the client role a single-process test can drive:
## joined, not hosting. The real client peer id arrives over ENet, so
## CLIENT_PEER stands for it here.
func _become_client() -> void:
	NetworkManager.start_solo()
	NetworkManager.is_host = false
	NetworkManager.local_peer_id = CLIENT_PEER
	NetworkManager.peer_ids = [HOST_PEER, CLIENT_PEER] as Array[int]


## Spawns the real player scene for `peer_id` and registers it the way
## PlayerSpawner does once a spawn completes. The node enters the tree because
## the revive range reads positions.
func _join(peer_id: int) -> Player:
	var player := _scene.instantiate() as Player
	add_child_autofree(player)
	player.peer_id = peer_id
	NetworkManager.players[peer_id] = player
	_players[peer_id] = player
	return player


## Calls the spec's own client entry point on a player: `Player.request_revive`
## is declared by SPEC-player-controller, so the test drives that name rather
## than reaching for the transport behind it.
func player_request_revive(holder: Player, target: Player) -> void:
	holder.request_revive(target)


## Starts a host run for the given peers with the forced seed, so every test run
## is reproducible.
func _start_run(peer_ids: Array[int]) -> void:
	GameState.forced_seed = FORCED_SEED
	var party: Array[PlayerSpawnInfo] = []
	for peer_id: int in peer_ids:
		party.append(PlayerSpawnInfo.new(peer_id))
	GameState.start_run(0, 1, party)
	assert_true(GameState.run != null, "test run is live")


func _slice(peer_id: int) -> RunPlayerState:
	return GameState.run.get_player(peer_id)


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
