class_name StatusEnemyStub
extends CharacterBody2D
## Test double for Dev A's enemy (enemies-ai, W4-A1): a `CharacterBody2D` that
## joins the `enemy` group and carries a `Health` double, so SHOCK's radius
## chain (stats-status, G22) has something to find, measure and damage.
## Owned by stats-status (tests).
##
## blocked on Dev A (W4-A1, enemies-ai): the real chain-target source is the
## group Dev A's enemy base registers in, which does not exist yet. This double
## registers in the group name the component looks for —
## `StatusEffects.ENEMY_TAG` — so the swap-in is a delete, not a rewrite, the
## same shape `EnemyBaseStub` uses for the spawner tests.
##
## Sync: none — a test helper. The real enemy is host-authoritative, and chain
## damage is resolved on the host only (SPEC-stats-status, "Multiplayer
## ownership").

## The node name of the `Health` child, taken from the component's own constant
## so the double and the lookup cannot drift apart.
const HEALTH_NODE: NodePath = ^"Health"
const HEALTH_MARKER: StringName = &"Health"

## The `Health` double this enemy receives chain damage through.
var health: StatusHealthStub = null

## Whether this enemy counts as `wet` for CONDUCT (stats-status, G24): the
## spec's trigger is "Storm on a `wet` target (standing in water tile or Drowned
## enemy)". The real property belongs to the world — the tile the entity stands
## on, or Dev A's `Drowned` enemy — **blocked on Dev A (W4-A1)**; the component
## reads it off `StatusEffects.WET_PROPERTY`, so the swap-in is Dev A declaring
## the same property rather than a change here.
var wet: bool = false

## The enemies the connected water area holds, returned when CONDUCT asks this
## entity for `StatusEffects.WATER_AREA_METHOD`. The real query belongs to
## floor-generation's water tiles — **blocked on Dev A (W2-A1, floor-generation
## water tiles)**.
var water_targets: Array[Node] = []

## How many times CONDUCT asked this entity for the connected water area, so a
## case can assert the request the seam receives rather than only its result.
var water_area_calls: int = 0

## Every pull COLLAPSE requested on this enemy, as `{origin, radius}`: the
## request Dev A's enemy body will receive (**blocked on Dev A (W4-A1)**), which
## is why the case asserts the request and not a moved position.
var pulls: Array[Dictionary] = []


## Builds an enemy double at `at` under `parent`, in the `enemy` group, with a
## `Health` double of `max_hp`. The caller owns it (parent it under an autofreed
## node and it goes with it).
static func make(parent: Node, at: Vector2 = Vector2.ZERO, max_hp: int = 100) -> StatusEnemyStub:
	var enemy := StatusEnemyStub.new()
	enemy.name = &"StatusEnemyStub"
	enemy.position = at
	enemy.collision_layer = 0
	enemy.collision_mask = 0
	parent.add_child(enemy)
	enemy.add_to_group(StatusEffects.ENEMY_TAG)
	var health := StatusHealthStub.new()
	health.name = HEALTH_MARKER
	health.max_hp = max_hp
	health.current_hp = max_hp
	enemy.add_child(health)
	enemy.health = health
	return enemy


## The seam CONDUCT's spread asks for: the enemies touching the connected water
## area. Returns this double's `water_targets` (empty until a case sets one) and
## counts the ask.
func connected_water_targets() -> Array[Node]:
	water_area_calls += 1
	return water_targets


## The seam COLLAPSE's pull asks for: this enemy is pulled toward `origin` from
## up to `radius` px away. The double records the request; the movement itself
## is Dev A's enemy body and does not exist yet.
func pull_toward(origin: Node2D, radius: float) -> void:
	pulls.append({"origin": origin, "radius": radius})
