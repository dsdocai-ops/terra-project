class_name ProjectilePool
extends Node
## Recycles the `Projectile` nodes combat-core flies (SPEC-combat-core
## "Projectiles": pooled through `ProjectilePool`, per scene type,
## grow-on-demand, pre-warm 64 per common type). Owned by combat-core.
## Sync: none — the pool is a host-side recycle of local nodes and never
## touches the replicated spawn path. `ProjectileSpawner` (W2-B3) owns the
## MultiplayerSpawner spawns, and its despawn frees the client copies, so a
## pooled instance is never handed to it; a client runs its own identical pool
## under its own World for its own use. Nothing here reaches across the wire.
##
## Idle projectiles wait hidden under this node with their hitbox cold. An
## acquired one moves into `spawn_root` (World's Entities container, so its
## position is world-relative next to the spawner's bolts) and flies when the
## caller calls `launch` — which re-arms every flight number, so a reused
## projectile starts clean. A retired one hands itself back (deferred, because
## the death path runs inside physics) and nothing is ever freed mid-run.

## Instances created up front for a warmed type, so the first volley of a
## fight never allocates (SPEC-combat-core: pre-warm 64 per common type).
const WARM_PER_TYPE: int = 64
## The common type a World warms at load: the base projectile scene.
const COMMON_SCENE_PATH: String = "res://scenes/projectiles/projectile.tscn"
## The fixed name keeps the pool findable under whatever root attaches it.
const POOL_NODE_NAME: String = "ProjectilePool"

## How many projectiles this pool has made in its life (tests count this:
## after warm-up the number must not move).
var created_count: int = 0
## Where an acquired projectile flies from. `attach` defaults it to the attach
## root; World points it at its Entities container.
var spawn_root: Node = null

## Scene resource path -> the idle projectiles of that type, parked hidden
## under this node. Keyed by path so a freed list never holds a scene alive;
## values are `Array[Projectile]` (nested typed collections do not parse).
var _free: Dictionary = {}


## Attaches one pool named `POOL_NODE_NAME` under `parent`, reusing an existing
## one (the same pattern as DamageNumberPool.attach). The pool's spawn root
## defaults to `parent`; a caller that wants acquired projectiles elsewhere
## (World: its Entities container) sets `spawn_root` after attaching.
static func attach(parent: Node) -> ProjectilePool:
	var existing := parent.get_node_or_null(POOL_NODE_NAME) as ProjectilePool
	if existing != null:
		return existing
	var pool := ProjectilePool.new()
	pool.name = POOL_NODE_NAME
	parent.add_child(pool)
	pool.spawn_root = parent
	return pool


## Creates `count` instances of `scene` up front (default the spec's 64). A
## type warmed twice accumulates; every instance waits hidden and cold.
func warm(scene: PackedScene, count: int = WARM_PER_TYPE) -> void:
	for _instance in count:
		var projectile := _make(scene)
		add_child(projectile)
		_free_list(scene.resource_path).append(projectile)


## Hands out a projectile of `scene`'s type: from the free list when one waits,
## grown fresh when the type is empty (grow-on-demand — growth is the design,
## not a leak; the no-allocation rule starts after warm-up). The projectile
## comes out unretired, visible and cold; the caller places it and calls
## `launch`, which (re)arms every flight number. The tree change here is only
## safe outside physics — a caller inside one defers the acquire itself.
func acquire(scene: PackedScene) -> Projectile:
	var free_list := _free_list(scene.resource_path)
	var projectile: Projectile = free_list.pop_back() if not free_list.is_empty() else _make(scene)
	projectile._retired = false
	projectile.visible = true
	projectile.active = false
	projectile.homing_target = null
	if spawn_root != null:
		if projectile.get_parent() != null:
			projectile.get_parent().remove_child(projectile)
		spawn_root.add_child(projectile)
	return projectile


## Takes a finished projectile back: parked hidden under this node, hitbox
## cold, on its type's free list. Never frees it — a pooled projectile is
## recycled for the whole run.
func release(projectile: Projectile) -> void:
	projectile._retired = true
	projectile.active = false
	projectile.visible = false
	projectile.homing_target = null
	if projectile.get_parent() != null:
		projectile.get_parent().remove_child(projectile)
	add_child(projectile)
	projectile.pool = self
	_free_list(projectile.scene_file_path).append(projectile)


## The projectile's own death path (a physics callback) asks for the hand-back
## this way: the tree change waits for the end of the frame.
func release_deferred(projectile: Projectile) -> void:
	release.call_deferred(projectile)


## How many of `scene`'s type wait idle (tests and tuning read this).
func free_count(scene: PackedScene) -> int:
	return _free_list(scene.resource_path).size()


func _make(scene: PackedScene) -> Projectile:
	created_count += 1
	var projectile := scene.instantiate() as Projectile
	# A scene whose root is not a Projectile is a caller bug: say so and hand
	# back a bare one rather than a null that crashes the acquire.
	if projectile == null:
		push_error("ProjectilePool: %s does not instantiate a Projectile" % scene.resource_path)
		projectile = Projectile.new()
	projectile.pool = self
	projectile.visible = false
	projectile.active = false
	return projectile


## The free list of one scene type, made on first ask.
func _free_list(path: String) -> Array[Projectile]:
	if not _free.has(path):
		var fresh: Array[Projectile] = []
		_free[path] = fresh
	return _free[path] as Array[Projectile]
