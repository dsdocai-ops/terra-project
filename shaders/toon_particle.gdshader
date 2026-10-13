shader_type spatial;
// Cel-shaded particle sprite for CPUParticles3D quads (see scripts/toon_fx.gd). Instead of a soft
// fading blob, each particle is a hard-edged shape in flat colour with an ink rim, and it shrinks
// away rather than fading: the particle colour's alpha is the shape's size (1 = full, 0 = gone);
// for a ring it is the ring's thickness instead.
//   shape 0 = round blob, 1 = four-point sparkle, 2 = diamond, 3 = ring
// The white-hot core (core_size) shrinks over the particle's life.
// `puff` adds two-tone shading (a lit side and a tinted shadow side), for smoke clouds;
// `wobble` scallops the edge into cloud bumps.
// Billboards like BILLBOARD_PARTICLES, spinning by the particle's angle.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform int shape = 0;
uniform vec4 ink_color : source_color = vec4(0.08, 0.07, 0.1, 1.0);
uniform float ink_width = 0.18;   // fraction of the radius drawn as the rim (0 = no rim)
uniform vec3 core_color : source_color = vec3(1.0);
uniform float core_size = 0.0;    // fraction of the radius drawn as a white-hot core
uniform float energy = 1.0;       // > 1 makes the colours bloom (the world has glow on)
uniform bool puff = false;
uniform vec3 shadow_tint : source_color = vec3(0.72, 0.7, 0.88);  // puff shadow side
uniform float wobble = 0.0;       // depth of the cloud bumps around the edge (0 = smooth)

varying float spin;
varying float seed;
varying float life;  // 0 at birth, 1 at death

void vertex() {
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]),
			normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	world = world * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	world = world * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	spin = a;
	life = INSTANCE_CUSTOM.y;
	seed = fract(a * 1.7 + MODEL_MATRIX[3].x * 0.13 + MODEL_MATRIX[3].z * 0.29);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d;  // 0 at the centre, 1 on the shape's edge
	if (shape == 1) {
		vec2 q = sqrt(abs(p));
		d = q.x + q.y;
	} else if (shape == 2) {
		d = abs(p.x) + abs(p.y);
	} else {
		d = length(p);
	}
	if (wobble > 0.0) {
		float ang = atan(p.y, p.x);
		d /= 1.0 - wobble * (1.0 - abs(sin(ang * 3.0 + seed * 40.0)));  // six bulging arcs
	}
	float size = shape == 3 ? 1.0 : clamp(COLOR.a, 0.0, 1.0);
	if (d > size) {
		discard;
	}
	float r = d / max(size, 0.001);  // 0..1 across the shape as it is now
	if (shape == 3 && r < 1.0 - 0.5 * COLOR.a) {
		discard;
	}
	vec3 col = COLOR.rgb;
	if (puff) {
		vec2 up = vec2(p.x, -p.y) / max(size, 0.001);  // quad space, +y up
		vec3 n = vec3(cos(spin) * up.x + sin(spin) * up.y, -sin(spin) * up.x + cos(spin) * up.y, 0.0);  // screen space
		n.z = sqrt(max(1.0 - dot(n.xy, n.xy), 0.0));
		float lit = dot(n, normalize(vec3(-0.45, 0.65, 0.6)));
		col *= lit > 0.3 ? vec3(1.0) : shadow_tint;
	}
	if (r < core_size * max(1.0 - life * 1.4, 0.0)) {
		col = core_color;
	}
	col *= energy;
	if (r > 1.0 - ink_width) {
		col = ink_color.rgb;
	}
	ALBEDO = col;
}
