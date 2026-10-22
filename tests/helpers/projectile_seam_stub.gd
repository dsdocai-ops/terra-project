class_name ProjectileSeamStub
extends Node2D
## The double for the seam an On Hit relic asks when it wants something a
## **projectile already in flight** should do: **Rune of Ricochet**'s two extra
## bounces.
##
## The projectile's body, its travel and its ricochet are combat-core's
## (**blocked on Dev A (W2-A6)**), and a relic cannot reach into it, so the relic
## asks the projectile node for the bounce and the ask is what a case can assert:
## `add_bounce(count)`, recorded in `bounces`. The effect looks the node up on the
## `projectile_fired` payload, checks `has_method()` before calling, and a
## projectile without the seam is a guarded no-op rather than an error — the C6
## shape the whole project uses for a provider another lane owns.
##
## The real projectile is Dev A's: a `Projectile` node carrying `add_bounce()`
## replaces this double name for name, and the effect does not change.
##
## Owned by relics (tests). Sync: none — a test double. The real projectile is
## host-only; its bounces replicate as the projectile's own state.
##
## blocked on Dev A (W2-A6, combat-core's `Projectile`): the ricochet itself.
## `SplittingShotEffect`'s splitting is the same seam family, and it goes through
## `Effect.fire_projectile()` → `EffectSpawner.projectiles` instead, because it
## *creates* projectiles rather than redirecting one already flying.

## The method the relic asks for, so the effect's constant and the double's
## method cannot drift apart.
const BOUNCE_METHOD: StringName = &"add_bounce"

## Every `add_bounce()` call's argument, in order — one entry per ask, so a case
## can tell "asked once for 2" from "asked twice for 1".
var bounces: Array[int] = []


## Builds a projectile double under `parent`. The caller owns it (parent it
## under an autofreed node and it goes with it).
static func make(parent: Node) -> ProjectileSeamStub:
	var shot := ProjectileSeamStub.new()
	shot.name = &"ProjectileSeamStub"
	parent.add_child(shot)
	return shot


## The ask: this projectile should ricochet to `count` more enemies. The ricochet
## itself is Dev A's and does not exist yet, so the request is recorded and
## nothing here moves or redirects anything.
func add_bounce(count: int) -> void:
	bounces.append(count)


## The total number of extra bounces asked for — the one-line read a case takes
## when it does not care how the asks were split.
func bounces_requested() -> int:
	var total: int = 0
	for count: int in bounces:
		total += count
	return total