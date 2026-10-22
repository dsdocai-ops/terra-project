class_name Pickup
extends Area2D
## One physical drop: a coin, an ore chunk, an echo shard, a rune stone, a relic
## or a potion. Owned by run-economy (W4-B8, goal G12).
##
## SPEC-run-economy, "Currencies": "Pickups are physical: `Pickup` scene (gold
## coin, ore chunk, echo shard, rune stone, relic, potion) spawned by host,
## magnetized to the nearest player within `pickup_radius` (Ore Magnet makes it
## room-wide). Shared currencies are collected by whoever touches them.
## Per-player pickups (relics, runes) are per-player drops: each player sees
## only their own (design doc), implemented as pickups with `visible_to_peer`."
## Those four sentences are the whole of this file: the six `KINDS`, the magnet,
## the collect that emits `Events.pickup_collected`, and the per-peer visibility.
##
## **The magnet is a distance test, not a physics overlap.** The spec's own word
## is "within `pickup_radius`", so `nearest_player_in_range()` measures to the
## players in the `player` group and `magnet_step()` pulls toward the nearest of
## them. `PICKUP_LAYER` is 0 on purpose: a coin must not answer
## SPEC-player-controller's interact scan, and the `TouchShape` in the scene is
## the overlap path the pickup spawner (`W4-B8`, the drop goal) will read rather
## than a collision that exists today.
##
## **Ore Magnet** (design doc 9.1 no. 48: "pick up loot from across the room") is
## read the way every cross-module relic read in this lane is: an id asked of the
## holder's `EffectHost` (`has_effect(ROOM_WIDE_RELIC_ID)`), never a flag on the
## player and never a hard-coded relic class. `magnet_radius()` is the one place
## that decides the radius, so the magnet and any later caller cannot disagree.
##
## Sync: host-authoritative. SPEC-run-economy, "Multiplayer ownership": "loot
## rolls, currency totals ... host". The host integrates the magnet and publishes
## the pose on `synced_position` for `StateSync` to replicate; a client only
## presents it (`magnet_step()` returns immediately off-host, asserted by a
## case). Per-player drops set `visible_to_peer` and `apply_visibility()` points
## the scene's `MultiplayerSynchronizer` at that peer alone, so a relic a player
## earned never appears in a team-mate's world.
##
## Nothing places a pickup in a live scene yet: `PickupSpawner` (W4-B8, the drop
## goal) is what calls `spawn_pickup()`, and `LootDrops` beside it in
## `world.tscn` is what rolls the table that feeds it. The enemy/elite death
## those listen for is Dev A's W4-A4. Recorded, not worked around.

## The six kinds, in the order SPEC-run-economy lists them.
const KIND_GOLD: StringName = &"gold"
const KIND_ORE: StringName = &"ore"
const KIND_ECHO: StringName = &"echo"
const KIND_RUNE: StringName = &"rune"
const KIND_RELIC: StringName = &"relic"
const KIND_POTION: StringName = &"potion"
const KINDS: Array[StringName] = [KIND_GOLD, KIND_ORE, KIND_ECHO, KIND_RUNE, KIND_RELIC, KIND_POTION]

## `visible_to_peer`'s "everyone" sentinel: a shared currency drop.
const VISIBLE_TO_ALL: int = 0
## How many units one pickup carries when nobody says otherwise.
const DEFAULT_AMOUNT: int = 1
## How far a pickup reaches for a player, in pixels, unless the scene or the
## spawner sets `pickup_radius` (SPEC-run-economy's `pickup_radius`).
const DEFAULT_PICKUP_RADIUS: float = 32.0
## Ore Magnet's "across the room" radius. A room is a handful of 64x32 tiles, so
## this is larger than any room this project builds and smaller than INF, which
## a squared-distance compare cannot hold cleanly.
const ROOM_WIDE_RADIUS: float = 4096.0
## Design doc 9.1 no. 48, Ore Magnet. The id is the relic's `.tres` file name
## (SPEC-project: "Content ids are the snake_case file name"), and the relic
## itself is a week-8 content item this lane does not author.
const ROOM_WIDE_RELIC_ID: StringName = &"ore_magnet"
## The magnet's feel: a pull that ramps in and is capped, so a coin crosses a
## room in well under a second without overshooting into a blur.
const MAGNET_ACCELERATION: float = 900.0
const MAGNET_MAX_SPEED: float = 480.0
## "Collected by whoever touches them": this close counts as touching.
const COLLECT_DISTANCE: float = 8.0
## The group a player joins when it spawns (networking's `PlayerSpawner`).
const PLAYER_GROUP: StringName = StatusEffects.PLAYER_TAG
## The child the per-peer visibility is set on.
const SYNC_NODE_NAME: StringName = &"StateSync"
## No physics layer: the magnet is a distance test and a pickup is not an
## interactable (see the class comment).
const PICKUP_LAYER: int = 0
## The scene the spawner instantiates. Loaded at runtime rather than preloaded,
## because that scene's root script is this file and a preload would be a cycle.
const SCENE_PATH: String = "res://scenes/pickups/pickup.tscn"

## What this pickup is: one of `KINDS`.
@export var kind: StringName = KIND_GOLD
## Which one, for the kinds that have types: the ore id (`copper`), the relic id,
## the potion id. Empty for a plain gold coin.
@export var id: StringName = &""
## How many units it pays out, in the currency or item `kind`/`id` name.
@export var amount: int = DEFAULT_AMOUNT
## How far it reaches for a player. Ore Magnet widens this at read time; nothing
## overwrites the exported value.
@export var pickup_radius: float = DEFAULT_PICKUP_RADIUS
## `VISIBLE_TO_ALL`, or the peer id of the one player this drop is for.
@export var visible_to_peer: int = VISIBLE_TO_ALL

## Host-written pose, replicated by `StateSync`. Clients present it.
var synced_position: Vector2 = Vector2.ZERO
## True once this pickup has been collected and is on its way out.
var collected: bool = false
## The magnet's current velocity, so a pull ramps rather than snapping.
var _magnet_velocity: Vector2 = Vector2.ZERO
## The peer `apply_visibility()` last pointed the synchronizer at, so switching
## a drop back to shared can clear that override instead of leaving it behind.
var _visibility_peer: int = VISIBLE_TO_ALL


func _ready() -> void:
	synced_position = global_position
	apply_visibility()
	apply_art()


## Host: integrate the magnet and publish the pose. Client: present the pose the
## host sent. Gameplay runs on the host only (BRIEF C11).
func _physics_process(delta: float) -> void:
	if not NetworkManager.is_host:
		global_position = synced_position
		return
	magnet_step(delta)
	synced_position = global_position


# --- the magnet -------------------------------------------------------------


## One step of the magnet. Host only. Returns nothing; the outcome a caller
## watches is `collected`, `position` and the bus. Split out of
## `_physics_process()` so a case can step it deterministically instead of
## racing the engine's frame.
func magnet_step(delta: float) -> void:
	if not NetworkManager.is_host:
		return
	if collected:
		return
	var target: Player = nearest_player_in_range()
	if target == null:
		_magnet_velocity = Vector2.ZERO
		return
	var offset: Vector2 = target.global_position - global_position
	if offset.length() <= COLLECT_DISTANCE:
		collect(target)
		return
	# TimeManager, never the engine's global scale: a pickup is not an enemy, so
	# an enemy time stop leaves it at normal speed (SPEC-time-manager).
	var step: float = delta * TimeManager.scale_for(self)
	_magnet_velocity = (_magnet_velocity + offset.normalized() * MAGNET_ACCELERATION * step).limit_length(MAGNET_MAX_SPEED)
	global_position += _magnet_velocity * step


## The nearest living player this pickup reaches for, or null when nobody is
## inside `magnet_radius()` of them. A downed player cannot pick anything up, so
## it is skipped rather than vacuuming loot off the floor.
func nearest_player_in_range() -> Player:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var best: Player = null
	var best_distance: float = INF
	for candidate: Node in tree.get_nodes_in_group(PLAYER_GROUP):
		var other: Player = candidate as Player
		if other == null or other.is_downed:
			continue
		var distance: float = global_position.distance_to(other.global_position)
		if distance < best_distance:
			best_distance = distance
			best = other
	if best == null:
		return null
	if best_distance > magnet_radius(best):
		return null
	return best


## How far this pickup reaches for `player`: the scene's `pickup_radius`, or
## Ore Magnet's room-wide radius when that player holds the relic. The one place
## the radius is decided.
func magnet_radius(player: Player) -> float:
	if holds_room_wide_relic(player):
		return ROOM_WIDE_RADIUS
	return pickup_radius


## Whether `player` holds Ore Magnet, read as an id off the holder's effect host
## (SPEC-effect-system: the host is the one registry of what a player holds). A
## player with no host — a client copy, or a test fixture without one — holds
## nothing, which is the same answer as holding the wrong relic.
func holds_room_wide_relic(player: Player) -> bool:
	if player == null:
		return false
	var host: EffectHost = player.get_node_or_null(NodePath(EffectHost.NODE_NAME)) as EffectHost
	if host == null:
		return false
	return host.has_effect(ROOM_WIDE_RELIC_ID)


# --- collecting -------------------------------------------------------------


## Collects this pickup for `player`. Host only by construction: the magnet is
## the only caller, and it does not run off-host. Emits `Events.pickup_collected`
## — one of the five signals SPEC-effect-system says clients re-emit from
## replicated state, which is the spawner's job when it lands — and frees the
## node. False when the pickup was already spent.
func collect(player: Player) -> bool:
	if collected:
		return false
	collected = true
	Events.pickup_collected.emit(player, self)
	queue_free()
	return true


# --- per-player drops -------------------------------------------------------


## Points the scene's synchronizer at `visible_to_peer`: everyone for a shared
## currency, that one peer for a per-player drop. Called on ready and by whoever
## sets `visible_to_peer` afterwards (the spawner knows the peer before the node
## enters the tree, so ready alone is enough there).
func apply_visibility() -> void:
	var sync: MultiplayerSynchronizer = state_sync()
	if sync == null:
		return
	if _visibility_peer != VISIBLE_TO_ALL and _visibility_peer != visible_to_peer:
		sync.set_visibility_for(_visibility_peer, false)
		_visibility_peer = VISIBLE_TO_ALL
	if visible_to_peer == VISIBLE_TO_ALL:
		sync.public_visibility = true
		return
	sync.public_visibility = false
	sync.set_visibility_for(visible_to_peer, true)
	_visibility_peer = visible_to_peer


## Whether `peer_id` receives this pickup. Reads the synchronizer's own two
## properties rather than re-deriving the rule, so the answer cannot drift from
## what the engine actually sends.
func is_visible_to(peer_id: int) -> bool:
	var sync: MultiplayerSynchronizer = state_sync()
	if sync == null:
		return visible_to_peer == VISIBLE_TO_ALL or visible_to_peer == peer_id
	if sync.public_visibility:
		return true
	return sync.get_visibility_for(peer_id)


## The scene's synchronizer, or null when the node is not the scene (a bare
## `Pickup.new()`).
func state_sync() -> MultiplayerSynchronizer:
	return get_node_or_null(NodePath(SYNC_NODE_NAME)) as MultiplayerSynchronizer


# --- art --------------------------------------------------------------------

const ART_DIR: String = "res://assets/sprites/props/"


## The sprite for a pickup `kind`: pickup_<kind>.png under ART_DIR.
static func art_path_for(pickup_kind: StringName) -> String:
	return ART_DIR + "pickup_" + String(pickup_kind) + ".png"


## Puts this kind's sprite on the Body node. A kind with no sprite keeps the
## scene's default (the gold nugget) rather than blanking the pickup.
func apply_art() -> void:
	var body: Sprite2D = get_node_or_null("Body") as Sprite2D
	var path: String = art_path_for(kind)
	if body != null and ResourceLoader.exists(path):
		body.texture = load(path) as Texture2D
