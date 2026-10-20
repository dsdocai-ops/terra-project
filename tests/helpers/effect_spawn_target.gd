class_name EffectSpawnTarget
extends Node2D
## Test double for a scene an effect spawns: the smallest node that *declares*
## the two provenance fields `Effect.spawn()` stamps, so the "the scene owns the
## property" branch of the stamp can be asserted. A scene that does not declare
## them gets the values as metadata instead (the other branch, covered by the
## plain `Node2D` case in `tests/unit/test_effect_spawn.gd`).
##
## The field names are taken from `EffectSpawner` itself, so the double and the
## stamp cannot drift apart.
##
## Sync: none — a test double. A real spawned root is host-authored and reaches
## clients through the FX/entity spawner.

var proc_source_id: StringName = &""
var proc_depth: int = 0
