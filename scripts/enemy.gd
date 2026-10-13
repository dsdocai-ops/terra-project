extends CharacterBody3D
## A hostile Vela-07 mech (vela_model.gd with the Vela-07 model; the player is Vela-08) with a
## simple state-machine AI:
##   PATROL  - wanders between random spots around its home, pausing now and then.
##   CHASE   - has seen the player (in SIGHT_RANGE with a clear line of sight, or was shot):
##             runs toward them.
##   ATTACK  - inside ATTACK_RANGE: circles the player, backing off if they get too close, and
##             fires energy balls (raising the cannon for AIM_TIME first; shots lead the player a
##             little and spread, so they can be dodged).
##   RETURN  - lost the player for LOSE_TIME (or they died, or it strayed past LEASH): walks
##             home, then patrols again.
## Energy balls call take_hit(), which flashes its armour (and alerts it); at zero health it
## blows up (vela_model.gd explode()) and reassembles at home after RESPAWN_TIME.
## Feet are at y = 0 and it faces -Z.

enum State { PATROL, CHASE, ATTACK, RETURN }

const VelaModel := preload("res://scripts/vela_model.gd")
const EnergyBall := preload("res://scripts/energy_ball.gd")
const MAX_HEALTH := 50.0
const RESPAWN_TIME := 4.0
const TURN_SPEED := 6.0
const WALK_SPEED := 4.0          # patrolling
const RUN_SPEED := 9.0           # chasing and heading home
const STRAFE_SPEED := 5.0        # circling the player while attacking
const ACCEL := 20.0
const PATROL_RADIUS := 14.0      # how far from home it wanders
const SIGHT_RANGE := 70.0        # notices the player within this range (with line of sight)
const ATTACK_RANGE := 40.0       # starts shooting inside this range
const KEEP_AWAY := 14.0          # backs off when the player is closer than this
const LOSE_TIME := 4.0           # gives up after this long without seeing the player
const LEASH := 90.0              # never chases further than this from home
const SEPARATION := 4.0          # keeps this far from other enemies
const FIRE_PAUSE := Vector2(1.8, 3.0)  # random wait between shots (seconds)
const AIM_TIME := 0.5            # raises the cannon this long before each shot
const SPREAD := 1.2              # random miss at the target, in metres
const LEAD := 0.5                # how much of the player's motion it leads (1 = perfect)
const SHOT_DAMAGE := 10.0
const SHOT_COLOR := Color(1.0, 0.32, 0.12)   # red-orange, so enemy fire reads apart from yours
const SHOT_RIM := Color(0.75, 0.1, 0.05)

var player: Node3D  # set by enemy_spawner.gd before the enemy is added to the tree
var health := MAX_HEALTH
var state := State.PATROL

var _model: VelaModel
var _alive := true
var _home: Vector3
var _layer: int
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _wander_to := Vector3.ZERO
var _wait := 0.0                 # patrol pause left
var _stuck := 0.0                # time spent barely moving toward a patrol point
var _since_seen := INF
var _strafe_dir := 1.0
var _strafe_time := 0.0
var _fire_timer := 0.0


func _ready() -> void:
	add_to_group("enemies")
	_home = position
	_layer = collision_layer
	_build_body()
	_pick_wander_point()
	_wait = randf_range(0.0, 2.0)
	_fire_timer = randf_range(FIRE_PAUSE.x, FIRE_PAUSE.y)


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	var player_ok: bool = player != null and not player.get("dead")
	var to_player := (player.global_position - global_position) if player_ok else Vector3.ZERO
	var dist := Vector2(to_player.x, to_player.z).length()
	if player_ok and dist < SIGHT_RANGE and _can_see_player():
		_since_seen = 0.0
	else:
		_since_seen += delta
	_think(player_ok, dist)

	var move := _steer(delta, to_player, dist) + _separation() * RUN_SPEED * 0.5
	velocity.x = move_toward(velocity.x, move.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, move.z, ACCEL * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()

	# Face the player while fighting; otherwise face the way it walks.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var facing := rotation.y
	if (state == State.ATTACK or state == State.CHASE) and _since_seen < LOSE_TIME:
		facing = atan2(-to_player.x, -to_player.z)
	elif hspeed > 0.5:
		facing = atan2(-velocity.x, -velocity.z)
	rotation.y = lerp_angle(rotation.y, facing, TURN_SPEED * delta)
	_model.update_motion(is_on_floor(), hspeed, false)
	_shoot_logic(delta, player_ok)


## Called by energy balls on impact. Getting shot alerts it.
func take_hit(damage: float, _point: Vector3) -> void:
	if not _alive:
		return
	health = maxf(health - damage, 0.0)
	_model.hit_flash()
	if health <= 0.0:
		_die()
	elif state == State.PATROL or state == State.RETURN:
		state = State.CHASE
		_since_seen = 0.0


## True while the robot is standing (the weapon's aim assist ignores downed ones).
func is_targetable() -> bool:
	return _alive


## Where the weapon's aim assist points: the chest core (2.45 m up on the Vela model).
func aim_point() -> Vector3:
	return global_position + Vector3(0.0, 2.45, 0.0)


## State changes.
func _think(player_ok: bool, dist: float) -> void:
	var far_from_home := global_position.distance_to(_home) > LEASH
	match state:
		State.PATROL:
			if _since_seen == 0.0:
				state = State.CHASE
		State.CHASE:
			if not player_ok or _since_seen > LOSE_TIME or far_from_home:
				state = State.RETURN
			elif dist < ATTACK_RANGE and _since_seen == 0.0:
				state = State.ATTACK
		State.ATTACK:
			if not player_ok or _since_seen > LOSE_TIME or far_from_home:
				state = State.RETURN
			elif dist > ATTACK_RANGE * 1.25 or _since_seen > 1.0:
				state = State.CHASE
		State.RETURN:
			if global_position.distance_to(_home) < 3.0:
				state = State.PATROL
				_wait = randf_range(1.0, 2.5)
			elif _since_seen == 0.0 and not far_from_home:
				state = State.CHASE


## Desired horizontal velocity for the current state.
func _steer(delta: float, to_player: Vector3, dist: float) -> Vector3:
	match state:
		State.PATROL:
			if _wait > 0.0:
				_wait -= delta
				return Vector3.ZERO
			var to := _flat(_wander_to - global_position)
			_stuck = _stuck + delta if Vector2(velocity.x, velocity.z).length() < 0.5 else 0.0
			if to.length() < 1.5 or _stuck > 2.0:  # arrived (or blocked): pause, then pick a new spot
				_pick_wander_point()
				_wait = randf_range(1.0, 3.0)
				_stuck = 0.0
				return Vector3.ZERO
			return to.normalized() * WALK_SPEED
		State.CHASE:
			return _flat(to_player).normalized() * RUN_SPEED
		State.ATTACK:
			_strafe_time -= delta
			if _strafe_time <= 0.0:  # switch circling direction now and then
				_strafe_dir = -_strafe_dir if randf() < 0.6 else _strafe_dir
				_strafe_time = randf_range(1.5, 3.0)
			var radial := _flat(to_player).normalized()
			var side := radial.cross(Vector3.UP) * _strafe_dir
			var close := 0.0
			if dist < KEEP_AWAY:
				close = -1.0               # back off
			elif dist > ATTACK_RANGE * 0.8:
				close = 0.6                # close in a little
			return (side + radial * close).normalized() * STRAFE_SPEED
		State.RETURN:
			return _flat(_home - global_position).normalized() * RUN_SPEED
	return Vector3.ZERO


## Raises the cannon and fires while attacking; lowers it otherwise.
func _shoot_logic(delta: float, player_ok: bool) -> void:
	var attacking := state == State.ATTACK and player_ok and _since_seen < 0.5
	var target := _player_chest() if player_ok else global_position - global_basis.z * 10.0
	if attacking:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire(target)
			_fire_timer = randf_range(FIRE_PAUSE.x, FIRE_PAUSE.y)
	else:
		_fire_timer = maxf(_fire_timer, AIM_TIME)  # always aim for a moment before the first shot
	_model.aim_arm(target, attacking and _fire_timer < AIM_TIME + 0.3, delta)


func _fire(target: Vector3) -> void:
	var muzzle := _model.muzzle_transform().origin
	var flight := muzzle.distance_to(target) / EnergyBall.SPEED
	var vel: Vector3 = player.get("velocity") if player is CharacterBody3D else Vector3.ZERO
	var miss := Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * SPREAD
	var ball := EnergyBall.new()
	ball.damage = SHOT_DAMAGE
	ball.glow_color = SHOT_COLOR
	ball.rim_color = SHOT_RIM
	get_parent().add_child(ball)
	ball.launch(muzzle, target + vel * flight * LEAD + miss, self)
	_model.fire_recoil()


func _can_see_player() -> bool:
	var eye := global_position + Vector3(0.0, 2.6, 0.0)
	var query := PhysicsRayQueryParameters3D.create(eye, _player_chest())
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == player


func _player_chest() -> Vector3:
	return player.global_position + Vector3(0.0, 2.4, 0.0)


## Push away from enemies that are too close, so they don't bunch up.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self:
			continue
		var away := _flat(global_position - (other as Node3D).global_position)
		var d := away.length()
		if d > 0.01 and d < SEPARATION:
			push += away / d * (1.0 - d / SEPARATION)
	return push


func _pick_wander_point() -> void:
	var a := randf() * TAU
	var r := randf_range(4.0, PATROL_RADIUS)
	_wander_to = _home + Vector3(cos(a) * r, 0.0, sin(a) * r)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _build_body() -> void:
	_model = VelaModel.new()
	_model.model_scene = VelaModel.VELA_07
	add_child(_model)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 3.0, 1.0)  # the mech standing with its arms down
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 1.5, 0)
	add_child(cs)


func _die() -> void:
	_alive = false
	velocity = Vector3.ZERO
	collision_layer = 0  # shots pass through a downed robot
	_model.explode()
	get_tree().create_timer(RESPAWN_TIME).timeout.connect(_respawn)


func _respawn() -> void:
	position = _home
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	health = MAX_HEALTH
	_alive = true
	collision_layer = _layer
	state = State.PATROL
	_since_seen = INF
	_wait = randf_range(1.0, 2.5)
	_pick_wander_point()
	_model.reassemble()
