shader_type canvas_item;
// Solid black over everything the local player has not entered. Room rects are
// in tile space (edges, wall ring included); `lit` marks the entered ones.
// Outside a room's floor (its wall ring counts as outside), a hallway clears (walls included) once the player has stepped
// into it; `corridors` is a one-texel-per-tile mask of the cleared ones.

const int MAX_ROOMS = 16;
const float GRID = 96.0;

uniform vec4 rects[MAX_ROOMS];
uniform float lit[MAX_ROOMS];
uniform int count = 0;
uniform sampler2D corridors : filter_nearest, repeat_disable;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float u = world.x / 32.0;
	float v = world.y / 16.0;
	vec2 t = vec2((u + v) * 0.5 - 1.0, (v - u) * 0.5);
	bool in_inner = false;
	bool revealed = false;
	for (int i = 0; i < MAX_ROOMS; i++) {
		if (i >= count) {
			break;
		}
		vec4 r = rects[i];
		if (t.x >= r.x && t.x < r.z && t.y >= r.y && t.y < r.w) {
			if (t.x >= r.x + 1.0 && t.x < r.z - 1.0 && t.y >= r.y + 1.0 && t.y < r.w - 1.0) {
				in_inner = true;
			}
			if (lit[i] > 0.5) {
				revealed = true;
			}
		}
	}
	if (!in_inner) {
		vec2 cell = floor(t + 0.5);
		if (texture(corridors, (cell + 0.5) / GRID).r > 0.5) {
			revealed = true;
		}
	}
	COLOR = revealed ? vec4(0.0) : vec4(0.0, 0.0, 0.0, 1.0);
}
