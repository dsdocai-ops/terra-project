class_name SoulJarEffect
extends Effect
## Soul Jar — design doc 9.1 no. 16: "kills charge a jar, at 20 kills it releases
## a ghost army for 10s". Owned by relics (W4-B6, goal G7).
##
## It counts this player's kills. Each one charges the jar by `charge_per_kill()`;
## when the charge reaches `SOUL_JAR_KILLS` the jar releases: one ghost army is
## spawned at the holder, armed to stand for `GHOST_ARMY_SECONDS`, and the jar is
## emptied of exactly that many kills — so a kill that arrives while the army is
## out starts charging the next jar rather than being lost, and the twentieth kill
## releases once rather than on the twenty-first as well.
##
## **The count is the relic's, not the run's.** Every bound is a constant of this
## script and `charge()` is published for the HUD strip (goal G19) to draw the jar
## without re-deriving it; `armies_released()` is published beside it so a case can
## tell "released once" from "still charging". Both are reads — nothing outside
## this effect writes them.
##
## **Stacking is what makes a second copy worth holding.** `max_stacks = 2` in the
## data file and `charge_per_kill()` returns the copy count, so two Jars fill in
## half the kills. The design doc gives no stack rule for this relic, so both the
## cap and the "more copies charge faster" reading are this lane's calls — the
## relic is a build-around whose whole promise is a count, and a second copy that
## did nothing would be the only relic in the batch with no reason to pick it
## twice. Which *relics* the four stackable ones are is the batch's own question;
## `Soul Jar` is one of them (PLAN, G7).
##
## **The ghost army itself.** `ContentData.vfx_id` — SPEC-art-audio: "each
## ability, relic proc, and mutation names its VFX id in its data" — resolved as
## `res://scenes/vfx/<vfx_id>.tscn`, exactly as Ember Boots resolves its trail.
## The scene is spawned only when one resolves: while
## `scenes/vfx/relic_proc_on_kill.tscn` does not exist (**blocked on art-audio
## (W4-B12/B13)**) a full jar in a game build today still charges, still empties
## and still counts the release, and spawns nothing — rather than warning once per
## twentieth kill. What the army then *does* — who it fights for, how long it
## really lasts, whether it is a minion or a hazard — is `arm_lifetime()`'s
## contract with the root and the root's own gameplay (**blocked on Dev A
## (W4-A4)**); a root without the method is spawned unarmed rather than refused, so
## an emitter-only scene can stand in without erroring.
##
## **The duration is the doc's.** `GHOST_ARMY_SECONDS` is 10.0 because the design
## doc's line says "for 10s"; `arm_lifetime()` is the one place it is handed to
## the root, and it is handed over in seconds so the root measures it the way the
## doc states it and not in frames or ticks.
##
## **Which kills count.** This player's kills, read off `hit.owner_player`, for the
## reason Volatile Core reads its own: `enemy_killed` is emitted by the dying enemy
## (Dev A, W4-A4) and carries no `Player` argument for `Effect.listen()`'s filter,
## so a teammate's kill and an unattributed one must be told apart here.
##
## Sync: host-only (SPEC-relics, "Multiplayer ownership"). The charge is host state
## and is not replicated; the army reaches clients through the spawner seam, which
## runs on the host, and `charge()` is read by the HUD of the player who owns the
## jar.

## How many kills fill the jar. Design doc 9.1 no. 16: "at 20 kills it releases a
## ghost army for 10s".
const SOUL_JAR_KILLS: int = 20
## How long the released army stands, in seconds. The same line's "for 10s".
const GHOST_ARMY_SECONDS: float = 10.0
## The arming method this relic asks the root it spawned for. The gameplay inside
## the army is Dev A's W4-A4, so a request is what this lane can make; a root
## without the method is spawned unarmed rather than refused.
const ARM_LIFETIME_METHOD: StringName = &"arm_lifetime"
## The folder SPEC-art-audio keeps the per-id emitter scenes in, and the extension
## every scene in that library uses — the same two constants Ember Boots uses, so
## the batch resolves its scenes one way.
const SCENE_DIR: String = "res://scenes/vfx"
const SCENE_EXTENSION: String = ".tscn"

## The kills charged into the jar so far, 0 to `SOUL_JAR_KILLS - 1` after a
## release. Per effect, so a Mimic Crown copy holds its own jar.
var _charge: int = 0
## How many times this effect has released an army, for the batch's cases.
var _armies_released: int = 0

## The scene to spawn, when something hands one over: a test injects a double
## here, and the FX-with-gameplay spawner (W4-A4) may hand the real army over the
## same way. Left null, the relic resolves its own `vfx_id`.
var fx_scene: PackedScene = null


func _on_attach() -> void:
	listen(Events.enemy_killed, _on_enemy_killed)


## The kills charged into the jar right now — the read the HUD strip (G19) draws
## and the read the batch's cases assert 19 and 20 against.
func charge() -> int:
	return _charge


## How many ghost armies this effect has released, ever.
func armies_released() -> int:
	return _armies_released


## How many kills one charge costs. One per copy of the relic: `max_stacks = 2`,
## so two Jars charge the same kill twice and fill in half the time.
func charge_per_kill() -> int:
	return maxi(stacks, 1)


## One of this player's kills: charge the jar, and release when it is full.
func _on_enemy_killed(enemy: Node, hit: HitData) -> void:
	if not _is_my_kill(enemy, hit):
		return
	_charge += charge_per_kill()
	if _charge < SOUL_JAR_KILLS:
		return
	_charge -= SOUL_JAR_KILLS
	_release()


## True when `enemy` is a valid node and `hit` is this player's own kill. The
## `owner_player` read is the payload's, not a signal argument: `enemy_killed`
## carries no `Player` for `Effect.listen()` to filter on.
func _is_my_kill(enemy: Node, hit: HitData) -> bool:
	if player == null or enemy == null or not is_instance_valid(enemy):
		return false
	if hit == null:
		return false
	return hit.owner_player == player


## Releases one ghost army at the holder: the spawn, the arming, and the count.
## The charge was already spent by the caller, so a release that spawns nothing
## (no scene yet) still leaves the jar empty — the twentieth kill does not charge
## the jar it filled.
func _release() -> void:
	_armies_released += 1
	var scene: PackedScene = _resolve_scene()
	if scene == null:
		return
	spawn(scene, player.global_position, Callable(self, &"_arm_lifetime"))


## Arms the army the seam handed back. Runs before the army enters the tree
## (`EffectSpawner.spawn_node()` calls `setup` before `add_child()`), so the army
## is already counting down its ten seconds by its first frame.
func _arm_lifetime(army: Node) -> void:
	if army.has_method(ARM_LIFETIME_METHOD):
		army.call(ARM_LIFETIME_METHOD, GHOST_ARMY_SECONDS)


## The army scene: the injected one when there is one, otherwise this relic's own
## `vfx_id` under SPEC-art-audio's folder. Null — a dropped spawn and not an error
## — while the art library does not have it yet (W4-B12/B13).
func _resolve_scene() -> PackedScene:
	if fx_scene != null:
		return fx_scene
	if source == null or source.vfx_id == &"":
		return null
	var path: String = SCENE_DIR.path_join("%s%s" % [source.vfx_id, SCENE_EXTENSION])
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene