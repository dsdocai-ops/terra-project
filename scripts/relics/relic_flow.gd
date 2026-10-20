class_name RelicFlow
extends RefCounted
## The host half of the Shrine pick flow: validates a client's
## `request_pick_relic(index)` against the offer that peer actually received,
## attaches the chosen relic through the player's `EffectHost`, emits
## `relic_picked`, appends it to the peer's `RunPlayerState.relics` and records
## it in the codex. Owned by relics (W4-B5, PLAN G10 / raw goals G30 + G31).
##
## SPEC-relics "Shrine flow": "`SHRINE` populator spawns a `Shrine` interactable.
## Interact (host validates one use per player per shrine) rolls 3 relics the
## player does not already hold at max stacks and sends
## `relic_choice_offered(peer_id, ids)`; `ui-hud` shows the popup;
## `request_pick_relic(index)`; host attaches via `EffectHost.add`, emits
## `relic_picked`, updates codex." The Shrine (G9) produces the offer; this file
## is everything after it.
##
## Sync: host-authoritative. The host owns the offer, the validation, the attach,
## the run slice and the codex write; a client never attaches a relic or rolls
## one. `NetworkManager.request_pick_relic` is the `any_peer` request and reads
## `multiplayer.get_remote_sender_id()` before calling `apply_pick_request()`;
## the host -> everyone broadcasts (`relic_choice_offered`, `relic_picked`) are
## `authority` RPCs on `NetworkManager`, the same split `Rope` and the revive
## contract use.
##
## The offer lives here rather than on the Shrine because the RPC is on
## `NetworkManager`: the shrine node is spawned by the host's populator, so a
## client never holds the instance whose `_offers` could be consulted, and a
## host-side handler must not reach through the scene tree to find it
## (SPEC-project forbids cross-module tree-path reach-through). `Shrine` hands
## its offer over on the one line after it announces it — one owner for the
## pick's state, one for the roll's.
##
## blocked on Dev A (W2-A1, player.tscn): the player scene has no `EffectHost`
## child yet; the attach path resolves it with `EffectHost.NODE_NAME` exactly as
## `EffectHostPlayer` installs it, so the swap-in moves the node into the scene
## and touches nothing here. Until then a pick is refused with
## `REFUSAL_NO_EFFECT_HOST` rather than silently dropped.
##
## blocked on save-system (week 5): `SaveManager.profile` is a null `RefCounted`
## stub. The codex write below reads and writes the `codex.relics` field
## SPEC-save-system already names, creating the holder on first use, and changes
## no save schema and no serialisation — `SaveManager.save()` is still its week-1
## stub.

## Where a relic's data lives (SPEC-project: `data/<type>/<id>.tres`).
const DATA_DIR: String = "res://data/relics/"

## The refusal reasons. The whole host rule is `pick_refusal_reason()`, so the
## RPC, the tests and the log line share one answer rather than three copies.
const REFUSAL_NONE: StringName = &""
## This peer does not host, so it applies nothing.
const REFUSAL_NOT_HOST: StringName = &"not_host"
## A direct local call reports sender 0: that is not a client's request.
const REFUSAL_NOT_A_REQUEST: StringName = &"not_a_request"
## The peer was never offered anything, or its offer was already spent.
const REFUSAL_NO_OFFER: StringName = &"no_offer"
## The index is outside the offer that peer received.
const REFUSAL_BAD_INDEX: StringName = &"bad_index"
## No run is live, so there is nothing to pick into.
const REFUSAL_NO_RUN: StringName = &"no_run"
## The shrine that made the offer is gone.
const REFUSAL_SHRINE_GONE: StringName = &"shrine_gone"
## The offer names no player, or the run keeps no slice for it.
const REFUSAL_NO_PLAYER: StringName = &"no_player"
## The offered id resolves to no `RelicData` under `data/relics/`.
const REFUSAL_NO_DATA: StringName = &"no_data"
## The player carries no `EffectHost` (blocked on Dev A W2-A1).
const REFUSAL_NO_EFFECT_HOST: StringName = &"no_effect_host"
## The player already holds the relic at its `max_stacks`.
const REFUSAL_AT_MAX_STACKS: StringName = &"at_max_stacks"
## `EffectHost.add()` refused the attach (already attached, no effect script).
const REFUSAL_ATTACH_FAILED: StringName = &"attach_failed"

## peer_id -> {ids: Array[StringName], shrine: Node, player: Player}. The offer
## the host announced to that peer and has not yet seen picked. One offer per
## peer: a shrine hands one and the pick consumes it.
static var _pending: Dictionary[int, Dictionary] = {}
## Why the most recent request was refused, `REFUSAL_NONE` when one applied.
## Reset by every attempt, so it is never stale.
static var last_refusal: StringName = REFUSAL_NONE


## The minimal profile holder the codex writes into until save-system's
## `PlayerProfile` lands (week 5). `codex.relics` is the field SPEC-save-system
## names; nothing else is invented and nothing is serialised.
class CodexProfile extends RefCounted:
	var codex: Dictionary = {"relics": []}


## Clears the pending offers and the last refusal. For tests and for a session
## that ends; the real flow spends offers one by one through `apply_pick_request`.
static func reset() -> void:
	_pending.clear()
	last_refusal = REFUSAL_NONE


# --- the offer the Shrine hands over ---------------------------------------


## Host only. Records the offer announced to `peer_id`, so a later
## `request_pick_relic(index)` is validated against **this** peer's offer, and
## records every offered id in the codex — SPEC-relics "Codex": "Every relic seen
## (offered or picked) is added to `profile.codex.relics`". Returns false for a
## request with no peer or no ids.
static func record_offer(peer_id: int, ids: Array[StringName], shrine: Node, player: Player) -> bool:
	if peer_id <= 0 or ids.is_empty():
		return false
	var copy: Array[StringName] = ids.duplicate()
	_pending[peer_id] = {"ids": copy, "shrine": shrine, "player": player}
	for id: StringName in copy:
		record_codex(id)
	return true


## True while `peer_id` still has an unpicked offer from a shrine.
static func has_offer(peer_id: int) -> bool:
	return _pending.has(peer_id)


## The ids `peer_id` was offered, empty when it has none. A copy, so a caller
## cannot edit the record the validation reads.
static func offer_ids(peer_id: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var entry: Variant = _pending.get(peer_id)
	if not entry is Dictionary:
		return out
	var ids: Variant = (entry as Dictionary).get("ids")
	if not ids is Array:
		return out
	for id: Variant in ids as Array:
		out.append(StringName(str(id)))
	return out


# --- the host's validation and apply ---------------------------------------


## Why a `request_pick_relic(index)` from `sender` would be refused right now, or
## `REFUSAL_NONE` when it applies. One place the rules are ordered, so the RPC,
## the seam and the tests cannot disagree:
##  * this peer hosts, and the request came from a remote client (sender > 0);
##  * a run is live and the offering shrine is still there;
##  * the sender has an unpicked offer and `index` is inside it (never trust an
##    index past what that peer was shown);
##  * the offer names a player with a run slice and an `EffectHost`, and the id
##    resolves to content the player does not already hold at `max_stacks`.
static func pick_refusal_reason(sender: int, index: int) -> StringName:
	if not NetworkManager.is_host:
		return REFUSAL_NOT_HOST
	if sender <= 0:
		return REFUSAL_NOT_A_REQUEST
	if GameState.run == null:
		return REFUSAL_NO_RUN
	var entry: Variant = _pending.get(sender)
	if not entry is Dictionary:
		return REFUSAL_NO_OFFER
	var offer: Dictionary = entry as Dictionary
	# is_instance_valid first: `is Node` on a freed instance is an engine error,
	# and a freed shrine is exactly the case this refusal exists for.
	var shrine: Variant = offer.get("shrine")
	if not is_instance_valid(shrine) or not shrine is Node:
		return REFUSAL_SHRINE_GONE
	var ids: Variant = offer.get("ids")
	if not ids is Array:
		return REFUSAL_NO_OFFER
	var list: Array = ids as Array
	if index < 0 or index >= list.size():
		return REFUSAL_BAD_INDEX
	var player: Variant = offer.get("player")
	if not player is Player:
		return REFUSAL_NO_PLAYER
	var actor: Player = player as Player
	var data: RelicData = data_for(StringName(str(list[index])))
	if data == null:
		return REFUSAL_NO_DATA
	if effect_host_of(actor) == null:
		return REFUSAL_NO_EFFECT_HOST
	if RelicRoller.run_slice(actor) == null:
		return REFUSAL_NO_PLAYER
	var held: Dictionary[StringName, int] = RelicRoller.held_counts(actor)
	if int(held.get(data.id, 0)) >= data.max_stacks:
		return REFUSAL_AT_MAX_STACKS
	return REFUSAL_NONE


## Host only. Applies a pick that passed the rule: attaches the relic through
## `EffectHost.add()`, appends its id to the picker's `RunPlayerState.relics`,
## records it in the codex (idempotent — the offer already recorded it) and emits
## `Events.relic_picked`, then announces it to the other peers. The offer is
## consumed, so the same three cannot be picked twice. Returns true when applied;
## a refusal leaves the offer intact and records why in `last_refusal`.
static func apply_pick_request(sender: int, index: int) -> bool:
	var reason: StringName = pick_refusal_reason(sender, index)
	last_refusal = reason
	if reason != REFUSAL_NONE:
		return false
	var offer: Dictionary = _pending[sender]
	var ids: Array = offer["ids"] as Array
	var id: StringName = StringName(str(ids[index]))
	var player: Player = offer["player"] as Player
	var data: RelicData = data_for(id)
	if data == null:
		last_refusal = REFUSAL_NO_DATA
		return false
	var effect_host: EffectHost = effect_host_of(player)
	var effect: Effect = effect_host.add(data)
	if effect == null:
		last_refusal = REFUSAL_ATTACH_FAILED
		return false
	var slice: RunPlayerState = RelicRoller.run_slice(player)
	if slice != null:
		slice.relics.append(id)
	_pending.erase(sender)
	record_codex(id)
	Events.relic_picked.emit(player, data)
	NetworkManager.route_relic_picked(player, data)
	return true


# --- the two reads the flow shares ----------------------------------------


## The player's `EffectHost`, or null when the player carries none. The node name
## is `EffectHost.NODE_NAME`, the same one `EffectHostPlayer` installs and
## `Effect` resolves, so the swap-in into Dev A's player scene is one node.
static func effect_host_of(player: Player) -> EffectHost:
	if player == null:
		return null
	return player.get_node_or_null(NodePath(EffectHost.NODE_NAME)) as EffectHost


## The `RelicData` for `id` under `data/relics/`, or null when the file is
## absent or is not a `RelicData`. The id is the file name (SPEC-project), which
## is what makes the offer's ids resolvable without carrying Resources over the
## wire.
static func data_for(id: StringName) -> RelicData:
	if id == &"":
		return null
	var path: String = DATA_DIR + String(id) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as RelicData


# --- the codex ---------------------------------------------------------------


## Records `id` in `profile.codex.relics` if it is not already there. Returns
## true when it was new. Called when an offer is announced (seen) and again when
## it is picked (held); the second call is a no-op, which is what makes "picking
## does not double-record" true.
static func record_codex(id: StringName) -> bool:
	if id == &"":
		return false
	var profile: RefCounted = _ensure_profile()
	var codex: Dictionary = _codex_of(profile)
	var seen: Variant = codex.get("relics")
	if not seen is Array:
		seen = []
		codex["relics"] = seen
	var list: Array = seen as Array
	if list.has(id):
		return false
	list.append(id)
	return true


## Every relic id the profile has seen, empty when nothing has been recorded.
static func seen_relics() -> Array[StringName]:
	var out: Array[StringName] = []
	var profile: RefCounted = SaveManager.profile
	if profile == null:
		return out
	var codex: Variant = profile.get(&"codex")
	if not codex is Dictionary:
		return out
	var seen: Variant = (codex as Dictionary).get("relics")
	if not seen is Array:
		return out
	for id: Variant in seen as Array:
		out.append(StringName(str(id)))
	return out


## The profile the codex writes into: `SaveManager.profile` when save-system has
## created one, otherwise the minimal holder above, installed into the existing
## slot so the field path is the spec's (`profile.codex.relics`) from day one.
static func _ensure_profile() -> RefCounted:
	var profile: RefCounted = SaveManager.profile
	if profile == null:
		profile = CodexProfile.new()
		SaveManager.profile = profile
	return profile


## The `codex` dictionary on `profile`, created in place when absent.
static func _codex_of(profile: RefCounted) -> Dictionary:
	var existing: Variant = profile.get(&"codex")
	if existing is Dictionary:
		return existing as Dictionary
	var made: Dictionary = {"relics": []}
	profile.set(&"codex", made)
	return made
