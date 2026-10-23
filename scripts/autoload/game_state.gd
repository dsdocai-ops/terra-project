extends Node
## Run data and persistent data. Owned by run-economy.
## start_run / next_floor / end_run are the run loop's spine: the host builds a
## RunState from the party, advances floors, and ends the run with a RunResult
## that run_ended hands to the death/extract screen. Rope rooms, floor
## generation, networking, the HUD and the debug console all call or listen
## here (SPEC-run-economy).
## The host also owns the run's failure branch: it watches player_downed /
## player_died and ends the run with DEFEAT once nobody is left standing,
## printing the placeholder death/extract summary (W3-B2b).
## Sync: run state, votes and loot rolls are host-authoritative; per-player
## totals are sent to their owning peer. Clients call request_* and read the
## past-tense broadcasts. See SPEC-run-economy.

signal run_started(run_seed: int)
signal floor_changed(floor_index: int, biome: Resource)
signal run_ended(result: RefCounted)

## The lowest and highest seed a host roll may produce. 0 as a seed means
## "roll one", so the range never contains 0.
const MIN_RUN_SEED: int = 1
const MAX_RUN_SEED: int = 2147483646

## Why the most recent next_floor() call was refused. Recorded so a refusal is
## a readable reason rather than only a log line: the debug console (W3-B5)
## and the exit-door UI both want to say why the door will not open.
const ADVANCE_REFUSAL_NONE: StringName = &""
const ADVANCE_REFUSAL_NOT_HOST: StringName = &"not_host"
const ADVANCE_REFUSAL_NO_RUN: StringName = &"no_run"
const ADVANCE_REFUSAL_EXIT_SHUT: StringName = &"exit_shut"
const ADVANCE_REFUSAL_LAST_FLOOR: StringName = &"last_floor"

## The three words the end-of-run summary prints for a player. Kept as
## constants so the death/extract screen (week 5) and the tests read the same
## strings the placeholder log line writes.
const PLAYER_STATUS_STANDING: String = "standing"
const PLAYER_STATUS_DOWNED: String = "downed"
const PLAYER_STATUS_DEAD: String = "dead"

## The live World scene. Modules reach World/Players etc. through this,
## never by absolute path.
var world: World = null
## The live run; null in town and after end_run().
var run: RunState = null
## TODO(save-system): PlayerProfile, alias of SaveManager.profile.
var profile: RefCounted = null
## Seed forced from the command line (--seed=<int>); 0 means roll one.
var forced_seed: int = 0
## Why the last next_floor() call was refused; ADVANCE_REFUSAL_NONE when it
## advanced (or when next_floor() has not run). Reset by every call.
var last_advance_refusal: StringName = ADVANCE_REFUSAL_NONE
## The end-of-run summary line the last end_run() printed (or "" before the
## first run ends). The placeholder death/extract screen is one print until
## ui-hud builds the real panel (week 5); keeping the text here makes what the
## player sees readable from code and from tests, not only from a log.
var last_run_summary: String = ""
## The floor the host's floor_ready named, recorded on a client so the HUD and
## anything else that follows the floor can read it without a RunState. 0 until
## the host has declared a floor (W3-B3a).
var remote_floor_index: int = 0
## The modifiers the host named for that floor.
var remote_floor_modifiers: Array[int] = []
## The last floor on which this peer's own generated layout disagreed with the
## host's, and the two hashes involved: 0/0/0 while the peers have agreed on
## every floor. SPEC-networking "Seed sync" makes a mismatch an error the client
## recovers from by taking the host's layout; this is that fact as a value the
## code and the log can both read, rather than a log line alone (W3-B3b).
var floor_divergence_floor: int = 0
var floor_divergence_local_hash: int = 0
var floor_divergence_host_hash: int = 0


## Host only. Starts a run: resolves the seed, builds the RunState at
## `start_floor`, fills one RunPlayerState per party member, and emits
## run_started. `party` is an Array of PlayerSpawnInfo. A second call replaces
## the live run — call end_run() first if that is not what you want.
func start_run(run_seed: int, start_floor: int, party: Array) -> void:
	if not NetworkManager.is_host:
		push_warning("[run] start_run refused: the host owns run state")
		return
	if run != null:
		push_warning("[run] start_run replaced a live run; call end_run() first")
	var resolved_seed: int = _resolve_run_seed(run_seed)
	run = RunState.new(resolved_seed, start_floor)
	for entry: Variant in party:
		var info: PlayerSpawnInfo = entry as PlayerSpawnInfo
		if info == null:
			push_warning("[run] party entry is not a PlayerSpawnInfo; skipped")
			continue
		run.add_player(_slice_from(info))
	_subscribe_room_cleared()
	_subscribe_player_events()
	run_started.emit(resolved_seed)
	Events.run_started.emit(resolved_seed)
	print("[run] started seed %d at floor %d with %d player(s)" % [resolved_seed, run.floor_index, run.players.size()])


## Host only. Moves to the next floor, recomputes the biome and emits
## floor_changed. Refused past floor 30 (the floor-30 boss is the ending, from
## story-dialogue in week 10) and while the current floor's exit is still shut.
## Every refusal records why in `last_advance_refusal`.
func next_floor() -> void:
	last_advance_refusal = ADVANCE_REFUSAL_NONE
	if not NetworkManager.is_host:
		_refuse_advance(ADVANCE_REFUSAL_NOT_HOST, "the host owns floor state")
		return
	if run == null:
		_refuse_advance(ADVANCE_REFUSAL_NO_RUN, "no run is live")
		return
	if not can_advance_floor():
		_refuse_advance(ADVANCE_REFUSAL_EXIT_SHUT, "floor %d's exit is still shut (%d of %d room(s) cleared)" % [
			run.floor_index, run.rooms_cleared, run.required_rooms_cleared])
		return
	if not run.advance_floor():
		_refuse_advance(ADVANCE_REFUSAL_LAST_FLOOR, "floor %d is the last floor" % run.floor_index)
		return
	floor_changed.emit(run.floor_index, _biome_for(run))
	print("[run] floor %d (biome %d)" % [run.floor_index, run.biome_index])


## True when the live run's current floor may be left: a run exists and its
## exit is open. The room-clear counters behind this are written by the host
## (`_on_room_cleared`), and `required_rooms_cleared` is the seam Dev A's Exit
## rule writes into — blocked on Dev A (W3-A2) for the concrete determinant
## (all COMBAT/ELITE_COMBAT rooms on a Start-Exit path), so until it lands the
## field is whatever the generated floor sets and 0 means "nothing required".
## Reading it on a client is safe; only the host's next_floor() acts on it.
func can_advance_floor() -> bool:
	return run != null and run.exit_open


## Client only. The host's floor_ready named a floor; this peer has already
## generated its layout locally (NetworkManager) and now records which floor it
## is, so the HUD and everything else that follows the floor agrees with the
## host. Refused on the host, which owns the live run and emits floor_changed
## from next_floor() itself — accepting a remote floor there would also loop:
## this signal is what the host broadcasts on.
func apply_remote_floor(floor_index: int, biome_id: int, modifiers: Array[int]) -> bool:
	if NetworkManager.is_host:
		push_warning("[run] apply_remote_floor refused: the host owns floor state")
		return false
	remote_floor_index = floor_index
	remote_floor_modifiers.assign(modifiers)
	floor_changed.emit(floor_index, biome_for_index(biome_id))
	print("[run] client follows the host to floor %d (biome %d)" % [floor_index, biome_id])
	return true


## The biome resource a floor's biome id names. This is the single swap point
## for Dev A's BiomeData (blocked on Dev A W3-A1/A6): when it lands this returns
## BiomeData and BiomePlaceholder is deleted.
func biome_for_index(biome_id: int) -> Resource:
	return BiomePlaceholder.from_index(biome_id)


## Client side. Records that this peer generated a different floor from the
## host's for `floor_index` (SPEC-networking "Seed sync": the client logs an
## error and falls back to the host's layout). Written by networking when the
## hash assertion fails, so a divergence is provable from code and from the
## end-of-run summary rather than only from a log line.
func note_floor_divergence(floor_index: int, local_hash: int, host_hash: int) -> void:
	floor_divergence_floor = floor_index
	floor_divergence_local_hash = local_hash
	floor_divergence_host_hash = host_hash


## True once a layout-hash divergence has been recorded this session.
func has_floor_divergence() -> bool:
	return floor_divergence_floor != 0


## Records why an advance was refused and logs it once. Called from every
## refusal branch of next_floor(), so `last_advance_refusal` is never stale.
func _refuse_advance(reason: StringName, detail: String) -> void:
	last_advance_refusal = reason
	push_warning("[run] next_floor refused: %s" % detail)


## Host only. Counts one cleared room towards the current floor's exit
## requirement. Connected in start_run and disconnected in end_run, so an ended
## run never keeps counting. Guarded rather than subscribed conditionally,
## because Events is a global bus a client's own Room nodes might also drive.
func _on_room_cleared(_room: Node) -> void:
	if not NetworkManager.is_host:
		return
	if run == null:
		return
	run.rooms_cleared += 1


## Host only. One player went down (SPEC-player-controller's player_downed).
## Marks the run slice and ends the run with DEFEAT once nobody is left
## standing: SPEC-run-economy's "run ends when every player is downed or dead",
## and BRIEF Assumption 7 — downed counts as not living, so a solo run ends on
## its first down. Guarded rather than subscribed conditionally, because Events
## is a global bus clients also drive; the run's own downed flags stay
## host-authoritative.
func _on_player_downed(player: Player) -> void:
	if not _is_tracking_run():
		return
	var slice: RunPlayerState = _slice_for(player)
	if slice == null or slice.is_downed:
		# A repeat for an already-downed player is not a second loss.
		return
	slice.is_downed = true
	_check_run_defeat()


## Host only. One player died (SPEC-player-controller's player_died). A dead
## player never stands again this run, so this is the same all-downed check as
## a down — the slice keeps `is_dead` apart from `is_downed` only so the
## summary can say which happened.
func _on_player_died(player: Player) -> void:
	if not _is_tracking_run():
		return
	var slice: RunPlayerState = _slice_for(player)
	if slice == null:
		return
	slice.is_dead = true
	_check_run_defeat()


## Host only. A downed teammate stood back up (W3-B4b's revive). Clears the
## slice's downed flag, so `is_standing()` is true again and the all-downed rule
## counts this player as living once more. The route is the same one a down
## takes: the host applies the revive and `Events.player_revived` reaches here on
## every peer. A dead slice is left dead — SPEC-player-controller's "Dead for the
## rest of the floor", with the next-floor revive in week 5 — and only the
## `is_downed` half is written, so nothing here can resurrect one.
func _on_player_revived(player: Player, _by: Player) -> void:
	if not _is_tracking_run():
		return
	var slice: RunPlayerState = _slice_for(player)
	if slice == null:
		return
	slice.is_downed = false


## True when a player event belongs to a live run owned by this peer: nobody
## else may move the run's downed flags.
func _is_tracking_run() -> bool:
	return NetworkManager.is_host and run != null


## The run slice of the player an event named, or null when the event is not
## ours to act on. Warns rather than failing silently, so a stray event is
## visible in the log.
func _slice_for(player: Player) -> RunPlayerState:
	if player == null:
		push_warning("[run] a player event named no player; ignored")
		return null
	var slice: RunPlayerState = run.get_player(player.peer_id)
	if slice == null:
		push_warning("[run] peer %d is not in this run; its event is ignored" % player.peer_id)
	return slice


## Host only. Ends the run with DEFEAT when no player is left standing
## (BRIEF Assumption 7). Run after every downed and dead event. end_run()
## clears `run` before it emits, so a listener that ends the run again, and any
## further event from the same frame, lands on the null guard instead: the run
## ends exactly once.
func _check_run_defeat() -> void:
	if run == null:
		return
	for peer_id: int in run.players:
		var slice: RunPlayerState = run.get_player(peer_id)
		if slice != null and slice.is_standing():
			return
	print("[run] every player is downed or dead; ending the run")
	end_run(RunEndReason.Reason.DEFEAT)


## The status word for one player in the summary line.
static func player_status_word(slice: RunPlayerState) -> String:
	if slice == null:
		return PLAYER_STATUS_STANDING
	if slice.is_dead:
		return PLAYER_STATUS_DEAD
	if slice.is_downed:
		return PLAYER_STATUS_DOWNED
	return PLAYER_STATUS_STANDING


## The one-line end-of-run summary: why the run stopped, its seed, how far the
## party got and how each player ended up. It is the placeholder death/extract
## screen (W3-B2 acceptance text) until ui-hud builds the real panel in week 5.
## `finished` is the run as it was at the moment it ended, because end_run()
## has already cleared the live one.
func _run_summary_line(result: RunResult, finished: RunState) -> String:
	var standings: PackedStringArray = PackedStringArray()
	if finished != null:
		for peer_id: int in finished.players:
			standings.append("%d %s" % [peer_id, player_status_word(finished.get_player(peer_id))])
	return "[run] %s — seed %d, floors cleared %d, players: %s" % [
		RunEndReason.Reason.keys()[result.reason],
		result.seed,
		result.floors_cleared,
		", ".join(standings) if not standings.is_empty() else "none",
	]


## Host only. One rope vote, arrived over the wire or sent by the host's own
## prompt (NetworkManager.request_vote_rope is the transport; this is Owned by
## run-economy (week 5)). A solo run extracts immediately — there is nobody
## else to agree with. In co-op a yes is recorded and, once every living
## player (not downed, not dead) has voted yes, the run ends with EXTRACT; a
## `no` cancels the call and empties the tally, so the rope stays usable and
## the next use starts fresh (BRIEF Assumptions 1–6). Downed and dead players
## neither vote nor count towards the unanimity, so a living player's yes
## extracts even with a downed teammate waiting on a revive. Every change is
## broadcast through Events.rope_vote_updated so every peer sees the same vote
## state; the vote prompt UI itself is week-5 scope and stays out of here.
func request_extract_vote(peer_id: int, yes: bool) -> void:
	if not NetworkManager.is_host:
		push_warning("[run] request_extract_vote refused: votes are applied on the host")
		return
	if run == null:
		push_warning("[run] request_extract_vote refused: no run is live")
		return
	var slice: RunPlayerState = run.get_player(peer_id)
	if slice == null:
		push_warning("[run] request_extract_vote refused: peer %d is not in this run" % peer_id)
		return
	if not slice.is_standing():
		# Downed and dead players are excluded from the tally — their vote must
		# neither count nor cancel one (BRIEF Assumption 3).
		push_warning("[run] request_extract_vote refused: peer %d is downed or dead" % peer_id)
		return
	if not yes:
		var was_open: bool = run.has_open_vote()
		run.reset_vote_state()
		if was_open:
			Events.rope_vote_updated.emit(run.vote_state())
		print("[run] peer %d voted no; the rope vote is canceled and the rope stays usable" % peer_id)
		return
	if run.players.size() == 1:
		# Solo extraction is immediate, without tallying (BRIEF Assumption 1).
		end_run(RunEndReason.Reason.EXTRACT)
		return
	if run.has_voted_yes(peer_id):
		# A repeat yes from a peer whose vote is already recorded is the rope
		# being used again (Rope re-enters through the same transport), so the
		# call starts fresh: prior votes clear and this peer's yes opens the new
		# tally (BRIEF Assumption 6). Rope.gd only forwards uses, so this is the
		# one signal GameState gets that a fresh vote call began.
		run.reset_vote_state()
	run.record_yes_vote(peer_id)
	var votes: Dictionary[int, bool] = run.vote_state()
	var living: int = _living_voter_count()
	Events.rope_vote_updated.emit(votes)
	print("[run] rope vote: %d of %d living player(s) agreed" % [votes.size(), living])
	if votes.size() >= living:
		print("[run] every living player voted yes; extracting")
		end_run(RunEndReason.Reason.EXTRACT)


## Host only. How many players in the live run still stand (not downed, not
## dead): the set whose yes votes must be unanimous before the rope extracts.
## An all-downed party counts zero, and a vote can never extract a run with
## zero living players — the defeat rule owns that case.
func _living_voter_count() -> int:
	var count: int = 0
	for peer_id: int in run.players:
		var slice: RunPlayerState = run.get_player(peer_id)
		if slice != null and slice.is_standing():
			count += 1
	return count


## Host only. Ends the live run: builds the RunResult from the run's final
## state, clears `run`, then emits run_ended. Clearing first makes a re-entrant
## call (a listener ending the run again) a no-op, so run_ended fires exactly
## once per run. Per-player kept/lost tables are the documented week-5 shape
## with neutral values (BRIEF Assumption 9).
func end_run(reason: RunEndReason.Reason) -> void:
	if not NetworkManager.is_host:
		push_warning("[run] end_run refused: the host owns run state")
		return
	if run == null:
		push_warning("[run] end_run refused: no run is live")
		return
	var finished: RunState = run
	var result: RunResult = RunResult.new(reason, finished.seed, finished.floors_cleared)
	RunEconomyRules.settle(result, finished, _skill_ranks_for(finished))
	run = null
	_unsubscribe_room_cleared()
	_unsubscribe_player_events()
	# The summary is built from the snapshot, because the live run is already
	# cleared: this print is the placeholder death/extract screen until ui-hud
	# builds the real one (week 5).
	last_run_summary = _run_summary_line(result, finished)
	print(last_run_summary)
	run_ended.emit(result)
	Events.run_ended.emit(result)


## Host only. The skill-tree ranks the keep rules read, peer_id -> {node_id:
## rank}. The host knows only its own profile (`skill_tree`, node id -> ranks),
## so remote peers settle at rank 0 until their ranks travel with the party
## (TODO(progression-trees)).
func _skill_ranks_for(finished: RunState) -> Dictionary[int, Dictionary]:
	var ranks: Dictionary[int, Dictionary] = {}
	var host_profile: PlayerProfile = (profile if profile != null else SaveManager.profile) as PlayerProfile
	if host_profile == null:
		return ranks
	for peer_id: int in finished.players:
		if peer_id == NetworkManager.local_peer_id:
			ranks[peer_id] = host_profile.skill_tree
	return ranks


## Host only. Starts counting cleared rooms for the live run. Idempotent, so a
## second start_run replacing a live run never double-counts a room.
func _subscribe_room_cleared() -> void:
	if not Events.room_cleared.is_connected(_on_room_cleared):
		Events.room_cleared.connect(_on_room_cleared)


## Stops counting rooms. Safe to call when nothing is connected.
func _unsubscribe_room_cleared() -> void:
	if Events.room_cleared.is_connected(_on_room_cleared):
		Events.room_cleared.disconnect(_on_room_cleared)


## Called by the host's start_run: starts listening for the player events the
## all-downed rule needs. Idempotent, so a second start_run replacing a live
## run never records one down twice.
func _subscribe_player_events() -> void:
	if not Events.player_downed.is_connected(_on_player_downed):
		Events.player_downed.connect(_on_player_downed)
	if not Events.player_died.is_connected(_on_player_died):
		Events.player_died.connect(_on_player_died)
	if not Events.player_revived.is_connected(_on_player_revived):
		Events.player_revived.connect(_on_player_revived)


## Stops listening for player events. Safe to call when nothing is connected.
## This is also what makes an ended run stay ended: no event can resurrect it.
func _unsubscribe_player_events() -> void:
	if Events.player_downed.is_connected(_on_player_downed):
		Events.player_downed.disconnect(_on_player_downed)
	if Events.player_died.is_connected(_on_player_died):
		Events.player_died.disconnect(_on_player_died)
	if Events.player_revived.is_connected(_on_player_revived):
		Events.player_revived.disconnect(_on_player_revived)


## Host only. The seed a run starts with: --seed (GameState.forced_seed) wins,
## then an explicit caller seed, then a host roll (BRIEF Assumption 12).
func _resolve_run_seed(requested: int) -> int:
	if forced_seed != 0:
		return forced_seed
	if requested != 0:
		return requested
	return _roll_run_seed()


## Host only. Rolls a run seed from clock entropy through a seeded
## RandomNumberGenerator — never a global roll call — so successive runs differ
## while the seed itself stays a single value both peers generate floors from.
func _roll_run_seed() -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_usec()
	return rng.randi_range(MIN_RUN_SEED, MAX_RUN_SEED)


## The RunPlayerState slice one party member starts a run with.
func _slice_from(info: PlayerSpawnInfo) -> RunPlayerState:
	var slice: RunPlayerState = RunPlayerState.new(info.peer_id, info.character_id, info.class_id)
	for weapon_id: StringName in info.weapon_ids:
		slice.add_weapon(weapon_id)
	return slice


## The biome resource floor_changed carries. Dev A's BiomeData (W6) replaces
## the placeholder; the parameter type stays Resource (BRIEF Assumption 17).
func _biome_for(state: RunState) -> Resource:
	return biome_for_index(state.biome_index)
