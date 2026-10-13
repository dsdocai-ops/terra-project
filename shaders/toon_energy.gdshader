shader_type spatial;
// Cel-shaded ball of energy (the cannon's shot): flat bands instead of a soft
// glow, a white-hot core where the surface faces the camera, the glow colour around it and a
// darker rim at the silhouette. The band edges ripple so it looks alive. Pair it with an ink
// outline (outline.gdshader as next_pass); see scripts/toon_fx.gd.
render_mode unshaded, shadows_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 0.95, 1.0);
uniform vec3 glow_color : source_color = vec3(0.7, 0.35, 1.0);
uniform vec3 rim_color : source_color = vec3(0.3, 0.2, 0.95);
uniform float energy = 1.6;

void fragment() {
	float facing = dot(normalize(NORMAL), normalize(VIEW));
	float ripple = 0.07 * sin(UV.x * TAU * 5.0 + TIME * 24.0) + 0.05 * sin(UV.y * 18.0 - TIME * 31.0);
	float f = facing + ripple;
	vec3 col = f > 0.72 ? core_color : (f > 0.38 ? glow_color : rim_color);
	ALBEDO = col * energy;
}
