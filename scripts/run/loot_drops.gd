class_name LootDrops
extends Node
## The host's drop path: an enemy or elite death rolls its `EnemyData.loot_table`,
## spawns the physical `Pickup`s through `PickupSpawner`, and credits the currency
## the roll produced. Owned by run-economy (W4-B8, goal G14).
##
## SPEC-run-economy, "Currencies": "Gold | enemies (by `EnemyData.loot_table`),
## chests, breakables ... | shared"; "Ore | ... elites 1, mini-boss 3, biome boss
## 6, always the biome's ore ... | shared"; "Echo Shards | ... | per player".
## SPEC-run-economy, "Interfaces consumed": "`enemies-ai`: `elite_killed`,
## `enemy_killed` with `EnemyData.loot_table`". SPEC-run-economy, "Multiplayer
## ownership": "Run state, votes, loot rolls, currency totals ... host."
##
## **Two signals, two payouts, no double count.** An elite's death is announced on
## both `enemy_killed` and `elite_killed` (the G8a decision that made the elite a
## normal death plus a flag), so the two paths are split by *what they pay* rather
## than by which enemy died: the table's drops come from `enemy_killed` alone, and
## the elite's flat Ore and Echo Shards come from `elite_killed` alone. Neither
## path reads the other's numbers, so an elite pays each exactly once however the
## two signals arrive. A case fires both and asserts it.
##
## **A table entry is a drop chance, not a share of one pick.** `LootTable.roll()`
## picks exactly one entry by relative weight — that is the shape a chest or a
## shrine wants, and SPEC-run-economy's own breakable sentence ("Breakables ...
## drop small gold with 30% chance") cannot be expressed as a share of a pick,
## because a single-entry table always picks its entry. So the death path reads
## the entries the other way round: **every entry is rolled independently, and its
## `weight` is the chance it drops** (1.0 is a guaranteed drop, which is how a
## table lists what an enemy always leaves behind). `amount` is uniform in
## `[min, max]`, and a rarity entry floors its tier exactly as `roll()` does. The
## `Entry` objects and the rarity formula are `LootTable`'s — this file reads them
## rather than keeping a second copy of the numbers.
##
## **The credit happens at the roll, not at the coin.** SPEC-run-economy's "Shared
## currencies are collected by whoever touches them" describes the collection path:
## `Pickup.collect()` banks nothing, it only announces `pickup_collected`, so a
## coin is spent once, at the host's roll, and a second touch cannot pay twice. The
## pickup is the presentation of a drop that has already been paid.
##
## Sync: host only. `_can_roll()` is the seam (the enemy spawner's `_can_spawn()`
## shape), so a client rolls nothing, spawns nothing and pays nothing; it learns
## the totals from the replicated run state.
##
## **Blocked on Dev A.** `EnemyData` (`W2-A9`) and the production
## `enemy_killed` / `elite_killed` emitters (`W4-A4`) are `enemies-ai`'s and are
## not in the tree, so the two fields are read off whatever enemy node the signal
## carries (`enemy.data.loot_table`) and the cases drive spec-shaped doubles. The
## swap is mechanical and recorded in `HANDOFF.md`.

## Where the pickup spawner is, when it is not handed in. `world.tscn` puts the
## two side by side under `Entities`.
const SPAWNER_PATH: NodePath = ^"../PickupSpawner"

## The currency ids the two shared pools are announced under. Echo announces
## through `EchoShards.CURRENCY_ID` and Ore through `OrePayout.CURRENCY_ID`, so
## the ids live with the code that pays them.
const CURRENCY_GOLD: StringName = &"gold"

## The kinds that are one player's alone. SPEC-run-economy: "Per-player pickups
## (relics, runes) are per-player drops: each player sees only their own" — the
## spec names these two and nothing else, so a coin, an ore chunk, an echo shard
## and a potion are all shared pickups.
const PER_PLAYER_KINDS: Array[StringName] = [Pickup.KIND_RELIC, Pickup.KIND_RUNE]

## Where the spawner is looked up. Overridden by `world.tscn` if it ever moves.
@export var spawner_path: NodePath = SPAWNER_PATH

## The spawner this node hands its drops to. Resolved from `spawner_path` on
## ready; a case may set it to null to prove the currency is still paid when
## nothing can spawn.
var spawner: PickupSpawner = null


func _ready() -> void:
	if spawner == null:
		spawner = get_node_or_null(spawner_path) as PickupSpawner
	if not Events.enemy_killed.is_connected(on_enemy_killed):
		Events.enemy_killed.connect(on_enemy_killed)
	if not Events.elite_killed.is_connected(on_elite_killed):
		Events.elite_killed.connect(on_elite_killed)


## Host gate. Split out so a case can drive the client side without a second
## instance, exactly as the spawners do with `_can_spawn()`.
func _can_roll() -> bool:
	return NetworkManager.is_host


# --- the two signals --------------------------------------------------------


## Host only. Rolls the dead enemy's `loot_table`, spawns every drop and credits
## what it carried. Returns true when the table was rolled — false on a client,
## on an enemy with no data or no table, and with no live run to pay into.
##
## The killer is `hit.owner_player` (SPEC-effect-system: "the killer, may be null
## (hazard)"). A hazard kill still drops the party's share: the drop is the
## enemy's, not the killer's, so the shared pools move and only the announcement
## — which names a player — is skipped. A per-player drop with no killer pays
## nobody, because there is nobody to pay.
func on_enemy_killed(enemy: Node, hit: HitInfo) -> bool:
	if not _can_roll():
		return false
	var run: RunState = GameState.run
	var table: LootTable = loot_table_of(enemy)
	if run == null or table == null:
		return false
	var killer: Player = killer_of(hit)
	var rng: RandomNumberGenerator = RelicRoller.seeded_rng()
	var at: Vector2 = position_of(enemy)
	for entry: LootTable.Entry in table.entry_list():
		if not _drops(entry, rng):
			continue
		var drop: Dictionary = _roll_drop(entry, rng)
		credit(run, killer, drop)
		spawn_drop(drop, at, killer, spawner)
	return true


## Host only. Pays the flat elite reward: the run counts the kill, the party's
## shared pool gains the biome's ore, and the killer's own Echo Shard total gains
## 1 to 2 through the multiplier table. Returns true when the host paid.
##
## The table's own drops are deliberately **not** rolled here: the game announces
## an elite's death on `enemy_killed` too, and rolling in both places would pay
## the table twice.
func on_elite_killed(enemy: Node, hit: HitInfo) -> bool:
	if not _can_roll():
		return false
	var run: RunState = GameState.run
	if run == null:
		return false
	var killer: Player = killer_of(hit)
	run.elites_killed += 1
	OrePayout.award(run, killer, OrePayout.KIND_ELITE)
	EchoShards.award(run, killer, EchoShards.for_elite())
	return true


# --- reading the enemy ------------------------------------------------------


## The `LootTable` the dead enemy carries, or null. Read off `EnemyData`
## (SPEC-enemies-ai: "`loot_table: LootTable` defined in run-economy"), which is
## Dev A's class and not in the tree — so the read is duck-typed and a missing
## field reads as no table rather than as an error. **Blocked on Dev A (W2-A9).**
func loot_table_of(enemy: Node) -> LootTable:
	if enemy == null or not is_instance_valid(enemy):
		return null
	var data: Variant = enemy.get("data")
	if data == null:
		return null
	return data.get("loot_table") as LootTable


## The player a kill is attributed to, or null for a hazard kill. `hit` may be
## null on a payload that never reached a player (SPEC-effect-system).
func killer_of(hit: HitInfo) -> Player:
	if hit == null:
		return null
	return hit.owner_player


## Where the drops land: the dead enemy's own position. An enemy that is not a
## `Node2D` (a bare `Node` double) drops at the origin rather than at nowhere.
func position_of(enemy: Node) -> Vector2:
	var node_2d: Node2D = enemy as Node2D
	if node_2d == null:
		return Vector2.ZERO
	return node_2d.global_position


# --- the roll ---------------------------------------------------------------


## Whether one entry drops at all: its `weight` read as a chance, clamped to
## 0..1 so a relative-frequency table (weights that sum past 1) cannot make an
## entry drop more than always. Weight 1.0 — the shape an enemy's table is
## authored in — is a guaranteed drop.
func _drops(entry: LootTable.Entry, rng: RandomNumberGenerator) -> bool:
	return rng.randf() < clampf(entry.weight, 0.0, 1.0)


## One entry's drop, in `LootTable.roll()`'s own result shape: `{kind, id,
## rarity, amount}`. Draw order is amount first, then the rarity roll, matching
## `roll()` so a seeded sequence stays stable. The rarity formula is
## `LootTable`'s, not a second copy of it.
func _roll_drop(entry: LootTable.Entry, rng: RandomNumberGenerator) -> Dictionary:
	var drop: Dictionary = {
		"kind": entry.kind,
		"id": entry.id,
		"rarity": LootTable.RARITY_NONE,
		"amount": rng.randi_range(entry.min_amount, entry.max_amount),
	}
	if entry.rolls_rarity():
		drop["id"] = &""
		drop["rarity"] = maxi(entry.rarity, LootTable.rarity_for_roll(rng.randf()))
	return drop


# --- paying -----------------------------------------------------------------


## Credits one drop. Gold and Ore are the party's; Echo Shards are the killer's
## own, so they go through `EchoShards.award()` (which carries the Collector,
## Resonance and Heat multipliers); relics, runes and potions are items, not
## currency, and pay nothing here.
##
## Every shared credit announces `Events.currency_gained` once, under the id of
## the pool it moved — which is what the HUD's currency row listens to. A kill
## with no killer still moves the shared pools and announces nothing, because
## there is no player to name.
##
## Static because it reads no node: a container (`Chest`, `Breakable`,
## `MiningNode`) pays through this one function rather than growing a second way
## for a coin to reach a pool.
static func credit(run: RunState, killer: Player, drop: Dictionary) -> void:
	var kind: StringName = drop.get("kind", &"")
	var amount: int = int(drop.get("amount", 0))
	if amount <= 0:
		return
	match kind:
		Pickup.KIND_GOLD:
			run.shared_gold += amount
			if killer != null:
				Events.currency_gained.emit(killer, CURRENCY_GOLD, amount)
		Pickup.KIND_ORE:
			var ore_id: StringName = drop.get("id", &"")
			if ore_id == &"":
				ore_id = OrePayout.id_for_biome(run.biome_index)
			if ore_id == &"":
				return
			run.shared_ore[ore_id] = int(run.shared_ore.get(ore_id, 0)) + amount
			if killer != null:
				Events.currency_gained.emit(killer, OrePayout.CURRENCY_ID, amount)
		Pickup.KIND_ECHO:
			EchoShards.award(run, killer, amount)


## Spawns the physical pickup for one drop, if there is anywhere to spawn it. A
## drop with no spawner is still paid: the currency is the host's to give, and the
## coin is only how a player sees it.
##
## A per-player drop (`PER_PLAYER_KINDS`) is visible to its earner alone; every other
## kind is everyone's, because the pools they pay are the party's.
##
## Static, with the spawner handed in, so a container pays and presents a drop
## with the same call a death does.
static func spawn_drop(drop: Dictionary, at: Vector2, killer: Player, spawner: PickupSpawner) -> void:
	if spawner == null or not is_instance_valid(spawner):
		return
	var kind: StringName = drop.get("kind", &"")
	var visible_to: int = Pickup.VISIBLE_TO_ALL
	if PER_PLAYER_KINDS.has(kind):
		if killer == null:
			return
		visible_to = killer.peer_id
	spawner.spawn_pickup(kind, drop.get("id", &""), int(drop.get("amount", 0)), at, visible_to)
