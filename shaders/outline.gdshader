shader_type spatial;
// Ink outline for the toon style, used as a material's next_pass ("inverted hull"): the mesh is
// drawn again slightly enlarged with only its back faces, so a dark rim shows around the edges.
// push_mode picks how vertices are pushed out, so flat-shaded meshes don't split at hard edges:
//   0 = along the normal (smooth or rigid meshes, e.g. the mech)
//   1 = away from the object's origin (blobs centred on the origin, e.g. boulders)
//   2 = away from the vertical axis, slightly up (cones stacked on the Y axis, e.g. pines)
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.08, 0.07, 0.1, 1.0);
uniform float width = 0.05;   // in the mesh's own units
uniform int push_mode = 0;

void vertex() {
	vec3 dir = NORMAL;
	if (push_mode == 1) {
		dir = normalize(VERTEX + vec3(0.0, 0.0001, 0.0));
	} else if (push_mode == 2) {
		dir = normalize(vec3(VERTEX.x, 0.0, VERTEX.z) + vec3(0.0, 0.2, 0.0));
	}
	VERTEX += dir * width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
