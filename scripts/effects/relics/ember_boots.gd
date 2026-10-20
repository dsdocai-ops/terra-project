class_name EmberBootsEffect
extends Effect
## Ember Boots — design doc 9.1 no. 1: "dodge leaves a fire trail". Owned by
## relics (W4-B6, goal G5).
##
## On `player_dodged` it asks the world's spawner seam (`Effect.spawn()` →
## `EffectSpawner.spawn_node()`) for one trail where the dodge happened, and arms
## that trail with the burn the relic's description names, so what stands in it
## burns. One dodge, one trail: nothing here stacks, and the data file pins
## `max_stacks = 1`.
##
## **Where the trail comes from.** `ContentData.vfx_id` — SPEC-art-audio: "each
## ability, relic proc, and mutation names its VFX id in its data" — resolved as
## `res://scenes/vfx/<vfx_id>.tscn`, the folder and the one-scene-per-id layout
## that spec fixes ("`GPUParticles2D` library under `scenes/vfx/`, one emitter
## scene per id"). `data/relics/ember_boots.tres` names `relic_proc_fire`, the
## id SPEC-art-audio's `relic_proc_<tag>` rule gives this relic's first tag.
##
## **What is not this relic's to finish.** `blocked on art-audio (W4-B12/B13)`:
## `scenes/vfx/relic_proc_fire.tscn` is not in the library yet, so a dodge in a
## game build today takes the guarded branch below and spawns nothing — an effect
## never instantiates a node itself and never reaches for `World/Entities` by
## path, so there is no second way for the trail to appear. `blocked on Dev A
## (W4-A4)`: what the trail *does* — its hurtbox, its tick, who it touches — is
## the FX-with-gameplay root's own gameplay, and `EffectSpawner.spawn_node()`'s
## "FX-with-gameplay roots — clones, slip zones, totems" are not wired into a
## game scene yet. `arm_trail()` is the contract this lane publishes for that
## root; a root that does not implement it is spawned unarmed rather than
## refused, so an emitter-only scene can stand in without erroring.
##
## Sync: host-only. SPEC-effect-system — an effect proc "runs on the host only"
## and its result reaches clients through the spawner seam, which is the one path
## this relic uses.

## The folder SPEC-art-audio keeps the per-id emitter scenes in.
const SCENE_DIR: String = "res://scenes/vfx"
## The extension every scene in that library uses.
const SCENE_EXTENSION: String = ".tscn"
## The arming method this relic asks the root it spawned for.
const TRAIL_ARM_METHOD: StringName = &"arm_trail"
## What the trail applies to what it touches — the relic is a *fire* trail.
const TRAIL_STATUS: StatusEffects.Status = StatusEffects.Status.BURN

## The scene to spawn, when something hands one over: a test injects a double
## here, and the FX-with-gameplay spawner (W4-A4) may hand the real trail over
## the same way. Left null, the relic resolves its own `vfx_id`.
var fx_scene: PackedScene = null


func _on_attach() -> void:
	listen(Events.player_dodged, _on_player_dodged)


## One dodge, one trail. `perfect` is not read: the design doc's line is about
## every dodge, not the perfect ones (compare Ghost Wrap).
func _on_player_dodged(_player: Player, _perfect: bool) -> void:
	if player == null:
		return
	var scene: PackedScene = _resolve_scene()
	if scene == null:
		return
	spawn(scene, player.global_position, Callable(self, &"_arm_trail"))


## Arms the trail the seam handed back. Runs before the trail enters the tree
## (`EffectSpawner.spawn_node()` calls `setup` before `add_child()`), so the
## trail is already burning by its first frame.
func _arm_trail(trail: Node) -> void:
	if trail.has_method(TRAIL_ARM_METHOD):
		trail.call(TRAIL_ARM_METHOD, TRAIL_STATUS)


## The trail scene: the injected one when there is one, otherwise this relic's
## own `vfx_id` under SPEC-art-audio's folder. Null — a dropped spawn and not an
## error — while the art library does not have it yet (W4-B12/B13).
func _resolve_scene() -> PackedScene:
	if fx_scene != null:
		return fx_scene
	if source == null or source.vfx_id == &"":
		return null
	var path: String = SCENE_DIR.path_join("%s%s" % [source.vfx_id, SCENE_EXTENSION])
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene
