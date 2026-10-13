shader_type spatial;
// Toon ground for terrain.gd: vertex colours (grass, dry grass, dirt, rock, set per heightmap
// vertex) with large, flat-toned patches from world-space noise, and cel-shaded lighting.

#include "res://shaders/toon_light.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float patches = texture(noise_tex, world_pos.xz * 0.004).r;
	ALBEDO = COLOR.rgb * mix(0.95, 1.04, smoothstep(0.48, 0.52, patches));
	ROUGHNESS = 1.0;
}
