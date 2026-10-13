extends Node3D
## Builds the demo level at startup: concrete ground plus a grid of futuristic
## towers separated by streets. Layout is seeded so it is identical every run.

const GROUND_SIZE := 240.0
const BLOCK := 30.0          # distance between building centres
const GRID := 3              # buildings extend GRID blocks in each direction
const CLEAR_RADIUS := 14.0   # keep the spawn area open


var _rng := RandomNumberGenerator.new()
var _building_shader: Shader = load("res://shaders/building.gdshader")
var _window_colors: Array[Color] = [
	Color(0.1, 0.9, 1.0), Color(1.0, 0.2, 0.8), Color(0.5, 1.0, 0.4), Color(1.0, 0.7, 0.2),
]


func _ready() -> void:
	_rng.seed = 1234
	_build_ground()
	for gx in range(-GRID, GRID + 1):
		for gz in range(-GRID, GRID + 1):
			var pos := Vector3(gx * BLOCK, 0.0, gz * BLOCK)
			if Vector2(pos.x, pos.z).length() < CLEAR_RADIUS:
				continue
			_build_tower(pos)


func _build_ground() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.04
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.57)
	mat.albedo_texture = tex
	mat.roughness = 0.95
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.05, 0.05, 0.05)
	_add_box(Vector3(0, -0.5, 0), Vector3(GROUND_SIZE, 1.0, GROUND_SIZE), mat)


func _build_tower(pos: Vector3) -> void:
	var w := _rng.randf_range(12.0, 20.0)
	var d := _rng.randf_range(12.0, 20.0)
	var h := _rng.randf_range(15.0, 70.0)
	var color := _window_colors[_rng.randi() % _window_colors.size()]
	var mat := ShaderMaterial.new()
	mat.shader = _building_shader
	mat.set_shader_parameter("window_color", color)

	# Main tower body.
	_add_box(pos + Vector3(0, h * 0.5, 0), Vector3(w, h, d), mat)
	# Setback upper tier on taller towers.
	if h > 40.0:
		var h2 := _rng.randf_range(8.0, 18.0)
		_add_box(pos + Vector3(0, h + h2 * 0.5, 0), Vector3(w * 0.6, h2, d * 0.6), mat)
		h += h2
	# Glowing neon beacon on the roof.
	var neon := StandardMaterial3D.new()
	neon.albedo_color = color
	neon.emission_enabled = true
	neon.emission = color
	neon.emission_energy_multiplier = 4.0
	_add_box(pos + Vector3(0, h + 1.0, 0), Vector3(1.0, 2.0, 1.0), neon, false)


func _add_box(pos: Vector3, size: Vector3, mat: Material, collide := true) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var body := StaticBody3D.new()
	body.position = pos
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	add_child(body)
