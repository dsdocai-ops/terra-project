extends Node
## Run data and persistent data. Owned by run-economy.
## start_run / next_floor / end_run are the run loop's spine: the host builds a
## RunState from the party, advances floors, and ends the run with a RunResult
## that run_ended hands to the death/extract screen. Rope rooms, floor
## generation, networking, the HUD and the debug console all call or listen
## here (SPEC-run-economy).
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


## Host only. A client's rope vote (SPEC-run-economy). Week 3 ships the
## signature and the host guard only: solo extraction is immediate (Rope), and
## the co-op vote prompt with its rope_vote_updated broadcast lands in week 5.
func request_extract_vote(peer_id: int, yes: bool) -> void:
	if not NetworkManager.is_host:
		push_warning("[run] request_extract_vote refused: votes are applied on the host")
		return
	# TODO(run-economy, week 5): tally the living players' votes, broadcast
	# rope_vote_updated, and end_run(EXTRACT) once every living player voted yes.
	print("[run] rope vote from peer %d (%s) ignored — the vote prompt lands in week 5" % [peer_id, "yes" if yes else "no"])


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
	for peer_id: int in finished.players:
		result.set_player_tables(peer_id, RunResult.empty_table(), RunResult.empty_table())
	run = null
	_unsubscribe_room_cleared()
	run_ended.emit(result)
	Events.run_ended.emit(result)
	print("[run] ended (%s) after %d floor(s), seed %d" % [RunEndReason.Reason.keys()[reason], finished.floors_cleared, finished.seed])


## Host only. Starts counting cleared rooms for the live run. Idempotent, so a
## second start_run replacing a live run never double-counts a room.
func _subscribe_room_cleared() -> void:
	if not Events.room_cleared.is_connected(_on_room_cleared):
		Events.room_cleared.connect(_on_room_cleared)


## Stops counting rooms. Safe to call when nothing is connected.
func _unsubscribe_room_cleared() -> void:
	if Events.room_cleared.is_connected(_on_room_cleared):
		Events.room_cleared.disconnect(_on_room_cleared)


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
	return BiomePlaceholder.from_index(state.biome_index)
