class_name FrostwalkersEffect
extends Effect
## Frostwalkers — design doc 9.1 no. 4: "dodge freezes the ground, enemies slip".
## Owned by relics (W4-B6, goal G5).
##
## On `player_dodged` it asks the world's spawner seam (`Effect.spawn()` →
## `EffectSpawner.spawn_node()`) for one patch on the ground the dodge crossed —
## a slip zone, which is the second of `EffectSpawner.spawn_node()`'s own
## examples of an FX-with-gameplay root — and arms it with `PATCH_STATUS`, the
## freezing the description names. One dodge, one patch.
##
## The patch is `relic_proc_frost` here, from SPEC-art-audio's
## `relic_proc_<tag>` rule applied to this relic's first tag (frost; it also
## carries dodge, which is what Phantom Dancer counts). Its scene,
## `res://scenes/vfx/relic_proc_frost.tscn`, is resolved from the relic's own
## `vfx_id` exactly as Ember Boots' trail and Mirror Step's clone are.
##
## **What is not this relic's to finish.** `blocked on art-audio (W4-B12/B13)`
## for the scene, and `blocked on Dev A (W4-A4)` for the gameplay in it: which
## entity the patch catches, how long it stays frozen on the ground, and how the
## slip changes an enemy's movement are all the zone's own — a slip zone is a
## movement effect on other entities, and neither the hurtbox path nor the enemy
## body is this lane's. This lane's contract for the root is `arm_patch(status)`:
## a root that does not implement it is spawned unarmed rather than refused.
##
## Sync: host-only. The patch is host-authored and reaches clients through the
## spawner seam; a client never runs this handler.

## The folder SPEC-art-audio keeps the per-id emitter scenes in.
const SCENE_DIR: String = "res://scenes/vfx"
## The extension every scene in that library uses.
const SCENE_EXTENSION: String = ".tscn"
## The arming method this relic asks the root it spawned for.
const PATCH_ARM_METHOD: StringName = &"arm_patch"
## What the patch does to what crosses it: the design doc says "freezes the
## ground", and `Status.CHILL` is the weaker of the two cold statuses — the
## ground is frozen, not chilled.
const PATCH_STATUS: StatusEffects.Status = StatusEffects.Status.FREEZE

## The scene to spawn, when something hands one over (a test's double, or the
## FX-with-gameplay spawner, W4-A4). Left null, the relic resolves its `vfx_id`.
var fx_scene: PackedScene = null


func _on_attach() -> void:
	listen(Events.player_dodged, _on_player_dodged)


## One dodge, one patch. `perfect` is not read: the line is about every dodge.
func _on_player_dodged(_player: Player, _perfect: bool) -> void:
	if player == null:
		return
	var scene: PackedScene = _resolve_scene()
	if scene == null:
		return
	spawn(scene, player.global_position, Callable(self, &"_arm_patch"))


## Arms the patch the seam handed back — before it enters the tree, so the
## ground is already frozen on the patch's first frame.
func _arm_patch(patch: Node) -> void:
	if patch.has_method(PATCH_ARM_METHOD):
		patch.call(PATCH_ARM_METHOD, PATCH_STATUS)


## The patch scene: the injected one when there is one, otherwise this relic's
## own `vfx_id` under SPEC-art-audio's folder. Null — a dropped spawn, not an
## error — while the art library does not have it (W4-B12/B13).
func _resolve_scene() -> PackedScene:
	if fx_scene != null:
		return fx_scene
	if source == null or source.vfx_id == &"":
		return null
	var path: String = SCENE_DIR.path_join("%s%s" % [source.vfx_id, SCENE_EXTENSION])
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene
