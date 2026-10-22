class_name Hurtbox
extends Area2D
## Where an entity can be hit, and the one place a hit becomes damage. Owned by
## combat-core. Sits at `<entity>/Hurtbox`, beside `Health`, `StatBlock` and
## `StatusEffects`, which is where `Effect.deal_damage` looks for it.
## Sync: host only. `receive` early-returns on clients; they render the result
## from the replicated `Events.hit_landed` and the replicated `current_hp`.

## The hit landed on a dodging player and was avoided. `Player` listens for the
## perfect-dodge check ("only when a hit was actually blocked").
signal blocked_during_dodge(hit: HitInfo)

const HEALTH_NODE: NodePath = ^"../Health"
const STAT_BLOCK_NODE: NodePath = ^"../StatBlock"
## The attacker's own `StatBlock`, found under `hit.source`.
const SOURCE_STAT_BLOCK_NODE: NodePath = ^"StatBlock"
const STATUS_NODE: NodePath = ^"../StatusEffects"
## The entity method that applies knockback and hit-stun, when it has one:
## `apply_knockback(impulse: Vector2, stun_seconds: float)`. HitStun (W2-A3)
## provides it on players and enemies.
const KNOCKBACK_METHOD: StringName = &"apply_knockback"
## Neutral stats for a source or target with no `StatBlock` (a hazard, a
## destructible): attack 100 is the formula's reference, defense 0.
const NEUTRAL_ATTACK: float = 100.0

@export var team: Team.Kind = Team.Kind.PLAYER:
	set(value):
		team = value
		_apply_layer()
## While true no hit lands. Post-hit i-frames, dodge i-frames and scripted
## immunity (Stone Skin) all set it.
var invulnerable: bool = false
## True during a dodge roll's i-frames: an invulnerable hit then reports
## `blocked_during_dodge` instead of silently vanishing.
var dodge_invulnerable: bool = false


func _ready() -> void:
	_apply_layer()
	monitoring = false


func _apply_layer() -> void:
	collision_layer = Hitbox.LAYER_ENEMY_BODY if team != Team.Kind.PLAYER else Hitbox.LAYER_PLAYER_BODY
	collision_mask = 0


## Resolves `hit` against this entity. Returns whether it connected: false on a
## client, on an invulnerable or dead target, or with no `Health` to damage.
func receive(hit: HitInfo) -> bool:
	if hit == null or not multiplayer.is_server():
		return false
	var entity: Node = get_parent()
	var health := get_node_or_null(HEALTH_NODE) as Health
	if health == null or health.is_dead:
		return false
	if invulnerable:
		if dodge_invulnerable:
			blocked_during_dodge.emit(hit)
		return false
	hit.target = entity
	hit.from_behind = _is_from_behind(entity, hit)
	var statuses := get_node_or_null(STATUS_NODE) as StatusEffects
	_compute_damage(hit, statuses)
	if not health.apply_damage(hit):
		return false
	Events.hit_landed.emit(hit)
	if hit.is_crit:
		Events.crit_landed.emit(hit)
	var player := entity as Player
	if player != null:
		Events.player_damaged.emit(player, hit)
	if not health.is_dead:
		_apply_reactions(entity, hit, statuses)
	return true


func _compute_damage(hit: HitInfo, statuses: StatusEffects) -> void:
	var attacker: StatBlock = null
	if hit.source != null and is_instance_valid(hit.source):
		attacker = hit.source.get_node_or_null(SOURCE_STAT_BLOCK_NODE) as StatBlock
	var target := get_node_or_null(STAT_BLOCK_NODE) as StatBlock
	var temporary: Array[StatBlock] = []
	if attacker == null:
		attacker = StatBlock.new()
		attacker.base = {StatBlock.Stat.ATTACK: NEUTRAL_ATTACK}
		temporary.append(attacker)
	if target == null:
		target = StatBlock.new()
		temporary.append(target)
	Damage.compute(attacker, target, hit, null, statuses)
	for block: StatBlock in temporary:
		block.free()


## Knockback along the hit direction and the hit's statuses. Skipped for a dead
## target.
func _apply_reactions(entity: Node, hit: HitInfo, statuses: StatusEffects) -> void:
	if not hit.knockback.is_zero_approx() and entity.has_method(KNOCKBACK_METHOD):
		entity.call(KNOCKBACK_METHOD, hit.knockback, hit.hit_stun_seconds)
	if statuses == null:
		return
	for application: StatusApplication in hit.statuses:
		statuses.apply_status(application.status, application.stacks, hit.source)


## Compares the target's facing with the direction the hit came from.
func _is_from_behind(entity: Node, hit: HitInfo) -> bool:
	var body := entity as Node2D
	var facing_value: Variant = entity.get("facing")
	if body == null or not facing_value is Vector2:
		return false
	var origin := hit.source as Node2D
	var to_attacker: Vector2 = Vector2.ZERO
	if origin != null:
		to_attacker = origin.global_position - body.global_position
	elif not hit.knockback.is_zero_approx():
		to_attacker = -hit.knockback
	return HitInfo.is_from_behind(facing_value, to_attacker)
