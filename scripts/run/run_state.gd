class_name RunState
extends RefCounted
## One live run: seed, current floor and biome, party-wide pools, per-player
## slices, the floor-advance threshold state and the open rope vote. Owned by
## run-economy (week 5); built by the host's GameState.start_run() and read by
## HUD/networking.
## Sync: host-authoritative. The host mutates the run state; shared totals are
## broadcast on change and each per-player slice is sent to its owning peer.

const MIN_FLOOR: int = 1
const MAX_FLOOR: int = 30
const FLOORS_PER_BIOME: int = 5
const MIN_BIOME: int = 1
const MAX_BIOME: int = 6

## The seed both peers generate this run's floors from.
var seed: int = 0
## Current floor, clamped to 1..30.
var floor_index: int:
	get:
		return _floor_index
	set(value):
		_floor_index = clampi(value, MIN_FLOOR, MAX_FLOOR)
## Biome derived from the floor: (floor - 1) / 5 + 1, always 1..6.
var biome_index: int:
	get:
		return (_floor_index - MIN_FLOOR) / FLOORS_PER_BIOME + MIN_BIOME
## peer_id -> that player's slice.
var players: Dictionary[int, RunPlayerState] = {}
var shared_gold: int = 0
## Ore id -> amount carried by the party.
var shared_ore: Dictionary[StringName, int] = {}
var elites_killed: int = 0
var bosses_killed: int = 0
var floors_cleared: int = 0
## Floors finished without a player taking a hit (Crown of the Deep).
var rooms_cleared_no_hit: int = 0
## Millisecond stamp from Time.get_ticks_msec() at run start.
var time_started: int = 0
## Rooms cleared on the current floor, written by the host.
var rooms_cleared: int = 0
## How many rooms must be cleared before the Exit opens. This is the seam
## Dev A's Exit rule writes into (blocked on Dev A, W3-A2); until it does, the
## host sets it from the generated floor.
var required_rooms_cleared: int = 0
## True once the current floor's exit requirement is met.
var exit_open: bool:
	get:
		return rooms_cleared >= required_rooms_cleared

var _floor_index: int = MIN_FLOOR

## The floor this run began on (the Map Room shortcut, or 1). Never moves after
## the run starts; classes-characters reads it for the Tier 2 start.
var start_floor: int = MIN_FLOOR
## True when the Ascension is picked at run start (start past biome 1).
var ascension_pick_at_start: bool:
	get:
		return MapRoom.ascension_picked_at_start(start_floor)
## True when the run starts at Tier 2 (start past biome 4).
var starts_tier_two: bool:
	get:
		return MapRoom.starts_tier_two(start_floor)

## Votes recorded on the currently open rope extraction call: peer_id -> true
## for a recorded yes; a peer's absence means it has not voted. Owned by
## run-economy (week 5). Host-authoritative like the rest of the run: only the
## host's GameState tally writes it, a `no` vote or a finished call empties it,
## so the next rope use always starts a fresh call (SPEC-run-economy "Rope
## points"). Downed and dead players are never recorded here — GameState
## refuses their votes before tallying.
var _vote_yes: Dictionary[int, bool] = {}

## How many yes votes the open rope call has recorded. Derived from _vote_yes
## rather than kept alongside it, so the count and the per-player record can
## never disagree.
var _vote_tally: int:
	get:
		return _vote_yes.size()


func _init(p_seed: int = 0, p_start_floor: int = MIN_FLOOR) -> void:
	seed = p_seed
	floor_index = p_start_floor
	start_floor = _floor_index
	time_started = Time.get_ticks_msec()


## Host only. True when next_floor() may move to the next floor.
func can_advance() -> bool:
	return exit_open


## Host only. Moves to the next floor when the exit is open and another floor
## exists. Room progress resets; the required count stays until the new floor
## sets it, so the exit is never open by accident after advancing.
func advance_floor() -> bool:
	if not can_advance() or _floor_index >= MAX_FLOOR:
		return false
	floors_cleared += 1
	floor_index = _floor_index + 1
	rooms_cleared = 0
	return true


## Host only. Registers (or replaces) one player's run slice.
func add_player(player: RunPlayerState) -> void:
	players[player.peer_id] = player


## The slice for a peer, or null when that peer is not in the run.
func get_player(peer_id: int) -> RunPlayerState:
	var player: Variant = players.get(peer_id)
	return player as RunPlayerState


## Host only. Records `peer_id`'s yes vote on the open rope call. The host's
## tally (GameState.request_extract_vote) checks standing and repeats first.
func record_yes_vote(peer_id: int) -> void:
	_vote_yes[peer_id] = true


## True when a rope vote call is open with at least one yes recorded. A
## canceled call and a call nobody has voted on both count as closed.
func has_open_vote() -> bool:
	return not _vote_yes.is_empty()


## True when `peer_id` already voted yes on the open rope call, so a repeat
## vote from the same peer must not count twice.
func has_voted_yes(peer_id: int) -> bool:
	return _vote_yes.has(peer_id)


## The open rope call's vote state as a broadcast payload: peer_id -> true for
## each recorded yes. A copy, so listeners can hold it while the tally moves.
func vote_state() -> Dictionary[int, bool]:
	return _vote_yes.duplicate()


## Empties the vote record: a `no` canceled the call, or the rope is being used
## again and the next call must start fresh (BRIEF Assumption 6).
func reset_vote_state() -> void:
	_vote_yes.clear()
