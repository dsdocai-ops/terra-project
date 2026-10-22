class_name EffectSpawner
extends Node
## The seam `Effect.spawn()` and `Effect.fire_projectile()` go through: the one
## place an effect asks the world for a spawned thing. Owned by effect-system
## (W4-B2, goal G15).
##
## SPEC-effect-system says effect procs "run on the host only" and that "their
## visible results are spawned via the spawners so clients see them", so an
## effect never instantiates a node itself and never reaches for
## `World/Entities` by path (SPEC-project forbids cross-module tree-path
## reach-through). Instead the world hands the player's `EffectHost` one of
## these, and the host forwards every request here.
##
## Two paths, one per kind of result:
##
## - `spawn_node()` for FX-with-gameplay roots — clones, slip zones, totems,
##   the things SPEC-networking's spawner list calls "FX-with-gameplay". The
##   instance is stamped, positioned, handed to the caller's `setup` callable
##   and only then parented, so a `setup` may still configure the node before
##   it exists in the tree (and before any of its `_ready()` could run).
## - `spawn_projectile()` for a `ProjectileSpec`: it hands the spec to the
##   projectile spawner whole — scene, speed, damage, element, pierce and
##   bounce are exactly the spec's fields — and then stamps the same numbers
##   onto the projectile the spawner returned, so the result carries what
##   `ProjectileSpec` described.
##
## Provenance (`proc_source_id`, `proc_depth`) is stamped on every result here,
## not by each calling effect: SPEC-effect-system's "Visual language" rule says
## a spawned node knows which content made it and at what proc depth, and the
## debug overlay (W4-B11) reads that. A spawned root that declares the field
## gets it as a property (the `ProjectileSpawner.synced_position` convention);
## one that does not gets it as metadata, so an art-audio scene can never
## silently lose the value. `read_stamp()` is the one reader for both.
##
## Refusal is a *warning*, never an error: the FX spawner and combat-core's
## Projectile (Dev A's lane) are unlanded, so a title with neither wired drops
## its spawns and keeps the suite engine-error free.
## `blocked on Dev A (W4-A4)`: the FX-with-gameplay spawner and the real
## projectile scene are Dev A's; the swap-in is a wiring change on the world,
## not a change here.
##
## Sync: host-only. The client gate lives on `EffectHost` (`can_spawn()`), the
## single boundary an effect reaches, so there is exactly one place a client
## request is refused. Whatever this seam spawns is host-authored and reaches
## clients through the `MultiplayerSpawner`s under `World/Entities`.

## The two provenance fields every result carries. Named exactly as SPEC-
## effect-system's "Visual language" and "Proc chain limits" name them.
const PROC_SOURCE_ID: StringName = &"proc_source_id"
const PROC_DEPTH: StringName = &"proc_depth"
## `ProjectileSpec`'s own field names, so the stamp lands on a real projectile
## without a translation table and the swap-in stays mechanical.
const SPEC_SPEED: StringName = &"speed"
const SPEC_DAMAGE: StringName = &"damage"
const SPEC_ELEMENT: StringName = &"element"
const SPEC_PIERCE: StringName = &"pierce"
const SPEC_BOUNCE: StringName = &"bounce"
## The kind id a proc-fired projectile is registered under with the projectile
## spawner; the scene it uses comes from the spec.
const PROJECTILE_KIND: StringName = &"effect_proc"
## Who the spawned projectile is attributed to until combat-core owns the
## ownership field. `ProjectileSpawnInfo`'s own default.
const OWNER_PEER_ID: int = 1

## Where spawned FX-with-gameplay roots are parented. Left unset, spawns are
## dropped with a warning rather than landing in whatever node happens to be
## the seam's parent.
var container: Node = null
## Where to find the container when nobody assigned one: resolved once on
## `_ready()`. The world sets either this or `container`.
@export var container_path: NodePath = ^""
## The projectile spawner to fire through (networking, W2-B3). Unset until a
## world wires one, which is the Dev A W4-A4 swap-in.
@export var projectile_spawner: ProjectileSpawner = null


func _ready() -> void:
	if container == null and not container_path.is_empty():
		container = get_node_or_null(container_path)


## Instantiates `scene`, stamps it with its provenance, puts it at `pos`,
## runs `setup` on it and parents it under `container`. Returns the instance,
## or null — with a warning, never an error — when there is no scene or no
## container to parent into.
##
## The caller's `setup` callable runs *before* `add_child()`, so a spawner can
## still decide things about a node that has not entered the tree; `setup` is
## host-local, so anything that must reach clients travels in `source_id` /
## `depth` (and, later, the concrete spawner's own payload) instead.
func spawn_node(
	scene: PackedScene,
	pos: Vector2,
	setup: Callable,
	source_id: StringName,
	depth: int,
) -> Node:
	if scene == null:
		push_warning("[effect-spawner] spawn_node() needs a scene, nothing spawned")
		return null
	if container == null or not is_instance_valid(container):
		push_warning("[effect-spawner] no container wired, %s's spawn dropped (blocked on Dev A W4-A4)" % source_id)
		return null
	var instance: Node = scene.instantiate()
	if instance == null:
		push_warning("[effect-spawner] %s did not instantiate a node, spawn dropped" % scene.resource_path)
		return null
	_stamp(instance, PROC_SOURCE_ID, source_id)
	_stamp(instance, PROC_DEPTH, depth)
	if instance is Node2D:
		(instance as Node2D).position = pos
	if setup.is_valid():
		setup.call(instance)
	container.add_child(instance)
	return instance


## Fires `spec` through the projectile spawner and returns the projectile, or
## null — with a warning, never an error — when there is no spec or no spawner
## wired.
##
## The spec is handed over whole, so its scene, speed, damage, element, pierce
## and bounce are the values the spawner works from; the same numbers are then
## stamped onto the projectile that came back, so the result carries what the
## spec described even while the placeholder projectile declares none of them.
func spawn_projectile(
	spec: ProjectileSpec,
	from: Vector2,
	dir: Vector2,
	source_id: StringName,
	depth: int,
) -> Node:
	if spec == null:
		push_warning("[effect-spawner] spawn_projectile() needs a spec, nothing fired")
		return null
	if projectile_spawner == null or not is_instance_valid(projectile_spawner):
		push_warning("[effect-spawner] no projectile spawner wired, %s's shot dropped (blocked on Dev A W4-A4)" % source_id)
		return null
	if spec.scene != null:
		# The spawner holds one default scene; the spec names the projectile, so
		# point it at the spec's scene for this call. MultiplayerSpawner.spawn()
		# runs synchronously inside spawn_projectile(), so the change is scoped
		# to the call and cannot leak into the next one.
		projectile_spawner.projectile_scene = spec.scene
	var info := ProjectileSpawnInfo.new(PROJECTILE_KIND, from, dir.normalized() * spec.speed, OWNER_PEER_ID)
	var node: Node = projectile_spawner.spawn_projectile(info)
	if node == null:
		return null
	_stamp(node, PROC_SOURCE_ID, source_id)
	_stamp(node, PROC_DEPTH, depth)
	_stamp(node, SPEC_SPEED, spec.speed)
	_stamp(node, SPEC_DAMAGE, spec.damage)
	_stamp(node, SPEC_ELEMENT, int(spec.element))
	_stamp(node, SPEC_PIERCE, spec.pierce)
	_stamp(node, SPEC_BOUNCE, spec.bounce)
	return node


## The value `key` was stamped with on `node`: its property when the root
## declares one, otherwise its metadata. The one reader for both paths, so the
## debug overlay (W4-B11) and the trigger harness do not have to know which
## branch a given scene took. Null when the node carries neither.
static func read_stamp(node: Node, key: StringName) -> Variant:
	if node == null:
		return null
	if _declares(node, key):
		return node.get(key)
	return node.get_meta(key, null)


## Writes `value` under `key` as a property when the root declares one, and as
## metadata otherwise — so an art-audio FX scene that knows nothing about proc
## provenance still carries it.
static func _stamp(node: Node, key: StringName, value: Variant) -> void:
	if _declares(node, key):
		node.set(key, value)
	else:
		node.set_meta(key, value)


## True when `node` (or its script) publishes a property called `key`.
static func _declares(node: Node, key: StringName) -> bool:
	for entry: Dictionary in node.get_property_list():
		if StringName(entry.get("name", &"")) == key:
			return true
	return false
