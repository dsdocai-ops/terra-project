shader_type spatial;
// Toon pines for terrain.gd: flat vertex colour (linear) with cel-shaded lighting.
// Both sides are drawn so the open undersides of the cones aren't see-through.
render_mode cull_disabled;

#include "res://shaders/toon_light.gdshaderinc"

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
