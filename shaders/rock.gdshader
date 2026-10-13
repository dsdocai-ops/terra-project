shader_type spatial;
// Toon boulders for terrain.gd: grey stone (tinted per instance) with a hard-edged moss cap on
// upward-facing surfaces, and cel-shaded lighting.

#include "res://shaders/toon_light.gdshaderinc"

uniform vec3 stone : source_color = vec3(0.56, 0.56, 0.62);
uniform vec3 moss : source_color = vec3(0.32, 0.5, 0.2);

varying vec3 world_normal;

void vertex() {
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	float up = step(0.75, world_normal.y);
	ALBEDO = mix(stone * COLOR.rgb, moss, up);
	ROUGHNESS = 1.0;
}
