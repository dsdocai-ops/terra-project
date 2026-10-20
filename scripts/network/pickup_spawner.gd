class_name PickupSpawner
extends MultiplayerSpawner
## Spawns `Pickup`s under World/Entities on the host (SPEC-run-economy, W4-B8,
## goal G14). `LootDrops` is the caller: an enemy or elite death rolls its
## `EnemyData.loot_table` and hands every drop here.
## Sync: the host calls `spawn_pickup()`; MultiplayerSpawner replays the custom
## spawn function on every peer, including late joiners, and despawns when the
## host frees the node. Per-player drops carry their peer id in the spawn data,
## so the copy a team-mate receives is pointed away from them at spawn time
## rather than after the fact.
##
## The class is the enemy spawner's shape one step over (SPEC-project: "Every
## system names a module id"; the seam is the same `_can_spawn()`), so a client
## cannot conjure loot: it only renders what the host replicated, and the magnet
## that collects it is host-only too (SPEC-run-economy, "Multiplayer ownership":
## "loot rolls, currency totals ... host").

## The scene every drop instantiates. `Pickup` loads it at runtime rather than
## preloading, because that scene's root script is `pickup.gd` and a preload
## from here would be a cycle — this file is the other side of that edge.
const PICKUP_SCENE: PackedScene = preload("res://scenes/pickups/pickup.tscn")

## The node name `LootDrops` looks this up by, and what `world.tscn` calls it.
const NODE_NAME: StringName = &"PickupSpawner"

## The keys of the wire dictionary. Plain `String`s so the spawn payload is
## serialisable as-is (the enemy spawner's `to_dict()` rule).
const KEY_KIND: String = "kind"
const KEY_ID: String = "id"
const KEY_AMOUNT: String = "amount"
const KEY_POSITION: String = "position"
const KEY_VISIBLE_TO: String = "visible_to_peer"


func _ready() -> void:
	spawn_function = _spawn_from_data


## Host-only spawn: only the server spawns loot. Split out so unit tests can
## drive the client side without a second instance.
func _can_spawn() -> bool:
	return multiplayer.is_server()


## Host only. Spawns one pickup at `at` and returns it, or null on a client / on
## failure. `visible_to_peer` is `Pickup.VISIBLE_TO_ALL` for a shared currency
## and the earning peer's id for a per-player drop.
func spawn_pickup(
	kind: StringName,
	id: StringName,
	amount: int,
	at: Vector2,
	visible_to_peer: int = Pickup.VISIBLE_TO_ALL,
) -> Pickup:
	if not _can_spawn():
		push_warning("PickupSpawner.spawn_pickup refused: only the host spawns drops")
		return null
	return spawn(_to_wire(kind, id, amount, at, visible_to_peer)) as Pickup


## The spawn payload for one drop, with plain types only — what the engine hands
## `_spawn_from_data()` on every peer.
static func _to_wire(
	kind: StringName,
	id: StringName,
	amount: int,
	at: Vector2,
	visible_to_peer: int,
) -> Dictionary:
	return {
		KEY_KIND: String(kind),
		KEY_ID: String(id),
		KEY_AMOUNT: amount,
		KEY_POSITION: at,
		KEY_VISIBLE_TO: visible_to_peer,
	}


## Runs on every peer with the host's payload. Sets the four replicated fields
## before the node enters the tree, so `Pickup._ready()` publishes the right
## visibility in one go.
func _spawn_from_data(data: Variant) -> Node:
	var wire: Dictionary = data as Dictionary
	var pickup: Pickup = PICKUP_SCENE.instantiate() as Pickup
	pickup.kind = StringName(wire.get(KEY_KIND, String(Pickup.KIND_GOLD)))
	pickup.id = StringName(wire.get(KEY_ID, ""))
	pickup.amount = int(wire.get(KEY_AMOUNT, Pickup.DEFAULT_AMOUNT))
	pickup.visible_to_peer = int(wire.get(KEY_VISIBLE_TO, Pickup.VISIBLE_TO_ALL))
	var at: Vector2 = wire.get(KEY_POSITION, Vector2.ZERO)
	pickup.position = at
	# The replicated pose; `Pickup._physics_process()` publishes it every frame
	# from here on (the enemy spawner's `synced_position` rule).
	pickup.synced_position = at
	return pickup
