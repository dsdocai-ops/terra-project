class_name Shrine
extends Area2D
## The Shrine: the interactable that offers a player 1 of 3 relics. Owned by
## relics (W4-B5). One shrine is spawned per SHRINE room by the populator
## below, which is registered against floor-generation's registry.
##
## SPEC-relics, "Shrine flow": "`SHRINE` populator spawns a `Shrine`
## interactable. Interact (host validates one use per player per shrine) rolls
## 3 relics the player does not already hold at max stacks and sends
## `relic_choice_offered(peer_id, ids)`". Those two sentences are the whole of
## this file: the roll is the shared helper `RelicRoller.roll(player, 3, false)`
## — the Shrine is the caller that passes `allow_cursed = false`, which is
## SPEC-relics' "Cursed never roll at Shrines" — and the per-player use record
## lives here, keyed by peer id.
##
## Sync: host-authoritative. The host validates the use, rolls, and records both
## the use and the offer it announced; a client's `interact()` forwards up the
## request path and rolls nothing locally, so the same peer can never spend a
## shrine twice by asking on the wrong peer. Nothing here attaches a relic —
## the pick, the host attach and the codex are the pick flow (`W4-B5`, G10).
##
## blocked on Dev A (W4-A3): registering the SHRINE populator is a guarded no-op
## until FloorGenerator.register_populator() exists under scripts/generation/,
## so no generated floor places a shrine yet and two-instance smoke step 4 has
## nothing to walk to. Nothing else here depends on the other lane; the swap-in
## is nothing (this call starts working the moment that script exists with
## RoomType.SHRINE and the static register_populator(type, populator)).

## A client forwarded its use of the shrine to the host (the request_* path).
signal interaction_forwarded(peer_id: int)
## Host: the 3 ids offered to `peer_id`, in the order they will be shown.
signal relic_choice_offered(peer_id: int, ids: Array[StringName])
## Host: the use was refused, with the reason. `REFUSAL_NONE` is never emitted.
signal use_refused(peer_id: int, reason: StringName)

## What the prompt says. SPEC-player-controller's interact scan looks for an
## area with `prompt_text` and `interact(player)`.
const PROMPT_TEXT: String = "Pray"
## Press, not hold: only revive holds an interact (SPEC-player-controller).
const HOLD_SECONDS: float = 0.0
## Physics layer 6, "interactable" (project.godot layer_names).
const INTERACTABLE_LAYER: int = 32
## The scene the populator spawns. Loaded at runtime rather than preloaded,
## because that scene's root script is this file and a preload would be a cycle.
const SCENE_PATH: String = "res://scenes/dungeon/interactables/shrine.tscn"
## Where floor-generation's generator and its populator registry land
## (SPEC-project structure: scripts/generation/floor_generator.gd).
const GENERATOR_SCRIPT_PATH: String = "res://scripts/generation/floor_generator.gd"
## The constant name and value a SHRINE room is registered under. Read off the
## generator script at runtime, so this file never names a RoomType enum that
## does not exist yet.
const ROOM_TYPE_CONSTANT: StringName = &"RoomType"
const SHRINE_ROOM_TYPE: StringName = &"SHRINE"

## SPEC-relics: "rolls 3 relics the player does not already hold at max stacks".
const OFFER_COUNT: int = 3
## SPEC-relics: "Cursed never roll at Shrines." The one place a Shrine says so;
## the ban itself lives in `RelicRoller`'s candidate filter.
const ALLOW_CURSED: bool = false

const REFUSAL_NONE: StringName = &""
## The acting peer already took its one offer here.
const REFUSAL_ALREADY_USED: StringName = &"already_used"
## No run is live, so a shrine has nothing to offer anyone.
const REFUSAL_NO_RUN: StringName = &"no_run"

## Registering the populator is once per process; a second call is a no-op.
static var _populator_registered: bool = false
## The blocked-on-Dev-A note is worth one line per process, not one per call.
static var _blocker_logged: bool = false

var prompt_text: String = PROMPT_TEXT
var hold_seconds: float = HOLD_SECONDS
## peer_id -> true once that peer has taken its offer here. Host-owned; a client
## keeps its own empty copy and never reads it to decide anything.
var _used_peers: Dictionary[int, bool] = {}
## peer_id -> the ids that peer was offered, so the pick flow can validate a
## `request_pick_relic(index)` against the offer that peer actually received.
## The inner array is untyped because GDScript refuses a nested typed
## collection (`Dictionary[int, Array[StringName]]` is a parse error);
## `offer_of()` is the typed read.
var _offers: Dictionary[int, Array] = {}


# --- the Interactable contract ---------------------------------------------

## Called by the player's interact scan with the acting player
## (SPEC-player-controller). The host validates and rolls; a client forwards.
func interact(player: Player) -> void:
	var actor: int = peer_id_of(player)
	if not NetworkManager.is_host:
		_forward_use(actor)
		return
	_apply_use(player, actor)


## The peer behind an interactor; the local peer when the caller names none.
func peer_id_of(player: Player) -> int:
	if player == null:
		return NetworkManager.local_peer_id
	return player.peer_id


## True while `peer_id` may still use this shrine: it has not spent its one use.
## A client answers true until the host says otherwise, because the use record
## is host state.
func is_usable(peer_id: int) -> bool:
	return not has_used(peer_id)


## True once `peer_id` has taken its offer here.
func has_used(peer_id: int) -> bool:
	return _used_peers.has(peer_id)


## Why `peer_id`'s use would be refused right now, or `REFUSAL_NONE` when it
## would be applied. The one place the two rules are ordered, so the answer and
## the refusal cannot disagree.
func refusal_for(peer_id: int) -> StringName:
	if GameState.run == null:
		return REFUSAL_NO_RUN
	if has_used(peer_id):
		return REFUSAL_ALREADY_USED
	return REFUSAL_NONE


## The ids `peer_id` was offered at this shrine, empty when it was offered none.
## A copy, so a caller cannot edit the record the pick flow validates against.
func offer_of(peer_id: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var offered: Variant = _offers.get(peer_id)
	if not offered is Array:
		return out
	for id: Variant in offered as Array:
		out.append(StringName(str(id)))
	return out


# --- the host path ----------------------------------------------------------

## Host only. Rolls this player's 3 through the shared helper SPEC-relics names
## for Shrines, Merchant shops and Treasure chests.
func offer_for(player: Player) -> Array[StringName]:
	return RelicRoller.roll(player, OFFER_COUNT, ALLOW_CURSED)


## Host path: validate the one-use rule, spend it, and announce the roll.
func _apply_use(player: Player, peer_id: int) -> void:
	var refusal: StringName = refusal_for(peer_id)
	if refusal != REFUSAL_NONE:
		push_warning("[relics] shrine refused peer %d: %s" % [peer_id, refusal])
		use_refused.emit(peer_id, refusal)
		return
	_used_peers[peer_id] = true
	var ids: Array[StringName] = offer_for(player)
	_offers[peer_id] = ids.duplicate()
	relic_choice_offered.emit(peer_id, ids)


# --- the client path --------------------------------------------------------

## Client path. The host owns the roll and the use record, so the use travels
## up as a request and nothing changes locally. With no session there is nobody
## to ask.
## blocked on Dev B (G10, W4-B5): the request that opens a shrine travels on
## NetworkManager — the shrine node is spawned by the host's populator, so it
## cannot carry the RPC itself — and lands with the pick flow's request_pick_relic
## (SPEC-relics names no open request). Until then a forwarded use stops at the
## signal and the host is not told: recorded rather than faked, because an
## invented RPC name would fix a wire shape SPEC-networking does not name.
func _forward_use(peer_id: int) -> void:
	if not NetworkManager.is_active:
		push_warning("[relics] shrine refused: no session to send the request on")
		return
	interaction_forwarded.emit(peer_id)


# --- the SHRINE populator and its registration seam -------------------------

## The Callable the SHRINE room populator is registered as:
## `FloorGenerator.register_populator(RoomType.SHRINE, Shrine.shrine_populator())`.
static func shrine_populator() -> Callable:
	return Callable(Shrine, &"_populate_shrine_room")


## Registers the SHRINE populator with Dev A's registry, once per process.
## Returns true when it registered, false while the registry is absent.
## Guarded on purpose: a floor must never depend on the other lane landing
## first (BRIEF Assumption 8), so the absent-registry path is a recorded no-op
## that notes its blocker **once** — a floor change must not reprint it.
## blocked on Dev A (W4-A3): the swap-in is nothing — this call starts working
## the moment floor_generator.gd exists with RoomType.SHRINE and the static
## register_populator(type, populator).
static func register_populator() -> bool:
	if _populator_registered:
		return true
	var generator: Script = _generator_script()
	if generator == null:
		_note_blocked("%s does not exist yet, so the shrine spawns with the registry" % GENERATOR_SCRIPT_PATH)
		return false
	if not generator.has_method(&"register_populator"):
		_note_blocked("%s has no register_populator()" % GENERATOR_SCRIPT_PATH)
		return false
	var room_type: Variant = room_type_value(generator)
	if room_type == null:
		_note_blocked("%s declares no RoomType.SHRINE" % GENERATOR_SCRIPT_PATH)
		return false
	generator.call(&"register_populator", room_type, shrine_populator())
	_populator_registered = true
	print("[relics] SHRINE populator registered with FloorGenerator")
	return true


## How many blocked-on-Dev-A notes this process has written: 0, or 1. The
## guarded registration notes its blocker once and a second call is inert, and
## this read is how that is a checked claim rather than a comment.
static func blocker_warnings() -> int:
	return 1 if _blocker_logged else 0


## The RoomType.SHRINE value, read from a generator script's own constants so
## this file never references a type that does not exist yet. Null when the
## script declares no such enumeration or no SHRINE member in it. Public
## because the registration test drives it with a registry double.
static func room_type_value(generator: Script) -> Variant:
	if generator == null:
		return null
	var constants: Dictionary = generator.get_script_constant_map()
	var raw_types: Variant = constants.get(ROOM_TYPE_CONSTANT)
	if not raw_types is Dictionary:
		return null
	var room_types: Dictionary = raw_types as Dictionary
	return room_types.get(SHRINE_ROOM_TYPE)


## Host only. Spawns one shrine in a SHRINE room and returns it, or null when it
## refused (not the host, no room, a scene that will not load). The generator
## calls this through shrine_populator() after painting the room.
static func spawn_in(room: Node) -> Shrine:
	if not NetworkManager.is_host:
		return null
	if room == null:
		push_warning("[relics] SHRINE populator called with no room")
		return null
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("[relics] SHRINE populator could not load %s" % SCENE_PATH)
		return null
	var shrine: Shrine = packed.instantiate() as Shrine
	if shrine == null:
		push_warning("[relics] %s does not instantiate as a Shrine" % SCENE_PATH)
		return null
	# TODO(floor-generation, W4-A3): sit on RoomSpec's interactable anchor once
	# Room exposes it; the room's origin is the stand-in.
	shrine.position = Vector2.ZERO
	room.add_child(shrine)
	return shrine


## The registered populator, in the Callable(room: Room) -> void shape
## SPEC-floor-generation declares. Thin on purpose: spawn_in carries the body.
static func _populate_shrine_room(room: Node) -> void:
	spawn_in(room)


## Dev A's generator script, or null while it does not exist. Checked with
## ResourceLoader.exists first, because loading a missing path logs an engine
## error that would show up as noise in every headless run.
static func _generator_script() -> Script:
	if not ResourceLoader.exists(GENERATOR_SCRIPT_PATH):
		return null
	var loaded: Resource = load(GENERATOR_SCRIPT_PATH)
	return loaded as Script


## Notes the blocked path once per process.
static func _note_blocked(detail: String) -> void:
	if _blocker_logged:
		return
	_blocker_logged = true
	push_warning("[relics] SHRINE populator not registered — blocked on Dev A (W4-A3): %s" % detail)
