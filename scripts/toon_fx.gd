extends RefCounted
## Shared builders for the cel-shaded effects (thrusters, energy shots, muzzle sparkles), so they
## match the toon world: hard-edged particle shapes in flat colour with an ink rim
## (shaders/toon_particle.gdshader) and banded energy balls with an ink outline
## (shaders/toon_energy.gdshader). Particles shrink away instead of fading out.
## Use via preload: `const ToonFx := preload("res://scripts/toon_fx.gd")`.

const PARTICLE_SHADER := preload("res://shaders/toon_particle.gdshader")
const ENERGY_SHADER := preload("res://shaders/toon_energy.gdshader")
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")

enum Shape { BLOB, SPARKLE, DIAMOND, RING }

const INK := Color(0.08, 0.07, 0.1)
const VIOLET_INK := Color(0.2, 0.05, 0.38)   # rim for glowing purple effects: reads as ink, keeps the glow
const SMOKE_INK := Color(0.2, 0.17, 0.27)


## Particle sprite material. params sets any toon_particle.gdshader uniform
## (ink_color, ink_width, core_color, core_size, energy, puff, wobble).
static func sprite_material(shape: Shape, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PARTICLE_SHADER
	m.set_shader_parameter("shape", shape)
	for key in params:
		m.set_shader_parameter(key, params[key])
	return m


## A CPUParticles3D drawing `mat` on quads of `size` metres, not emitting yet (add it to the tree
## before setting emitting). ramp: [[offset, Color], ...]; with hard = true the colours switch in
## steps like cel shading, and alpha is the particle's size (keep it 1 and shrink with
## size_curve, the particle's size over its life, given as Vector2 points).
static func emitter(amount: int, lifetime: float, size: float, mat: Material, ramp: Array,
		size_curve: Array, hard := true) -> CPUParticles3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(ramp.map(func(stop): return stop[0]))
	gradient.colors = PackedColorArray(ramp.map(func(stop): return stop[1]))
	if hard:
		gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var curve := Curve.new()
	for point in size_curve:
		curve.add_point(point)
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.mesh = quad
	p.gravity = Vector3.ZERO
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_curve = curve
	p.color_ramp = gradient
	return p


## A one-shot burst: every particle at once, from a point, in all directions.
static func burst(amount: int, lifetime: float, size: float, mat: Material, ramp: Array,
		size_curve: Array, hard := true) -> CPUParticles3D:
	var p := emitter(amount, lifetime, size, mat, ramp, size_curve, hard)
	p.one_shot = true
	p.explosiveness = 1.0
	p.spread = 180.0
	return p


## Banded energy-ball material with a violet ink outline `outline_width` metres thick
## (in the mesh's own units).
static func energy_material(glow: Color, rim: Color, energy := 1.6, outline_width := 0.04) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ENERGY_SHADER
	m.set_shader_parameter("glow_color", glow)
	m.set_shader_parameter("rim_color", rim)
	m.set_shader_parameter("energy", energy)
	m.next_pass = outline(outline_width, VIOLET_INK)
	return m


static func outline(width: float, color := INK) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("outline_color", color)
	return m


static func sphere(radius: float, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
