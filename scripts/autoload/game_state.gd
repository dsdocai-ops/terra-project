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

## The live World scene. Modules reach World/Players etc. through this,
## never by absolute path.
var world: World = null
## The live run; null in town and after end_run().
var run: RunState = null
## TODO(save-system): PlayerProfile, alias of SaveManager.profile.
var profile: RefCounted = null
## Seed forced from the command line (--seed=<int>); 0 means roll one.
var forced_seed: int = 0


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
	run_started.emit(resolved_seed)
	Events.run_started.emit(resolved_seed)
	print("[run] started seed %d at floor %d with %d player(s)" % [resolved_seed, run.floor_index, run.players.size()])


## Host only. Moves to the next floor, recomputes the biome and emits
## floor_changed. Refused past floor 30 (the floor-30 boss is the ending, from
## story-dialogue in week 10) and while the current floor's exit is still shut
## (RunState.can_advance(), fed by the W3-B1c room-clear counters).
func next_floor() -> void:
	if not NetworkManager.is_host:
		push_warning("[run] next_floor refused: the host owns floor state")
		return
	if run == null:
		push_warning("[run] next_floor refused: no run is live")
		return
	if not run.advance_floor():
		push_warning("[run] next_floor refused: floor %d is the last floor or its exit is still shut" % run.floor_index)
		return
	floor_changed.emit(run.floor_index, _biome_for(run))
	print("[run] floor %d (biome %d)" % [run.floor_index, run.biome_index])


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
	run_ended.emit(result)
	Events.run_ended.emit(result)
	print("[run] ended (%s) after %d floor(s), seed %d" % [RunEndReason.Reason.keys()[reason], finished.floors_cleared, finished.seed])


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
