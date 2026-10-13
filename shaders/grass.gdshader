shader_type spatial;
// Grass clumps for terrain.gd (MultiMesh). UV.y runs from 0 at the root to 1 at the tip.
// The instance colour is the ground colour underneath, so grass blends into the terrain:
// roots are a little darker, tips lighter. Blades sway in a world-space wind and are lit as
// if facing straight up, so both sides of a blade shade the same as the ground.
render_mode cull_disabled;

#include "res://shaders/toon_light.gdshaderinc"

uniform float wind_strength = 0.22;
uniform float wind_speed = 1.6;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * wind_speed + world.x * 0.12 + world.z * 0.08)
			+ 0.5 * sin(TIME * wind_speed * 2.3 + world.x * 0.4 + world.z * 0.3);
	vec3 offset = vec3(1.0, 0.0, 0.5) * sway * wind_strength * UV.y * UV.y;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * offset;
}

void fragment() {
	vec3 base = COLOR.rgb;
	ALBEDO = mix(base * 0.7, base * 1.25 + vec3(0.02, 0.03, 0.0), UV.y);
	ROUGHNESS = 1.0;
	// Set per fragment so back faces aren't flipped dark.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
