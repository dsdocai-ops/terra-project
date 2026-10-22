class_name EffectSpawnerSpy
extends EffectSpawner
## Test double for the spawner seam: records every `spawn_node()` and
## `spawn_projectile()` call `EffectHost` makes and then runs the real base
## implementation, so a case can assert both *that* the seam was asked and
## *what* came back. Used by `tests/unit/test_effect_spawn.gd` and, from W4-B3,
## by the trigger-test harness's `SpyWorld`; never used in a game scene.
##
## Recording *before* delegating would lose the returned node when the base
## refuses, so each override calls `super()` first and stores the result with
## the arguments that produced it.
##
## Sync: none — a test double. The sealed cracks it stands in for are host-only.

## One entry per `spawn_node()` call: `{scene, position, setup, proc_source_id,
## proc_depth, node}`.
var spawns: Array[Dictionary] = []
## One entry per `spawn_projectile()` call: `{spec, from, direction,
## proc_source_id, proc_depth, node}`.
var projectiles: Array[Dictionary] = []


func spawn_node(
	scene: PackedScene,
	pos: Vector2,
	setup: Callable,
	source_id: StringName,
	depth: int,
) -> Node:
	var node: Node = super(scene, pos, setup, source_id, depth)
	spawns.append({
		"scene": scene,
		"position": pos,
		"setup": setup,
		"proc_source_id": source_id,
		"proc_depth": depth,
		"node": node,
	})
	return node


func spawn_projectile(
	spec: ProjectileSpec,
	from: Vector2,
	dir: Vector2,
	source_id: StringName,
	depth: int,
) -> Node:
	var node: Node = super(spec, from, dir, source_id, depth)
	projectiles.append({
		"spec": spec,
		"from": from,
		"direction": dir,
		"proc_source_id": source_id,
		"proc_depth": depth,
		"node": node,
	})
	return node


## The `proc_source_id` of the most recent spawn, or an empty name when none
## was asked for — the one-line form the harness cases read.
func last_source_id() -> StringName:
	if spawns.is_empty():
		return &""
	return StringName(spawns[spawns.size() - 1]["proc_source_id"])


## The `proc_depth` of the most recent spawn.
func last_depth() -> int:
	if spawns.is_empty():
		return -1
	return int(spawns[spawns.size() - 1]["proc_depth"])


## The spec of the most recent projectile, or null when none was fired.
func last_projectile_spec() -> ProjectileSpec:
	if projectiles.is_empty():
		return null
	return projectiles[projectiles.size() - 1]["spec"] as ProjectileSpec
