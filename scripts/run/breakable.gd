class_name Breakable
extends Area2D
## A crate, a barrel or a pile of bones: the room furniture that may hold a few
## coins. Owned by run-economy (W4-B8, goal G15).
##
## SPEC-run-economy, "Chests, breakables, mining nodes": "Breakables (crates,
## barrels, bones) drop small gold with 30% chance." That sentence is the whole
## of this file: one hit breaks it, the break rolls one chance, and the chance
## pays a small `LootTable` drop through `LootDrops` — the same credit and the
## same coin as an enemy death, so a crate cannot invent a second way for gold to
## reach the shared pool.
##
## The chance and the range are content: `data/loot/breakable.tres` is a
## `LootTable` whose single entry is `{kind: gold, weight: 0.30, min: 1, max: 3}`,
## and `GOLD_DROP_CHANCE` / `SMALL_GOLD_MIN` / `SMALL_GOLD_MAX` are this file's
## reading of it, pinned to it by `test_containers.gd` so the two cannot drift the
## way `LUCK_SHIFT_PER_POINT` cannot. `gold_chance` is a plain field on top of
## them, so a case can force the roll on and off instead of reproducing a 30%
## chance statistically.
##
## Sync: host-authoritative. `break_it()` is the host body and refuses off-host;
## a client's `interact()` forwards and breaks nothing locally, so a crate cannot
## be spent on the wrong peer. `_broken` is host state.
##
## blocked on Dev A (W3-A3): nothing places a breakable yet, because
## SPEC-floor-generation names no breakable room type — a crate is room furniture
## whose count belongs to the room's author, so `place_in(room, count)` waits on
## Dev A's `Room` and its populator registry rather than registering a room type
## run-economy invented. The swap-in is one call in the generator.

## A client forwarded its hit to the host.
signal interaction_forwarded(peer_id: int)
## Host: the break, with what it paid. `gold` is 0 on the 70% of rolls that pay
## nothing, so a listener can tell a broken crate from a broken empty crate.
signal broke(peer_id: int, gold: int)

## What the prompt says. SPEC-player-controller's interact scan looks for an
## area with `prompt_text` and `interact(player)`.
const PROMPT_TEXT: String = "Smash"
## Press, not hold: only revive holds an interact (SPEC-player-controller).
const HOLD_SECONDS: float = 0.0
## Physics layer 6, "interactable" (project.godot layer_names).
const INTERACTABLE_LAYER: int = 32
## The scene `place_in()` spawns. Loaded at runtime rather than preloaded,
## because that scene's root script is this file and a preload would be a cycle.
const SCENE_PATH: String = "res://scenes/dungeon/interactables/breakable.tscn"

## The table that carries the 30% chance and the small-gold range, in `data/loot/`
## with the chest tiers (SPEC-run-economy, "Data model").
const TABLE_PATH: String = "res://data/loot/breakable.tres"

## SPEC-run-economy: "drop small gold with 30% chance". The number the spec gives;
## `default_gold_chance()` reads the same one out of the table.
const GOLD_DROP_CHANCE: float = 0.30
## SPEC-run-economy: "small gold" — one to three, which is a coin's worth and not
## a chest's. The same reading the table carries.
const SMALL_GOLD_MIN: int = 1
const SMALL_GOLD_MAX: int = 3
## A crate is one hit. The spec gives no count for a breakable (it gives one only
## for the mining node's three), and a breakable that survived a hit would be a
## mining node.
const HITS_REQUIRED: int = 1

var prompt_text: String = PROMPT_TEXT
var hold_seconds: float = HOLD_SECONDS
## The chance this breakable's break pays anything. Starts at the spec's 30% and
## is a field so a case can force either end without a statistical assertion.
var gold_chance: float = GOLD_DROP_CHANCE
## The spawner the coin goes through. Resolved from the world on ready; null is
## fine, because the gold is the host's to give whether or not a coin lands.
var spawner: PickupSpawner = null

## Host state: the crate is gone.
var _broken: bool = false


func _ready() -> void:
	if spawner == null:
		spawner = RoomPopulator.world_pickup_spawner()


# --- the Interactable contract ---------------------------------------------


## Called by the player's interact scan with the acting player
## (SPEC-player-controller). The host breaks; a client forwards.
func interact(player: Player) -> void:
	if not NetworkManager.is_host:
		_forward_use(peer_id_of(player))
		return
	apply_hit(player)


## The peer behind an interactor; the local peer when the caller names none.
func peer_id_of(player: Player) -> int:
	if player == null:
		return NetworkManager.local_peer_id
	return player.peer_id


## True once this crate has been broken. Host state.
func is_broken() -> bool:
	return _broken


# --- the break --------------------------------------------------------------


## Combat's entry point. Host only: true when this hit is what broke the crate,
## false off-host, on a crate that is already broken, and with no live run to pay
## into (a crate is not spent for nothing).
func apply_hit(attacker: Player = null) -> bool:
	if _broken or not NetworkManager.is_host or GameState.run == null:
		return false
	break_it(attacker)
	return true


## Host only. Breaks the crate and returns the gold it paid: 0 when it was
## already broken, when the caller is not the host, when there is no run, and on
## the 70% of rolls that pay nothing. The crate is broken either way — the chance
## decides the coins, not the break.
func break_it(attacker: Player = null) -> int:
	if _broken or not NetworkManager.is_host:
		return 0
	var run: RunState = GameState.run
	if run == null:
		return 0
	_broken = true
	var paid: int = 0
	var rng: RandomNumberGenerator = RelicRoller.seeded_rng()
	if rolls_gold(gold_chance, rng.randf()):
		var amount_range: Vector2i = gold_range()
		var drop: Dictionary = {
			"kind": Pickup.KIND_GOLD,
			"id": &"",
			"rarity": LootTable.RARITY_NONE,
			"amount": rng.randi_range(amount_range.x, amount_range.y),
		}
		paid = int(drop.get("amount", 0))
		LootDrops.credit(run, attacker, drop)
		LootDrops.spawn_drop(drop, global_position, attacker, spawner)
	broke.emit(peer_id_of(attacker), paid)
	return paid


## Whether a `chance` in 0..1 pays on this roll. Both ends are exact: a chance of
## 1.0 always pays and a chance of 0.0 never does, so a case can force either
## without depending on `randf()`'s bounds.
static func rolls_gold(chance: float, roll: float) -> bool:
	var clamped: float = clampf(chance, 0.0, 1.0)
	if clamped >= 1.0:
		return true
	return roll < clamped


# --- the content ------------------------------------------------------------


## The breakable's `LootTable`, or null when the file will not load.
static func table() -> LootTable:
	return Chest.table_at(TABLE_PATH)


## The chance the table's first entry carries.
static func default_gold_chance() -> float:
	var entries: Array[LootTable.Entry] = _entries()
	if entries.is_empty():
		return GOLD_DROP_CHANCE
	return clampf(entries[0].weight, 0.0, 1.0)


## The amount range the table's first entry carries, as `(min, max)`.
static func gold_range() -> Vector2i:
	var entries: Array[LootTable.Entry] = _entries()
	if entries.is_empty():
		return Vector2i(SMALL_GOLD_MIN, SMALL_GOLD_MAX)
	return Vector2i(entries[0].min_amount, entries[0].max_amount)


static func _entries() -> Array[LootTable.Entry]:
	var data: LootTable = table()
	if data == null:
		push_warning("[run] breakable table %s did not load" % TABLE_PATH)
		return []
	return data.entry_list()


# --- the client path --------------------------------------------------------


## Client path. The host owns the break, so it travels up as a request and
## nothing changes locally. With no session there is nobody to ask.
## blocked on Dev B (G15): SPEC-run-economy names no hit request, so the
## forwarded hit stops at the signal rather than inventing an RPC name the wire
## does not have. The shape is `Shrine._forward_use()`'s.
func _forward_use(peer_id: int) -> void:
	if not NetworkManager.is_active:
		push_warning("[run] breakable refused: no session to send the request on")
		return
	interaction_forwarded.emit(peer_id)


# --- placement --------------------------------------------------------------


## Host only. Adds `count` breakables to `room` and returns them, or an empty
## array when it refused (not the host, no room, a scene that will not load).
## The count is the caller's because SPEC-floor-generation gives a breakable no
## room type and therefore no placement rule of its own.
static func place_in(room: Node, count: int = 1) -> Array[Breakable]:
	var spawned: Array[Breakable] = []
	if not NetworkManager.is_host:
		return spawned
	if room == null:
		push_warning("[run] breakable placement called with no room")
		return spawned
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("[run] breakable placement could not load %s" % SCENE_PATH)
		return spawned
	for crate_index: int in range(maxi(count, 0)):
		var crate: Breakable = packed.instantiate() as Breakable
		if crate == null:
			push_warning("[run] %s does not instantiate as a Breakable" % SCENE_PATH)
			break
		# TODO(floor-generation, W3-A2): sit on RoomSpec's furniture anchor once
		# Room exposes one; the room's origin is the stand-in, as it is for the
		# rope, the shrine and a chest.
		crate.position = Vector2.ZERO
		room.add_child(crate)
		spawned.append(crate)
	return spawned
