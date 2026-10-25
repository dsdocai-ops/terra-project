shader_type canvas_item;
// Solid black over everything the local player has not entered. Room rects are
// in tile space (edges, wall ring included); `lit` marks the entered ones.
// Outside any room (hallways) only a small lamp around the player is clear.

const int MAX_ROOMS = 16;

uniform vec4 rects[MAX_ROOMS];
uniform float lit[MAX_ROOMS];
uniform int count = 0;
uniform vec2 player_tile = vec2(0.0);
uniform float lamp = 4.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float u = world.x / 32.0;
	float v = world.y / 16.0;
	vec2 t = vec2((u + v) * 0.5 - 1.0, (v - u) * 0.5);
	bool in_room = false;
	bool revealed = false;
	for (int i = 0; i < MAX_ROOMS; i++) {
		if (i >= count) {
			break;
		}
		vec4 r = rects[i];
		if (t.x >= r.x && t.x < r.z && t.y >= r.y && t.y < r.w) {
			in_room = true;
			if (lit[i] > 0.5) {
				revealed = true;
			}
		}
	}
	if (!in_room && distance(t, player_tile) < lamp) {
		revealed = true;
	}
	COLOR = revealed ? vec4(0.0) : vec4(0.0, 0.0, 0.0, 1.0);
}
