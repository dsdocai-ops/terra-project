shader_type canvas_item;
// Drifting cave fog over everything the local player has not entered. Room
// rects are in tile space (edges, wall ring included); `lit` marks the entered
// ones. Outside a room's floor (its wall ring counts as outside), a hallway
// clears (walls included) once the player has stepped into it; `corridors` is a
// one-texel-per-tile mask of the cleared ones. Edges feather over about a tile
// so revealed areas melt into the murk instead of cutting to a hard black line.

const int MAX_ROOMS = 16;
const float GRID = 96.0;

uniform vec4 rects[MAX_ROOMS];
uniform float lit[MAX_ROOMS];
uniform int count = 0;
uniform sampler2D corridors : filter_linear, repeat_disable;
uniform vec3 fog_dark : source_color = vec3(0.045, 0.05, 0.065);
uniform vec3 fog_light : source_color = vec3(0.13, 0.145, 0.17);
uniform float feather = 0.9;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float u = world.x / 32.0;
	float v = world.y / 16.0;
	vec2 t = vec2((u + v) * 0.5 - 1.0, (v - u) * 0.5);

	float room_reveal = 0.0;
	float inner_depth = -10.0;
	for (int i = 0; i < MAX_ROOMS; i++) {
		if (i >= count) {
			break;
		}
		vec4 r = rects[i];
		// Signed distance inside the rect (positive inside), and inside its floor.
		float d = min(min(t.x - r.x, r.z - t.x), min(t.y - r.y, r.w - t.y));
		float di = d - 1.0;
		inner_depth = max(inner_depth, di);
		if (lit[i] > 0.5) {
			room_reveal = max(room_reveal, smoothstep(-0.15, feather, d));
		}
	}
	// A hallway never lights the floor of a room that has not been entered.
	float corridor = texture(corridors, (t + 0.5) / GRID).r;
	corridor = smoothstep(0.15, 0.85, corridor) * (1.0 - smoothstep(-0.2, 0.6, inner_depth));
	float reveal = max(room_reveal, corridor);

	// Slowly drifting layered noise gives the murk body and movement.
	vec2 p = world * 0.012;
	float n = fbm(p + vec2(TIME * 0.02, TIME * 0.012));
	float n2 = fbm(p * 1.7 - vec2(TIME * 0.015, -TIME * 0.01) + 5.2);
	float body = clamp(n * 0.6 + n2 * 0.5, 0.0, 1.0);
	vec3 col = mix(fog_dark, fog_light, body);

	// Wisps thin out near the edge of what you can see; deep fog is opaque.
	float edge = 1.0 - reveal;
	float alpha = edge * mix(1.0, 0.72 + 0.28 * body, 1.0 - edge);
	alpha = reveal < 0.001 ? 1.0 : clamp(alpha, 0.0, 1.0);
	COLOR = vec4(col, alpha);
}
