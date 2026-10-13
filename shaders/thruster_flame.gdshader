shader_type spatial;
// Cel-shaded thruster jet for a cone mesh of height 1 centred on the origin, nozzle at the top.
// Drawn as flat, hard-edged bands like a cartoon flame: a white-hot core, a violet body and a
// blue outer sheath, narrowing to licking tongues at the tip. Bands pulse down the plume.
// `power` (0..1) is set by thruster.gd and shortens / thins the flame.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 0.95, 1.0);
uniform vec3 mid_color : source_color = vec3(0.72, 0.38, 1.0);
uniform vec3 tip_color : source_color = vec3(0.3, 0.42, 1.0);
uniform float intensity = 1.5;
uniform float power = 1.0;

varying float along;  // 0 at the nozzle, 1 at the tip

void vertex() {
	along = clamp(0.5 - VERTEX.y, 0.0, 1.0);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// Tongues of flame at the tip, flickering around the cone and pulsing down it.
	float lick = 0.1 * sin(UV.x * TAU * 6.0 - TIME * 38.0) + 0.06 * sin(along * 22.0 - TIME * 50.0);
	float body = facing - along * (1.15 - 0.35 * power) + lick * along;
	if (body < 0.12) {
		discard;
	}
	float pulse = step(0.0, sin(along * 16.0 - TIME * 42.0)) * 0.12;
	float heat = body + pulse * (1.0 - along);
	vec3 col = heat > 0.62 ? core_color : (heat > 0.32 ? mid_color : tip_color);
	ALBEDO = col * intensity;
}
