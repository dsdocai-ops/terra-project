extends Node3D
## Builds a basic mech from primitives: legs, torso, head with visor, arms with
## cannons, and glowing energy wings. Faces -Z (Godot forward). Feet at y = 0.

var _armor := _metal(Color(0.75, 0.78, 0.85))
var _dark := _metal(Color(0.12, 0.13, 0.16))
var _glow := _emissive(Color(0.1, 0.9, 1.0), 4.0)

var _wings: Array[Node3D] = []
var _spread := 0.0
var _flap_time := 0.0
var _flames: Array[CPUParticles3D] = []
var _flame_light: OmniLight3D


func _ready() -> void:
	_build_thrusters()
	# Legs and feet.
	for s in [-1.0, 1.0]:
		_box(Vector3(0.3, 0.9, 0.35), Vector3(0.35 * s, 0.9, 0), _armor)    # shin/thigh
		_box(Vector3(0.38, 0.2, 0.7), Vector3(0.35 * s, 0.1, -0.1), _dark)  # foot
	# Hips and torso.
	_box(Vector3(1.0, 0.3, 0.6), Vector3(0, 1.45, 0), _dark)
	_box(Vector3(1.3, 0.9, 0.8), Vector3(0, 2.05, 0), _armor)
	_box(Vector3(0.6, 0.3, 0.05), Vector3(0, 2.1, -0.43), _glow)           # chest core
	# Head with visor.
	_box(Vector3(0.55, 0.45, 0.55), Vector3(0, 2.75, 0), _armor)
	_box(Vector3(0.45, 0.12, 0.05), Vector3(0, 2.78, -0.29), _glow)
	# Arms with shoulder pads and cannons.
	for s in [-1.0, 1.0]:
		_box(Vector3(0.45, 0.35, 0.55), Vector3(0.9 * s, 2.45, 0), _armor)  # shoulder
		_box(Vector3(0.25, 0.8, 0.3), Vector3(0.9 * s, 1.9, 0), _dark)      # arm
		_cylinder(0.1, 0.9, Vector3(0.9 * s, 1.6, -0.45), Vector3(90, 0, 0), _dark)  # cannon
		_cylinder(0.06, 0.05, Vector3(0.9 * s, 1.6, -0.9), Vector3(90, 0, 0), _glow)
	# Back thruster pack and energy wings.
	_box(Vector3(0.7, 0.8, 0.35), Vector3(0, 2.1, 0.55), _dark)
	for s in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.position = Vector3(0.3 * s, 2.4, 0.6)
		wing.set_meta("side", s)
		_wings.append(wing)
		add_child(wing)
		# Three feathers per wing, getting longer toward the bottom.
		for i in 3:
			var feather_len := 1.6 + 0.5 * i
			var feather := _box(Vector3(feather_len, 0.06, 0.25), Vector3(s * feather_len * 0.5, -0.3 * i, 0), _glow, wing)
			feather.rotation_degrees.z = -8.0 * i * s
			_box(Vector3(feather_len * 0.95, 0.03, 0.34), Vector3(s * feather_len * 0.5, -0.3 * i - 0.04, 0.0), _dark, wing).rotation_degrees.z = -8.0 * i * s


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(mesh, pos, mat, parent)


func _cylinder(radius: float, height: float, pos: Vector3, rot_deg: Vector3, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	_add(mesh, pos, mat, self).rotation_degrees = rot_deg


func _add(mesh: Mesh, pos: Vector3, mat: Material, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _metal(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.7
	m.roughness = 0.35
	return m


func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


## Folds the wings against the back (spread 0) or opens them (spread 1).
## While flapping they beat up and down.
func update_wings(open: bool, flapping: bool, delta: float) -> void:
	_spread = move_toward(_spread, 1.0 if open else 0.0, 5.0 * delta)
	_flap_time += delta * (22.0 if flapping else 6.0)
	var flap := sin(_flap_time) * (22.0 if flapping else 4.0) * _spread
	for wing in _wings:
		var s: float = wing.get_meta("side")
		var yaw := lerpf(-85.0, -25.0, _spread)
		var roll := lerpf(70.0, 30.0, _spread) + flap
		wing.rotation_degrees = Vector3(0.0, yaw * s, roll * s)


## Thruster power 0..1: drives the boot flames and the light under the mech.
func set_thrust(level: float) -> void:
	for flame in _flames:
		flame.emitting = level > 0.05
		flame.initial_velocity_min = 3.0 + 7.0 * level
		flame.initial_velocity_max = 5.0 + 9.0 * level
	_flame_light.light_energy = 6.0 * level


func _build_thrusters() -> void:
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(0.5, 0.95, 1.0)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(0.2, 0.8, 1.0)
	flame_mat.emission_energy_multiplier = 3.0
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.14
	flame_mesh.height = 0.28
	flame_mesh.material = flame_mat
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	# Boots, plus the thruster pack on the back.
	for pos in [Vector3(-0.35, 0.05, -0.1), Vector3(0.35, 0.05, -0.1), Vector3(-0.2, 1.8, 0.8), Vector3(0.2, 1.8, 0.8)]:
		var p := CPUParticles3D.new()
		p.position = pos
		p.emitting = false
		p.amount = 40
		p.lifetime = 0.35
		p.local_coords = false
		p.direction = Vector3(0, -1, 0)
		p.spread = 8.0
		p.gravity = Vector3.ZERO
		p.scale_amount_curve = shrink
		p.mesh = flame_mesh
		add_child(p)
		_flames.append(p)
	_flame_light = OmniLight3D.new()
	_flame_light.position = Vector3(0, -0.3, 0)
	_flame_light.light_color = Color(0.3, 0.85, 1.0)
	_flame_light.omni_range = 12.0
	_flame_light.light_energy = 0.0
	add_child(_flame_light)
