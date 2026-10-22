class_name VolatileCoreEffect
extends Effect
## Volatile Core — design doc 9.1 no. 15: "enemies explode on death". Owned by
## relics (W4-B6, goal G7).
##
## When this player kills an enemy, the enemy explodes: every enemy within
## `EXPLOSION_RADIUS` of the one that died takes `EXPLOSION_DAMAGE`, and one FX
## root is spawned where it died.
##
## **The blast is this relic's own hit.** It is dealt through
## `Effect.deal_damage()` onto each enemy's hurtbox — the same delivery every
## weapon hit uses — carrying `EXPLOSION_ELEMENT` (fire, see below) and the
## victim's own damage shape is *not* copied: the explosion is the relic's, so its
## damage is the relic's constant and not a fraction of whatever killed the
## enemy. `deal_damage()` stamps it `proc_depth = trigger_depth + 1` and the
## `proc` tag.
##
## **The G17 rule, against a real relic.** This is the relic the no-self-retrigger
## rule exists for: the explosion kills the enemy beside it, that enemy's death is
## announced on `enemy_killed` exactly as any other death is, and this effect must
## not explode again off its own blast. It does not, for two reasons that
## compose — and the batch's case proves the pair, because either alone would be
## enough to hide a bug in the other:
##
##   - **rule 2**: every hit `_blast_hit()` builds carries `source_id()` in its
##     `tags`, so `Effect._forward()` drops the `enemy_killed` whose payload is
##     this blast before the handler ever runs (SPEC-effect-system, "Proc chain
##     limits", rule 2);
##   - **attribution**: the handler reads `hit.owner_player`, and the blast sets
##     it to this player, so the *next* link would also be filtered had the tag
##     been forgotten.
##
## **The FX root.** `ContentData.vfx_id` — SPEC-art-audio: "each ability, relic
## proc, and mutation names its VFX id in its data" — resolved as
## `res://scenes/vfx/<vfx_id>.tscn`, exactly as Ember Boots resolves its trail.
## `data/relics/volatile_core.tres` names `relic_proc_fire`, the id
## SPEC-art-audio's `relic_proc_<tag>` rule gives this relic's first tag — which is
## fire because SPEC-relics' Pyromaniac row lists Volatile Core among the fire
## relics and names this relic's explosions as the reason. The scene is spawned
## only when one resolves: while `scenes/vfx/relic_proc_fire.tscn` does not exist
## (**blocked on art-audio (W4-B12/B13)**) a kill in a game build today deals its
## blast and spawns nothing, rather than warning once per kill.
##
## **The blast lands even with no FX.** The damage is the gameplay — "enemies
## explode" is what the relic does — so a missing art scene must not disarm it.
## The FX root is cosmetic and armed with nothing: an explosion is instantaneous,
## so unlike the trail, the clone and the patch it has no `arm_*()` contract to
## ask for (**blocked on Dev A (W4-A4)** for whatever the root's own body does).
##
## **Which kills count.** This player's kills, read off `hit.owner_player`, for the
## reason the On Hit relics read their hits off it: `enemy_killed` is emitted by
## the dying enemy (Dev A, W4-A4) and carries no `Player` argument for
## `Effect.listen()`'s filter, so a teammate's kill, a hazard's and a status
## tick's must be told apart here. A kill nothing attributes — an unattributed hit
## — explodes for nobody.
##
## **The damage is a host-dealt hit, not a spawned hazard.** Co-op reaches clients
## the way any host hit does; SPEC-effect-system's "Movement calls position
## changes" and the FX-with-gameplay spawner (W4-A4) are not on this path.
##
## `max_stacks = 1` in the data file: one death, one explosion. Two copies are not
## two blasts in the doc's sentence, and no line of it says "(stacks)".
##
## Sync: host-only (SPEC-relics, "Multiplayer ownership").

## How far from the enemy that died the blast reaches. The design doc gives no
## number, so this lane's balance call: SHATTER's own burst is 64 px
## (`StatusEffects.SHATTER_RADIUS`), and a death explosion is that kind of burst
## rather than COLLAPSE's 128 px pull.
const EXPLOSION_RADIUS: float = 64.0
## What the blast deals to each enemy it reaches. Also this lane's call: the doc
## gives no number and the week-12 balance pass owns the value; it is set below a
## weapon hit's typical damage so a chain of deaths does not out-damage the
## killing blow itself.
const EXPLOSION_DAMAGE: float = 24.0
## The blast's element. SPEC-relics' Pyromaniac row: "Ember Boots, Kindling, Ember
## Heart, Volatile Core, Glass Cannonball (explosions tagged fire), Prism" — the
## parenthetical is why this relic's first tag, and therefore its proc id, is
## fire.
const EXPLOSION_ELEMENT: HitInfo.Element = HitInfo.Element.FIRE
## The folder SPEC-art-audio keeps the per-id emitter scenes in, and the extension
## every scene in that library uses — the same two constants Ember Boots uses, so
## the batch resolves its scenes one way.
const SCENE_DIR: String = "res://scenes/vfx"
const SCENE_EXTENSION: String = ".tscn"

## The scene to spawn, when something hands one over: a test injects a double
## here, and the FX-with-gameplay spawner (W4-A4) may hand the real explosion over
## the same way. Left null, the relic resolves its own `vfx_id`.
var fx_scene: PackedScene = null


func _on_attach() -> void:
	listen(Events.enemy_killed, _on_enemy_killed)


## One of this player's kills: the corpse explodes.
func _on_enemy_killed(enemy: Node, hit: HitInfo) -> void:
	if not _is_my_kill(enemy, hit):
		return
	_explode(enemy)


## True when `enemy` is a valid node and `hit` is this player's own kill. The
## `owner_player` read is the pair's second half — see the class comment's rule-2
## note — and the null check is what keeps an unattributed kill (a hazard's, a
## double's) inert rather than credited to nobody's player.
func _is_my_kill(enemy: Node, hit: HitInfo) -> bool:
	if player == null or enemy == null or not is_instance_valid(enemy):
		return false
	if hit == null:
		return false
	return hit.owner_player == player


## Blows up the enemy that died: the FX root where it fell, and one hit on every
## enemy the blast reaches. A corpse with no position has no centre to centre the
## blast on, so the whole gesture is skipped rather than centred on the origin.
func _explode(enemy: Node) -> void:
	var centre := enemy as Node2D
	if centre == null:
		return
	_play_explosion(centre.global_position)
	for target: Node in _blast_targets(centre):
		deal_damage(target, _blast_hit())


## Spawns the explosion's scene, when one resolves. Nothing is armed: an
## explosion has no duration and no status to leave behind, so an FX root needs no
## `arm_*()` contract the way the trail, the clone and the patch do.
func _play_explosion(at: Vector2) -> void:
	var scene: PackedScene = _resolve_scene()
	if scene != null:
		spawn(scene, at)


## The enemies within `EXPLOSION_RADIUS` of the enemy that died, in group order,
## excluding the corpse itself: it is the centre of the blast, and it is already
## dead — "enemies explode on death" is about what the death does to the *others*.
## The candidate set is the group `StatusEffects.ENEMY_TAG`, read the way SHOCK's
## chain and Storm Sandals read it, and an entity that is not positioned is skipped
## rather than assumed to be at the origin.
func _blast_targets(centre: Node2D) -> Array[Node]:
	var reached: Array[Node] = []
	var tree := get_tree()
	if tree == null:
		return reached
	var here: Vector2 = centre.global_position
	for candidate: Node in tree.get_nodes_in_group(StatusEffects.ENEMY_TAG):
		if candidate == centre or not is_instance_valid(candidate):
			continue
		var positioned := candidate as Node2D
		if positioned == null:
			continue
		if here.distance_to(positioned.global_position) <= EXPLOSION_RADIUS:
			reached.append(candidate)
	return reached


## The hit the blast deals. Its own payload rather than the killing hit's: the
## damage is the relic's constant, the element is the relic's fire, and the tags
## carry `source_id()` so rule 2 can stop the chain at this link. Built fresh per
## target so each enemy's hit is its own object — the hurtbox may consume or retag
## what it is handed.
func _blast_hit() -> HitInfo:
	var hit := HitInfo.new()
	hit.base_damage = EXPLOSION_DAMAGE
	hit.element = EXPLOSION_ELEMENT
	hit.owner_player = player
	var own_tag: Array[StringName] = [source_id()]
	hit.tags = own_tag
	return hit


## The explosion scene: the injected one when there is one, otherwise this relic's
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