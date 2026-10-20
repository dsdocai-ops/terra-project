class_name MirrorStepEffect
extends Effect
## Mirror Step — design doc 9.1 no. 3: "dodge leaves a clone that explodes after
## 1s". Owned by relics (W4-B6, goal G5).
##
## On `player_dodged` it asks the world's spawner seam (`Effect.spawn()` →
## `EffectSpawner.spawn_node()`) for one clone where the dodge happened and arms
## it with the fuse the description names, `CLONE_FUSE_SECONDS = 1.0`, so the
## clone detonates one second later. One dodge, one clone.
##
## **Where the clone comes from** is `ContentData.vfx_id` resolved under
## SPEC-art-audio's folder, exactly as Ember Boots resolves its trail:
## `data/relics/mirror_step.tres` names `relic_proc_dodge` — this relic carries
## the Dodge tag and no element tag, so the proc id is the dodge one — and the
## scene is `res://scenes/vfx/relic_proc_dodge.tscn`.
##
## **What is not this relic's to finish.** The clone is a `FriendlyUnit` in
## SPEC-enemies-ai's own words — "Mirror Step clone" is named in that spec's list
## of `Team.PLAYER` units, with `owner_player`, `inherit_stats_fraction` and
## `lifetime` — so everything past the spawn is another lane's: the detonation's
## hurtbox and damage pass are combat-core's (`blocked on Dev A (W4-A4)`), and
## the minion's lifetime, stats and targeting are enemies-ai's (`blocked on Dev A
## (W4-A1)`). `blocked on art-audio (W4-B12/B13)` for the scene itself. The relic
## supplies the one number the design doc gives it — the fuse — and this lane's
## contract for the root is `arm_fuse(seconds)`: a root that does not implement
## it is spawned unarmed rather than refused.
##
## Sync: host-only, and more visibly so than the others: a minion is spawned
## through the spawner seam (SPEC-effect-system's "clones" are exactly
## `spawn_node()`'s case), never instantiated by this effect on each peer.

## The folder SPEC-art-audio keeps the per-id emitter scenes in.
const SCENE_DIR: String = "res://scenes/vfx"
## The extension every scene in that library uses.
const SCENE_EXTENSION: String = ".tscn"
## The arming method this relic asks the root it spawned for.
const CLONE_ARM_METHOD: StringName = &"arm_fuse"
## How long the clone stands before it detonates, in seconds. Design doc 9.1
## no. 3: "explodes after 1s" — and the data file's description says the same 1s.
const CLONE_FUSE_SECONDS: float = 1.0

## The scene to spawn, when something hands one over (a test's double, or the
## FX-with-gameplay spawner, W4-A4). Left null, the relic resolves its `vfx_id`.
var fx_scene: PackedScene = null


func _on_attach() -> void:
	listen(Events.player_dodged, _on_player_dodged)


## One dodge, one clone, armed with its fuse. `perfect` is not read: the line is
## about every dodge.
func _on_player_dodged(_player: Player, _perfect: bool) -> void:
	if player == null:
		return
	var scene: PackedScene = _resolve_scene()
	if scene == null:
		return
	spawn(scene, player.global_position, Callable(self, &"_arm_clone"))


## Arms the clone the seam handed back — before it enters the tree, so the fuse
## starts from a clone that is already configured.
func _arm_clone(clone: Node) -> void:
	if clone.has_method(CLONE_ARM_METHOD):
		clone.call(CLONE_ARM_METHOD, CLONE_FUSE_SECONDS)


## The clone scene: the injected one when there is one, otherwise this relic's
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
