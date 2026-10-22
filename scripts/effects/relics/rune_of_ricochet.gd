class_name RuneOfRicochetEffect
extends Effect
## Rune of Ricochet — design doc 9.1 no. 14: "projectiles bounce to 2 more
## enemies". Owned by relics (W4-B6, goal G7).
##
## On `projectile_fired(player, projectile)` it asks that projectile for
## `EXTRA_BOUNCES` more ricochets. The projectile's body, its travel, what a
## bounce targets and how a ricochet is resolved are combat-core's (Dev A,
## W2-A6), and a relic cannot reach into a node it did not build — so the relic
## asks by name, guarded by `has_method()`, and the ask is the relic's whole
## contribution. A projectile without the seam is a skipped ask, not an error:
## the swap-in is Dev A declaring `add_bounce()`, and this script does not change
## (**blocked on Dev A (W2-A6)**).
##
## This is the sibling of Splitting Shot's seam and deliberately not the same
## one. `Splitting Shot` *creates* projectiles, so it goes through
## `Effect.fire_projectile()` → `EffectSpawner.projectiles` and the specs a case
## reads back are its own. This relic redirects a projectile somebody else fired,
## so the only channel is the node on the signal payload, and the case asserts the
## request rather than a spawn. `tests/helpers/projectile_seam_stub.gd` is the
## double; the real projectile replaces it name for name.
##
## **Who the projectiles are.** `Effect.listen()`'s player filter drops a
## `projectile_fired` for any player but this effect's own — that signal declares
## a `Player` argument (unlike `hit_landed`), so nothing here reads the owner off
## the payload by hand.
##
## **`extra_bounces()` is published.** The read exists so the number one projectile
## carries is inspectable without a fired shot — by a case, and by the debug
## overlay — and so the number is one decision rather than the ask's alone. It is
## the same shape Hungry Steel's `damage_multiplier_for()` publishes, except this
## one has no consumer in the attack pipeline to hand a step to: a bounce is
## resolved inside the projectile, so the ask *is* the mechanism.
##
## `max_stacks = 1` in the data file: the design doc's "2 more" is a fixed number
## and two copies are not written as "4 more" anywhere, so the read stays the
## doc's 2 whatever the copy count. A stack rule for this relic would need the
## doc to say "(stacks)", which its line does not.
##
## Sync: host-only (SPEC-relics, "Multiplayer ownership"). SPEC-effect-system —
## the projectile is host-authoritative and its bounces replicate as the
## projectile's own state.

## How many extra ricochets one projectile is asked for. Design doc 9.1 no. 14:
## "projectiles bounce to 2 more enemies".
const EXTRA_BOUNCES: int = 2
## The method the ricochet is requested through. combat-core's `Projectile` owns
## it; named here so the double and the effect cannot drift apart
## (**blocked on Dev A (W2-A6)**).
const BOUNCE_METHOD: StringName = &"add_bounce"


func _on_attach() -> void:
	listen(Events.projectile_fired, _on_projectile_fired)


## The extra ricochets this effect asks a projectile for. The design doc's number,
## not the copy count: `max_stacks = 1`.
func extra_bounces() -> int:
	return EXTRA_BOUNCES


## The holder's shot: ask it to bounce on to `EXTRA_BOUNCES` more enemies. The
## player argument is the filter's — `listen()` has already refused a teammate's
## shot before this runs — so it is not read again here.
func _on_projectile_fired(_player: Player, projectile: Node) -> void:
	if projectile == null or not is_instance_valid(projectile):
		return
	if projectile.has_method(BOUNCE_METHOD):
		projectile.call(BOUNCE_METHOD, extra_bounces())