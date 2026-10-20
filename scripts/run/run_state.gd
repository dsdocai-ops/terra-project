class_name RunState
extends RefCounted
## One live run: seed, current floor and biome, party-wide pools, per-player
## slices and the floor-advance threshold state. Owned by run-economy (week 3);
## built by the host's GameState.start_run() and read by HUD/networking.
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


func _init(p_seed: int = 0, p_start_floor: int = MIN_FLOOR) -> void:
	seed = p_seed
	floor_index = p_start_floor
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
