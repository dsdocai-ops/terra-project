class_name OrePayout
extends RefCounted
## The Ore payout table, the biome-to-ore lookup and Wren's +25%. Owned by
## run-economy (W4-B8, goal G14).
##
## SPEC-run-economy, "Currencies": "Ore | mining nodes (interactable, 3 hits with
## any attack, Wren +25%), elites 1, mini-boss 3, biome boss 6, always the
## biome's ore: copper, iron, crystal, pearl, ember_ore, heartstone | shared".
## SPEC-biomes' biome table gives the same six in biome order, which is what
## `data/ore/<id>.tres`'s `biome_index` records and what `id_for_biome()` reads.
##
## Ore is a **shared** pool (`RunState.shared_ore`, ore id -> amount), so
## `award()` credits the party rather than a player — but the amount can still
## depend on the killer, because Wren's character passive is a property of one
## player and the spec says the ore is hers to raise. So the two questions are
## separate: `amount_for(kill_kind)` is the table's, and
## `amount_for_kill(kill_kind, player)` is that amount through the earner's own
## bonus.
##
## **Wren's passive is read as an id off the effect host**, the same read
## `EchoShards.collector_bonus()` makes and `Pickup.holds_room_wide_relic()`
## already makes: every class passive is an `Effect` attached to the player's
## host (SPEC-classes-characters: `passive_effect` is "always attached"), so the
## id is the whole of "is this player Wren". The passive's content is
## `classes-characters`' and is not in the tree — **blocked on Dev A (W5-A)** —
## so a run without it reads 1.0 and pays the bare table.
##
## Sync: host only, for the same reason every currency total is
## (SPEC-run-economy, "Multiplayer ownership"). `award()` refuses off-host.

## The folder the six `OreData` resources live in.
const ORE_DIR: String = "res://data/ore"

## The three kill payouts, from the spec's own sentence: "elites 1, mini-boss 3,
## biome boss 6". Mining nodes are the fourth source and are not a kill — they
## are `run-economy`'s own interactable (W4-B8, goal G15) and pay by the node's
## own yield, so they are deliberately absent from this table.
const ORE_ELITE: int = 1
const ORE_MINI_BOSS: int = 3
const ORE_BIOME_BOSS: int = 6

## The kill kinds the table is keyed by, so a caller names a kind with a constant
## instead of a literal.
const KIND_ELITE: StringName = &"elite"
const KIND_MINI_BOSS: StringName = &"mini_boss"
const KIND_BIOME_BOSS: StringName = &"biome_boss"

## The kill payout of each kind, keyed by the constants above.
const PAYOUT_BY_KIND: Dictionary[StringName, int] = {
	KIND_ELITE: ORE_ELITE,
	KIND_MINI_BOSS: ORE_MINI_BOSS,
	KIND_BIOME_BOSS: ORE_BIOME_BOSS,
}

## Wren, the Miner's Daughter: "Ore drops +25%" (design doc 4.1, SPEC-classes-
## characters' character table). Read off the effect host under this id; the
## passive's own content is `classes-characters`' and is not in the tree yet
## (blocked on Dev A, W5-A), so the read answers false and the bonus is 1.0.
const WREN_EFFECT_ID: StringName = &"wren_ore_bonus"
const WREN_ORE_BONUS: float = 0.25

## The biome range the ore table is defined over, matching `RunState.MIN_BIOME` /
## `MAX_BIOME`.
const MIN_BIOME: int = 1
const MAX_BIOME: int = 6

## The currency id every ore payout is announced under,
## `Events.currency_gained(player, currency, amount)`.
const CURRENCY_ID: StringName = &"ore"

## The node a player's effects are read from (`player.EffectHost`).
const EFFECT_HOST_NODE: NodePath = ^"EffectHost"


# --- the table --------------------------------------------------------------


## The ore a `kill_kind` pays before any character bonus: 1 for an elite, 3 for
## a mini-boss, 6 for a biome boss, 0 for a kind the spec does not name.
static func amount_for(kill_kind: StringName) -> int:
	return PAYOUT_BY_KIND.get(kill_kind, 0)


## `player`'s ore multiplier: 1.25 while Wren's passive is attached, 1.0
## otherwise. Read as an id off the holder's `EffectHost`, so a player with no
## host reads 1.0 — the same answer as not being Wren.
static func bonus_for(player: Player) -> float:
	if player == null:
		return 1.0
	var host: EffectHost = player.get_node_or_null(EFFECT_HOST_NODE) as EffectHost
	if host == null:
		return 1.0
	if not host.has_effect(WREN_EFFECT_ID):
		return 1.0
	return 1.0 + WREN_ORE_BONUS


## The ore `kill_kind` pays to `player`: the table's amount through the earner's
## own bonus, rounded once. 0 stays 0, so an unknown kind cannot be inflated into
## a payout by the bonus.
static func amount_for_kill(kill_kind: StringName, player: Player) -> int:
	var base: int = amount_for(kill_kind)
	if base <= 0:
		return 0
	return maxi(roundi(float(base) * bonus_for(player)), 0)


# --- the biome's ore --------------------------------------------------------


## Every ore id in `data/ore/`, sorted by the biome it belongs to. Read off the
## folder rather than a list here, so a new ore is one `.tres` and no code
## (SPEC-project: content is data). No cache, because a cached list would outlive
## an edit — and this is read on an elite death, not per frame.
static func ore_ids() -> Array[StringName]:
	var found: Array[OreData] = all_ore()
	var ids: Array[StringName] = []
	for ore: OreData in found:
		ids.append(ore.id)
	return ids


## Every `OreData` under `data/ore/`, in biome order. An unreadable folder or a
## file that is not an `OreData` is skipped rather than fatal.
static func all_ore() -> Array[OreData]:
	var found: Array[OreData] = []
	var dir: DirAccess = DirAccess.open(ORE_DIR)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".tres"):
			var ore: OreData = load(ORE_DIR.path_join(entry)) as OreData
			if ore != null:
				found.append(ore)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort_custom(_by_biome)
	return found


## The ore `biome_index` mines, or an empty id when no file claims that biome.
## SPEC-biomes gives each of the six biomes exactly one ore, so this is a
## lookup and not a roll.
static func id_for_biome(biome_index: int) -> StringName:
	if biome_index < MIN_BIOME or biome_index > MAX_BIOME:
		return &""
	for ore: OreData in all_ore():
		if ore.biome_index == biome_index:
			return ore.id
	return &""


## The `OreData` for `id`, or null when `data/ore/` holds no such file.
static func load_ore(id: StringName) -> OreData:
	if id == &"":
		return null
	return load(ORE_DIR.path_join("%s.tres" % id)) as OreData


# --- the award --------------------------------------------------------------


## Host only. Adds `amount` of the biome's ore to the party's shared pool,
## announces it once on `Events.currency_gained`, and returns what was added.
## 0 — writing nothing and announcing nothing — off-host, without a run, without
## a biome that has an ore, or for a non-positive amount.
##
## `player` is the earner and is named in the announcement; it may be null (a
## hazard kill pays the party but names nobody).
static func award(
	run: RunState,
	player: Player,
	kill_kind: StringName,
	amount_override: int = 0,
) -> int:
	if not NetworkManager.is_host:
		push_warning("[ore] payout refused: the host owns currency totals")
		return 0
	if run == null:
		return 0
	var ore_id: StringName = id_for_biome(run.biome_index)
	if ore_id == &"":
		push_warning("[ore] biome %d has no ore resource; payout dropped" % run.biome_index)
		return 0
	var amount: int = amount_override if amount_override > 0 else amount_for_kill(kill_kind, player)
	if amount <= 0:
		return 0
	run.shared_ore[ore_id] = int(run.shared_ore.get(ore_id, 0)) + amount
	Events.currency_gained.emit(player, CURRENCY_ID, amount)
	return amount


## Biome-ascending order, so `ore_ids()` is the spec's biome table order.
static func _by_biome(a: OreData, b: OreData) -> bool:
	return a.biome_index < b.biome_index
