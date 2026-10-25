class_name Chest
extends Area2D
## The chest: the interactable a TREASURE room holds 2 to 3 of. Owned by
## run-economy (W4-B8, goal G15).
##
## SPEC-run-economy, "Chests, breakables, mining nodes": "`LootTable` Resource:
## weighted entries `{kind, id or rarity, weight, min, max}`. Chest rarity tiers
## common/rare/legendary; Treasure room has 2 to 3 chests ... Luck stat raises
## rarity rolls: `rarity_roll += LUCK * 0.01`." SPEC-relics, "Shrine flow":
## "Merchant shops and Treasure chests use the same roll helper
## `RelicRoller.roll(player, count, allow_cursed)`."
##
## Three sentences, three parts. An **open** rolls the tier's `LootTable` under
## `data/loot/` and pays it through `LootDrops` — the same credit and the same
## pickup as an enemy death, so a chest cannot invent a second way for a coin to
## reach a pool. The **relic draw** is `RelicRoller.roll()`, the helper the spec
## names, on the same `count` and `allow_cursed` the spec leaves to the caller;
## this file reads them off `RELIC_COUNT` and `ALLOW_CURSED`, which is where the
## two judgement calls are recorded. The **tier** is the game's own rarity roll,
## Luck-shifted and then promoted to a chest tier, so the paragraph's Luck
## sentence is the shipped `LootTable` formula rather than a second one.
##
## Sync: host-authoritative. `loot()` is the host body and refuses off-host; a
## client's `interact()` forwards up the request path and opens nothing locally,
## so a chest cannot be spent on the wrong peer. The open flag is host state and
## is replicated as part of the room's `cleared` presentation once Dev A's
## `Room` lands.
##
## blocked on Dev A (W3-A3): registering the TREASURE populator is a guarded
## no-op until `RoomPopulator.generator_script()` resolves, so no generated
## floor places a chest yet. Nothing else here depends on the other lane; the
## swap-in is nothing (this call starts working the moment
## `scripts/generation/floor_generator.gd` exists with `RoomType.TREASURE` and
## the static `register_populator(type, populator)`).

## A client forwarded its open to the host (the request_* path).
signal interaction_forwarded(peer_id: int)
## Host: the drops this open produced, in the order they were credited.
signal looted(peer_id: int, drops: Array[Dictionary])
## Host: the relic ids this open offered the opener.
signal relics_rolled(peer_id: int, ids: Array[StringName])

## What the prompt says. SPEC-player-controller's interact scan looks for an
## area with `prompt_text` and `interact(player)`.
const PROMPT_TEXT: String = "Open"
## Press, not hold: only revive holds an interact (SPEC-player-controller).
const HOLD_SECONDS: float = 0.0
## Physics layer 6, "interactable" (project.godot layer_names).
const INTERACTABLE_LAYER: int = 32
## The scene the populator spawns. Loaded at runtime rather than preloaded,
## because that scene's root script is this file and a preload would be a cycle.
const SCENE_PATH: String = "res://scenes/dungeon/interactables/chest.tscn"
## Where the three tier tables live (SPEC-run-economy, "Data model":
## "`LootTable extends Resource` under `data/loot/`").
const TABLE_DIR: String = "res://data/loot"
## The table each tier opens, by file name. One entry per `LootTable.CHEST_TIERS`
## member, so a missing tier is a missing key rather than a silent fallback.
const TIER_FILES: Dictionary[int, String] = {
	LootTable.CHEST_TIER_COMMON: "chest_common.tres",
	LootTable.CHEST_TIER_RARE: "chest_rare.tres",
	LootTable.CHEST_TIER_LEGENDARY: "chest_legendary.tres",
}
## The rarities a chest tier is rolled from, ascending. `Cursed` is left out
## because a chest never makes one.
const RARITIES: Array[int] = [
	RelicData.Rarity.COMMON, RelicData.Rarity.RARE, RelicData.Rarity.EPIC, RelicData.Rarity.LEGENDARY,
]

## SPEC-run-economy: "Treasure room has 2 to 3 chests", both ends reachable.
const MIN_CHESTS: int = 2
const MAX_CHESTS: int = 3

## The room type the populator is registered under. SPEC-floor-generation's room
## table: "`TREASURE` | 1 per floor, chests, dead end preferred".
const ROOM_TYPE: StringName = &"TREASURE"

## How many relics one open draws, and whether a cursed one may come up. Both are
## the caller's to choose (SPEC-relics writes them as `count` and
## `allow_cursed`), and both are judgement calls this goal records: the design
## doc's Trickster node says "chests can drop double", which makes one the
## ordinary count, and SPEC-relics gives cursed relics exactly one source, the
## `CURSED_ALTAR` ("`CURSED_ALTAR` populator spawns an altar with 1 cursed
## relic"), which makes a chest none.
const RELIC_COUNT: int = 1
const ALLOW_CURSED: bool = false

## Registering the populator is once per process; a second call is a no-op.
static var _populator_registered: bool = false
## The blocked-on-Dev-A note is worth one line per process, not one per call.
static var _blocker_logged: bool = false

var prompt_text: String = PROMPT_TEXT
var hold_seconds: float = HOLD_SECONDS
## The table this chest opens, when it is not its rolled tier's. A case pins it
## to a single-entry fixture so the payout is an exact number rather than a
## property of a random roll.
@export var table_path: String = ""
## The spawner every drop goes through. Resolved from the world on ready, and
## handed in directly by a case; null is fine, because a drop with nowhere to
## land is still a drop the host has paid.
var spawner: PickupSpawner = null

## Host state: the open happened, so the chest is spent.
var _open: bool = false
## Host state: the tier this chest was rolled as, `-1` before it was opened.
var _tier: int = -1


func _ready() -> void:
	if spawner == null:
		spawner = RoomPopulator.world_pickup_spawner()


# --- the Interactable contract ---------------------------------------------


## Called by the player's interact scan with the acting player
## (SPEC-player-controller). The host opens; a client forwards.
func interact(player: Player) -> void:
	if not NetworkManager.is_host:
		_forward_use(peer_id_of(player))
		return
	loot(player)


## The peer behind an interactor; the local peer when the caller names none.
func peer_id_of(player: Player) -> int:
	if player == null:
		return NetworkManager.local_peer_id
	return player.peer_id


## True once this chest has been opened. Host state.
func is_open() -> bool:
	return _open


## The tier this chest was rolled as, or `-1` before it was opened.
func tier() -> int:
	return _tier


# --- the host body ----------------------------------------------------------


## Host only. Rolls the tier, opens the tier's table, credits and spawns what it
## held, then draws the relic offer. Returns the drops it produced — empty on a
## client, on a chest that is already open, and with no live run to pay into
## (the chest stays shut rather than being spent for nothing).
func loot(player: Player) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	if _open or not NetworkManager.is_host:
		return drops
	var run: RunState = GameState.run
	if run == null:
		return drops
	_open = true
	var opener: int = peer_id_of(player)
	var luck: float = RelicRoller.luck_of(player)
	var rng: RandomNumberGenerator = RelicRoller.seeded_rng()
	_tier = tier_from_roll(rng.randf(), luck)
	if table_path == "":
		table_path = table_path_for_tier(_tier)
	var table: LootTable = table_at(table_path)
	if table != null:
		var drop: Dictionary = table.roll(rng, luck)
		if not drop.is_empty():
			drops.append(drop)
			LootDrops.credit(run, player, drop)
			LootDrops.spawn_drop(drop, global_position, player, spawner)
	var ids: Array[StringName] = RelicRoller.roll(player, relic_count(_tier), allows_cursed(_tier))
	if not ids.is_empty():
		relics_rolled.emit(opener, ids)
	looted.emit(opener, drops)
	return drops


# --- the client path --------------------------------------------------------


## Client path. The host owns the open, so it travels up as a request and
## nothing changes locally. With no session there is nobody to ask.
## blocked on Dev B (G15): SPEC-run-economy names no open request, so the
## forwarded open stops at the signal rather than inventing an RPC name the wire
## does not have. The shape is `Shrine._forward_use()`'s.
func _forward_use(peer_id: int) -> void:
	if not NetworkManager.is_active:
		push_warning("[run] chest refused: no session to send the request on")
		return
	interaction_forwarded.emit(peer_id)


# --- the tier ---------------------------------------------------------------


## The table path a tier opens. A tier the spec does not name — and the `-1` of a
## chest that has not been opened — reads as the common chest, so a chest always
## has something to open.
static func table_path_for_tier(tier: int) -> String:
	var file: String = TIER_FILES.get(tier, TIER_FILES[LootTable.CHEST_TIER_COMMON])
	return TABLE_DIR.path_join(file)


## The `LootTable` a tier opens, or null when the file will not load.
static func table_for_tier(tier: int) -> LootTable:
	return table_at(table_path_for_tier(tier))


## The `LootTable` at `path`, or null. Split out so an opened chest reads the
## same loader whether the path came from its tier or from `table_path`.
static func table_at(path: String) -> LootTable:
	if path == "":
		return null
	return load(path) as LootTable


## The chest tier a rarity roll lands in. The roll itself is `LootTable`'s — the
## same four weights and the same Luck shift every other roll in the game uses —
## and a rarity no chest drawer holds (epic) is promoted to the tier above it, so
## a chest that rolls epic holds legendary-quality rather than being downgraded.
static func tier_from_roll(rarity_roll: float, luck: float = 0.0) -> int:
	return tier_from_rarity(LootTable.rarity_for_roll(LootTable.shifted_rarity_roll(rarity_roll, luck)))


## The chest tier `rarity` is promoted to: the first chest tier at or above it,
## and the top tier when there is none (cursed, which a chest never rolls).
static func tier_from_rarity(rarity: int) -> int:
	for tier: int in LootTable.CHEST_TIERS:
		if tier >= rarity:
			return tier
	return LootTable.CHEST_TIERS[LootTable.CHEST_TIERS.size() - 1]


## The weight `tier` is rolled with: every rarity that promotes into it, which is
## `RelicData`'s own weight for its own rarity. The four rarities' weights land on
## three tiers and still add up to 100, so the spec's sentence about chest tiers
## in the Luck paragraph is the game's rarity table and not a second one.
static func tier_weight(tier: int) -> int:
	var total: int = 0
	for rarity: int in RARITIES:
		if tier_from_rarity(rarity) == tier:
			total += RelicData.roll_weight(rarity)
	return total


# --- the relic draw ---------------------------------------------------------


## How many relics a tier's open draws. The tier is the parameter rather than
## nothing because a caller that wants a richer chest has one place to say so.
static func relic_count(_tier: int) -> int:
	return RELIC_COUNT


## Whether a tier's open may draw a cursed relic.
static func allows_cursed(_tier: int) -> bool:
	return ALLOW_CURSED


## The stock the draw is made from: `RelicRoller`'s own pool, so a chest and a
## shrine offer the same relics and the content folder has one reader.
static func relic_pool() -> Array[RelicData]:
	return RelicRoller.load_pool()


# --- the TREASURE populator and its registration seam -----------------------


## The Callable the TREASURE room populator is registered as:
## `FloorGenerator.register_populator(RoomType.TREASURE, Chest.treasure_populator())`.
static func treasure_populator() -> Callable:
	return Callable(Chest, &"_populate_treasure_room")


## Registers the TREASURE populator with Dev A's registry, once per process.
## Returns true when it registered, false while the registry is absent.
## Guarded on purpose: a floor must never depend on the other lane landing first
## (BRIEF Assumption 4), so the absent-registry path is a recorded no-op that
## notes its blocker **once** — a floor change must not reprint it.
## blocked on Dev A (W3-A3): the swap-in is nothing — this call starts working
## the moment floor_generator.gd exists with RoomType.TREASURE and the static
## register_populator(type, populator).
static func register_populator() -> bool:
	if _populator_registered:
		return true
	var generator: Script = RoomPopulator.generator_script()
	if generator == null:
		_note_blocked("%s does not exist yet, so a chest spawns with the registry" % RoomPopulator.GENERATOR_SCRIPT_PATH)
		return false
	if not generator.has_method(RoomPopulator.REGISTER_METHOD):
		_note_blocked("%s has no %s()" % [RoomPopulator.GENERATOR_SCRIPT_PATH, RoomPopulator.REGISTER_METHOD])
		return false
	var room_type: Variant = room_type_value(generator)
	if room_type == null:
		_note_blocked("%s declares no RoomType.TREASURE" % RoomPopulator.GENERATOR_SCRIPT_PATH)
		return false
	generator.call(RoomPopulator.REGISTER_METHOD, room_type, treasure_populator())
	_populator_registered = true
	print("[run] TREASURE populator registered with FloorGenerator")
	return true


## How many blocked-on-Dev-A notes this process has written: 0, or 1. The guarded
## registration notes its blocker once and a second call is inert, and this read
## is how that is a checked claim rather than a comment.
static func blocker_warnings() -> int:
	return 1 if _blocker_logged else 0


## The `RoomType.TREASURE` value, read off a generator script's own constants so
## this file never references a type that does not exist yet. Public because the
## registration test drives it with a registry double.
static func room_type_value(generator: Script) -> Variant:
	return RoomPopulator.room_type_value(generator, ROOM_TYPE)


## Host only. Fills `room` with `MIN_CHESTS` to `MAX_CHESTS` chests and returns
## them, or an empty array when it refused (not the host, no room). The generator
## calls this through `treasure_populator()` after painting the room.
static func populate_room(room: Node, rng: RandomNumberGenerator = null) -> Array[Chest]:
	var generator: RandomNumberGenerator = rng
	if generator == null:
		generator = RelicRoller.seeded_rng()
	return place_in(room, generator.randi_range(MIN_CHESTS, MAX_CHESTS))


## Host only. Adds `count` chests to `room` and returns them. Public because the
## populator is one caller and a room's own author is another.
static func place_in(room: Node, count: int = 1) -> Array[Chest]:
	var spawned: Array[Chest] = []
	if not NetworkManager.is_host:
		return spawned
	if room == null:
		push_warning("[run] TREASURE populator called with no room")
		return spawned
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("[run] TREASURE populator could not load %s" % SCENE_PATH)
		return spawned
	for chest_index: int in range(maxi(count, 0)):
		var chest: Chest = packed.instantiate() as Chest
		if chest == null:
			push_warning("[run] %s does not instantiate as a Chest" % SCENE_PATH)
			break
		# TODO(floor-generation, W3-A2): sit on RoomSpec's interactable anchor
		# once Room exposes it; the room's origin is the stand-in, as it is for
		# the rope and the shrine.
		chest.position = RoomFurniture.spot(chest_index, count)
		room.add_child(chest)
		spawned.append(chest)
	return spawned


## The registered populator, in the `Callable(room: Room) -> void` shape
## SPEC-floor-generation declares. Thin on purpose: `populate_room` carries the
## body, and the room does not choose the count because the spec does.
static func _populate_treasure_room(room: Node) -> void:
	populate_room(room)


## Notes the blocked path once per process.
static func _note_blocked(detail: String) -> void:
	if _blocker_logged:
		return
	_blocker_logged = true
	push_warning("[run] TREASURE populator not registered — %s" % RoomPopulator.blocker_line(detail))
