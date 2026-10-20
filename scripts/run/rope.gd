class_name Rope
extends Area2D
## The extraction rope: the interactable that ends a run with EXTRACT. Owned by
## run-economy (week 3). One rope is spawned per ROPE room by the ROPE
## populator below, which is registered against floor-generation's registry.
## Sync: host-authoritative. The host decides extraction: a run with one player
## extracts the moment the rope is used; in co-op the vote prompt lands in week
## 5, so the host records the use, leaves the rope usable and says so. A client
## never ends its own run — it sends request_vote_rope up and waits for the host.
## blocked on Dev A (W3-A3): registering the ROPE populator is a guarded no-op
## until FloorGenerator.register_populator() exists under scripts/generation/;
## nothing else here depends on the other lane.

## A client forwarded its use of the rope to the host (the request_* path).
signal interaction_forwarded(peer_id: int)
## The host applied the use and ended the run with EXTRACT.
signal extract_applied(peer_id: int)
## Co-op: the use was recorded, but the vote prompt is week 5 scope.
signal extract_deferred(peer_id: int)

## What the prompt says. SPEC-player-controller's interact scan looks for an
## area with `prompt_text` and `interact(player)`.
const PROMPT_TEXT: String = "Extract"
## Press, not hold: only revive holds an interact (SPEC-player-controller).
const HOLD_SECONDS: float = 0.0
## Physics layer 6, "interactable" (project.godot layer_names).
const INTERACTABLE_LAYER: int = 32
## The scene the populator spawns. Loaded at runtime rather than preloaded,
## because that scene's root script is this file and a preload would be a cycle.
const SCENE_PATH: String = "res://scenes/dungeon/interactables/rope.tscn"
## Where floor-generation's generator and its populator registry land
## (SPEC-project structure: scripts/generation/floor_generator.gd).
const GENERATOR_SCRIPT_PATH: String = "res://scripts/generation/floor_generator.gd"
## The constant name and value a ROPE room is registered under. Read off the
## generator script at runtime, so this file never names a RoomType enum that
## does not exist yet.
const ROOM_TYPE_CONSTANT: StringName = &"RoomType"
const ROPE_ROOM_TYPE: StringName = &"ROPE"

## Registering the populator is once per process; a second call is a no-op.
static var _populator_registered: bool = false

var prompt_text: String = PROMPT_TEXT
var hold_seconds: float = HOLD_SECONDS


## The Interactable contract (SPEC-player-controller): called by the player's
## interact scan with the acting player.
func interact(player: Player) -> void:
	var actor: int = peer_id_of(player)
	if not is_usable():
		push_warning("[run] rope refused: there is no live run to extract from")
		return
	if not NetworkManager.is_host:
		_forward_use(actor)
		return
	_apply_use(actor)


## True while there is a run to extract from. A co-op use that only reports the
## week-5 deferral leaves this true, so the rope is usable again afterwards.
func is_usable() -> bool:
	return GameState.run != null


## The peer behind an interactor; the local peer when the caller names none.
func peer_id_of(player: Player) -> int:
	if player == null:
		return NetworkManager.local_peer_id
	return player.peer_id


## Client path. The host owns extraction, so the use travels up as a request
## and nothing changes locally. With no session there is nobody to ask; with a
## session that cannot reach a remote host (solo, an offline peer) the use is
## recorded and never applied locally.
func _forward_use(peer_id: int) -> void:
	if not NetworkManager.is_active:
		push_warning("[run] rope refused: no session to send the request on")
		return
	interaction_forwarded.emit(peer_id)
	if not NetworkManager.can_send_request():
		push_warning("[run] rope use not sent: this session has no remote host to ask")
		return
	NetworkManager.rpc_id(NetworkManager.HOST_PEER_ID, &"request_vote_rope", true)


## Host path. A run with one player extracts immediately (SPEC-run-economy:
## "Solo: immediate"). With more players the unanimous vote is the week-5 vote
## prompt, so the use is recorded, the rope stays usable, and the deferral is
## announced (BRIEF Assumption 8).
func _apply_use(peer_id: int) -> void:
	var run: RunState = GameState.run
	if run == null:
		return
	if run.players.size() > 1:
		print("[run] rope vote prompt lands in week 5 — %d players must agree; the rope stays usable" % run.players.size())
		extract_deferred.emit(peer_id)
		return
	extract_applied.emit(peer_id)
	GameState.end_run(RunEndReason.Reason.EXTRACT)


## The Callable the ROPE room populator is registered as:
## `FloorGenerator.register_populator(RoomType.ROPE, Rope.rope_populator())`.
static func rope_populator() -> Callable:
	return Callable(Rope, &"_populate_rope_room")


## Registers the ROPE populator with Dev A's registry, once per process.
## Returns true when it registered, false while the registry is absent.
## Guarded on purpose: a run must never depend on the other lane landing first
## (BRIEF Assumption 4), so the absent-registry path is a recorded no-op.
## blocked on Dev A (W3-A3): the swap-in is nothing — this call starts working
## the moment floor_generator.gd exists with RoomType.ROPE and the static
## register_populator(type, populator).
static func register_populator() -> bool:
	if _populator_registered:
		return true
	var generator: Script = _generator_script()
	if generator == null:
		print("[run] ROPE populator not registered — blocked on Dev A (W3-A3): %s does not exist yet, so the rope spawns with the registry" % GENERATOR_SCRIPT_PATH)
		return false
	if not generator.has_method(&"register_populator"):
		push_warning("[run] ROPE populator not registered: %s has no register_populator()" % GENERATOR_SCRIPT_PATH)
		return false
	var room_type: Variant = _room_type_value(generator)
	if room_type == null:
		push_warning("[run] ROPE populator not registered: %s declares no RoomType.ROPE" % GENERATOR_SCRIPT_PATH)
		return false
	generator.call(&"register_populator", room_type, rope_populator())
	_populator_registered = true
	print("[run] ROPE populator registered with FloorGenerator")
	return true


## Host only. Spawns one rope in a ROPE room and returns it, or null when it
## refused (not the host, no room, a scene that will not load). The generator
## calls this through rope_populator() after painting the room.
static func spawn_in(room: Node) -> Rope:
	if not NetworkManager.is_host:
		return null
	if room == null:
		push_warning("[run] ROPE populator called with no room")
		return null
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("[run] ROPE populator could not load %s" % SCENE_PATH)
		return null
	var rope: Rope = packed.instantiate() as Rope
	if rope == null:
		push_warning("[run] %s does not instantiate as a Rope" % SCENE_PATH)
		return null
	# TODO(floor-generation, W3-A2): sit on RoomSpec's interactable anchor once
	# Room exposes it; the room's origin is the week-3 stand-in.
	rope.position = Vector2.ZERO
	room.add_child(rope)
	return rope


## The registered populator, in the Callable(room: Room) -> void shape
## SPEC-floor-generation declares. Thin on purpose: spawn_in carries the body.
static func _populate_rope_room(room: Node) -> void:
	spawn_in(room)


## Dev A's generator script, or null while it does not exist. Checked with
## ResourceLoader.exists first, because loading a missing path logs an engine
## error that would show up as noise in every headless run.
static func _generator_script() -> Script:
	if not ResourceLoader.exists(GENERATOR_SCRIPT_PATH):
		return null
	var loaded: Resource = load(GENERATOR_SCRIPT_PATH)
	return loaded as Script


## The RoomType.ROPE value, read from the generator script's own constants so
## this file never references a type that does not exist yet.
static func _room_type_value(generator: Script) -> Variant:
	var constants: Dictionary = generator.get_script_constant_map()
	var raw_types: Variant = constants.get(ROOM_TYPE_CONSTANT)
	if not raw_types is Dictionary:
		return null
	var room_types: Dictionary = raw_types as Dictionary
	return room_types.get(ROPE_ROOM_TYPE)
