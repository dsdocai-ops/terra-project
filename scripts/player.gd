extends CharacterBody3D
## Third-person flying mech.
## WASD / arrows: move. Mouse: orbit camera. Esc frees the mouse, click recaptures it.
## Left mouse: fire. Right mouse: aim down sights (zoom in, steadier look).
## Space: jump, and hold to fire the thrusters (they spool up, then you climb with momentum).
## Shift: run on the ground (no effect in the air). Ctrl (or C): descend.
## F: lock-in cruise (in the air). Holds altitude and builds up to a high horizontal speed;
## steer with WASD. Press F again, or land, to exit.
## H: hover mode. Lifts off (or catches you mid-air) and holds altitude; WASD moves you around,
## Space climbs, Ctrl (or C) sinks. Press H again, or touch down, to exit.
## Health: take_hit(damage, point) hurts the mech; at zero it blows up (vela_model.gd explode())
## and respawns at the start point after RESPAWN_TIME. K: self-destruct (to test the death).

const WALK_SPEED := 14.0
const RUN_SPEED := 30.0        # hold Shift on the ground
const RUN_ACCEL := 60.0        # how quickly you reach walking/running speed on the ground
const RUN_LEAN := deg_to_rad(12.0)
const JUMP_VELOCITY := 11.0     # launch speed of a ground jump (about 6 m high), applied on press
const JUMP_THRUST_DELAY := 0.2  # seconds into a jump before holding Space fires the thrusters
const THRUST := 10.0          # upward acceleration at full thruster power (on top of cancelling gravity)
const THRUST_SPOOL := 1.0     # how fast thrusters reach full power (per second)
const MAX_RISE_SPEED := 8.0
const MAX_FALL_SPEED := 30.0
const FLY_SPEED := 12.0       # top horizontal speed under thrust
const H_THRUST := 6.0         # horizontal push from the thrusters toward the direction you steer
const AIR_CONTROL := 8.0      # weak steering in the air with thrusters off
const AIR_DRAG := 3.0         # slow bleed of horizontal speed in the air
const TURN_BOOST := 1.8       # extra thrust multiplier when you steer against your current motion
const DIVE_ACCEL := 40.0          # how quickly descent speed is reached
const DESCEND_SPEED := 15.0       # steady downward speed while descending
const CRUISE_SPEED := 70.0       # horizontal speed reached in lock-in (cruise) mode
const CRUISE_RAMP := 12.0         # how fast cruise speed builds up (m/s per second)
const CRUISE_TURN := 1.5          # how quickly the cruise heading follows your steering
const CRUISE_LEAN := deg_to_rad(70.0)
const HOVER_SPEED := 16.0         # horizontal speed while moving in hover mode
const HOVER_ACCEL := 35.0         # how quickly hover movement speeds up and brakes
const HOVER_CLIMB := 6.0          # vertical speed with Space / Ctrl in hover mode
const HOVER_V_ACCEL := 20.0       # how quickly vertical speed settles in hover mode
const HOVER_THRUST := 0.6         # thruster level while holding still in hover mode
const MAX_LEAN := deg_to_rad(40.0)
const MAX_ROLL := deg_to_rad(30.0)  # bank angle while turning
const BASE_FOV := 75.0
const MAX_FOV := 90.0
const MOUSE_SENSITIVITY := 0.003
const TURN_SPEED := 10.0
const ADS_FOV := 55.0
const ADS_SENSITIVITY := 0.45   # look sensitivity multiplier while aiming
const ADS_ARM := 3.5             # camera distance while aiming
const HIP_ARM := 5.0             # camera distance normally
const ADS_TIME := 0.18           # seconds to ease fully into / out of aiming down sights
const MAX_HEALTH := 100.0
const HEALTH_GREEN := Color(0.22, 0.85, 0.38)         # health cell fill and its lit top band
const HEALTH_GREEN_LIGHT := Color(0.62, 1.0, 0.58)
const HUD_INK := Color(0.08, 0.07, 0.1)               # the game's ink colour
const HUD_NAVY := Color(0.008, 0.025, 0.09, 0.92)     # dark armour blue, behind the cells
const HUD_CELL_EMPTY := Color(0.03, 0.07, 0.15)
const HUD_GLOW := Color(0.1, 0.6, 1.0)                # cyan glow strip, as on the mech
const HEALTH_CELLS := 10
const RESPAWN_TIME := 3.5        # seconds from blowing up to respawning
const SHAKE_TIME := 0.6          # camera shake when the mech explodes
const SHAKE_STRENGTH := 0.35

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var thrust_level := 0.0
var cruise := false
var cruise_heading := Vector3.FORWARD
var cruise_speed := 0.0
var hover_mode := false
var _space_was_down := false
var _jump_pressed := false
var _air_time := 0.0
var aiming := false
var ads := 0.0  # eased 0 (hip) .. 1 (aiming down sights): camera, zoom, look speed and crosshair follow it
var _ads_raw := 0.0
var _speed_fov := BASE_FOV
var shoulder_offset := 1.0  # how far right of the body the camera sits (over-the-shoulder)
var weapon: Node
var health := MAX_HEALTH
var dead := false
var _spawn: Vector3
var _layer: int
var _shake := 0.0
var _death_label: Label
var _hud: Control
var _shown_health := MAX_HEALTH  # health bar trail that drains smoothly after a hit
var _hurt := 0.0                  # red screen-edge flash when hit (1 -> 0)

@onready var pivot: Node3D = $CameraPivot
@onready var model: Node3D = $Model  # vela_model.gd
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var arm: SpringArm3D = $CameraPivot/SpringArm3D


func _ready() -> void:
	$CameraPivot/SpringArm3D.add_excluded_object(get_rid())
	weapon = preload("res://scripts/weapon.gd").new()
	add_child(weapon)
	weapon.setup(self, camera, model)
	shoulder_offset = clampf(_body_radius() + 0.4, 1.0, 3.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_spawn = global_position
	_layer = collision_layer
	model.connect("exploded", func(): _shake = SHAKE_TIME)
	_build_death_label()


func _process(delta: float) -> void:
	_shake = maxf(_shake - delta, 0.0)
	var k := SHAKE_STRENGTH * _shake / SHAKE_TIME
	camera.h_offset = randf_range(-k, k)
	camera.v_offset = randf_range(-k, k)
	_shown_health = move_toward(_shown_health, health, maxf(absf(_shown_health - health) * 3.0, 20.0) * delta)
	_hurt = maxf(_hurt - delta * 3.0, 0.0)
	_hud.queue_redraw()


## Damages the mech (e.g. from an enemy shot); it blows up at zero health.
func take_hit(damage: float, _point: Vector3) -> void:
	if dead:
		return
	health = maxf(health - damage, 0.0)
	model.call("hit_flash")
	_hurt = 1.0
	if health <= 0.0:
		die()


## Blows the mech up, then respawns it at the start point after RESPAWN_TIME.
func die() -> void:
	if dead:
		return
	dead = true
	health = 0.0
	cruise = false
	hover_mode = false
	thrust_level = 0.0
	aiming = false
	collision_layer = 0  # shots and debris pass through the wreck
	model.call("explode")
	_death_label.show()
	get_tree().create_timer(RESPAWN_TIME).timeout.connect(_respawn)


func _respawn() -> void:
	global_position = _spawn
	velocity = Vector3.ZERO
	model.rotation = Vector3(0.0, model.rotation.y, 0.0)
	health = MAX_HEALTH
	dead = false
	collision_layer = _layer
	model.call("reassemble")
	_death_label.hide()


func _build_death_label() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_death_label = Label.new()
	_death_label.text = "DESTROYED"
	_death_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_death_label.position.y -= 80.0
	_death_label.add_theme_font_size_override("font_size", 56)
	_death_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2))
	_death_label.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.1))
	_death_label.add_theme_constant_override("outline_size", 14)
	_death_label.hide()
	layer.add_child(_death_label)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	_hud.draw.connect(_draw_hud)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		pivot.rotate_y(-event.relative.x * _sens())
		pivot.rotation.x = clampf(pivot.rotation.x - event.relative.y * _sens(), deg_to_rad(-80.0), deg_to_rad(40.0))
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F and not event.echo:
		_toggle_cruise()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_H and not event.echo:
		_toggle_hover()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_K and not event.echo:
		die()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if dead:  # the wreck just drops and slides to a stop; no control until respawn
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		velocity.y = maxf(velocity.y - gravity * delta, -MAX_FALL_SPEED)
		move_and_slide()
		return
	var on_floor := is_on_floor()
	var space := Input.is_physical_key_pressed(KEY_SPACE)
	_jump_pressed = space and not _space_was_down
	_space_was_down = space
	_air_time = 0.0 if on_floor else _air_time + delta
	var hover := Input.is_physical_key_pressed(KEY_SHIFT)
	var dive := Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C)

	if cruise and on_floor:
		cruise = false
	if hover_mode and on_floor and velocity.y <= 0.0:
		hover_mode = false  # touched down
		thrust_level = minf(thrust_level, 0.2)  # cut the hover thrust so it settles straight onto the ground

	# Thrusters spool up while Space is held and wind down when released.
	if not cruise and not hover_mode:
		var thrusting := space and _air_time > JUMP_THRUST_DELAY
		thrust_level = move_toward(thrust_level, 1.0 if thrusting else 0.0, THRUST_SPOOL * delta)

	var input := Vector2(
		_axis(KEY_D, KEY_RIGHT) - _axis(KEY_A, KEY_LEFT),
		_axis(KEY_S, KEY_DOWN) - _axis(KEY_W, KEY_UP)
	)
	# Move relative to where the camera is facing (yaw only).
	var yaw_basis := Basis(Vector3.UP, pivot.rotation.y)
	var direction := (yaw_basis * Vector3(input.x, 0.0, input.y)).normalized()

	# Over-the-shoulder camera always; aiming pulls in closer and zooms.
	aiming = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_ads_raw = move_toward(_ads_raw, 1.0 if aiming else 0.0, delta / ADS_TIME)
	ads = smoothstep(0.0, 1.0, _ads_raw)
	arm.spring_length = lerpf(HIP_ARM, ADS_ARM, ads)
	# Offset the spring arm itself: SpringArm3D repositions its child camera each frame, so
	# an offset on the camera would be overwritten.
	arm.position.x = lerpf(arm.position.x, shoulder_offset, 10.0 * delta)

	if cruise:
		_cruise_step(direction, delta)
	elif hover_mode:
		_hover_step(direction, space, dive, delta)
	else:
		_fly_step(direction, on_floor, hover, dive, delta)

	# --- Model: face travel direction, lean into the flight ---
	# The mech turns to face the way it is steering (cruise: its heading), then leans
	# into the move, banking toward the turn while it swings round.
	var target_yaw := model.rotation.y
	if cruise:
		target_yaw = atan2(-cruise_heading.x, -cruise_heading.z)
	elif aiming:
		target_yaw = pivot.rotation.y  # body turns to face where the camera looks
	elif direction != Vector3.ZERO:
		target_yaw = atan2(-direction.x, -direction.z)
	var turn := angle_difference(model.rotation.y, target_yaw)
	model.rotation.y = lerp_angle(model.rotation.y, target_yaw, TURN_SPEED * delta)

	var airborne := not on_floor
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var pitch := 0.0
	var roll := 0.0
	if airborne:
		if cruise:
			pitch = -clampf(hspeed / CRUISE_SPEED, 0.0, 1.0) * CRUISE_LEAN
		elif direction != Vector3.ZERO:
			pitch = -clampf(hspeed / FLY_SPEED, 0.0, 1.0) * MAX_LEAN  # negative X tilts the top forward
		roll = clampf(turn * 0.6, -MAX_ROLL, MAX_ROLL)               # bank into the turn
	elif Input.is_physical_key_pressed(KEY_SHIFT) and direction != Vector3.ZERO:
		pitch = -RUN_LEAN  # lean into a run
	model.rotation.x = lerpf(model.rotation.x, pitch, 6.0 * delta)
	model.rotation.z = lerpf(model.rotation.z, roll, 6.0 * delta)
	model.call("update_wings", airborne, thrust_level > 0.1, delta)
	model.call("set_thrust", thrust_level)
	# Hover pose in hover mode, or when barely moving in the air.
	var hovering := airborne and (hover_mode or (hspeed < 2.0 and absf(velocity.y) < 1.5))
	model.call("update_motion", on_floor, hspeed, cruise, hovering)

	# Speed feel: widen the field of view as you accelerate.
	var speed_t := clampf(velocity.length() / CRUISE_SPEED, 0.0, 1.0)
	_speed_fov = lerpf(_speed_fov, lerpf(BASE_FOV, MAX_FOV, speed_t), 4.0 * delta)
	camera.fov = lerpf(_speed_fov, ADS_FOV, ads)  # zoom eases in step with the camera pulling in

	move_and_slide()


func _axis(key: Key, alt_key: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(key) or Input.is_physical_key_pressed(alt_key) else 0.0


func _toggle_hover() -> void:
	if hover_mode:
		hover_mode = false
		return
	hover_mode = true
	cruise = false
	if is_on_floor():
		velocity.y = JUMP_VELOCITY  # lift off into the hover


func _toggle_cruise() -> void:
	if cruise:
		cruise = false
	elif not is_on_floor():
		cruise = true
		hover_mode = false
		var hvel := Vector3(velocity.x, 0.0, velocity.z)
		cruise_speed = hvel.length()
		var yaw_basis := Basis(Vector3.UP, pivot.rotation.y)
		cruise_heading = hvel.normalized() if cruise_speed > 1.0 else -yaw_basis.z


## Normal flight: Space-driven thrust with momentum, steered by WASD.
func _fly_step(direction: Vector3, on_floor: bool, hover: bool, dive: bool, delta: float) -> void:
	# Shift only runs on the ground; in the air it does nothing (hovering is the H mode).
	# --- Vertical ---
	velocity.y -= gravity * delta
	velocity.y += (gravity + THRUST) * thrust_level * delta
	if dive and not on_floor:
		# Controlled descent: ease toward a steady downward speed, overriding thrust.
		velocity.y = move_toward(velocity.y, -DESCEND_SPEED, DIVE_ACCEL * delta)
	velocity.y = clampf(velocity.y, -MAX_FALL_SPEED, MAX_RISE_SPEED)
	# The jump is an impulse applied after the clamp so it is not capped by the thrust rise limit.
	if on_floor and _jump_pressed:
		velocity.y = JUMP_VELOCITY

	# --- Horizontal ---
	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	var thrusting := thrust_level > 0.1
	if on_floor and not thrusting:
		var ground_speed := RUN_SPEED if hover else WALK_SPEED
		hvel = hvel.move_toward(direction * ground_speed, RUN_ACCEL * delta)
	else:
		# Thrusters push you in the direction you steer; with them off you can only nudge.
		var accel := H_THRUST * thrust_level if thrusting else AIR_CONTROL
		accel *= _turn_boost(hvel, direction)
		var cap := FLY_SPEED if thrusting else WALK_SPEED
		var pushed := hvel + direction * accel * delta
		hvel = pushed.limit_length(maxf(cap, hvel.length()))
		if direction == Vector3.ZERO or not thrusting:
			hvel = hvel.move_toward(Vector3.ZERO, AIR_DRAG * delta)
	velocity.x = hvel.x
	velocity.z = hvel.z


## Hover mode: altitude is held and WASD moves you around mid-air. Space climbs, Ctrl/C sinks.
## Thrusters idle at HOVER_THRUST and flare up while you move or climb.
func _hover_step(direction: Vector3, space: bool, dive: bool, delta: float) -> void:
	var busy := space or direction != Vector3.ZERO
	thrust_level = move_toward(thrust_level, 1.0 if busy else HOVER_THRUST, 2.0 * delta)
	var climb := (HOVER_CLIMB if space else 0.0) - (HOVER_CLIMB if dive else 0.0)
	velocity.y = move_toward(velocity.y, climb, HOVER_V_ACCEL * delta)
	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	hvel = hvel.move_toward(direction * HOVER_SPEED, HOVER_ACCEL * delta)
	velocity.x = hvel.x
	velocity.z = hvel.z


## Lock-in cruise: altitude is held and horizontal speed ramps up to CRUISE_SPEED.
func _cruise_step(direction: Vector3, delta: float) -> void:
	thrust_level = move_toward(thrust_level, 1.0, THRUST_SPOOL * delta)
	if direction != Vector3.ZERO:
		cruise_heading = cruise_heading.lerp(direction, CRUISE_TURN * delta).normalized()
	cruise_speed = move_toward(cruise_speed, CRUISE_SPEED, CRUISE_RAMP * delta)
	velocity.y = move_toward(velocity.y, 0.0, 60.0 * delta)
	velocity.x = cruise_heading.x * cruise_speed
	velocity.z = cruise_heading.z * cruise_speed



## 1.0 when steering the way you are already moving, up to TURN_BOOST when steering against
## it, so changing direction is snappy instead of fighting your momentum.
func _turn_boost(hvel: Vector3, direction: Vector3) -> float:
	if direction == Vector3.ZERO or hvel.length() < 0.5:
		return 1.0
	var alignment := hvel.normalized().dot(direction)  # 1 = same way, -1 = opposite
	return lerpf(TURN_BOOST, 1.0, (alignment + 1.0) * 0.5)


## Look sensitivity, easing down while aiming down sights (no sudden change on right-click).
func _sens() -> float:
	return MOUSE_SENSITIVITY * lerpf(1.0, ADS_SENSITIVITY, ads)


## Horizontal radius of the model, so the over-the-shoulder camera can sit just clear of it.
func _body_radius() -> float:
	var radius := 0.5
	var to_model := model.global_transform.affine_inverse()
	for mi in model.find_children("*", "VisualInstance3D", true, false):
		var box: AABB = (to_model * mi.global_transform) * mi.get_aabb()
		for i in 8:
			var corner := box.get_endpoint(i)
			radius = maxf(radius, Vector2(corner.x, corner.z).length())
	return radius


## Health bar (bottom left): a slanted mech-style panel of energy cells with ink outlines and a
## cyan glow strip, in the game's toon look, with a small triangle badge echoing the reticle. A
## pale trail behind the cells drains away smoothly after a hit; the screen edges flash red.
func _draw_hud() -> void:
	var size := _hud.size
	if _hurt > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.15, 0.1, 0.35 * _hurt), false, 36.0)
	var t := clampf(health / MAX_HEALTH, 0.0, 1.0)
	var trail := clampf(_shown_health / MAX_HEALTH, 0.0, 1.0)
	var filled := minf(t, trail)

	var width := 300.0
	var height := 20.0
	var slant := 12.0
	var gap := 4.0
	var origin := Vector2(64.0, size.y - 56.0)

	# Triangle badge, drawn like the reticle: three short lines with gaps at the corners.
	var badge := Vector2(origin.x - 30.0, origin.y + height * 0.5)
	for i in 3:
		var a := badge + _hud_corner(i, 10.0)
		var b := badge + _hud_corner(i + 1, 10.0)
		_hud.draw_line(a.lerp(b, 0.25), a.lerp(b, 0.75), Color(HUD_INK, 0.5), 5.0, true)
		_hud.draw_line(a.lerp(b, 0.25), a.lerp(b, 0.75), Color.WHITE, 2.5, true)

	# Panel: dark armour blue, thick ink outline, thin cyan glow line just inside it.
	var pad := 5.0
	var panel := _hud_slant(origin.x - pad, origin.y - pad, width + pad * 2.0, height + pad * 2.0, slant, 0.0, 1.0)
	_hud.draw_colored_polygon(panel, HUD_NAVY)
	_hud.draw_polyline(_hud_closed(_hud_slant(origin.x - 2.0, origin.y - 2.0, width + 4.0, height + 4.0, slant, 0.0, 1.0)),
			Color(HUD_GLOW, 0.75), 1.5, true)
	_hud.draw_polyline(_hud_closed(panel), HUD_INK, 4.0, true)

	# Energy cells: empty slot, pale damage trail, green fill with a lit top band, ink outline.
	var cell_w := (width - gap * (HEALTH_CELLS - 1)) / HEALTH_CELLS
	for i in HEALTH_CELLS:
		var x := origin.x + i * (cell_w + gap)
		var from := float(i) / HEALTH_CELLS
		var fill_f := clampf((filled - from) * HEALTH_CELLS, 0.0, 1.0)
		var trail_f := clampf((trail - from) * HEALTH_CELLS, 0.0, 1.0)
		_hud.draw_colored_polygon(_hud_slant(x, origin.y, cell_w, height, slant, 0.0, 1.0), HUD_CELL_EMPTY)
		if trail_f > fill_f and trail_f > 0.05:
			_hud.draw_colored_polygon(_hud_slant(x, origin.y, cell_w * trail_f, height, slant, 0.0, 1.0), Color(1.0, 0.9, 0.75))
		if fill_f > 0.05:
			_hud.draw_colored_polygon(_hud_slant(x, origin.y, cell_w * fill_f, height, slant, 0.0, 1.0), HEALTH_GREEN)
			_hud.draw_colored_polygon(_hud_slant(x, origin.y, cell_w * fill_f, height, slant, 0.0, 0.38), HEALTH_GREEN_LIGHT)
		_hud.draw_polyline(_hud_closed(_hud_slant(x, origin.y, cell_w, height, slant, 0.0, 1.0)), HUD_INK, 2.0, true)


## A slanted (parallelogram) slice of a box: the top edge leans `slant` px right of the bottom.
## y0f / y1f pick the slice, as fractions of the height from the top.
func _hud_slant(x: float, y: float, w: float, h: float, slant: float, y0f: float, y1f: float) -> PackedVector2Array:
	var top := slant * (1.0 - y0f)
	var bottom := slant * (1.0 - y1f)
	return PackedVector2Array([
		Vector2(x + top, y + h * y0f), Vector2(x + w + top, y + h * y0f),
		Vector2(x + w + bottom, y + h * y1f), Vector2(x + bottom, y + h * y1f)])


func _hud_closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	closed.append(points[0])
	return closed


## Corner i of an upward-pointing triangle around the origin (same shape as the reticle).
func _hud_corner(i: int, radius: float) -> Vector2:
	var angle := deg_to_rad(-90.0 + 120.0 * i)
	return Vector2(cos(angle), sin(angle)) * radius
