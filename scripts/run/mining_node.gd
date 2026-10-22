class_name MiningNode
extends Area2D
## An ore seam in the rock: three hits with any attack, then the biome's ore.
## Owned by run-economy (W4-B8, goal G15).
##
## SPEC-run-economy, "Currencies": "Ore | mining nodes (interactable, 3 hits with
## any attack, Wren +25%), elites 1, mini-boss 3, biome boss 6, always the
## biome's ore: copper, iron, crystal, pearl, ember_ore, heartstone | shared."
##
## **"Any attack" is why `apply_hit()` takes no weapon and does not look at one.**
## Whatever a player swings, the seam counts a hit; the `damage` argument is there
## because combat's hit path carries one, and the spec's sentence is that it does
## not matter. `HITS_REQUIRED` is the spec's 3, counted here and nowhere else.
##
## **The payout is not computed here.** It goes through `OrePayout.award()` — the
## shipped G14 path, which already reads Wren's `wren_ore_bonus` +25% off the
## holder's `EffectHost` and already resolves the biome's ore — so ore from a seam
## and ore from a boss are one currency, one signal and one piece of bonus
## arithmetic. This file decides only *when* and *how much of what*: the spec's
## kill table names no mining node, so `OrePayout.KIND_MINED` is the seam's own
## row and `MINE_YIELD` is its reading of it.
##
## Sync: host-authoritative. The hit count and the spent flag are host state
## (`SPEC-run-economy, Multiplayer ownership`: "Run state, votes, loot rolls,
## currency totals ... host"); a client's `interact()` forwards up the request
## path and counts nothing, so a seam cannot be emptied faster by hitting it from
## two peers.
##
## blocked on Dev A (W3-A3): SPEC-floor-generation's room-type table names no ore
## room, so a seam is room furniture whose count and placement belong to the
## room's author rather than to a room type run-economy would have to invent. That
## placement is `place_in(room, count)`, and nothing calls it until Dev A's `Room`
## and the populator registry land — `scripts/generation/floor_generator.gd` does
## not exist, so there is no anchor to sit a seam on and no generated floor holds
## one yet. The swap-in is one call in the generator.

## A client forwarded its hit to the host.
signal interaction_forwarded(peer_id: int)
## Host: the seam gave out, with the ore id it paid and how much. `amount` is 0
## when there was no live run to pay into, so a listener can tell a spent seam
## from a paid one.
signal mined(peer_id: int, ore_id: StringName, amount: int)

## What the prompt says. SPEC-player-controller's interact scan looks for an
## area with `prompt_text` and `interact(player)`.
const PROMPT_TEXT: String = "Mine"
## Press, not hold: only revive holds an interact (SPEC-player-controller).
const HOLD_SECONDS: float = 0.0
## Physics layer 6, "interactable" (project.godot layer_names).
const INTERACTABLE_LAYER: int = 32
## The scene `place_in()` spawns. Loaded at runtime rather than preloaded,
## because that scene's root script is this file and a preload would be a cycle.
const SCENE_PATH: String = "res://scenes/dungeon/interactables/mining_node.tscn"

## SPEC-run-economy: "3 hits with any attack". The count the spec gives, and the
## only thing that empties a seam.
const HITS_REQUIRED: int = 3

## What one seam yields, in ore. SPEC-run-economy's sentence gives numbers for
## the three *kills* ("elites 1, mini-boss 3, biome boss 6") and none for a node,
## so this is run-economy's own reading of `OrePayout`'s row rather than a second
## number: the seam pays what a mini-boss pays, because both are one body of work
## in the rock. Changing it changes `OrePayout.PAYOUT_BY_KIND`, which is one
## place.
const MINE_YIELD: int = OrePayout.ORE_MINED

var prompt_text: String = PROMPT_TEXT
var hold_seconds: float = HOLD_SECONDS
## The spawner the ore chunk goes through. Resolved from the world on ready; null
## is fine, because the ore is the host's to give whether or not a chunk lands.
var spawner: PickupSpawner = null

## Host state: hits taken so far, and whether the seam has given out.
var hits_taken: int = 0
var _depleted: bool = false


func _ready() -> void:
	if spawner == null:
		spawner = RoomPopulator.world_pickup_spawner()


# --- the Interactable contract ---------------------------------------------


## Called by the player's interact scan with the acting player
## (SPEC-player-controller). The host counts the hit; a client forwards.
func interact(player: Player) -> void:
	if not NetworkManager.is_host:
		_forward_use(peer_id_of(player))
		return
	apply_hit(1, player)


## The peer behind an interactor; the local peer when the caller names none.
func peer_id_of(player: Player) -> int:
	if player == null:
		return NetworkManager.local_peer_id
	return player.peer_id


## True once this seam has given out. Host state.
func is_depleted() -> bool:
	return _depleted


## Hits still owed before the seam gives out. Never negative.
func hits_left() -> int:
	return maxi(HITS_REQUIRED - hits_taken, 0)


# --- the hit ----------------------------------------------------------------


## Combat's entry point — "3 hits with any attack". Host only. True when this hit
## landed, false off-host, on a spent seam, and with no live run to pay into (a
## seam is not spent for nothing, so an unpaid hit is not counted either).
##
## `damage` is accepted and ignored: the count is what empties a seam. `attacker`
## is the miner the ore is attributed to, and is who Wren's +25% is read from;
## null is a hazard hit and pays the party, naming nobody.
func apply_hit(damage: int, attacker: Player = null) -> bool:
	if _depleted or not NetworkManager.is_host or GameState.run == null:
		return false
	hits_taken += 1
	if hits_taken < HITS_REQUIRED:
		return true
	pay_out(attacker)
	return true


## The biome's ore id, or an empty id when there is no live run and no biome. One
## line, because `OrePayout` owns the biome-to-ore table.
func ore_id() -> StringName:
	var run: RunState = GameState.run
	if run == null:
		return &""
	return OrePayout.id_for_biome(run.biome_index)


## Host only. Empties the seam and returns the ore it paid, or 0 when it was
## already spent, when the caller is not the host, and when there is no live run.
## The amount is `OrePayout`'s, Wren's bonus included; a seam left unemptied by
## `apply_hit` is emptied here, so the two callers cannot disagree.
func pay_out(attacker: Player = null) -> int:
	if _depleted or not NetworkManager.is_host:
		return 0
	var run: RunState = GameState.run
	if run == null:
		return 0
	_depleted = true
	var paid: int = OrePayout.award(run, attacker, OrePayout.KIND_MINED)
	mined.emit(peer_id_of(attacker), ore_id(), paid)
	_leave_ore(attacker, paid)
	return paid


## A spent seam leaves its ore on the floor as well as in the party's pool, so a
## miner sees what they mined. The chunk is the presentation of a payout that has
## already happened, which is why `OrePayout.award` pays and this only spawns —
## crediting here as well would count the ore twice.
func _leave_ore(attacker: Player, amount: int) -> void:
	if amount <= 0:
		return
	var drop: Dictionary = {
		"kind": Pickup.KIND_ORE,
		"id": ore_id(),
		"rarity": LootTable.RARITY_NONE,
		"amount": amount,
	}
	LootDrops.spawn_drop(drop, global_position, attacker, spawner)


# --- the client path --------------------------------------------------------


## Client path. The host owns the hit count, so it travels up as a request and
## nothing changes locally. With no session there is nobody to ask.
## blocked on Dev B (G15): SPEC-run-economy names no hit request, so the forwarded
## hit stops at the signal rather than inventing an RPC name the wire does not
## have. The shape is `Shrine._forward_use()`'s.
func _forward_use(peer_id: int) -> void:
	if not NetworkManager.is_active:
		push_warning("[run] mining node refused: no session to send the request on")
		return
	interaction_forwarded.emit(peer_id)


# --- placement --------------------------------------------------------------


## Host only. Adds `count` seams to `room` and returns them, or an empty array
## when it refused (not the host, no room, a scene that will not load). The count
## is the caller's because SPEC-floor-generation gives a mining node no room type
## and therefore no placement rule of its own.
static func place_in(room: Node, count: int = 1) -> Array[MiningNode]:
	var spawned: Array[MiningNode] = []
	if not NetworkManager.is_host:
		return spawned
	if room == null:
		push_warning("[run] mining node placement called with no room")
		return spawned
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("[run] mining node placement could not load %s" % SCENE_PATH)
		return spawned
	for seam_index: int in range(maxi(count, 0)):
		var seam: MiningNode = packed.instantiate() as MiningNode
		if seam == null:
			push_warning("[run] %s does not instantiate as a MiningNode" % SCENE_PATH)
			break
		# TODO(floor-generation, W3-A2): sit on RoomSpec's furniture anchor once
		# Room exposes one; the room's origin is the stand-in, as it is for the
		# rope, the shrine and a chest.
		seam.position = Vector2.ZERO
		room.add_child(seam)
		spawned.append(seam)
	return spawned
