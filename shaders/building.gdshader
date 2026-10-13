shader_type spatial;
// Dark metallic facade with a grid of randomly lit neon windows.
// Uses world position so any box size gets evenly spaced windows.

uniform vec3 wall_color : source_color = vec3(0.06, 0.07, 0.10);
uniform vec3 window_color : source_color = vec3(0.1, 0.9, 1.0);
uniform float window_energy = 2.5;
uniform vec2 cell_size = vec2(3.0, 3.5);

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = wall_color;
	METALLIC = 0.8;
	ROUGHNESS = 0.3;
	if (abs(world_normal.y) < 0.5) {
		float u = abs(world_normal.x) > 0.5 ? world_pos.z : world_pos.x;
		vec2 p = vec2(u, world_pos.y) / cell_size;
		vec2 cell = floor(p);
		vec2 f = fract(p);
		bool in_window = f.x > 0.2 && f.x < 0.8 && f.y > 0.25 && f.y < 0.75;
		float lit = step(0.45, hash(cell + floor(world_pos.xz * 0.0) + vec2(world_normal.x + world_normal.z, 0.0)));
		if (in_window && world_pos.y > 1.0) {
			EMISSION = window_color * window_energy * lit;
		}
	}
}
