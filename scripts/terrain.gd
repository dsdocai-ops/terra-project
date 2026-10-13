extends Node3D
## Builds the outdoor level at startup: a grassy valley ringed by forested hills and rocky
## mountains, with a dirt trail, wind-swept grass, pine forests and mossy boulders, in a
## toon / cel-shaded style (shaders/toon_light.gdshaderinc, ink outlines from outline.gdshader).
## Seeded, so the layout is identical every run. The spawn (origin) is a flat clearing at y = 0.

const SIZE := 1600.0          # terrain width and depth (m)
const CELL := 5.0             # heightmap spacing (m)
const SPAWN_CLEAR := 30.0     # flat clearing radius around the spawn
const GRASS_RADIUS := 220.0   # grass is scattered within this distance of the spawn
const GRASS_CHUNK := 40.0     # grass is split into chunks this size so distant ones can be culled
const GRASS_DENSITY := 0.8    # clumps per square metre
const GRASS_VIEW := 150.0     # grass chunks are hidden beyond this distance from the camera
const TREE_TRIES := 16000
const ROCK_COUNT := 450

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const ROCK_SHADER := preload("res://shaders/rock.gdshader")
const FOLIAGE_SHADER := preload("res://shaders/toon_foliage.gdshader")
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")

# Toon palette (sRGB): saturated, flat colours.
const LUSH := Color(0.32, 0.56, 0.22)
const LIGHT := Color(0.5, 0.68, 0.28)
const DRY := Color(0.82, 0.76, 0.36)
const DIRT := Color(0.62, 0.46, 0.3)
const ROCK := Color(0.52, 0.52, 0.58)
const TRUNK := Color(0.42, 0.27, 0.16)
const NEEDLES_DARK := Color(0.1, 0.36, 0.2)
const NEEDLES_LIGHT := Color(0.2, 0.52, 0.26)

var _rng := RandomNumberGenerator.new()
var _hills := _noise(11, 0.0035, 4)
var _detail := _noise(12, 0.03, 2)
var _ridges := _noise(13, 0.006, 3)
var _patches := _noise(14, 0.012, 2)
var _forest := _noise(15, 0.008, 2)
var _n := int(SIZE / CELL) + 1      # heightmap vertices per side
var _origin_height := 0.0
var _heights := PackedFloat32Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()   # linear, ready for the shaders
var _bare := PackedFloat32Array()   # 0 = grass, 1 = dirt or rock (no grass or trees)


func _ready() -> void:
	_rng.seed = 2024
	_origin_height = _raw_height(0.0, 0.0)
	_build_heightfield()
	_build_ground()
	_build_grass()
	_build_trees()
	_build_rocks()


# --- Shape of the land -----------------------------------------------------

func _raw_height(x: float, z: float) -> float:
	var h := _hills.get_noise_2d(x, z) * 14.0 + _detail.get_noise_2d(x, z) * 1.2
	# Mountains rise around the rim of the valley.
	var rim := smoothstep(260.0, 650.0, Vector2(x, z).length())
	h += rim * (60.0 + 160.0 * (1.0 - absf(_ridges.get_noise_2d(x, z))))
	# The trail is worn slightly into the ground.
	h -= (1.0 - smoothstep(2.0, 7.0, _trail_distance(x, z))) * 0.4
	return h


## Height with the spawn clearing flattened to y = 0.
func _height(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	return (_raw_height(x, z) - _origin_height) * smoothstep(SPAWN_CLEAR * 0.5, SPAWN_CLEAR * 2.0, d)


## Distance across a winding trail that runs east-west past the spawn.
func _trail_distance(x: float, z: float) -> float:
	return absf(z - (50.0 * sin(x * 0.006) + 20.0 * sin(x * 0.017 + 1.0)))


func _grid_coord(i: int) -> float:
	return -SIZE * 0.5 + i * CELL


func _build_heightfield() -> void:
	var count := _n * _n
	_heights.resize(count)
	_normals.resize(count)
	_colors.resize(count)
	_bare.resize(count)
	for j in _n:
		for i in _n:
			_heights[j * _n + i] = _height(_grid_coord(i), _grid_coord(j))
	for j in _n:
		for i in _n:
			var hl := _heights[j * _n + maxi(i - 1, 0)]
			var hr := _heights[j * _n + mini(i + 1, _n - 1)]
			var hu := _heights[maxi(j - 1, 0) * _n + i]
			var hd := _heights[mini(j + 1, _n - 1) * _n + i]
			var normal := Vector3(hl - hr, 2.0 * CELL, hu - hd).normalized()
			var k := j * _n + i
			_normals[k] = normal
			_paint(k, _grid_coord(i), _grid_coord(j), _heights[k], 1.0 - normal.y)


## Picks the ground colour and how bare (no grass) a vertex is.
func _paint(k: int, x: float, z: float, h: float, slope: float) -> void:
	# Narrow blends so the patches read as flat toon shapes rather than gradients.
	var c := LUSH.lerp(LIGHT, smoothstep(-0.03, 0.03, _patches.get_noise_2d(x, z)))
	c = c.lerp(DRY, smoothstep(0.36, 0.42, _patches.get_noise_2d(x * 2.3 + 500.0, z * 2.3)) * 0.8)
	var d := Vector2(x, z).length()
	var trail := (1.0 - smoothstep(2.5, 5.0, _trail_distance(x, z))) * (1.0 - smoothstep(250.0, 400.0, d))
	var scuff := (1.0 - smoothstep(8.0, 22.0, d)) * smoothstep(0.0, 0.5, _detail.get_noise_2d(x * 3.0, z * 3.0))
	var dirt := maxf(trail, scuff)
	var rock := maxf(smoothstep(0.45, 0.7, slope), smoothstep(110.0, 170.0, h))
	c = c.lerp(DIRT, dirt).lerp(ROCK, rock)
	_colors[k] = c.srgb_to_linear()
	_bare[k] = maxf(dirt, rock)


func _sample(values: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x + SIZE * 0.5) / CELL, 0.0, _n - 1.001)
	var fz := clampf((z + SIZE * 0.5) / CELL, 0.0, _n - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var top := lerpf(values[j * _n + i], values[j * _n + i + 1], tx)
	var bottom := lerpf(values[(j + 1) * _n + i], values[(j + 1) * _n + i + 1], tx)
	return lerpf(top, bottom, tz)


func _color_at(x: float, z: float) -> Color:
	var i := clampi(roundi((x + SIZE * 0.5) / CELL), 0, _n - 1)
	var j := clampi(roundi((z + SIZE * 0.5) / CELL), 0, _n - 1)
	return _colors[j * _n + i]


# --- Ground mesh and collision ---------------------------------------------

func _build_ground() -> void:
	var verts := PackedVector3Array()
	verts.resize(_n * _n)
	for j in _n:
		for i in _n:
			verts[j * _n + i] = Vector3(_grid_coord(i), _heights[j * _n + i], _grid_coord(j))
	var indices := PackedInt32Array()
	indices.resize((_n - 1) * (_n - 1) * 6)
	var w := 0
	for j in _n - 1:
		for i in _n - 1:
			var a := j * _n + i
			var c := a + _n
			for v in [a, a + 1, c, a + 1, c + 1, c]:
				indices[w] = v
				w += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = _noise(16, 0.05, 3)
	noise_tex.seamless = true
	noise_tex.width = 256
	noise_tex.height = 256
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("noise_tex", noise_tex)

	var body := StaticBody3D.new()
	body.name = "Ground"
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	# Heightmap collision has 1 m spacing, so store heights / CELL and scale uniformly by CELL.
	var shape := HeightMapShape3D.new()
	shape.map_width = _n
	shape.map_depth = _n
	var scaled := _heights.duplicate()
	for k in scaled.size():
		scaled[k] /= CELL
	shape.map_data = scaled
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * CELL
	body.add_child(cs)
	add_child(body)


# --- Grass -----------------------------------------------------------------

func _build_grass() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	var mesh := _grass_clump_mesh()
	mesh.surface_set_material(0, mat)
	var half := ceili(GRASS_RADIUS / GRASS_CHUNK)
	var per_chunk := int(GRASS_CHUNK * GRASS_CHUNK * GRASS_DENSITY)
	for cz in range(-half, half):
		for cx in range(-half, half):
			var corner := Vector2(cx, cz) * GRASS_CHUNK
			var centre := corner + Vector2.ONE * GRASS_CHUNK * 0.5
			if centre.length() > GRASS_RADIUS + GRASS_CHUNK:
				continue
			var xforms: Array[Transform3D] = []
			var colors := PackedColorArray()
			for k in per_chunk:
				var p := corner + Vector2(_rng.randf(), _rng.randf()) * GRASS_CHUNK
				if p.length() > GRASS_RADIUS or _sample(_bare, p.x, p.y) > _rng.randf_range(0.2, 0.8):
					continue
				var s := _rng.randf_range(0.7, 1.4)
				var turn := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.3), s))
				xforms.append(Transform3D(turn, Vector3(p.x - centre.x, _sample(_heights, p.x, p.y), p.y - centre.y)))
				colors.append(_color_at(p.x, p.y).lightened(_rng.randf() * 0.08))
			if xforms.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			mm.instance_count = xforms.size()
			for k in xforms.size():
				mm.set_instance_transform(k, xforms[k])
				mm.set_instance_color(k, colors[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.position = Vector3(centre.x, 0.0, centre.y)
			mmi.visibility_range_end = GRASS_VIEW
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)


## A clump of twelve tapered blades, each one triangle. UV.y is 0 at the root and 1 at the tip.
func _grass_clump_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 12:
		var angle := rng.randf() * TAU
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var across := Vector3(-dir.z, 0.0, dir.x) * rng.randf_range(0.07, 0.12)
		var root := dir * rng.randf_range(0.0, 0.25)
		var tip := root + dir * rng.randf_range(0.1, 0.3) + Vector3(0.0, rng.randf_range(0.45, 0.95), 0.0)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(root - across)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(root + across)
		st.set_uv(Vector2(0.5, 1.0))
		st.add_vertex(tip)
	st.generate_normals()
	return st.commit()


# --- Pine forests ----------------------------------------------------------

func _build_trees() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE_SHADER
	mat.next_pass = _outline(0.1, 2)
	var variants := [_pine_mesh(3, 9.0), _pine_mesh(4, 12.0), _pine_mesh(5, 15.0)]
	var xforms := [[], [], []]
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.5
	trunk.height = 8.0
	var body := StaticBody3D.new()
	body.name = "Trees"
	add_child(body)
	for t in TREE_TRIES:
		var p := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * 720.0
		var d := p.length()
		if d < SPAWN_CLEAR + 15.0 or d > 720.0:
			continue
		var density := smoothstep(-0.15, 0.35, _forest.get_noise_2d(p.x, p.y)) * lerpf(0.25, 1.0, smoothstep(60.0, 260.0, d))
		if _rng.randf() > density or _sample(_bare, p.x, p.y) > 0.4:
			continue
		var y := _sample(_heights, p.x, p.y)
		if y > 180.0:
			continue
		var s := _rng.randf_range(0.7, 1.4)
		var turn := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
		xforms[_rng.randi() % 3].append(Transform3D(turn, Vector3(p.x, y - 0.3, p.y)))
		var cs := CollisionShape3D.new()
		cs.shape = trunk
		cs.position = Vector3(p.x, y + trunk.height * 0.5, p.y)
		body.add_child(cs)
	for v in variants.size():
		_add_multimesh(variants[v], mat, xforms[v], true)


## Low-poly pine: a trunk and `layers` stacked, overlapping cones, flat shaded.
func _pine_mesh(layers: int, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var trunk_h := height * 0.3
	_cone(st, 0.0, trunk_h, height * 0.025, height * 0.02, TRUNK.srgb_to_linear(), 6)
	var y := trunk_h * 0.6
	var step := (height - y) / (layers + 0.6)
	for k in layers:
		var t := float(k) / layers
		var col := NEEDLES_DARK.lerp(NEEDLES_LIGHT, t).srgb_to_linear()
		_cone(st, y, step * 1.6, height * 0.22 * (1.0 - t * 0.7), 0.0, col, 8)
		y += step
	st.generate_normals()
	return st.commit()


## Adds a (possibly truncated) cone's sides: radius r0 at y0, r1 at y0 + h.
func _cone(st: SurfaceTool, y0: float, h: float, r0: float, r1: float, col: Color, segs: int) -> void:
	st.set_color(col)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var b0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var b1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var t0 := Vector3(cos(a0) * r1, y0 + h, sin(a0) * r1)
		var t1 := Vector3(cos(a1) * r1, y0 + h, sin(a1) * r1)
		for v in [b0, b1, t0, b1, t1, t0]:
			st.add_vertex(v)


# --- Boulders --------------------------------------------------------------

func _build_rocks() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = ROCK_SHADER
	mat.next_pass = _outline(0.035, 1)
	var meshes: Array[ArrayMesh] = []
	var shapes: Array[Shape3D] = []
	for v in 4:
		var mesh := _rock_mesh(100 + v)
		meshes.append(mesh)
		shapes.append(mesh.create_convex_shape())
	var xforms := [[], [], [], []]
	var colors := [PackedColorArray(), PackedColorArray(), PackedColorArray(), PackedColorArray()]
	var body := StaticBody3D.new()
	body.name = "Rocks"
	add_child(body)
	var placed := 0
	while placed < ROCK_COUNT:
		var p := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * 650.0
		var d := p.length()
		if d < 12.0 or d > 650.0:
			continue
		# Mostly on rocky ground, plus a scattering around the clearing.
		var chance := 0.15 + 0.85 * _sample(_bare, p.x, p.y) + (0.5 if d < 90.0 else 0.0)
		if _rng.randf() > chance:
			continue
		placed += 1
		var big := _rng.randf() < 0.1
		var s := _rng.randf_range(6.0, 16.0) if big else _rng.randf_range(0.6, 3.5)
		var turn := Basis.from_euler(Vector3(_rng.randf() * 0.4, _rng.randf() * TAU, _rng.randf() * 0.4)).scaled(Vector3.ONE * s)
		var xform := Transform3D(turn, Vector3(p.x, _sample(_heights, p.x, p.y) - s * 0.15, p.y))
		var v := _rng.randi() % 4
		xforms[v].append(xform)
		colors[v].append(Color(1, 1, 1).darkened(_rng.randf() * 0.25))
		var cs := CollisionShape3D.new()
		cs.shape = shapes[v]
		cs.transform = xform
		body.add_child(cs)
	for v in 4:
		meshes[v].surface_set_material(0, mat)
		_add_multimesh(meshes[v], null, xforms[v], true, colors[v])


## A lumpy, flat-shaded boulder about 1 m across, squashed vertically.
func _rock_mesh(seed_value: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 10
	sphere.rings = 7
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var noise := _noise(seed_value, 1.6, 3)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for k in index:
		var dir := verts[k].normalized()
		var p := dir * 0.5 * (1.0 + noise.get_noise_3dv(dir) * 0.45)
		p.y *= 0.7
		st.add_vertex(p)
	st.generate_normals()
	return st.commit()


# --- Helpers ---------------------------------------------------------------

func _add_multimesh(mesh: Mesh, mat: Material, xforms: Array, shadows: bool, colors := PackedColorArray()) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		if mm.use_colors:
			mm.set_instance_color(k, colors[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Ink outline material (see outline.gdshader for push modes). Width is in mesh units.
func _outline(width: float, push_mode: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("push_mode", push_mode)
	return m


static func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n
