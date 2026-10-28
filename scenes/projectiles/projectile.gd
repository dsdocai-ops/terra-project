class_name Projectile
extends Hitbox
## A projectile for both teams (SPEC-combat-core `Projectile`): straight flight,
## plus pierce, bounce, homing, lifetime, reflect and time-scaled movement.
## Owned by combat-core. Sync: the host owns flight and damage; StateSync
## replicates `synced_position`, `synced_velocity`, `owner_peer_id` and
## `hostile`, and clients only present that pose. The flight math itself lives
## in the pure `ProjectileFlight` core, and the `ProjectilePool` recycles the
## nodes on the host. Replicated bolts still spawn and despawn through
## ProjectileSpawner (W2-B3), whose despawn frees the client copies — so a
## pooled instance is never handed to it.
## Placeholder art: a small coloured diamond.

const WALL_MASK: int = 1
const PLAYER_COLOR: Color = Color(1.0, 0.9, 0.5, 1.0)
const ENEMY_COLOR: Color = Color(1.0, 0.45, 0.2, 1.0)
## Range a spawner-driven projectile flies when `launch` never armed it.
const DEFAULT_RANGE: float = 400.0

var synced_position: Vector2 = Vector2.ZERO
var synced_velocity: Vector2 = Vector2.ZERO
var owner_peer_id: int = 1
## True for enemy projectiles; replicated so clients tint them.
var hostile: bool = false:
	set(value):
		hostile = value
		_apply_color()

## Radians per second the projectile may turn toward `homing_target`
## (SPEC-combat-core `homing_strength`). 0.0 flies dead straight.
var homing_strength: float = 0.0
## The node the homing turn chases, when the projectile homes at all.
var homing_target: Node2D = null
## Seconds of flight before the projectile expires on its own. 0 = unlimited;
## the range budget always applies.
var lifetime_seconds: float = ProjectileFlight.NO_LIFETIME
## Whether a reflect source (Guardian block, Crystal Hollows crystals) can bat
## the projectile back at the other team (SPEC-combat-core `reflectable`).
var reflectable: bool = false

## combat-core's pool when this projectile is pooled; null flies free and dies
## with the old queue_free.
var pool: ProjectilePool = null

var _pierce_left: int = 0
var _flight: ProjectileFlight = null
var _body: Polygon2D = null
## Set the frame the projectile retires: the hand-back to the pool is deferred,
## so until it lands no further frame may step a dead projectile. The pool
## clears it on acquire.
var _retired: bool = false


func _ready() -> void:
	super._ready()
	_body = get_node_or_null("Body") as Polygon2D
	_apply_color()
	synced_position = position
	hit_connected.connect(_on_hit_connected)


## Host. Arms the projectile: `hit` is its damage template. A non-null `spec`
## supplies every flight number — bounce count, homing turn rate, lifetime and
## the reflect flag — and is where a caller carries speed and pierce; without
## one the projectile flies the old way, on its own vars: straight, no
## ricochet.
func launch(hit: HitInfo, side: Team.Kind, max_range: float, pierce: int, spec: ProjectileSpec = null) -> void:
	team = side
	hostile = side == Team.Kind.ENEMY
	template = hit
	_pierce_left = pierce
	hit_once_per_target = true
	active = true
	if spec != null:
		homing_strength = spec.homing_strength
		lifetime_seconds = spec.lifetime_seconds
		reflectable = spec.reflectable
	# The flight object is reused, not remade: `arm` rewrites every number it
	# carries, so a pooled projectile's next shot never allocates mid-run.
	_ensure_flight()
	_flight.arm(synced_velocity, max_range, lifetime_seconds)
	_flight.bounces_left = spec.bounce if spec != null else 0
	_flight.homing_strength = homing_strength
	_flight.reflectable = reflectable
	_update_time_group()


## The seam a relic asks when it wants this projectile already in flight to
## ricochet more (`ProjectileSeamStub.BOUNCE_METHOD`): `count` more bounces.
func add_bounce(count: int) -> void:
	_ensure_flight()
	_flight.bounces_left += count


## A reflect source bats the projectile back at the other team. Returns whether
## it reflected — a projectile without the flag is a guarded no-op, the same
## shape the relic seam uses for a provider that is not there.
func reflect_projectile() -> bool:
	_ensure_flight()
	if not _flight.reflect():
		return false
	team = Team.Kind.ENEMY if team == Team.Kind.PLAYER else Team.Kind.PLAYER
	hostile = team == Team.Kind.ENEMY
	# The time group follows the team across a reflect too: a reflected enemy
	# bolt must stop freezing with the enemy stack, a reflected player bolt
	# must join it.
	_update_time_group()
	return true


## Enemy projectiles respect the enemy time stack (SPEC-combat-core): a global
## slow or stop drags their flight with it. Player projectiles register in the
## PLAYER group, which `scale_for` treats exactly like unregistered.
func _update_time_group() -> void:
	TimeManager.set_group(self, TimeManager.Group.ENEMY if hostile else TimeManager.Group.PLAYER)


## Test and seam read of the bounce budget left.
func bounces_left() -> int:
	_ensure_flight()
	return _flight.bounces_left


## Test and seam read of the range budget left.
func range_left() -> float:
	_ensure_flight()
	return _flight.distance_left


## Test and seam read of the flight's current velocity (post turn or bounce).
func flight_velocity() -> Vector2:
	_ensure_flight()
	return _flight.velocity


func _physics_process(delta: float) -> void:
	if _retired:
		return
	if not multiplayer.is_server():
		position = synced_position
		return
	_ensure_flight()
	_host_step(delta)


## Parked for the pool (`ProjectilePool._make` and `release`): retired, so
## `_physics_process` steps nothing while the bolt waits idle, and with the
## flight object already made, so even the first launch after warm-up
## allocates nothing.
func park() -> void:
	_retired = true
	_ensure_flight()


## The pool calls this on acquire: a reused projectile starts clean, with the
## flight numbers a previous launch left behind reset to what a fresh node
## carries. The next `launch` re-arms whatever that shot needs — with no spec
## it flies the defaults, not the last shot's homing, lifetime or reflect —
## and the last shot's size does not ride along either.
func reset_for_reuse() -> void:
	homing_strength = 0.0
	homing_target = null
	lifetime_seconds = ProjectileFlight.NO_LIFETIME
	reflectable = false
	_pierce_left = 0
	scale = Vector2.ONE


## End of flight — a wall with no bounce left, a spent budget, pierce run out:
## a pooled projectile hands itself back to its pool (deferred, because this
## runs inside physics), and only an unpooled one dies with queue_free. The
## retirement lands this frame either way, so nothing dead keeps flying.
func _retire() -> void:
	if _retired:
		return
	_retired = true
	if pool != null and is_instance_valid(pool):
		pool.release_deferred(self)
	else:
		queue_free()


## Host. One frame of flight: steer, step, die on an empty budget, bounce off
## a wall or stop at one. `ProjectileFlight` carries every number; this is only
## the glue to the physics ray and the replicated pose. The step is raycast
## before its cost is committed, so a bounce frame spends the frame's time but
## not its range.
func _host_step(delta: float) -> void:
	var time_scale: float = TimeManager.scale_for(self)
	_steer(delta, time_scale)
	var step: Vector2 = _flight.step_for(delta, time_scale)
	var bounced := false
	if step != Vector2.ZERO:
		var wall: Dictionary = _wall_normal_ahead(step)
		if not wall.is_empty():
			if not _flight.hit_wall(wall["normal"], delta, time_scale):
				_retire()
				return
			# The bounce spends this frame turning; the next step flies out.
			# The frame's time still passes (`hit_wall` burns the lifetime),
			# but the range does not: nothing moved.
			step = Vector2.ZERO
			bounced = true
	if not bounced:
		_flight.commit(step, delta, time_scale)
	if _flight.is_expired():
		_retire()
		return
	if step != Vector2.ZERO:
		position += step
		synced_position = position
	synced_velocity = _flight.velocity


func _steer(delta: float, time_scale: float) -> void:
	if homing_strength <= 0.0:
		return
	if homing_target == null or not is_instance_valid(homing_target):
		return
	_flight.turn_toward(homing_target.global_position, global_position, delta, time_scale)


## The surface normal of the wall the step would cross, or an empty Dictionary
## when the step is clear. Rays never span zero length.
func _wall_normal_ahead(step: Vector2) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step, WALL_MASK)
	return space.intersect_ray(query)


## Flight for a projectile the spawner placed but nobody launched yet: it flies
## straight on its defaults until something arms it properly.
func _ensure_flight() -> void:
	if _flight != null:
		return
	_flight = ProjectileFlight.new()
	_flight.arm(synced_velocity, DEFAULT_RANGE, lifetime_seconds)
	_flight.homing_strength = homing_strength
	_flight.reflectable = reflectable


func _on_hit_connected(_hurtbox: Hurtbox, _hit: HitInfo) -> void:
	if _pierce_left <= 0:
		_retire()
		return
	_pierce_left -= 1


func _apply_color() -> void:
	if _body != null:
		_body.color = ENEMY_COLOR if hostile else PLAYER_COLOR
