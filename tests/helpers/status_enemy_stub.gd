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
