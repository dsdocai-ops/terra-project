extends Node3D
## A ball of energy fired by the arm cannon (weapon.gd). Flies straight at SPEED and bursts on
## whatever it hits, or fizzles out after MAX_DISTANCE. Cel-shaded to match the toon world (see
## toon_fx.gd): a single banded, ink-outlined ball that grows out of the barrel and trails a few
## sparkles, and a cartoon impact (star flash, shock ring, sparkles and puffs of smoke).
## Where it lands it also deals a small splash (SPLASH_RADIUS) to anything nearby.
## Add it to the scene, then call launch().

const ToonFx := preload("res://scripts/toon_fx.gd")
const SPEED := 45.0
const DAMAGE := 25.0          # damage dealt to anything with take_hit()
const MAX_DISTANCE := 500.0
const SPLASH_RADIUS := 3.0         # small blast where the ball lands
const SPLASH_DAMAGE := 0.6         # fraction of `damage` dealt at the centre, fading toward the edge
const SPLASH_REACH := 1.0          # allowance for a body being wider than its centre point
const RADIUS := 0.3
const CORE_COLOR := Color(1.0, 0.95, 1.0)
const GLOW_COLOR := Color(0.7, 0.35, 1.0)
const TRAIL_COLOR := Color(0.35, 0.45, 1.0)
const SMOKE_COLOR := Color(0.92, 0.88, 1.0)

## Per-shot settings; set them before adding the ball to the scene (defaults: the player's shot).
var damage := DAMAGE
var glow_color := GLOW_COLOR
var rim_color := Color(0.4, 0.25, 1.0)
var core_color := CORE_COLOR              # white-hot centre of the sparkles
var spark_color := Color(0.85, 0.6, 1.0)  # mid colour of the sparkles
var trail_color := TRAIL_COLOR            # where the sparks cool to
var smoke_color := SMOKE_COLOR
var ink_color := ToonFx.VIOLET_INK        # outline of the impact flash and shock ring

var _velocity := Vector3.ZERO
var _travelled := 0.0
var _exclude: Array[RID] = []
var _shooter: Node
var _done := false
var _ball: Node3D
var _trails: Array[CPUParticles3D] = []
var _light: OmniLight3D


func _ready() -> void:
	_ball = ToonFx.sphere(RADIUS, ToonFx.energy_material(glow_color, rim_color, 1.6, 0.05))
	add_child(_ball)
	# Grows out of the barrel, so the shot reads as one ball from the cannon to the target.
	_ball.scale = Vector3.ONE * 0.2
	var grow := create_tween()
	grow.tween_property(_ball, "scale", Vector3.ONE * 1.15, 0.06).set_ease(Tween.EASE_OUT)
	grow.tween_property(_ball, "scale", Vector3.ONE, 0.05)
	var sparkles := ToonFx.emitter(10, 0.35, RADIUS * 0.8,
		ToonFx.sprite_material(ToonFx.Shape.SPARKLE, {"ink_width": 0.0, "energy": 2.2}),
		[[0.0, core_color], [0.5, spark_color]],
		[Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
	sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparkles.emission_sphere_radius = RADIUS
	sparkles.spread = 180.0
	sparkles.initial_velocity_min = 1.0
	sparkles.initial_velocity_max = 3.0
	add_child(sparkles)
	sparkles.emitting = true
	_trails.append(sparkles)
	_light = OmniLight3D.new()
	_light.light_color = glow_color
	_light.light_energy = 3.0
	_light.omni_range = 7.0
	add_child(_light)


## Starts the shot at `from` heading toward `toward`; `shooter` is never hit.
func launch(from: Vector3, toward: Vector3, shooter: CollisionObject3D) -> void:
	global_position = from
	var dir := toward - from
	_velocity = (dir.normalized() if dir.length() > 0.01 else -shooter.global_basis.z) * SPEED
	_exclude = [shooter.get_rid()]
	_shooter = shooter


func _physics_process(delta: float) -> void:
	if _done:
		return
	var step := _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	query.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit["position"]
		var target: Object = hit["collider"]
		if target.has_method("take_hit") and not _same_side(target):
			target.call("take_hit", damage, global_position)
		_splash(target)
		_burst()
		return
	global_position += step
	_travelled += step.length()
	if _travelled > MAX_DISTANCE:
		_burst()


## Swaps the ball for a cartoon impact: a star flash, an expanding shock ring, a spray of
## sparkles and a few puffs of smoke, then frees itself.
func _burst() -> void:
	_done = true
	_ball.hide()
	for trail in _trails:
		trail.emitting = false
	var flash := ToonFx.burst(1, 0.16, RADIUS * 9.0,
		ToonFx.sprite_material(ToonFx.Shape.SPARKLE, {
			"ink_color": ink_color, "ink_width": 0.1, "core_size": 0.6, "energy": 2.0}),
		[[0.0, glow_color]], [Vector2(0.0, 0.5), Vector2(0.3, 1.0), Vector2(1.0, 0.0)])
	flash.spread = 0.0
	var ring := ToonFx.burst(1, 0.35, SPLASH_RADIUS * 2.0,  # the shock ring spans the blast
		ToonFx.sprite_material(ToonFx.Shape.RING, {"ink_color": ink_color, "ink_width": 0.04, "energy": 1.6}),
		[[0.0, Color(glow_color, 0.6)], [1.0, Color(rim_color, 0.05)]],
		[Vector2(0.0, 0.15), Vector2(1.0, 1.0)], false)
	ring.spread = 0.0
	ring.angle_min = 0.0
	ring.angle_max = 0.0
	var sparks := ToonFx.burst(18, 0.45, RADIUS * 1.1,
		ToonFx.sprite_material(ToonFx.Shape.SPARKLE, {"ink_width": 0.0, "energy": 2.2}),
		[[0.0, core_color], [0.35, spark_color], [0.7, trail_color]],
		[Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
	sparks.initial_velocity_min = 5.0
	sparks.initial_velocity_max = 13.0
	sparks.damping_min = 8.0
	sparks.damping_max = 12.0
	var smoke := ToonFx.burst(7, 0.7, RADIUS * 2.2,
		ToonFx.sprite_material(ToonFx.Shape.BLOB, {
			"ink_color": ToonFx.SMOKE_INK, "ink_width": 0.1, "puff": true, "wobble": 0.12}),
		[[0.0, smoke_color], [0.55, smoke_color.darkened(0.08)]],
		[Vector2(0.0, 0.0), Vector2(0.35, 1.0), Vector2(1.0, 0.0)])  # grows in after the flash
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = RADIUS
	smoke.initial_velocity_min = 3.0
	smoke.initial_velocity_max = 5.0
	smoke.damping_min = 3.0
	smoke.damping_max = 4.0
	smoke.gravity = Vector3(0, 1.5, 0)
	for p in [smoke, sparks, ring, flash]:
		add_child(p)
		p.emitting = true
	var tween := create_tween()
	tween.tween_property(_light, "light_energy", 10.0, 0.05)
	tween.tween_property(_light, "light_energy", 0.0, 0.35)
	get_tree().create_timer(0.8).timeout.connect(queue_free)


## Splash: anything with take_hit() within SPLASH_RADIUS of the impact takes a fraction of the
## damage, fading with distance. What the ball hit directly already took the full damage; the
## shooter and its own side are skipped.
func _splash(direct_hit: Object) -> void:
	var shape := SphereShape3D.new()
	shape.radius = SPLASH_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.exclude = _exclude
	var seen := {}
	for result in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var body: Object = result["collider"]
		if body == direct_hit or seen.has(body) or not body.has_method("take_hit") or _same_side(body):
			continue
		seen[body] = true
		var centre: Vector3 = (body as Node3D).global_position + Vector3(0.0, 1.4, 0.0)
		var falloff := clampf(1.0 - global_position.distance_to(centre) / (SPLASH_RADIUS + SPLASH_REACH), 0.25, 1.0)
		body.call("take_hit", damage * SPLASH_DAMAGE * falloff, global_position)


## True when the shooter and what was hit are on the same side (enemies don't hurt each other).
func _same_side(target: Object) -> bool:
	return _shooter != null and target is Node and _shooter.is_in_group("enemies") \
			and (target as Node).is_in_group("enemies")
