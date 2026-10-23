class_name RunSetup
extends RefCounted
## The pre-run flow (SPEC-town "Pre-run flow", W5-B5): collects every player's
## SelectionState, the party-wide start floor, and starts the run once all are
## ready. Owned by town. The UI that edits it is ui-hud's (W5-B6).
##
## Sync: host-authoritative. Clients submit their own SelectionState; the host
## validates it, stores it, and starts the run through GameState.start_run with one
## PlayerSpawnInfo per peer. The host checks unlocks against the profile it is
## given for that peer; it only holds its own profile, so a remote peer's
## selection is checked for shape alone until profiles travel with the party
## (TODO(save-system)). The Relic Vault / Rune Library picks and heat levels join
## here in weeks 6 and 11.

const REFUSAL_NONE: StringName = &""
const REFUSAL_NOT_HOST: StringName = &"not_host"
const REFUSAL_NO_SELECTION: StringName = &"no_selection"
const REFUSAL_NOT_READY: StringName = &"not_ready"
const REFUSAL_BAD_START_FLOOR: StringName = &"bad_start_floor"
const REFUSAL_NO_PLAYERS: StringName = &"no_players"

var selections: Dictionary[int, SelectionState] = {}
var start_floor: int = MapRoom.FIRST_FLOOR
var last_refusal: StringName = REFUSAL_NONE


## Stores `selection` (ready cleared: changing a choice un-readies the player).
## `profile` is the profile to check unlocks against; null checks shape only.
func submit(selection: SelectionState, profile: PlayerProfile = null) -> StringName:
	var reason: StringName = selection.refusal_for(profile) if profile != null else selection.shape_refusal()
	last_refusal = reason
	if reason != REFUSAL_NONE:
		return reason
	var stored: SelectionState = selection.copy()
	stored.ready = false
	selections[selection.peer_id] = stored
	return REFUSAL_NONE


func set_ready(peer_id: int, is_ready: bool) -> StringName:
	if not selections.has(peer_id):
		last_refusal = REFUSAL_NO_SELECTION
		return last_refusal
	selections[peer_id].ready = is_ready
	last_refusal = REFUSAL_NONE
	return REFUSAL_NONE


## Picks the party's start floor; it must be one the host's Map Room allows.
func set_start_floor(floor_index: int, deepest_rope: int) -> StringName:
	if not MapRoom.can_start_at(floor_index, deepest_rope):
		last_refusal = REFUSAL_BAD_START_FLOOR
		return last_refusal
	start_floor = floor_index
	last_refusal = REFUSAL_NONE
	return REFUSAL_NONE


func remove(peer_id: int) -> void:
	selections.erase(peer_id)


## True when every peer in `peer_ids` has a stored, ready selection.
func all_ready(peer_ids: Array[int]) -> bool:
	if peer_ids.is_empty():
		return false
	for peer_id: int in peer_ids:
		if not selections.has(peer_id) or not selections[peer_id].ready:
			return false
	return true


## One PlayerSpawnInfo per peer, slots in ascending peer order.
func build_party(peer_ids: Array[int]) -> Array[PlayerSpawnInfo]:
	var party: Array[PlayerSpawnInfo] = []
	var ordered: Array[int] = peer_ids.duplicate()
	ordered.sort()
	for slot: int in range(ordered.size()):
		var selection: SelectionState = selections.get(ordered[slot])
		if selection == null:
			continue
		party.append(PlayerSpawnInfo.new(
			selection.peer_id,
			selection.character_id,
			selection.class_id,
			selection.weapon_ids,
			Vector2.ZERO,
			slot,
		))
	return party


## Host only. Starts the run when everyone is ready. Returns REFUSAL_NONE on a start.
func start(peer_ids: Array[int], run_seed: int = 0) -> StringName:
	if not NetworkManager.is_host:
		last_refusal = REFUSAL_NOT_HOST
	elif peer_ids.is_empty():
		last_refusal = REFUSAL_NO_PLAYERS
	elif not all_ready(peer_ids):
		last_refusal = REFUSAL_NOT_READY
	else:
		GameState.start_run(run_seed, start_floor, build_party(peer_ids))
		last_refusal = REFUSAL_NONE
	return last_refusal
