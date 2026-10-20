class_name ActiveRelicController
extends Node
## The active-relic slots: slot 1 on the `relic_active_1` input action, its
## charges, its cooldown, and the host path a client's
## `request_activate_relic(slot)` travels. Owned by relics (W4-B7, PLAN G11 /
## raw goals G36 + G37).
##
## SPEC-relics, "Active relics": "Slot 1 on `relic_active_1` (C), slot 2 on
## `relic_active_2` (B) after Abyssal Attunement. Active relics are `Effect`s
## with `activate()`; charges refill per room where stated; cooldown shown on
## HUD." And its "Interfaces provided" row names exactly two reads:
## `ActiveRelicController` (`activate(slot)`, `cooldown_fraction(slot)`). Those
## two sentences plus SPEC-foundation's action table are the whole of this file.
##
## What each sentence becomes here:
##
##  * **the slot is a data-driven position, not new state** — the peer's active
##    relics are the `RelicData` of `Kind.ACTIVE` in the `RunPlayerState.relics`
##    list the host already keeps (SPEC-relics "Interfaces consumed"), in pick
##    order, so slot 1 is the first active and slot 2 the second. Nothing is
##    stored twice and a pick needs no extra bookkeeping; the pick-order reading
##    is also what "picking an active when slots are full offers replace-or-skip"
##    will need in week 11, and it is recorded as a HANDOFF decision.
##  * **the binding is the Input Map's.** `action_for(slot)` derives the action
##    name and `slot_of()` asks `InputMap.event_is_action`, so no keycode is
##    written down here and a rebind is a `project.godot` edit and nothing else.
##  * **charges** are the relic's own `active_charges`; one is spent per applied
##    activation and an activation with nothing left is refused. A relic that
##    states no charges has none to spend and is refused — the design doc's
##    actives (Bomb Bag, 3) all state one; the day a cooldown-only active lands,
##    `active_charges == 0` is the line that decides what it means.
##  * **the cooldown** is the relic's `active_cooldown`, counted down through
##    `TimeManager.scale_for(player)` — never `Engine.time_scale`, and never the
##    enemies' clock: a time stop on the enemies does not stall a player's relic,
##    while the player's own frozen state does.
##  * **the refill is the relic's**: on `Events.room_entered` for this player, a
##    slot refills only when its effect answers
##    `refills_charges_per_room()` — "where stated".
##
## Sync: host-authoritative (SPEC-relics, "Multiplayer ownership": "Rolls, picks,
## attaches, actives, synergy evaluation: host"). `request_activate_relic(slot)`
## is the client's request and `NetworkManager` carries it (the same split the
## pick flow uses, and for the same reason: this node lives under a player the
## client does not own); the host validates and applies, then announces the use
## to the other peers with `relic_activated` so the HUD sees it on every screen
## (SPEC-relics "Testing": "active relic use visible to both"). A client never
## spends a charge: its own `activate()` refuses with `REFUSAL_NOT_HOST`, and
## both `last_refusal` and `send_activate_request()`'s false return record it
## rather than faking an activation.
##
## One controller per player, installed the way `EffectHost` is: `for_player()`
## returns the node under the player or adds one, keyed by `NODE_NAME`.
## `blocked on Dev A (W2-A1, player.tscn)`: when the player scene's composition
## gains its components, this node moves into `player.tscn` and the lookup here
## keeps working unchanged. Until then the tests (and the HUD hook, W4-B7's G19)
## call `for_player()`, and an activation whose relic is not attached is refused
## with `REFUSAL_NOT_ATTACHED` rather than silently dropped.
##
## The actives themselves are week 8's content batch: this file ships the slot,
## its charges, its clock and its request path, and the tests drive it with an
## `Effect` double instead of inventing a `.tres` the design doc does not have
## yet.

## Node name the controller is looked up by under the player.
const NODE_NAME: StringName = &"ActiveRelicController"

## Slot 1 is the C key, slot 2 the B key (SPEC-relics "Active relics";
## SPEC-foundation's action table). Slot 2's relic is Abyssal Attunement's, and
## the slot exists here so criterion 2's "an active in that slot" is a real
## question with a real answer.
const SLOT_1: int = 1
const SLOT_2: int = 2
const SLOT_COUNT: int = 2

## The action name's one form, so the controller, the test and a rebind cannot
## drift: `action_for(1)` is `relic_active_1`.
const ACTION_PREFIX: String = "relic_active_"

## Returned by `slot_of()` for an event in no relic-slot binding.
const NO_SLOT: int = -1

## The action name slot `slot` is bound to. Derived rather than listed, and
## every read of it goes through `InputMap.has_action()` first — the binding
## itself lives in the Input Map and is never assumed here.
static func action_for(slot: int) -> StringName:
	return StringName(ACTION_PREFIX + str(slot))


## The refusal reasons. The whole host rule is `_refusal_for()`, so the RPC, the
## public apply, the tests and a log line share one answer rather than five.
const REFUSAL_NONE: StringName = &""
## This peer does not host, so it applies no activation.
const REFUSAL_NOT_HOST: StringName = &"not_host"
## A direct local call reports sender 0: that is not a client's request.
const REFUSAL_NOT_A_REQUEST: StringName = &"not_a_request"
## There is no player for the request — this controller has none, or the host
## has no player node for the requesting peer.
const REFUSAL_NO_PLAYER: StringName = &"no_player"
## The slot is outside the pair.
const REFUSAL_BAD_SLOT: StringName = &"bad_slot"
## The peer holds no active relic in that slot.
const REFUSAL_NO_ACTIVE: StringName = &"no_active"
## The relic is held but its effect is not attached, so there is nothing to fire.
const REFUSAL_NOT_ATTACHED: StringName = &"not_attached"
## Nothing left to spend (`active_charges` exhausted).
const REFUSAL_NO_CHARGES: StringName = &"no_charges"
## The slot is still counting its own `active_cooldown` down.
const REFUSAL_ON_COOLDOWN: StringName = &"on_cooldown"
## The relic's own `Effect.activate()` said no (an empty charge, an out-of-range
## target). Nothing was spent.
const REFUSAL_EFFECT_REFUSED: StringName = &"effect_refused"

## Why the most recent activation was refused, `REFUSAL_NONE` when one applied.
## Reset by every attempt, so it is never stale.
##
## Static and not per-instance because the RPC that reports a refusal is a
## `NetworkManager` method with no controller of its own, and because this is a
## diagnostic rather than state: `RelicFlow.last_refusal` is the same shape. The
## authoritative per-player state is the charge and cooldown dictionaries below,
## which are instance state.
static var last_refusal: StringName = REFUSAL_NONE

## Host: the slot was used. The HUD's hook (G19) listens for the sweep; the host
## itself hears it, and the other peers hear `relic_activated`.
signal slot_activated(slot: int, id: StringName)

## The player this controller belongs to, resolved from the parent on `_ready()`.
var player: Player = null
## The relic pool ids are resolved in, in `RelicRoller`'s own injectable shape:
## empty means "the whole content folder" (`RelicFlow.data_for`), and a caller
## with its own stock (a shop, a test fixture) passes the pool it may offer.
var pool: Array[RelicData] = []

## slot -> the id the slot's charges and cooldown belong to, so a replaced relic
## starts full rather than inheriting the old one's spent charge.
var _slot_ids: Dictionary[int, StringName] = {}
## slot -> charges left.
var _charges: Dictionary[int, int] = {}
## slot -> seconds of cooldown left, already scaled by the player's time.
var _cooldown: Dictionary[int, float] = {}


func _ready() -> void:
	player = _resolve_player()
	if player == null:
		push_warning("[relics] %s is not parented to a Player, no slot can fire" % name)
		return
	Events.room_entered.connect(_on_room_entered)


func _exit_tree() -> void:
	if Events.room_entered.is_connected(_on_room_entered):
		Events.room_entered.disconnect(_on_room_entered)


## The controller `player` carries, installing one when it has none — the lookup
## shape `EffectHostPlayer.install` uses for the host, so the swap into
## `player.tscn` is one node and this call is unchanged.
static func for_player(actor: Player) -> ActiveRelicController:
	if actor == null:
		return null
	var existing: Node = actor.get_node_or_null(NodePath(NODE_NAME))
	if existing is ActiveRelicController:
		return existing as ActiveRelicController
	if existing != null:
		actor.remove_child(existing)
		existing.queue_free()
	var made := ActiveRelicController.new()
	made.name = NODE_NAME
	actor.add_child(made)
	return made


# --- the clock ---------------------------------------------------------------


## Every physics frame the cooldown advances by the player's own scaled time.
func _physics_process(delta: float) -> void:
	advance(delta)


## Advances every running cooldown by `delta` of the **player's** time, so a
## caller may drive it directly (a test, a catch-up on a late join) and the
## engine's own tick is not a second code path. `TimeManager.scale_for(player)`
## is the spec's rule: never `Engine.time_scale`, and never the enemies' stack —
## a time stop on the enemies leaves a player's relic cooldown running, while the
## player's own hit-stop freezes it.
func advance(delta: float) -> void:
	var scaled: float = delta * time_scale()
	if scaled <= 0.0:
		return
	for slot: int in _cooldown.keys():
		_cooldown[slot] = maxf(float(_cooldown[slot]) - scaled, 0.0)


## How fast time passes for this controller right now: the player's own
## `TimeManager` scale, or normal time when there is no player to ask.
func time_scale() -> float:
	if player == null or not is_instance_valid(player):
		return 1.0
	return TimeManager.scale_for(player)


## How much of `slot`'s cooldown is left, 1.0 the instant it was used and 0.0
## when it is ready again — the number the HUD's sweep reads (SPEC-relics
## "Interfaces provided": `cooldown_fraction(slot)`). 0.0 for a slot with no
## active relic, which draws as "ready" rather than as a full sweep.
func cooldown_fraction(slot: int) -> float:
	var data: RelicData = slot_data(slot)
	if data == null or data.active_cooldown <= 0.0:
		return 0.0
	return clampf(float(_cooldown.get(slot, 0.0)) / data.active_cooldown, 0.0, 1.0)


## True while `slot` may fire: a live active, a charge to spend and no cooldown
## left. The one place the three are combined, so the HUD and the refusal cannot
## disagree about what "usable" means.
func is_ready(slot: int) -> bool:
	var data: RelicData = slot_data(slot)
	if data == null:
		return false
	return cooldown_fraction(slot) <= 0.0 and charges_left(slot, data) > 0


# --- the slot's relic and its charges ---------------------------------------


## The active relics `player` holds, in pick order — slot 1 is the first. Read
## from the replicated run slice through `RelicRoller.run_slice()`, so the
## controller stores no second copy of the loadout.
func active_relics() -> Array[RelicData]:
	var out: Array[RelicData] = []
	var slice: RunPlayerState = RelicRoller.run_slice(player)
	if slice == null:
		return out
	for relic_id: StringName in slice.relics:
		var data: RelicData = data_for(relic_id)
		if data != null and data.kind == RelicData.Kind.ACTIVE:
			out.append(data)
	return out


## The `RelicData` in `slot`, or null when the peer holds no active there.
func slot_data(slot: int) -> RelicData:
	if slot < SLOT_1 or slot > SLOT_COUNT:
		return null
	var actives: Array[RelicData] = active_relics()
	var index: int = slot - SLOT_1
	if index >= actives.size():
		return null
	return actives[index]


## The charges left in `slot`, with the slot's own relic resolved first so a
## newly held active starts from its `active_charges`.
func charges(slot: int) -> int:
	var data: RelicData = slot_data(slot)
	if data == null:
		return 0
	_sync_slot(slot, data)
	return int(_charges.get(slot, 0))


## The pool `slot`'s relic refills to: its own `active_charges`.
func max_charges(slot: int) -> int:
	var data: RelicData = slot_data(slot)
	return data.active_charges if data != null else 0


## `id`'s `RelicData`: this controller's pool first (a shop's stock, a test
## fixture), then the content folder through `RelicFlow.data_for()`.
func data_for(id: StringName) -> RelicData:
	if id == &"":
		return null
	for data: RelicData in pool:
		if data != null and data.id == id:
			return data
	return RelicFlow.data_for(id)


## Resets a slot's charges and cooldown when the relic in it changed, so a
## replacement starts full and an id that is still there keeps what it spent.
func _sync_slot(slot: int, data: RelicData) -> void:
	var held: StringName = _slot_ids.get(slot, &"")
	if held == data.id:
		return
	_slot_ids[slot] = data.id
	_charges[slot] = data.active_charges
	_cooldown[slot] = 0.0
	_slot_reset(slot)


## Hook for a subclass (and the HUD's future read) that a slot's relic changed.
func _slot_reset(_slot: int) -> void:
	pass


## The charges left in `slot` for the already-resolved `data`.
func charges_left(slot: int, data: RelicData) -> int:
	_sync_slot(slot, data)
	return int(_charges.get(slot, 0))


# --- the input ---------------------------------------------------------------


## The slot an `InputEvent` aims at, `NO_SLOT` when it is not a relic-slot
## binding. The match is `InputMap.event_is_action`, so the binding is the Input
## Map's and this file holds no keycode.
func slot_of(event: InputEvent) -> int:
	if event == null:
		return NO_SLOT
	for slot: int in range(SLOT_1, SLOT_COUNT + 1):
		var action: StringName = action_for(slot)
		if not InputMap.has_action(action):
			continue
		if InputMap.event_is_action(event, action):
			return slot
	return NO_SLOT


## The input entry point: a press of a bound action asks for that slot. Pressed
## and non-echo only, so a release or an echo is not a second use. Returns true
## when the request applied.
func handle_input_event(event: InputEvent) -> bool:
	if event == null or event.is_echo() or not event.is_pressed():
		return false
	var slot: int = slot_of(event)
	if slot == NO_SLOT:
		return false
	return request_activation(slot)


## The node's own `_input`: the HUD and the player's other input paths are not
## this file's business, so the handler above is the one place a press is read.
func _input(event: InputEvent) -> void:
	handle_input_event(event)


# --- the host path ----------------------------------------------------------


## The input/UI entry point: the one press path. It is always
## `NetworkManager.send_activate_request()`, so a hosting press and a client's
## press are the same call and only the wire differs — the host branch of that
## call applies through `apply_local_activation()`, the client's sends
## `request_activate_relic(slot)`. `activate()` is not called from here directly,
## so there is no second host path to keep in step. Returns true when the
## activation applied.
func request_activation(slot: int) -> bool:
	return NetworkManager.send_activate_request(slot)


## Host only. Applies this player's use of `slot`: refuses through
## `_refusal_for()`, fires the relic's own `Effect.activate()`, then spends one
## charge, starts the relic's `active_cooldown`, announces the use and routes it
## to the other peers. Returns true when applied.
##
## The order matters and is the whole of the rule: the charge and the cooldown
## are spent **after** the relic agreed, so a relic that refuses costs nothing.
func activate(slot: int) -> bool:
	last_refusal = _refusal_for(slot)
	if last_refusal != REFUSAL_NONE:
		return false
	var data: RelicData = slot_data(slot)
	var effect: Effect = _effect_of(data)
	if effect == null or not effect.activate():
		last_refusal = REFUSAL_EFFECT_REFUSED
		return false
	_sync_slot(slot, data)
	_charges[slot] = maxi(int(_charges.get(slot, 0)) - 1, 0)
	_cooldown[slot] = data.active_cooldown
	slot_activated.emit(slot, data.id)
	NetworkManager.route_relic_activated(player, slot, data.id)
	return true


## Why `slot` would be refused right now, or `REFUSAL_NONE` when it would apply.
## One place the rules are ordered, so the refusal, the log line and the HUD's
## "usable" read cannot disagree:
##  * this peer hosts, the slot exists, and there is a player to act for;
##  * the player holds an active in that slot, and its effect is attached;
##  * there is a charge left and the slot is not still counting down.
func _refusal_for(slot: int) -> StringName:
	if not NetworkManager.is_host:
		return REFUSAL_NOT_HOST
	if slot < SLOT_1 or slot > SLOT_COUNT:
		return REFUSAL_BAD_SLOT
	if player == null or not is_instance_valid(player):
		return REFUSAL_NO_PLAYER
	var data: RelicData = slot_data(slot)
	if data == null:
		return REFUSAL_NO_ACTIVE
	if _effect_of(data) == null:
		return REFUSAL_NOT_ATTACHED
	if charges_left(slot, data) <= 0:
		return REFUSAL_NO_CHARGES
	if cooldown_fraction(slot) > 0.0:
		return REFUSAL_ON_COOLDOWN
	return REFUSAL_NONE


## Host only. The `request_activate_relic(slot)` half: validates that the sender
## is a remote client, resolves that peer's player and applies through **its**
## controller, so a client cannot spend another player's charge and the host
## never trusts a value beyond the slot index (SPEC-networking: "Never trust
## client values beyond ids and indices").
static func apply_activate_request(sender: int, slot: int) -> bool:
	if not NetworkManager.is_host:
		last_refusal = REFUSAL_NOT_HOST
		return false
	if sender <= 0:
		last_refusal = REFUSAL_NOT_A_REQUEST
		return false
	var actor: Player = NetworkManager.get_player(sender)
	if actor == null:
		last_refusal = REFUSAL_NO_PLAYER
		return false
	var controller: ActiveRelicController = for_player(actor)
	if controller == null:
		last_refusal = REFUSAL_NO_PLAYER
		return false
	return controller.activate(slot)


## Host only. The `send_activate_request()` half for the host's own player: solo
## and a hosting peer must run the same apply as a remote client's request does,
## so `NetworkManager.send_activate_request()` is the one entry point and this is
## the branch its host case takes. The acting peer is `local_peer_id` — the peer
## this machine is playing as, which a solo session sets to the host id — and
## nothing about the request comes from outside, so there is no sender to
## distrust here.
static func apply_local_activation(slot: int) -> bool:
	if not NetworkManager.is_host:
		last_refusal = REFUSAL_NOT_HOST
		return false
	var actor: Player = NetworkManager.get_player(NetworkManager.local_peer_id)
	if actor == null:
		last_refusal = REFUSAL_NO_PLAYER
		return false
	var controller: ActiveRelicController = for_player(actor)
	if controller == null:
		last_refusal = REFUSAL_NO_PLAYER
		return false
	return controller.activate(slot)


## Host only. Fires `slot`. The relic's effect, resolved through the player's
## `EffectHost` — the same node every other attach path uses, so a slot can
## never fire a relic the player does not hold.
func _effect_of(data: RelicData) -> Effect:
	if data == null:
		return null
	var host: EffectHost = RelicFlow.effect_host_of(player)
	if host == null:
		return null
	return host.get_effect(data.id)


# --- the room refill ---------------------------------------------------------


## Every room this player enters, refill the slots whose relic states it
## (SPEC-relics "Active relics": "charges refill per room where stated"). The
## entering player is checked, because `room_entered` fires for whoever walked
## in and a teammate's room is not this player's reload.
func _on_room_entered(_room: Node, who: Player) -> void:
	if player == null:
		player = _resolve_player()
	if who == null or who != player:
		return
	for slot: int in range(SLOT_1, SLOT_COUNT + 1):
		var data: RelicData = slot_data(slot)
		if data == null:
			continue
		var effect: Effect = _effect_of(data)
		if effect == null or not effect.refills_charges_per_room():
			continue
		_charges[slot] = data.active_charges


# --- internals ---------------------------------------------------------------


## The player this controller drives: its parent when that is a Player.
func _resolve_player() -> Player:
	var parent: Node = get_parent()
	if parent is Player:
		return parent as Player
	return null
