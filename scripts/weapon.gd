extends Node
## Arm cannon on the mech's right arm. Hold left mouse to blast balls of energy
## (energy_ball.gd) toward wherever the crosshair (screen centre) points. While aiming
## (right mouse, handled in player.gd) or shooting, the arm swings up to point the cannon at
## the target, and each shot kicks it back with muzzle sparkles (vela_model.gd).

const EnergyBall := preload("res://scripts/energy_ball.gd")
const FIRE_INTERVAL := 0.3    # seconds between shots
const RANGE := 500.0
const AIM_HOLD := 0.8         # keep the arm raised this long after the last shot
const ASSIST_RADIUS := 0.035  # aim-assist circle radius, as a fraction of the screen height
const ASSIST_RANGE := 150.0   # enemies further than this are never assisted
const TRIANGLE_RADIUS := 13.0      # reticle size in pixels (centre to corner)
const TRIANGLE_RADIUS_ADS := 9.0   # tighter while aiming down sights
const TRIANGLE_GAP := 0.28         # fraction of each edge left empty at both ends
const RING_SEGMENTS := 96         # points around the circle; more = smoother
# Smoothing: everything on the reticle eases instead of snapping (rates are per second).
# The player's shots are blue to match the Vela-08 (enemy shots are red-orange, see enemy.gd).
const SHOT_GLOW := Color(0.25, 0.6, 1.0)
const SHOT_RIM := Color(0.05, 0.2, 0.85)
const SHOT_CORE := Color(0.9, 0.97, 1.0)
const SHOT_SPARK := Color(0.5, 0.8, 1.0)
const SHOT_TRAIL := Color(0.1, 0.35, 1.0)
const SHOT_SMOKE := Color(0.88, 0.93, 1.0)
const SHOT_INK := Color(0.03, 0.12, 0.4)
const KICK_PIXELS := 6.0          # how far the triangle opens out on each shot
const KICK_RECOVERY := 10.0        # how fast it settles back (exponential)
const LOCK_SPEED := 10.0           # how fast the assist circle tints / the lock ring closes in
const FADE_SPEED := 6.0            # reticle fade in / out (e.g. while blown up)
const ARM_FOLLOW := 18.0           # how fast the cannon arm follows the aim point (no twitch
                                   # when the crosshair crosses from near to far objects)

var _player: CharacterBody3D
var _camera: Camera3D
var _model: Node3D
var _cooldown := 0.0
var _since_shot := INF
var _crosshair: Control
var _assist_target: Node3D            # the enemy inside the assist circle, if any
var _assist_screen := Vector2.ZERO    # where its aim point is on screen
var _kick := 0.0                      # 1 right after a shot, easing back to 0
var _lock := 0.0                      # eased 0..1: how locked-on the reticle looks
var _lock_screen := Vector2.ZERO      # smoothed position of the lock ring
var _alpha := 1.0                     # reticle opacity
var _arm_target := Vector3.ZERO       # smoothed point the cannon arm aims at


## Called once by player.gd after it has added this node.
func setup(player: CharacterBody3D, camera: Camera3D, model: Node3D) -> void:
	_player = player
	_camera = camera
	_model = model
	_build_crosshair()


func _process(delta: float) -> void:
	var dead: bool = _player.get("dead")
	_alpha = move_toward(_alpha, 0.0 if dead else 1.0, FADE_SPEED * delta)
	_kick *= exp(-KICK_RECOVERY * delta)  # eases back: fast at first, gentle at the end
	_crosshair.queue_redraw()
	if dead:  # no shooting while the mech is blown up
		_lock = 0.0
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_since_shot += delta
	# Aim assist: an enemy inside the circle around the crosshair pulls the shot onto itself.
	_assist_target = _find_assist_target()
	var target := _aim_point()
	if _assist_target != null:
		var assisted: Vector3 = _assist_target.call("aim_point")
		_assist_screen = _camera.unproject_position(assisted)
		target = assisted
	var firing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if firing and _cooldown <= 0.0:
		_cooldown = FIRE_INTERVAL
		_since_shot = 0.0
		_shoot(target)
	# The lock-on tint and ring ease in and out; the ring glides after the target on screen.
	_lock = move_toward(_lock, 1.0 if _assist_target != null else 0.0, LOCK_SPEED * delta)
	if _assist_target != null:
		var from := _crosshair.size * 0.5 if _lock < 0.05 else _lock_screen
		_lock_screen = from.lerp(_assist_screen, 1.0 - exp(-25.0 * delta))
	# The arm follows a smoothed aim point; shots still go straight to the real (or assisted) target.
	var arm_active: bool = _player.aiming or _since_shot < AIM_HOLD
	if _arm_target == Vector3.ZERO or _model.get("_aim_blend") == 0.0:
		_arm_target = target
	_arm_target = _arm_target.lerp(target, 1.0 - exp(-ARM_FOLLOW * delta))
	_model.call("aim_arm", _arm_target, arm_active, delta)


## Where the crosshair points: the first thing the camera ray hits, or far ahead.
func _aim_point() -> Vector3:
	var from := _camera.global_position
	var to := from - _camera.global_basis.z * RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return to if hit.is_empty() else hit["position"]


## The enemy whose aim point is closest to the crosshair and inside the assist circle, in range
## and in clear line of sight. null if there is none.
func _find_assist_target() -> Node3D:
	var centre := _crosshair.size * 0.5
	var best: Node3D = null
	var best_dist := ASSIST_RADIUS * _crosshair.size.y
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.call("is_targetable"):
			continue
		var p: Vector3 = enemy.call("aim_point")
		if _camera.is_position_behind(p) or _camera.global_position.distance_to(p) > ASSIST_RANGE:
			continue
		var d := _camera.unproject_position(p).distance_to(centre)
		if d < best_dist and _has_line_of_sight(p, enemy):
			best = enemy
			best_dist = d
	return best


func _has_line_of_sight(p: Vector3, enemy: Object) -> bool:
	var query := PhysicsRayQueryParameters3D.create(_camera.global_position, p)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == enemy


func _shoot(target: Vector3) -> void:
	var muzzle: Transform3D = _model.call("muzzle_transform")
	var ball := EnergyBall.new()
	ball.glow_color = SHOT_GLOW
	ball.rim_color = SHOT_RIM
	ball.core_color = SHOT_CORE
	ball.spark_color = SHOT_SPARK
	ball.trail_color = SHOT_TRAIL
	ball.smoke_color = SHOT_SMOKE
	ball.ink_color = SHOT_INK
	_player.get_parent().add_child(ball)
	ball.launch(muzzle.origin, target, _player)
	_model.call("fire_recoil")
	_kick = 1.0


func _build_crosshair() -> void:
	var layer := CanvasLayer.new()
	_player.add_child(layer)
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_crosshair)
	_crosshair.draw.connect(_draw_crosshair)


## Three short lines forming a triangle with gaps at the corners (it tightens while aiming down
## sights), inside a smooth full aim-assist circle. The circle turns red and a small ring marks
## the enemy's aim point when one is caught. Everything is antialiased so edges are not jagged,
## and eases rather than snaps: the triangle tightens with the aim-down-sights blend and opens
## briefly on each shot, the circle fades to red and the lock ring closes in on the target and
## follows it smoothly, and the whole reticle fades out while the mech is blown up.
func _draw_crosshair() -> void:
	if _alpha <= 0.0:
		return
	var centre := _crosshair.size * 0.5
	var ads: float = _player.get("ads")
	var reticle := Color(1.0, 1.0, 1.0, 0.95 * _alpha)
	var radius := lerpf(TRIANGLE_RADIUS, TRIANGLE_RADIUS_ADS, ads) + KICK_PIXELS * _kick
	for i in 3:
		var a := centre + _triangle_corner(i, radius)
		var b := centre + _triangle_corner(i + 1, radius)
		var from := a.lerp(b, TRIANGLE_GAP)
		var to := a.lerp(b, 1.0 - TRIANGLE_GAP)
		_crosshair.draw_line(from, to, Color(0.0, 0.0, 0.0, 0.35 * _alpha), 4.0, true)  # soft shadow for contrast
		_crosshair.draw_line(from, to, reticle, 2.0, true)
	var assist_radius := ASSIST_RADIUS * _crosshair.size.y
	var lock := Color(1.0, 0.35, 0.3, 0.95)
	var ring := Color(1.0, 1.0, 1.0, 0.3).lerp(Color(lock, 0.55), _lock)
	_draw_ring(centre, assist_radius, Color(ring, ring.a * _alpha), 1.5)
	if _lock > 0.0:
		_draw_ring(_lock_screen, lerpf(30.0, 14.0, _lock), Color(lock, lock.a * _lock * _alpha), 2.0)


## Corner i of an upward-pointing triangle around the origin.
func _triangle_corner(i: int, radius: float) -> Vector2:
	var angle := deg_to_rad(-90.0 + 120.0 * i)
	return Vector2(cos(angle), sin(angle)) * radius


## A smooth antialiased full circle.
func _draw_ring(centre: Vector2, radius: float, color: Color, width: float) -> void:
	_crosshair.draw_arc(centre, radius, 0.0, TAU, RING_SEGMENTS, color, width, true)
