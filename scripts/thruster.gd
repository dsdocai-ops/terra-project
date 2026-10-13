extends Node3D
## One mech thruster firing along local -Y, cel-shaded to match the toon world: a hard-banded
## jet cone (white core, violet body, blue tongues), cartoon flame blobs with a violet ink rim,
## four-point sparkles and puffy two-tone smoke clouds. Particles shrink away instead of fading
## (see toon_fx.gd). Call set_power(0..1) every frame; it flickers by itself.

const JET_SHADER := preload("res://shaders/thruster_flame.gdshader")
const ToonFx := preload("res://scripts/toon_fx.gd")

# Flame colour steps over each puff's life (hot at the nozzle, cooling to blue), and smoke.
const FLAME_HOT := Color(1.0, 0.88, 1.0)
const FLAME := Color(0.88, 0.5, 1.0)
const FLAME_DEEP := Color(0.6, 0.28, 1.0)
const FLAME_TIP := Color(0.3, 0.36, 1.0)
const SMOKE := Color(0.97, 0.95, 1.0)
const SMOKE_DARK := Color(0.86, 0.84, 0.95)

# The blue set, for the player's Vela-08 (the purple set above is Vela-07's): deep blues, down to the
# model's dark armour blue, rather than bright cyan.
const BLUE_FLAME_HOT := Color(0.3, 0.5, 0.95)
const BLUE_FLAME := Color(0.1, 0.25, 0.8)
const BLUE_FLAME_DEEP := Color(0.04, 0.12, 0.55)
const BLUE_FLAME_TIP := Color(0.02, 0.05, 0.3)
const BLUE_SPARK_MID := Color(0.25, 0.42, 0.9)
const BLUE_SPARK_END := Color(0.06, 0.14, 0.55)
const BLUE_INK := Color(0.01, 0.02, 0.12)

var jet_length := 0.9   # jet cone length at full power, in metres
var jet_radius := 0.13
var blue := false       # blue flames instead of purple; set before adding to the scene

var _jet: Node3D
var _jet_mat: ShaderMaterial
var _flames: CPUParticles3D
var _sparks: CPUParticles3D
var _smoke: CPUParticles3D


func _ready() -> void:
	_build_jet()
	var ink := BLUE_INK if blue else ToonFx.VIOLET_INK
	var flame_steps := [[0.0, BLUE_FLAME_HOT], [0.18, BLUE_FLAME], [0.45, BLUE_FLAME_DEEP], [0.72, BLUE_FLAME_TIP]] \
			if blue else [[0.0, FLAME_HOT], [0.18, FLAME], [0.45, FLAME_DEEP], [0.72, FLAME_TIP]]
	var spark_steps := [[0.0, Color(1.0, 1.0, 1.0)], [0.45, BLUE_SPARK_MID], [0.8, BLUE_SPARK_END]] \
			if blue else [[0.0, Color(1.0, 1.0, 1.0)], [0.45, Color(0.85, 0.65, 1.0)], [0.8, Color(0.5, 0.55, 1.0)]]
	_flames = _add(ToonFx.emitter(36, 0.26, 0.32,
		ToonFx.sprite_material(ToonFx.Shape.BLOB, {"ink_color": ink, "ink_width": 0.14, "energy": 1.3}),
		flame_steps,
		[Vector2(0.0, 0.6), Vector2(0.12, 1.0), Vector2(0.7, 0.4), Vector2(1.0, 0.0)]))
	_flames.emission_sphere_radius = 0.06
	_flames.spread = 7.0
	_flames.damping_min = 1.0
	_flames.damping_max = 3.0

	_sparks = _add(ToonFx.emitter(14, 0.4, 0.17,
		ToonFx.sprite_material(ToonFx.Shape.SPARKLE, {"ink_width": 0.0, "energy": 2.2}),
		spark_steps,
		[Vector2(0.0, 1.0), Vector2(1.0, 0.0)]))
	_sparks.spread = 24.0
	_sparks.initial_velocity_min = 6.0
	_sparks.initial_velocity_max = 12.0
	_sparks.gravity = Vector3(0, -6.0, 0)

	_smoke = _add(ToonFx.emitter(10, 0.8, 0.45,
		ToonFx.sprite_material(ToonFx.Shape.BLOB, {
			"ink_color": ToonFx.SMOKE_INK, "ink_width": 0.1, "puff": true, "wobble": 0.12}),
		[[0.0, SMOKE], [0.6, SMOKE_DARK]],
		[Vector2(0.0, 0.25), Vector2(0.3, 1.0), Vector2(0.65, 0.8), Vector2(1.0, 0.0)]))
	_smoke.emission_sphere_radius = 0.1
	_smoke.spread = 14.0
	_smoke.initial_velocity_min = 2.0
	_smoke.initial_velocity_max = 3.5
	_smoke.damping_min = 1.5
	_smoke.damping_max = 2.5


func set_power(level: float) -> void:
	var flicker := randf_range(0.85, 1.15)
	var width := lerpf(0.5, 1.0, level)
	_jet.visible = level > 0.03
	_jet.scale = Vector3(width, jet_length * lerpf(0.3, 1.0, level) * flicker, width)
	_jet_mat.set_shader_parameter("power", clampf(level * flicker, 0.0, 1.0))
	_flames.emitting = level > 0.05
	_flames.initial_velocity_min = 3.0 + 6.0 * level
	_flames.initial_velocity_max = 5.0 + 9.0 * level
	_sparks.emitting = level > 0.35
	_smoke.emitting = level > 0.5


func _build_jet() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = jet_radius
	cone.bottom_radius = jet_radius * 0.15
	cone.height = 1.0
	cone.radial_segments = 16
	cone.rings = 4
	cone.cap_top = false
	cone.cap_bottom = false
	_jet_mat = ShaderMaterial.new()
	_jet_mat.shader = JET_SHADER
	if blue:
		_jet_mat.set_shader_parameter("core_color", Vector3(0.35, 0.55, 1.0))
		_jet_mat.set_shader_parameter("mid_color", Vector3(0.06, 0.18, 0.75))
		_jet_mat.set_shader_parameter("tip_color", Vector3(0.02, 0.06, 0.35))
	var mesh := MeshInstance3D.new()
	mesh.mesh = cone
	mesh.material_override = _jet_mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = Vector3(0, -0.5, 0)  # nozzle (top of the cone) at this node's origin
	_jet = Node3D.new()
	_jet.visible = false
	_jet.add_child(mesh)
	add_child(_jet)


## Adds an emitter firing down the jet, with a little size variety.
func _add(p: CPUParticles3D) -> CPUParticles3D:
	p.randomness = 0.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.04
	p.direction = Vector3(0, -1, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	add_child(p)
	return p
