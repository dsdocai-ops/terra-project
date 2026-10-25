extends EnemyState
## One enemy attack through the combat-core contract: windup (telegraph shown,
## nothing can hit), active (the hitbox or projectile goes live), recovery
## (vulnerable, cannot act). Owned by enemies-ai. Sync: host-only; clients draw
## the telegraph from the replicated `telegraph_progress` and `aim_dir`.

enum Phase { WINDUP, ACTIVE, RECOVERY }

const MELEE_ARC_STEPS: int = 6

var _pattern: AttackPattern = null
var _phase: Phase = Phase.WINDUP
var _elapsed: float = 0.0
var _dir: Vector2 = Vector2.DOWN


func enter(_from: StringName) -> void:
	_pattern = enemy.next_attack
	if _pattern == null:
		machine.change_to(&"Chase")
		return
	_phase = Phase.WINDUP
	_elapsed = 0.0
	_dir = Vector2.DOWN
	if is_instance_valid(enemy.target):
		_dir = (enemy.target.global_position - enemy.global_position).normalized()
	enemy.aim_dir = _dir
	enemy.telegraph.configure(_pattern, _dir)
	enemy.telegraph_progress = 0.0
	enemy.current_anim = &"windup"


func exit(_to: StringName) -> void:
	enemy.telegraph_progress = -1.0
	enemy.hitbox.active = false


func physics_update(delta: float) -> void:
	if _pattern == null:
		return
	_elapsed += delta
	match _phase:
		Phase.WINDUP:
			enemy.stop_moving(delta)
			enemy.telegraph_progress = clampf(_elapsed / maxf(_pattern.windup_seconds, 0.01), 0.0, 1.0)
			if _elapsed >= _pattern.windup_seconds:
				_start_active()
		Phase.ACTIVE:
			if _pattern.kind == AttackPattern.Kind.RUSH:
				enemy.velocity = _dir * _pattern.speed
				enemy.move_and_slide()
			else:
				enemy.stop_moving(delta)
			if _elapsed >= _pattern.active_seconds:
				_start_recovery()
		Phase.RECOVERY:
			enemy.stop_moving(delta)
			if _elapsed >= _pattern.recovery_seconds:
				enemy.attack_cooldown_left = 0.2
				machine.change_to(&"Chase")


func _start_active() -> void:
	_phase = Phase.ACTIVE
	_elapsed = 0.0
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
			circle.radius = enemy.data.radius + 6.0
			enemy.hitbox_shape.shape = circle
			enemy.hitbox.rotation = 0.0
			enemy.hitbox.template = hit
			enemy.hitbox.active = true
		AttackPattern.Kind.PROJECTILE:
			_fire(hit)


func _start_recovery() -> void:
	_phase = Phase.RECOVERY
	_elapsed = 0.0
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
	hit.tags.append(&"enemy")
	return hit


func _cone_shape() -> ConvexPolygonShape2D:
	var half: float = deg_to_rad(_pattern.telegraph_size.y) * 0.5
	var points := PackedVector2Array([Vector2.ZERO])
	for step: int in range(MELEE_ARC_STEPS + 1):
		var angle: float = lerpf(-half, half, float(step) / float(MELEE_ARC_STEPS))
		points.append(Vector2.RIGHT.rotated(angle) * _pattern.telegraph_size.x)
	var shape := ConvexPolygonShape2D.new()
	shape.points = points
	return shape


func _fire(hit: HitInfo) -> void:
	var world: World = GameState.world
	if world == null:
		return
	var info := ProjectileSpawnInfo.new(&"fireball", enemy.global_position + _dir * 12.0, _dir * _pattern.speed, 1)
	var projectile: Projectile = world.projectile_spawner.spawn_projectile(info) as Projectile
	if projectile != null:
		projectile.launch(hit, Team.Kind.ENEMY, 420.0, 0)
