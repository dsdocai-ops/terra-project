class_name CorpseBloomEffect
extends Effect
## Corpse Bloom — design doc 9.1 no. 18: "dead enemies sprout healing flowers".
## Owned by relics (W4-B6, goal G8a).
##
## One of this player's kills plants one flower where the enemy fell. The flower
## is an **FX-with-gameplay root**: it is spawned through `Effect.spawn()` — the
## seam that refuses on a client and parents host-side — and whatever healing
## lives inside it is the root's own body, exactly as the trail's burn is Ember
## Boots' root's and the ghost army's is Soul Jar's.
##
## **No `arm_*()` contract, and that is deliberate.** `RelicFxRootStub` records
## four arming calls (`arm_trail`, `arm_fuse`, `arm_patch`, `arm_lifetime`), one
## per relic whose design-doc line states a number — Ember Boots' burn, Mirror
## Step's fuse, Frostwalkers' status, Soul Jar's "for 10s". No. 18 states no
## number at all: "dead enemies sprout healing flowers" says what happens and not
## how much is healed or how long a flower stands. So this relic arms nothing and
## asks the root for nothing it has not been given a shape for: the flower is
## spawned unarmed, and the amount it heals is **blocked on the class-balance
## pass** to state and on Dev A (W4-A4) for the root body that does it. Inventing
## a number here — "heals 3% of max HP over 5s" — would be this lane writing
## balance the design doc has not decided, which is the one thing the batch's
## data cases cannot catch.
##
## **The FX root.** `ContentData.vfx_id` — SPEC-art-audio: "each ability, relic
## proc, and mutation names its VFX id in its data" — resolved as
## `res://scenes/vfx/<vfx_id>.tscn`, exactly as Volatile Core resolves its
## explosion. `data/relics/corpse_bloom.tres` names `relic_proc_on_kill`, the id
## SPEC-art-audio's `relic_proc_<tag>` rule gives this relic's first tag. The
## scene is spawned only when one resolves: while
## `scenes/vfx/relic_proc_on_kill.tscn` does not exist (**blocked on art-audio
## (W4-B12/B13)**) a kill in a game build today plants nothing, rather than
## warning once per kill.
##
## **`flowers_planted()` counts flowers, not kills.** It is incremented only when
## the seam handed a node back, so it is the number of flowers actually standing
## — the read the HUD strip (goal G19) draws and the batch's case asserts 1 and 2
## against. With the proc scene unlanded it reads 0, which is the truth rather
## than a count of intentions.
##
## **Which kills count.** This player's, read off `hit.owner_player`, for the
## reason the rest of the On Kill batch reads it: `enemy_killed` is emitted by the
## dying enemy (Dev A, W4-A4) and carries no `Player` argument for
## `Effect.listen()`'s filter, so a teammate's kill and an unattributed one must
## be told apart here. A death announced on `elite_killed` instead is **not** a
## second death — see the batch note in `bloodthirst.gd`.
##
## `max_stacks = 1` in the data file: one death, one flower. No line of no. 18
## says "(stacks)", and two copies of a relic whose whole effect is a spawn are
## not two spawns in the doc's sentence.
##
## The flower's *healing* reaches co-op the way the root's author makes it reach:
## the root is host-spawned through the seam, and the heal inside it is the
## root's to replicate. Nothing here writes a stat or `Health` by hand.
##
## Sync: host-only (SPEC-relics, "Multiplayer ownership").

## The folder SPEC-art-audio keeps the per-id emitter scenes in, and the extension
## every scene in that library uses — the same two constants Ember Boots, Volatile
## Core and Soul Jar use, so the batch resolves its scenes one way.
const SCENE_DIR: String = "res://scenes/vfx"
const SCENE_EXTENSION: String = ".tscn"

## The flowers this effect has planted, ever.
var _flowers: int = 0

## The scene to spawn, when something hands one over: a test injects a double
## here, and the FX-with-gameplay spawner (W4-A4) may hand the real flower over
## the same way. Left null, the relic resolves its own `vfx_id`.
var fx_scene: PackedScene = null


func _on_attach() -> void:
	listen(Events.enemy_killed, _on_enemy_killed)


## The flowers this effect has put on the ground — the read the HUD strip (G19)
## draws and the batch's case asserts 1 and 2 against.
func flowers_planted() -> int:
	return _flowers


## One of this player's kills: the corpse sprouts.
func _on_enemy_killed(enemy: Node, hit: HitInfo) -> void:
	if not _is_my_kill(enemy, hit):
		return
	_sprout(enemy)


## True when `enemy` is a positioned, valid node and `hit` is this player's own
## kill. The `owner_player` read is the payload's, not a signal argument:
## `enemy_killed` carries no `Player` for `Effect.listen()` to filter on.
func _is_my_kill(enemy: Node, hit: HitInfo) -> bool:
	if player == null or enemy == null or not is_instance_valid(enemy):
		return false
	if hit == null:
		return false
	return hit.owner_player == player


## Plants one flower where the enemy fell. A corpse with no position has nowhere
## to sprout, so the whole gesture is skipped rather than planted at the origin,
## and a spawn the seam refused plants nothing and is not counted.
func _sprout(enemy: Node) -> void:
	var corpse := enemy as Node2D
	if corpse == null:
		return
	var scene: PackedScene = _resolve_scene()
	if scene == null:
		return
	if spawn(scene, corpse.global_position) == null:
		return
	_flowers += 1


## The flower scene: the injected one when there is one, otherwise this relic's
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
