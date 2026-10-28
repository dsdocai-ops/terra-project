extends EnemyState
## One enemy attack through the combat-core contract: windup (telegraph shown,
## nothing can hit), active (the hitbox or projectile goes live), recovery
## (vulnerable, cannot act). Owned by enemies-ai. Sync: host-only; clients draw
## the telegraph from the enemy's replicated `telegraph_progress` and `aim_dir`.
##
## The phase timing and the "no hit without a telegraph" gate live in the
## combat-core `AttackDriver`: the hitbox arms only from its `active_started`,
## which only a windup that ran to completion — on screen for at least one
## frame — can fire, and the driver is disarmed on every re-entry, so a
## reused, interrupted or hitched attack cannot hit without a telegraph. The
## decisions around it — the aim direction, the rush velocity and the
## post-attack cooldown — are the pure `EnemyStateLogic`; this state applies
## them to the Enemy.

const MELEE_ARC_STEPS: int = 6
## A rush's live hitbox reaches this far past the enemy's body radius.
const RUSH_HITBOX_PADDING: float = 6.0

var _driver := AttackDriver.new()

## One cone hitbox per pattern, built the first time the pattern is used by this
## enemy and reused after that: attacking allocates no shapes once warm.
var _cone_cache: Dictionary = {}

var _pattern: AttackPattern = null
var _dir: Vector2 = Vector2.DOWN


func _on_setup() -> void:
	super()
	_driver.active_started.connect(_on_driver_active)
	_driver.recovery_started.connect(_on_driver_recovery)


func enter(_from: StringName) -> void:
	_pattern = enemy.next_attack
	if _pattern == null:
		machine.change_to(&"Chase")
		return
	_dir = Vector2.DOWN
	if is_instance_valid(enemy.target):
		_dir = EnemyStateLogic.aim(enemy.global_position, enemy.target.global_position)
	enemy.aim_dir = _dir
	enemy.telegraph.configure(_pattern, _dir)
	enemy.telegraph_progress = 0.0
	enemy.current_anim = &"windup"
	_driver.start(_pattern)


func exit(_to: StringName) -> void:
	_driver.stop()
	enemy.telegraph_progress = -1.0
	enemy.hitbox.active = false


func physics_update(delta: float) -> void:
	if _pattern == null:
		return
	# `advance` returns the phase whose behaviour this frame runs: a boundary
	# crossed inside the call takes effect on the next one, so every phase's
	# movement covers exactly its own frames — the same frame layout the
	# hand-rolled clock had — and the crossing's signal arms or disarms the
	# hitbox on the crossing frame itself.
	match _driver.advance(delta):
		AttackDriver.Phase.WINDUP:
			enemy.stop_moving(delta)
			enemy.telegraph_progress = _driver.telegraph_progress()
		AttackDriver.Phase.ACTIVE:
			if _pattern.kind == AttackPattern.Kind.RUSH:
				enemy.velocity = EnemyStateLogic.rush_velocity(_dir, _pattern.speed, machine.effective_scale)
				enemy.move_and_slide()
			else:
				enemy.stop_moving(delta)
		AttackDriver.Phase.RECOVERY:
			enemy.stop_moving(delta)
		AttackDriver.Phase.DONE:
			enemy.stop_moving(delta)
	# The frame the clock runs out is the frame the state hands back to the
	# chase, after the recovery behaviour above has run.
	if _driver.phase() == AttackDriver.Phase.DONE:
		enemy.attack_cooldown_left = EnemyStateLogic.ATTACK_COOLDOWN_SECONDS
		machine.change_to(&"Chase")


func _on_driver_active() -> void:
	enemy.telegraph_progress = -1.0
	enemy.current_anim = &"attack"
	var hit: HitInfo = _build_hit()
	match _pattern.kind:
		AttackPattern.Kind.MELEE:
			enemy.hitbox_shape.shape = _cone_shape()
			enemy.hitbox.rotation = _dir.angle()
			enemy.hitbox.template = hit
			enemy.hitbox.active = true
		AttackPattern.Kind.RUSH:
			var circle := CircleShape2D.new()
			circle.radius = enemy.data.radius + RUSH_HITBOX_PADDING
			enemy.hitbox_shape.shape = circle
			enemy.hitbox.rotation = 0.0
			enemy.hitbox.template = hit
			enemy.hitbox.active = true
		AttackPattern.Kind.PROJECTILE:
			_fire(hit)


func _on_driver_recovery() -> void:
	enemy.hitbox.active = false
	enemy.current_anim = &"recovery"


func _build_hit() -> HitInfo:
	var hit := HitInfo.new()
	hit.source = enemy
	var biome: int = GameState.run.biome_index if GameState.run != null else 1
	hit.base_damage = _pattern.damage * Scaling.enemy_damage_mult(biome)
	hit.element = _pattern.element
	hit.knockback = _dir * _pattern.knockback
	hit.hit_stun_seconds = _pattern.hit_stun_seconds
	hit.is_projectile = _pattern.kind == AttackPattern.Kind.PROJECTILE
	hit.is_heavy = _pattern.is_heavy
	hit.poise_damage = _pattern.poise_damage
	hit.tags.append(&"enemy")
	return hit


func _cone_shape() -> ConvexPolygonShape2D:
	var cached: ConvexPolygonShape2D = _cone_cache.get(_pattern) as ConvexPolygonShape2D
	if cached == null:
		cached = _build_cone_shape()
		_cone_cache[_pattern] = cached
	return cached


func _build_cone_shape() -> ConvexPolygonShape2D:
	var half: float = deg_to_rad(_pattern.telegraph_size.y) * 0.5
	var points := PackedVector2Array([Vector2.ZERO])
	for step: int in range(MELEE_ARC_STEPS + 1):
		var angle: float = lerpf(-half, half, float(step) / float(MELEE_ARC_STEPS))
		points.append(Vector2.RIGHT.rotated(angle) * _pattern.telegraph_size.x)
	var shape := ConvexPolygonShape2D.new()
	shape.set_point_cloud(points)
	return shape


func _fire(hit: HitInfo) -> void:
	var world: World = GameState.world
	if world == null:
		return
	var info := ProjectileSpawnInfo.new(&"fireball", enemy.global_position + _dir * 12.0, _dir * _pattern.speed, 1)
	var projectile: Projectile = world.projectile_spawner.spawn_projectile(info) as Projectile
	if projectile != null:
		projectile.launch(hit, Team.Kind.ENEMY, 420.0, 0)
